#!/usr/bin/env python3
"""build-map.py --src <solidity root> --graph <audit/graph dir> --out <dir>

The Fren Review map: every function in the Solidity tree, pinned to that tree.

Re-runs the mechanical skeleton (<graph>/skeleton.py) over <src>, then carries
each node's filled-in facts (authority, gate line, storage reads/writes, value
moved, call edges, reachability) over from the function graph — only as far as
they can be trusted:

  semantics = fresh    body_sha1 unchanged since the node was mapped
  semantics = stale    same function, body changed since: the facts describe
                       older code — read the source, treat them as a hint
  semantics = missing  function added after the graph was filled

Writes <out>/map/<cluster>.json and <out>/MAP.md. In the review repo,
tools/check-map.py proves the map still matches the source.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

SEMANTIC = ("authority", "authority_gate_quote", "reads", "writes", "value", "edges", "reachability", "observations")
# The order a reviewer should walk: value first, scaffolding last.
CLUSTER_ORDER = ("hook", "registry", "pool", "perp", "rotation", "nft", "governance", "seed", "art", "deploy")


def load_graphdiff(graph):
    spec = importlib.util.spec_from_file_location("graphdiff", os.path.join(graph, "diff.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(src, graph, out):
    gd = load_graphdiff(graph)
    key = lambda n: (n.get("contract", ""), gd.name_of(n), gd.sigkey(n.get("signature", "")))
    clusters = json.load(open(os.path.join(graph, "clusters.json")))
    summary = {}
    with tempfile.TemporaryDirectory() as tmp:
        r = subprocess.run([sys.executable, os.path.join(graph, "skeleton.py"), src, tmp], capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("skeleton.py failed:\n" + r.stdout[-2000:] + r.stderr[-2000:])
        os.makedirs(os.path.join(out, "map"), exist_ok=True)
        for c in CLUSTER_ORDER:
            skel = json.load(open(os.path.join(tmp, "skeleton", c + ".json")))
            filled = {}
            gpath = os.path.join(graph, c + ".json")
            if os.path.exists(gpath):
                for n in json.load(open(gpath))["nodes"]:
                    filled.setdefault(key(n), n)
            nodes = []
            for n in skel["nodes"]:
                old = filled.get(key(n))
                m = dict(n)
                if old is None:
                    m["semantics"] = "missing"
                else:
                    for f in SEMANTIC:
                        if f in old:
                            m[f] = old[f]
                    m["semantics"] = "fresh" if (old.get("body_sha1") or "") == (n.get("body_sha1") or "") else "stale"
                nodes.append(m)
            with open(os.path.join(out, "map", c + ".json"), "w") as f:
                json.dump({"cluster": c, "files": clusters[c], "nodes": nodes}, f, indent=1, sort_keys=True)
                f.write("\n")
            summary[c] = nodes
    write_index(os.path.join(out, "MAP.md"), summary, clusters)
    return summary


def source_digest(summary):
    h = hashlib.sha256()
    for c in CLUSTER_ORDER:
        for n in summary[c]:
            h.update(("%s|%s|%s|%s\n" % (n["file"], n.get("line"), n["contract"], n.get("body_sha1", ""))).encode())
    return h.hexdigest()


def is_entry(n):
    """Something an outside transaction can call that can change state."""
    return (
        n.get("kind") in ("function", "receive", "fallback")
        and n.get("visibility") in ("external", "public")
        and n.get("mutability") not in ("view", "pure")
        and bool(n.get("body_sha1"))  # skip interface declarations
    )


def cell(s, limit):
    s = " ".join(str(s or "").split()).replace("|", "\\|")
    return s if len(s) <= limit else s[: limit - 1] + "…"


def write_index(path, summary, clusters):
    total = sum(len(v) for v in summary.values())
    lines = [
        "# The map of the machine",
        "",
        "Every function in this repository's Solidity, pinned to the source in this commit (%d functions)." % total,
        "`python3 tools/check-map.py` proves it still matches.",
        "",
        "Source digest: `%s`" % source_digest(summary),
        "",
        "Per-function facts live in `map/<cluster>.json`: `authority`, `authority_gate_quote`,",
        "`reads`, `writes`, `value`, `edges` (TRUSTED/UNTRUSTED), `reachability`, `observations`.",
        "`semantics` says how far to trust them:",
        "",
        "- **fresh** — code unchanged since the node was mapped",
        "- **stale** — code changed since: the facts describe older code, read the source",
        "- **missing** — function added after mapping: read the source",
        "",
        "Below: the **entry points** (externally callable, state-changing) per cluster, in review order.",
        "",
        "| cluster | files | functions | fresh | stale | missing | entry points |",
        "|---|---|---|---|---|---|---|",
    ]
    for c in CLUSTER_ORDER:
        ns = summary[c]
        cnt = {s: sum(1 for n in ns if n.get("semantics") == s) for s in ("fresh", "stale", "missing")}
        lines.append("| %s | %d | %d | %d | %d | %d | %d |" % (
            c, len(clusters[c]), len(ns), cnt["fresh"], cnt["stale"], cnt["missing"], sum(1 for n in ns if is_entry(n))))
    for c in CLUSTER_ORDER:
        entries = [n for n in summary[c] if is_entry(n)]
        lines += ["", "## %s" % c, "", "Files: %s" % ", ".join("`%s`" % f for f in clusters[c]), ""]
        if not entries:
            lines.append("(no state-changing entry points)")
            continue
        lines += ["| function | where | who can call | value | map |", "|---|---|---|---|---|"]
        for n in sorted(entries, key=lambda n: (n["contract"], n.get("line") or 0)):
            fn = "%s.%s" % (n["contract"], n.get("name") or n.get("kind"))
            lines.append("| `%s` | %s:%s | %s | %s | %s |" % (
                cell(fn, 60), n["file"], n.get("line"),
                cell(n.get("authority", "?"), 70), cell(n.get("value", "?"), 50), n.get("semantics")))
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", required=True)
    ap.add_argument("--graph", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    summary = build(os.path.abspath(a.src), os.path.abspath(a.graph), os.path.abspath(a.out))
    print("map: %d functions, %d entry points -> %s" % (
        sum(len(v) for v in summary.values()), sum(1 for v in summary.values() for n in v if is_entry(n)), a.out))


if __name__ == "__main__":
    main()
