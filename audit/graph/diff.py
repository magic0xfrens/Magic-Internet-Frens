#!/usr/bin/env python3
"""diff.py <new_graph_or_skeleton.json> <old_graph.json>

Keys nodes by (contract, name, signature).  Reports ADDED / REMOVED /
CHANGED / MOVED.  CHANGED needs body_sha1 on BOTH sides; graphs written
before body_sha1 existed therefore cannot report CHANGED at all.
"""
import json
import os
import re
import sys


def norm(s):
    return re.sub(r"\s+", " ", s or "").strip()


NAME_RE = re.compile(r"^(function\s+|modifier\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\(")
UNNAMED = ("constructor", "receive", "fallback")


def name_of(n):
    """Older graphs carry no `name` field -- derive it from the signature."""
    if n.get("name") is not None:
        return n["name"]
    m = NAME_RE.match(norm(n.get("signature", "")))
    if not m:
        return ""
    if not m.group(1) and m.group(2) in UNNAMED:
        return ""
    return m.group(2)


def sigkey(s):
    """Canonical signature for keying across graph schema generations.

    Older graphs (a) drop the leading `function `/`modifier ` keyword and
    (b) hand-collapse multi-line parameter lists.  Neither is a code change,
    so neither may show up as churn.
    """
    s = norm(s)
    s = re.sub(r"^(?:function|modifier)\s+", "", s)
    s = re.sub(r"\(\s+", "(", s)
    s = re.sub(r"\s+\)", ")", s)
    s = re.sub(r"\s+,", ",", s)
    s = re.sub(r",(?=\S)", ", ", s)
    return s


def load(p):
    d = json.load(open(p))
    ns = d["nodes"] if isinstance(d, dict) else d
    out = {}
    for n in ns:
        k = (n.get("contract", ""), name_of(n), sigkey(n.get("signature", "")))
        out.setdefault(k, []).append(n)
    return d if isinstance(d, dict) else {}, out


def fmt(k, n):
    return "%s.%s  %s  (line %s)" % (k[0], k[1] or "<unnamed>", k[2][:110], n.get("line", "?"))


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: diff.py <new.json> <old.json>")
    newp, oldp = sys.argv[1], sys.argv[2]
    ndoc, new = load(newp)
    odoc, old = load(oldp)
    old_has_sha = any(n.get("body_sha1") for lst in old.values() for n in lst)

    added, removed, changed, moved = [], [], [], []
    for k in new:
        if k not in old:
            added += [(k, n) for n in new[k]]
    for k in old:
        if k not in new:
            removed += [(k, n) for n in old[k]]
    for k in set(new) & set(old):
        a, b = new[k][0], old[k][0]
        sa, sb = a.get("body_sha1"), b.get("body_sha1")
        if sa and sb:
            if sa != sb:
                changed.append((k, a, b))
        elif a.get("line") != b.get("line"):
            moved.append((k, a, b))

    out = []
    out.append("NEW : %s  (%d nodes, %d keys)" % (os.path.basename(newp), sum(len(v) for v in new.values()), len(new)))
    out.append("OLD : %s  (%d nodes, %d keys)" % (os.path.basename(oldp), sum(len(v) for v in old.values()), len(old)))
    if not old_has_sha:
        out.append("NOTE: the old graph carries no body_sha1, so CHANGED cannot be computed for it.")
        out.append("      A node whose body was rewritten in place, on the same line, is INVISIBLE to this diff.")
        out.append("      Same-key nodes that moved line are reported as MOVED instead.")
    out.append("")
    out.append("COUNTS  added=%d  removed=%d  changed=%d  moved=%d" % (
        len(added), len(removed), len(changed), len(moved)))
    for label, lst in (("ADDED", added), ("REMOVED", removed)):
        out.append("")
        out.append("%s (%d)" % (label, len(lst)))
        for k, n in sorted(lst, key=lambda x: (x[0][0], x[1].get("line", 0) or 0)):
            out.append("  + " + fmt(k, n) if label == "ADDED" else "  - " + fmt(k, n))
        if not lst:
            out.append("  (none)")
    out.append("")
    out.append("CHANGED (%d)" % len(changed))
    for k, a, b in sorted(changed, key=lambda x: (x[0][0], x[1].get("line", 0) or 0)):
        out.append("  ~ %s  body_sha1 %s -> %s" % (fmt(k, a), b.get("body_sha1", "")[:8], a.get("body_sha1", "")[:8]))
    if not changed:
        out.append("  (none%s)" % ("" if old_has_sha else " -- not computable, old graph has no body_sha1"))
    out.append("")
    out.append("MOVED (%d)" % len(moved))
    for k, a, b in sorted(moved, key=lambda x: (x[0][0], x[1].get("line", 0) or 0)):
        out.append("  > %s.%s  line %s -> %s" % (k[0], k[1] or "<unnamed>", b.get("line"), a.get("line")))
    if not moved:
        out.append("  (none)")
    print("\n".join(out))


if __name__ == "__main__":
    main()
