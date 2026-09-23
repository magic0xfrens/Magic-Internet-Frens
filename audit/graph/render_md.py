#!/usr/bin/env python3
"""render_md.py <graph_dir> <src_root>

Renders every <cluster>.json in clusters.json to <cluster>.md: one section per
contract, one entry per node with every semantic field. The JSON stays canonical;
the Markdown is a reading copy and is regenerated, never edited.
"""
import json
import os
import sys


def fmt_list(v):
    if not v:
        return "none"
    return "; ".join("`%s`" % x for x in v)


def fmt_text(v):
    if v is None or (isinstance(v, str) and not v.strip()):
        return "none"
    if isinstance(v, list):
        return " ".join(str(x) for x in v) or "none"
    return str(v)


def render(gdir, src, cluster, files):
    g = json.load(open(os.path.join(gdir, cluster + ".json")))
    nodes = g["nodes"]
    out = ["# Function graph — `%s`\n" % cluster,
           "Current source-derived semantic map: **%d nodes** across **%d files**. The JSON file is canonical; "
           "this document renders every semantic field for review.\n" % (len(nodes), len(files)),
           "## Source files\n", "| file | lines |", "|---|---:|"]
    for f in files:
        try:
            n = sum(1 for _ in open(os.path.join(src, f), encoding="utf-8", errors="replace"))
        except OSError:
            n = 0
        out.append("| `%s` | %d |" % (f, n))
    out.append("")
    current = None
    for n in nodes:
        if n["contract"] != current:
            current = n["contract"]
            out.append("\n## `%s`\n" % current)
        out.append("### `%s/%s` — %s:%d\n" % (n.get("name") or n.get("kind"), n.get("kind"),
                                              os.path.basename(n["file"]), n["line"]))
        out.append("- Signature: `%s`" % " ".join(str(n.get("signature", "")).split()))
        out.append("- Authority: %s" % fmt_text(n.get("authority")))
        out.append("- Gate evidence: `%s`" % fmt_text(n.get("authority_gate_quote")))
        out.append("- Reads: %s" % fmt_list(n.get("reads")))
        out.append("- Writes: %s" % fmt_list(n.get("writes")))
        out.append("- Value: %s" % fmt_text(n.get("value")))
        out.append("- Reachability: %s" % fmt_text(n.get("reachability")))
        out.append("- Edges: %s" % fmt_list(n.get("edges")))
        obs = n.get("observations") or []
        out.append("- Observations: %s" % ("none" if not obs else " | ".join(str(o) for o in obs)))
        out.append("")
    with open(os.path.join(gdir, cluster + ".md"), "w") as fh:
        fh.write("\n".join(out).rstrip() + "\n")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    gdir, src = sys.argv[1:]
    clusters = json.load(open(os.path.join(gdir, "clusters.json")))
    for c, files in clusters.items():
        render(gdir, src, c, files)
        print("rendered %s.md" % c)


if __name__ == "__main__":
    main()
