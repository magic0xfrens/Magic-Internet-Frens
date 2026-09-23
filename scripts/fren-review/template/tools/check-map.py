#!/usr/bin/env python3
"""check-map.py — prove map/ describes the Solidity in this checkout.

Re-extracts every function with tools/skeleton.py and compares each one's file,
line and body hash with map/<cluster>.json. Any drift means the map is from a
different commit: trust the source, not the map.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
IDENT = ("file", "contract", "kind", "name", "signature", "line", "body_sha1")


def ident(n):
    return tuple(n.get(k) for k in IDENT)


def main():
    clusters = json.load(open(os.path.join(ROOT, "tools", "clusters.json")))
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "skeleton.py"), ROOT, tmp],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("skeleton.py failed:\n" + r.stdout[-1500:] + r.stderr[-1500:])
        for c in clusters:
            fresh = sorted(ident(n) for n in json.load(open(os.path.join(tmp, "skeleton", c + ".json")))["nodes"])
            mapped = sorted(ident(n) for n in json.load(open(os.path.join(ROOT, "map", c + ".json")))["nodes"])
            if fresh != mapped:
                bad.append("%s (%d in source, %d in map)" % (c, len(fresh), len(mapped)))
    if bad:
        sys.exit("map does NOT match this source: " + ", ".join(bad))
    print("map matches this source: every function, line and body hash")


if __name__ == "__main__":
    main()
