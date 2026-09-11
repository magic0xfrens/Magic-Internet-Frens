#!/usr/bin/env python3
"""make_readme.py <graph_dir> <src_root> <validate_log_dir>

Assembles audit/graph/README.md from machine outputs only: the skeleton/graph JSON files, the
validator logs (`validate-<cluster>.log`, produced by validate.py), join.py, and CROSSCHECK.md if
present. Nothing in the README is typed from memory.
"""
import json
import os
import re
import subprocess
import sys
from datetime import date


def main():
    gdir, src, logdir = sys.argv[1:4]
    clusters = json.load(open(os.path.join(gdir, "clusters.json")))
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                            cwd=os.path.dirname(gdir)).stdout.strip()
    out = []
    out.append("# Cauldron function graph\n")
    out.append(f"Generated {date.today().isoformat()} at commit `{commit}` (branch snapshot of the working tree) "
               f"from the decontaminated source tree `{src}` (comment tags stripped; line numbers and body hashes "
               f"identical to `contracts/solidity` by construction; see `audit/FINAL_BLIND_2026-09-11/DECONTAMINATION.md`).\n")
    out.append("Extraction only: no severity judgment, no exploit narrative. Every node comes from `skeleton.py`; "
               "every number below comes from `validate.py`, `join.py`, or `CROSSCHECK.md`.\n")
    out.append("## Schema\n")
    out.append("Skeleton fields (mechanical, never edited by hand): `contract`, `file`, `line`, `kind` "
               "(function | constructor | receive | fallback | modifier), `name`, `signature` (declaration text up to `{` or `;`), "
               "`visibility`, `mutability`, `modifiers[]`, `body_lines`, `body_sha1` (sha1 of the body with comments removed and "
               "whitespace collapsed; empty for `;` bodies). Interfaces declared inside another file are named "
               "`\"IName (declared in File.sol)\"`.\n")
    out.append("Semantic fields (filled by extractors, machine-checked by the validator):\n")
    out.append("| field | meaning | check |\n|---|---|---|\n"
               "| `authority` | who can reach it: anyone, a role, `internal (callers: …)`, deployer | non-empty |\n"
               "| `authority_gate_quote` | the exact gating line as `<quote> (File.sol:N)` or `UNGATED` | substring of line N±1 |\n"
               "| `reads[]`, `writes[]` | storage only, as `name (line N)` / `(line N, immutable)` / `(line N, constant)` | name in `forge inspect storageLayout` ∪ immutables ∪ constants; identifier on line N |\n"
               "| `value` | `NONE` / receives native / sends native to X / ERC20 transfer of T to X, each with `(line N)` | identifier on line N |\n"
               "| `edges[]` | `Callee.fn (File.sol:N), TRUSTED|UNTRUSTED, in-cluster|out-of-cluster|delegatecall|library` | `fn` declared in-repo or under lib/, `fn` on line N |\n"
               "| `reachability` | prose: how a caller gets here, which gate, what state; every claim cites `` `id` File.sol:N `` or is tagged DERIVED | identifier on the cited line |\n"
               "| `observations[]` | comment-vs-code mismatches only, both sides cited | identifiers on cited lines |\n")
    out.append("TRUSTED = the callee's code is in this repo or a pinned lib; UNTRUSTED = an address a user or admin can point anywhere.\n")
    out.append("## Cluster map\n")
    out.append("| cluster | files |\n|---|---|")
    for c, v in clusters.items():
        files = v if isinstance(v, list) else v.get("files", [])
        out.append(f"| {c} | {', '.join('`%s`' % f for f in files)} |")
    out.append("")
    out.append("## How to re-run\n")
    out.append("```\ncd contracts/solidity && export FOUNDRY_PROFILE=cauldron && forge build\n"
               "python3 audit/graph/skeleton.py <src_root> audit/graph            # rebuild skeleton/<cluster>.json\n"
               "python3 audit/graph/diff.py audit/graph/skeleton/<c>.json audit/graph/<c>.json   # ADDED / REMOVED / CHANGED / MOVED nodes\n"
               "# re-extract only the CHANGED/ADDED nodes with a chunk file, then:\n"
               "python3 audit/graph/merge.py audit/graph <c> <chunk.json>\n"
               "python3 audit/graph/validate.py <src_root> audit/graph <c> [--partial]\n"
               "python3 audit/graph/join.py audit/graph\n"
               "python3 audit/graph/make_readme.py audit/graph <src_root> <validate_log_dir>\n```\n")
    # coverage per contract from validator logs
    out.append("## Coverage per contract (from validate.py)\n")
    out.append("| cluster | contract | skeleton nodes | graph nodes | with reachability | with edges | DERIVED | validator |\n|---|---|---|---|---|---|---|---|")
    totals = {}
    for c in clusters:
        lp = os.path.join(logdir, f"validate-{c}.log")
        if not os.path.exists(lp):
            out.append(f"| {c} | (no log) | | | | | | |")
            continue
        txt = open(lp).read()
        cov = re.search(r"^COVERAGE .*$", txt, re.M)
        rows = re.findall(r"^(\S.*?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$", txt, re.M)
        for r in rows:
            if r[0].startswith("contract") or r[0].startswith("COVERAGE"):
                continue
            out.append(f"| {c} | {r[0].strip()} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | |")
        totals[c] = cov.group(0) if cov else "no COVERAGE line"
    out.append("")
    out.append("| cluster | validator result |\n|---|---|")
    for c, v in totals.items():
        out.append(f"| {c} | `{v}` |")
    out.append("")
    # per-cluster totals from JSON
    out.append("## Per-cluster totals (from the graph JSON)\n")
    out.append("| cluster | nodes | external/public | authority = anyone | UNGATED | edges | UNTRUSTED edges | DERIVED tags | observations |\n|---|---|---|---|---|---|---|---|---|")
    grand = 0
    for c in clusters:
        p = os.path.join(gdir, c + ".json")
        if not os.path.exists(p):
            continue
        g = json.load(open(p))
        ns = g["nodes"]
        grand += len(ns)
        ext = sum(1 for n in ns if n.get("visibility") in ("external", "public"))
        anyone = sum(1 for n in ns if str(n.get("authority", "")).strip().lower().startswith("anyone"))
        ung = sum(1 for n in ns if str(n.get("authority_gate_quote", "")).strip() == "UNGATED")
        edges = sum(len(n.get("edges", [])) for n in ns)
        untr = sum(1 for n in ns for e in n.get("edges", []) if "UNTRUSTED" in str(e))
        der = sum(str(n.get("reachability", "")).count("DERIVED") + sum(str(o).count("DERIVED") for o in n.get("observations", [])) for n in ns)
        obs = sum(len(n.get("observations", [])) for n in ns)
        out.append(f"| {c} | {len(ns)} | {ext} | {anyone} | {ung} | {edges} | {untr} | {der} | {obs} |")
    out.append(f"\nTotal nodes: {grand}.\n")
    # join
    j = subprocess.run([sys.executable, os.path.join(gdir, "join.py"), gdir], capture_output=True, text=True).stdout
    out.append("## Cross-cluster edge join (from join.py)\n")
    out.append(j.strip() + "\n")
    # crosscheck
    cc = os.path.join(gdir, "CROSSCHECK.md")
    out.append("## Cross-check (from CROSSCHECK.md)\n")
    if os.path.exists(cc):
        txt = open(cc).read()
        out.append(txt.strip() + "\n")
    else:
        out.append("CROSSCHECK.md not present yet.\n")
    out.append("## Residual: what the validator cannot catch\n")
    out.append("The validator proves shape: every node exists in the skeleton, every cited line contains the named identifier, "
               "every gate quote is a real substring, every callee resolves, every storage name is in the compiled layout, every "
               "external selector matches the compiler. It does not prove that a `reachability` sentence is true, that an "
               "`authority` is complete (a gate hidden in a callee), or that a TRUSTED/UNTRUSTED label is right. Claims that could not "
               "be tied to a line carry the tag DERIVED; the per-cluster DERIVED counts above are the size of that residual. The cross-check "
               "section samples exactly those fields and re-derives them independently; its mismatch counts are the measured error rate.\n")
    out.append("Conventions that differ between extractors (found by the cross-check, kept as-is, read the field with this in mind): "
               "writes performed inside a modifier are attributed to the calling function in the registry cluster but to the modifier node in the nft cluster; "
               "an admin-settable protocol address (router, oracle, venue) is labelled TRUSTED in registry/rotation/perp and UNTRUSTED in hook/nft. "
               "The fix-up pass after the cross-check made PoolOps, CauldronGachaRouter, and CauldronFactory consistent with the rule \"UNTRUSTED = an address a user or admin can point elsewhere\".\n")
    out.append("Also outside the validator: public state-variable getters are part of the external surface but have no declaration node "
               "(the validator lists them as INFO per contract); contract creations (`new X`) are recorded in `value`/`reachability`, not as edges; "
               "and Yul functions inside `assembly` blocks are not nodes.\n")
    open(os.path.join(gdir, "README.md"), "w").write("\n".join(out))
    print("wrote", os.path.join(gdir, "README.md"))


if __name__ == "__main__":
    main()
