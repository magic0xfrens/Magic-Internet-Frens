#!/usr/bin/env python3
"""libfns.py <src_root> <graph_dir>

Writes <graph_dir>/cache/libfns.json in the per-type form validate.py and join.py
require: {"IPositionManager": ["ownerOf", ...], ...}. Only the dependency types in
validate.EXT_ALLOW are emitted. Each type's methods are the functions declared in
its body plus those of every base it inherits, found by scanning the Solidity
under <src_root>/lib. A legacy flat list cannot say which type owns a name, so
the validators fail closed on it; this replaces it.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate import EXT_ALLOW  # noqa: E402

RE_DECL = re.compile(r"\b(?:abstract\s+)?(contract|library|interface)\s+(\w+)\s*(?:is\s+([^{]*))?\{")
RE_FN = re.compile(r"\bfunction\s+(\w+)\s*\(")
RE_COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)


def body_end(src, i):
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return j
    return len(src)


def scan(root):
    fns, bases = {}, {}
    for dp, _, fs in os.walk(os.path.join(root, "lib")):
        for f in fs:
            if not f.endswith(".sol"):
                continue
            try:
                src = RE_COMMENT.sub("", open(os.path.join(dp, f), encoding="utf-8", errors="replace").read())
            except OSError:
                continue
            for m in RE_DECL.finditer(src):
                name = m.group(2)
                end = body_end(src, m.end() - 1)
                fns.setdefault(name, set()).update(RE_FN.findall(src[m.end():end]))
                for b in (m.group(3) or "").split(","):
                    b = re.sub(r"\(.*", "", b).strip()
                    if b:
                        bases.setdefault(name, set()).add(b)
    return fns, bases


def closure(name, fns, bases, seen=None):
    seen = seen if seen is not None else set()
    if name in seen:
        return set()
    seen.add(name)
    out = set(fns.get(name, ()))
    for b in bases.get(name, ()):
        out |= closure(b, fns, bases, seen)
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root, gdir = sys.argv[1:]
    fns, bases = scan(root)
    out = {n: sorted(closure(n, fns, bases)) for n in sorted(EXT_ALLOW) if n in fns}
    os.makedirs(os.path.join(gdir, "cache"), exist_ok=True)
    with open(os.path.join(gdir, "cache", "libfns.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    missing = sorted(EXT_ALLOW - set(out))
    print("libfns: %d dependency types written%s" % (len(out), ("; not found: " + ", ".join(missing)) if missing else ""))


if __name__ == "__main__":
    main()
