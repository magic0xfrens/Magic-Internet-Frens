#!/usr/bin/env python3
"""rebase.py <graph_dir> <cluster> <new_skeleton.json> <old_src_root> <new_src_root>

Rebuild <graph_dir>/<cluster>.json on a fresh skeleton, carrying the existing
semantic fields forward wherever they can still be true:

  * every citation — `(line N)` in the node's own file and `File.sol:N` in any
    file — is remapped through a line-level diff of that file between the
    graph's source tree (<old_src_root>) and the current tree (<new_src_root>);
  * unchanged body (same body_sha1)  -> fields carried with remapped citations
  * CHANGED body                     -> fields carried as a PREFILL; the node is
                                        listed for review, since its behaviour moved
  * ADDED                            -> fields left empty for extraction
  * any citation whose line was itself rewritten cannot be remapped; it is kept
    as-is and the node is listed (validate.py then decides).

Nodes are keyed like diff.py: (contract, name, normalized signature). The old
graph is kept as <cluster>.json.prev.
"""
import difflib
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from diff import name_of, norm  # noqa: E402

SEM = ["authority", "authority_gate_quote", "reads", "writes", "value", "edges", "reachability", "observations"]
_maps = {}


def find(root, base):
    for dp, _, fs in os.walk(root):
        if any(s in dp for s in ("/lib/", "/out/", "/cache/", "/test/", "/broadcast/")):
            continue
        if base in fs:
            return os.path.join(dp, base)
    return None


def line_map(old_root, new_root, base):
    if base not in _maps:
        po, pn = find(old_root, base), find(new_root, base)
        m = {}
        if po and pn:
            a = open(po, encoding="utf-8", errors="replace").read().split("\n")
            b = open(pn, encoding="utf-8", errors="replace").read().split("\n")
            for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
                if tag == "equal":
                    for k in range(i2 - i1):
                        m[i1 + k + 1] = j1 + k + 1
        _maps[base] = m
    return _maps[base]


def key(n):
    return (n["contract"], name_of(n), norm(n.get("signature", "")))


def remap(text, own, old_root, new_root, misses):
    def own_line(mt):
        n = int(mt.group(2))
        v = line_map(old_root, new_root, own).get(n)
        if v is None:
            misses.append("%s:%d" % (own, n))
            return mt.group(0)
        return mt.group(1) + str(v)

    def file_line(mt):
        base, n = mt.group(1), int(mt.group(2))
        v = line_map(old_root, new_root, base).get(n)
        if v is None:
            misses.append("%s:%d" % (base, n))
            return mt.group(0)
        return "%s:%d" % (base, v)

    text = re.sub(r"(\(line\s+)(\d+)", own_line, text)
    return re.sub(r"([A-Za-z0-9_$][A-Za-z0-9_.$-]*\.sol):(\d+)", file_line, text)


def main():
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    gdir, cluster, skel_path, old_root, new_root = sys.argv[1:]
    gp = os.path.join(gdir, cluster + ".json")
    old = json.load(open(gp))
    new = json.load(open(skel_path))
    by_key = {}
    for n in old["nodes"]:
        by_key.setdefault(key(n), []).append(n)
    report, stats = [], {"reused": 0, "prefilled": 0, "added": 0, "stale_cites": 0}
    for n in new["nodes"]:
        cands = by_key.get(key(n), [])
        if not cands:
            for f in SEM:
                n.pop(f, None)
            stats["added"] += 1
            report.append("ADDED     %s %s L%d" % (n["contract"], name_of(n) or n["kind"], n["line"]))
            continue
        same = [o for o in cands if o.get("body_sha1") == n.get("body_sha1")]
        o = same[0] if same else cands[0]
        own = os.path.basename(o["file"])
        misses = []
        for f in SEM:
            if f not in o:
                continue
            v = o[f]
            if isinstance(v, list):
                v = [remap(x, own, old_root, new_root, misses) if isinstance(x, str) else x for x in v]
            elif isinstance(v, str):
                v = remap(v, own, old_root, new_root, misses)
            n[f] = v
        if same:
            stats["reused"] += 1
        else:
            stats["prefilled"] += 1
            report.append("CHANGED   %s %s L%d (prefilled from old body; review)" % (n["contract"], name_of(n) or n["kind"], n["line"]))
        if misses:
            stats["stale_cites"] += 1
            report.append("STALECITE %s %s L%d: %s" % (n["contract"], name_of(n) or n["kind"], n["line"], ", ".join(sorted(set(misses)))[:200]))
    shutil.copy(gp, gp + ".prev")
    json.dump(new, open(gp, "w"), indent=1)
    print("%s: %d nodes; reused %d, changed-prefilled %d, added %d; nodes with unmappable cites %d" % (
        cluster, len(new["nodes"]), stats["reused"], stats["prefilled"], stats["added"], stats["stale_cites"]))
    for r in report:
        print("  " + r)


if __name__ == "__main__":
    main()
