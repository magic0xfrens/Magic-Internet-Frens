#!/usr/bin/env python3
"""join.py <graph_dir>

Joins every out-of-cluster / delegatecall / library edge across all cluster graphs to a node in
another cluster's graph, or to a function declared under lib/ (cache/libfns.json). Prints, per
cluster: edges, in-cluster, out-of-cluster, resolved-to-node, resolved-to-lib, unresolved; then the
unresolved list as `cluster | contract.fn | edge text`. Exit code 0 always (this is a report).
"""
import json
import os
import re
import sys

RE_EDGE = re.compile(r"^\s*(.+?)\.([A-Za-z_$][\w$]*)\s*\(([\w./-]+\.sol):(\d+)\)\s*,\s*(TRUSTED|UNTRUSTED)\s*,\s*([\w-]+)\s*$")
LOWLEVEL = {"call", "delegatecall", "staticcall", "transfer", "send"}


def main():
    gdir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    clusters = json.load(open(os.path.join(gdir, "clusters.json")))
    names = list(clusters)
    graphs = {}
    for c in names:
        p = os.path.join(gdir, c + ".json")
        if os.path.exists(p):
            graphs[c] = json.load(open(p))
    libfns = set()
    lp = os.path.join(gdir, "cache", "libfns.json")
    if os.path.exists(lp):
        libfns = set(json.load(open(lp)))
    # public getters have no skeleton node: resolve them through the compiler's method identifiers
    getters = {}
    cdir = os.path.join(gdir, "cache")
    if os.path.isdir(cdir):
        for fn_ in os.listdir(cdir):
            if fn_.endswith(".methodIdentifiers.json"):
                cname = fn_[: -len(".methodIdentifiers.json")].split(":")[-1]
                try:
                    keys = json.load(open(os.path.join(cdir, fn_)))
                    keys = keys.keys() if isinstance(keys, dict) else keys
                    getters[cname] = {k.split("(")[0] for k in keys}
                except Exception:
                    pass
    # index: (contract, fn) -> cluster ; fn -> set(clusters) ; contract -> cluster
    by_cf, by_f, by_c = {}, {}, {}
    for c, g in graphs.items():
        for n in g["nodes"]:
            cn = n["contract"].split(" (declared in ")[0]
            fn = n.get("name") or n.get("kind")
            by_cf[(cn, fn)] = c
            by_f.setdefault(fn, set()).add(c)
            by_c[cn] = c
    unresolved, rows = [], []
    for c, g in graphs.items():
        tot = inn = out = node = lib = unres = malformed = 0
        for n in g["nodes"]:
            for e in n.get("edges", []):
                tot += 1
                m = RE_EDGE.match(str(e))
                if m and m.group(1).strip().split(".")[-1] in ("", ):
                    m = None
                if not m:
                    malformed += 1
                    unresolved.append((c, n["contract"], n.get("name"), "MALFORMED: " + str(e)[:100]))
                    continue
                callee, fn, fb, ln, trust, scope = m.groups()
                if scope == "in-cluster":
                    inn += 1
                    continue
                out += 1
                if fn in LOWLEVEL:
                    lib += 1
                    continue
                if (callee, fn) in by_cf or (callee in by_c and fn in by_f) or (fn in by_f and callee not in by_c and len(by_f[fn]) >= 1):
                    node += 1
                elif callee in getters and fn in getters[callee]:
                    node += 1  # public getter of an in-repo contract (no declaration node by construction)
                elif fn in libfns:
                    lib += 1
                else:
                    unres += 1
                    unresolved.append((c, n["contract"], n.get("name"), str(e)[:120]))
        rows.append((c, tot, inn, out, node, lib, unres, malformed))
    print("| cluster | edges | in-cluster | out-of-cluster | resolved to node | resolved to lib/low-level | unresolved | malformed |")
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    missing = [c for c in names if c not in graphs]
    if missing:
        print("\nclusters without a graph yet: " + ", ".join(missing))
    print("\nUnresolved edges (%d):" % len(unresolved))
    for c, cn, fn, e in unresolved:
        print("- %s | %s.%s | %s" % (c, cn, fn, e))


if __name__ == "__main__":
    main()
