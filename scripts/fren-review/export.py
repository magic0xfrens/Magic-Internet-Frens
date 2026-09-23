#!/usr/bin/env python3
"""export.py --commit <ref> --out <review repo dir> [--round N] [--overlay PATH ...] [--git-commit]

Cut a Fren Review round: build the standalone review repository from one
commit of this repo.

What the IMD worker needs, and why this is not just a copy of contracts/solidity:
  * a Foundry project at the repository ROOT whose DEFAULT profile builds — the
    worker runs `forge config`, `forge build` and `forge test` at the root with no
    profile, each capped at 10 minutes, and refuses to submit if either fails;
  * no fs_permissions outside the repository — the worker rejects the config
    outright (our `cauldron` profile reads ../../compressed-traits);
  * an offline-green `forge test` — so only the PoC harness's own test files are
    compiled; every other test ships under reference/ (read, copy, not built).

The source is the tracked tree at <commit> (never the working tree). --overlay
adds working-tree paths on top, for trying an export before committing.
The ledger/ of an existing review repo is kept: it is the memory between rounds.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
HERE = os.path.dirname(os.path.abspath(__file__))
SOL = "contracts/solidity/"
KNOWN = "audit/FULL_SCOPE_2026-09-18/FINDINGS.md"
SOURCE_URL = "https://github.com/magic0xfrens/Magic-Internet-Frens"

# Compiled tests = the import closure of these. Everything else under test/ is reference.
TEST_SEEDS = ("test/fren-review/", "test/GenesisDiscountMint.t.sol")
DROP = ("out/", "cache/", "broadcast/", "render-out/", "audit/", "lib/", ".env", "foundry.toml")
IMPORT_RE = re.compile(r'import\s+(?:[^"\']*?from\s+)?["\']([^"\']+)["\']')


def git(*args, binary=False):
    r = subprocess.run(["git", *args], cwd=REPO, capture_output=True, check=True)
    return r.stdout if binary else r.stdout.decode()


def tracked(commit, paths):
    """{path: ("blob", bytes) | ("commit", sha)} for every tracked path under `paths` at `commit`."""
    out = {}
    for line in git("ls-tree", "-r", "--full-tree", commit, "--", *paths).splitlines():
        meta, path = line.split("\t", 1)
        mode, kind, sha = meta.split()
        out[path] = ("commit", sha) if kind == "commit" else ("blob", git("cat-file", "blob", sha, binary=True))
    return out


def overlay(files, paths):
    for p in paths:
        full = os.path.join(REPO, p)
        walk = [full] if os.path.isfile(full) else [os.path.join(d, f) for d, _, fs in os.walk(full) for f in fs]
        for f in walk:
            files[os.path.relpath(f, REPO)] = ("blob", open(f, "rb").read())


def test_closure(src):
    """Local .sol files reachable by import from the seed tests."""
    seen, stack = set(), [p for p in src if p.startswith("test/") and p.startswith(TEST_SEEDS)]
    while stack:
        p = os.path.normpath(stack.pop())
        if p in seen or p not in src:
            continue
        seen.add(p)
        for imp in IMPORT_RE.findall(src[p].decode(errors="ignore")):
            if imp.startswith("."):
                stack.append(os.path.join(os.path.dirname(p), imp))
            elif "/" in imp and not imp.split("/")[0].startswith(("@", "forge-std", "v4-", "permit2", "solmate", "openzeppelin", "ds-test")):
                stack.append(imp)
    return seen


def confined(path):
    return bool(path) and not path.startswith(("/", "~")) and not re.search(r"(^|/)\.\.(/|$)", path)


def toml_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, dict):
        return "{ " + ", ".join("%s = %s" % (k, toml_value(x)) for k, x in v.items()) + " }"
    if isinstance(v, list):
        if not v:
            return "[]"
        return "[\n" + "".join("    %s,\n" % toml_value(x) for x in v) + "]"
    raise TypeError(v)


def foundry_toml(original, commit):
    cfg = tomllib.loads(original)
    prof = cfg["profile"]
    default = {**prof["default"], **prof.get("cauldron", {})}
    render = {**prof["default"], **prof.get("render", {})}
    for p in (default, render):
        p["fs_permissions"] = [e for e in p.get("fs_permissions", []) if confined(e.get("path", "")) and e.get("access") == "read"]
        p["skip"] = list(dict.fromkeys([*p.get("skip", []), "reference/**", "tools/**"]))
    render["skip"] = [s for s in render["skip"] if s != "render/**"]
    lines = [
        "# Fren Review export of %s@%s." % (SOURCE_URL.split("github.com/")[1], commit[:12]),
        "# The DEFAULT profile is the source repo's `cauldron` profile, so a plain `forge build` works.",
        "# `render` builds the on-chain art (art cluster): FOUNDRY_PROFILE=render forge build.",
        "",
    ]
    for name, p in (("default", default), ("render", render)):
        lines.append("[profile.%s]" % name)
        for k, v in p.items():
            lines.append("%s = %s" % (k, toml_value(v)))
        lines.append("")
    return "\n".join(lines)


def gitmodules(original):
    return original.replace("path = contracts/solidity/lib/", "path = lib/").replace(
        '[submodule "contracts/solidity/lib/', '[submodule "lib/')


def write(out, rel, data):
    path = os.path.join(out, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode())


def main():
    ap = argparse.ArgumentParser(description="Cut a Fren Review round")
    ap.add_argument("--commit", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--round", type=int, default=1)
    ap.add_argument("--overlay", nargs="*", default=[])
    ap.add_argument("--git-commit", action="store_true", help="commit the round in the review repo")
    a = ap.parse_args()
    commit = git("rev-parse", a.commit).strip()
    out = os.path.abspath(a.out)

    files = tracked(commit, ["contracts/solidity", "audit/graph", KNOWN, ".gitmodules"])
    overlay(files, a.overlay)

    # Clear the review repo, keeping its history and its ledger.
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(out):
        if name in (".git", "ledger"):
            continue
        p = os.path.join(out, name)
        shutil.rmtree(p) if os.path.isdir(p) and not os.path.islink(p) else os.remove(p)

    src = {p[len(SOL):]: v[1] for p, v in files.items() if p.startswith(SOL) and v[0] == "blob"}
    subs = {p[len(SOL):]: v[1] for p, v in files.items() if p.startswith(SOL) and v[0] == "commit"}
    compiled_tests = test_closure(src)
    counts = {"source": 0, "tests": 0, "reference": 0}
    for rel, data in src.items():
        if rel.startswith(DROP) or os.path.basename(rel).startswith(".env"):
            continue
        if rel == "README.md":
            write(out, "docs/contracts-README.md", data)
        elif rel.startswith("test/"):
            if rel in compiled_tests:
                write(out, rel, data); counts["tests"] += 1
            else:
                write(out, "reference/" + rel, data); counts["reference"] += 1
        else:
            write(out, rel, data); counts["source"] += 1

    write(out, "foundry.toml", foundry_toml(src["foundry.toml"].decode(), commit))
    write(out, ".gitmodules", gitmodules(files[".gitmodules"][1].decode()))
    write(out, ".gitignore", "out/\ncache/\nbroadcast/\ntest/scratch/\n.imd-findings.json\n.imd-responses.json\n")

    # The map, built from the graph at the same commit.
    with tempfile.TemporaryDirectory() as graph:
        for p, (kind, data) in files.items():
            if p.startswith("audit/graph/") and kind == "blob" and "/" not in p[len("audit/graph/"):]:
                write(graph, os.path.basename(p), data)
        r = subprocess.run([sys.executable, os.path.join(HERE, "build-map.py"), "--src", out, "--graph", graph, "--out", out],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(r.stdout + r.stderr)
        print(r.stdout.strip())
        for tool in ("skeleton.py", "diff.py", "clusters.json"):
            write(out, "tools/" + tool, open(os.path.join(graph, tool), "rb").read())

    # The kit: skill, landing page, job templates, map checker; seed the ledger once.
    template = os.path.join(HERE, "template")
    for d, _, fs in os.walk(template):
        for f in fs:
            rel = os.path.relpath(os.path.join(d, f), template)
            if rel.startswith("ledger/") and os.path.exists(os.path.join(out, rel)):
                continue  # the ledger is the review repo's memory: seed it once, never overwrite
            write(out, rel, open(os.path.join(d, f), "rb").read())
    write(out, "ledger/KNOWN.md", files[KNOWN][1])
    write(out, "EXPORT.json", json.dumps({
        "source": SOURCE_URL, "commit": commit, "round": a.round,
        "exported_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "overlay": a.overlay, "submodules": subs,
    }, indent=2) + "\n")

    # Git: the submodules are gitlinks at the source repo's pinned commits.
    if not os.path.isdir(os.path.join(out, ".git")):
        subprocess.run(["git", "init", "-q", "-b", "main", out], check=True)
    run = lambda *args: subprocess.run(["git", "-C", out, *args], check=True, capture_output=True)
    run("add", "-A")
    for path, sha in subs.items():
        # An empty directory is what an uninitialised submodule looks like; without it a later
        # `git add -A` in the review repo sees the gitlink as deleted and drops lib/ silently.
        os.makedirs(os.path.join(out, path), exist_ok=True)
        run("update-index", "--add", "--cacheinfo", "160000,%s,%s" % (sha, path))
    if a.git_commit:
        run("commit", "-q", "-m",
            "Fren Review round %d: %s@%s" % (a.round, "Magic-Internet-Frens", commit[:12]))
    print("exported %s@%s -> %s  (%d source, %d compiled tests, %d reference tests, %d submodules)%s" % (
        "Magic-Internet-Frens", commit[:12], out, counts["source"], counts["tests"], counts["reference"], len(subs),
        "" if not a.overlay else "  overlay: " + ", ".join(a.overlay)))


if __name__ == "__main__":
    main()
