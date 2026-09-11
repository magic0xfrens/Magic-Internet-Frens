#!/usr/bin/env python3
"""merge.py <graph_dir> <cluster> <chunk.json>

Applies a chunk of semantic fields onto <graph_dir>/<cluster>.json (created from the skeleton on
first use). A chunk is a JSON list of objects; each must carry the node key
{"contract", "line"} (and optionally "signature" for disambiguation) plus any of the semantic
fields: authority, authority_gate_quote, reads, writes, value, edges, reachability, observations.
Skeleton fields can never be changed through this script. Unknown keys and unknown nodes are
errors. Prints how many nodes were updated and how many are still unfilled.
"""
import json
import os
import shutil
import sys

SEM = {"authority", "authority_gate_quote", "reads", "writes", "value", "edges", "reachability", "observations"}
KEY = {"contract", "line", "signature"}


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    gdir, cluster, chunk_path = sys.argv[1:]
    sk = os.path.join(gdir, "skeleton", cluster + ".json")
    gp = os.path.join(gdir, cluster + ".json")
    if not os.path.exists(gp):
        shutil.copy(sk, gp)
    g = json.load(open(gp))
    chunk = json.load(open(chunk_path))
    if not isinstance(chunk, list):
        sys.exit("chunk must be a JSON list")
    index = {}
    for n in g["nodes"]:
        index.setdefault((n["contract"], n["line"]), []).append(n)
    errors, updated = [], 0
    for i, u in enumerate(chunk):
        bad = set(u) - SEM - KEY
        if bad:
            errors.append("chunk[%d]: unknown keys %s" % (i, sorted(bad)))
            continue
        if "contract" not in u or "line" not in u:
            errors.append("chunk[%d]: needs contract and line" % i)
            continue
        cands = index.get((u["contract"], u["line"]), [])
        if "signature" in u:
            cands = [c for c in cands if c["signature"] == u["signature"]]
        if len(cands) != 1:
            errors.append("chunk[%d]: %d nodes match %s L%s" % (i, len(cands), u["contract"], u["line"]))
            continue
        n = cands[0]
        for f in SEM:
            if f in u:
                n[f] = u[f]
        updated += 1
    if errors:
        print("\n".join(errors))
        sys.exit(1)
    json.dump(g, open(gp, "w"), indent=1)
    unfilled = sum(1 for n in g["nodes"] if not str(n.get("authority", "")).strip())
    print("updated %d nodes; %d of %d still unfilled" % (updated, unfilled, len(g["nodes"])))


if __name__ == "__main__":
    main()
