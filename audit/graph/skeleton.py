#!/usr/bin/env python3
"""skeleton.py <src_root> <out_dir> [cluster]

Mechanically extract the per-cluster function-graph skeleton from a Solidity
tree.  Tokenizer-based: comments and string literals are masked out, brace and
paren depth are tracked, and no Solidity parser dependency is used.

"The skeleton is the universe" -- every declaration of kind
function | constructor | receive | fallback | modifier is emitted exactly once.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CLUSTERS_JSON = os.path.join(HERE, "clusters.json")

KEYWORDS = ("function", "constructor", "receive", "fallback", "modifier")
VISIBILITY = {"external", "public", "internal", "private"}
MUTABILITY = {"payable", "view", "pure", "constant"}
IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
UNIT_RE = re.compile(r"\b(abstract\s+contract|contract|library|interface)\s+([A-Za-z_$][A-Za-z0-9_$]*)")
KW_RE = re.compile(r"\b(function|constructor|receive|fallback|modifier)\b")


# ---------------------------------------------------------------- tokenizer
def mask(src):
    """Return (nocomment, masked).

    nocomment: comments -> spaces, string literals preserved.
    masked   : comments AND string/hex literals -> spaces.
    Both keep byte offsets and newlines identical to `src`.
    """
    n = len(src)
    nc = list(src)
    mk = list(src)
    i = 0
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                nc[k] = " "
                mk[k] = " "
            i = j
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if src[k] != "\n":
                    nc[k] = " "
                    mk[k] = " "
            i = j
        elif c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                if src[j] == "\n":      # unterminated; bail out safely
                    break
                j += 1
            for k in range(i, min(j, n)):
                if src[k] != "\n":
                    mk[k] = " "
            i = j
        else:
            i += 1
    return "".join(nc), "".join(mk)


def line_starts(src):
    out = [0]
    for i, ch in enumerate(src):
        if ch == "\n":
            out.append(i + 1)
    return out


def line_of(starts, off):
    lo, hi = 0, len(starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if starts[mid] <= off:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


def depth_map(masked):
    """brace depth *before* the character at each offset."""
    d = 0
    out = bytearray(len(masked) + 1)
    depths = []
    for ch in masked:
        depths.append(d)
        if ch == "{":
            d += 1
        elif ch == "}":
            d -= 1
    depths.append(d)
    return depths


def match_brace(masked, open_off):
    d = 0
    for i in range(open_off, len(masked)):
        if masked[i] == "{":
            d += 1
        elif masked[i] == "}":
            d -= 1
            if d == 0:
                return i
    return -1


def find_body_open(masked, start):
    """First '{' at paren depth 0 from `start`; stop at ';' (abstract unit)."""
    p = 0
    for i in range(start, len(masked)):
        c = masked[i]
        if c == "(":
            p += 1
        elif c == ")":
            p -= 1
        elif p == 0 and c == "{":
            return i
        elif p == 0 and c == ";":
            return -1
    return -1


def find_header_end(masked, start):
    """Offset of the '{' or ';' terminating a declaration header."""
    p = 0
    for i in range(start, len(masked)):
        c = masked[i]
        if c == "(":
            p += 1
        elif c == ")":
            p -= 1
        elif p == 0 and c in "{;":
            return i
    return -1


def skip_paren(masked, i):
    """`i` points at '('; return offset just past the matching ')'."""
    p = 0
    while i < len(masked):
        if masked[i] == "(":
            p += 1
        elif masked[i] == ")":
            p -= 1
            if p == 0:
                return i + 1
        i += 1
    return i


# ------------------------------------------------------------ header parsing
def parse_header(masked, src, kw_off, kw, hdr_end):
    """-> (name, visibility, mutability, modifiers, params_src)"""
    name = ""
    vis = ""
    mut = "nonpayable"
    mods = []
    i = kw_off + len(kw)
    seg = masked[i:hdr_end]
    if kw in ("function", "modifier"):
        m = IDENT.search(seg)
        if m:
            name = m.group(0)
            i = i + m.end()
    # parameter list (optional for a bare `modifier foo`)
    params = ""
    j = masked.find("(", i)
    if 0 <= j < hdr_end:
        k = skip_paren(masked, j)
        params = src[j + 1:k - 1]
        i = k
    # tail
    while i < hdr_end:
        c = masked[i]
        if c.isspace():
            i += 1
            continue
        m = IDENT.match(masked, i)
        if not m:
            i += 1
            continue
        tok = m.group(0)
        i = m.end()
        if tok in VISIBILITY:
            vis = tok
        elif tok in MUTABILITY:
            if tok != "constant":
                mut = tok
        elif tok == "virtual":
            pass
        elif tok in ("override", "returns"):
            nxt = i
            while nxt < hdr_end and masked[nxt].isspace():
                nxt += 1
            if nxt < hdr_end and masked[nxt] == "(":
                i = skip_paren(masked, nxt)
        else:
            nxt = i
            while nxt < hdr_end and masked[nxt].isspace():
                nxt += 1
            if nxt < hdr_end and masked[nxt] == "(":
                end = skip_paren(masked, nxt)
                mods.append(re.sub(r"\s+", " ", tok + src[nxt:end]).strip())
                i = end
            else:
                mods.append(tok)
    if kw in ("constructor", "receive", "fallback", "modifier"):
        vis = ""
    return name, vis, mut, mods, params


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


# ----------------------------------------------------------------- scanning
def scan_file(src_root, rel):
    path = os.path.join(src_root, rel)
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    nocomment, masked = mask(src)
    starts = line_starts(src)
    depths = depth_map(masked)
    stem = os.path.splitext(os.path.basename(rel))[0]
    base = os.path.basename(rel)

    # top-level units
    units = []          # (name, kind, body_open, body_close)
    for m in UNIT_RE.finditer(masked):
        if depths[m.start()] != 0:
            continue
        # a `contract`/`interface` word can only start a unit at depth 0
        o = find_body_open(masked, m.end())
        if o < 0:
            continue
        c = match_brace(masked, o)
        units.append((m.group(2), m.group(1).split()[-1], o, c))

    def unit_for(off):
        for nm, kind, o, c in units:
            if o < off < c:
                return nm, kind, o
        return None

    nodes = []
    notes = []
    for m in KW_RE.finditer(masked):
        off, kw = m.start(), m.group(1)
        prev = masked[:off].rstrip()
        if prev.endswith(".") or prev.endswith("$"):
            continue
        u = unit_for(off)
        d = depths[off]
        if u is None:
            if d != 0:
                continue
            cname = "<free> (declared in %s)" % base
            uo = None
        else:
            nm, ukind, uo = u
            if d != depths[uo] + 1:
                if kw in ("function", "constructor"):
                    notes.append((rel, line_of(starts, off), kw,
                                  "nested at brace depth %d inside %s (assembly/Yul or function type)" % (d, nm)))
                continue
            cname = nm if nm == stem else "%s (declared in %s)" % (nm, base)
        nxt = off + len(kw)
        while nxt < len(masked) and masked[nxt].isspace():
            nxt += 1
        if kw == "function":
            # `function (` with no name is a function *type*, not a declaration
            if nxt >= len(masked) or not IDENT.match(masked, nxt):
                notes.append((rel, line_of(starts, off), kw, "function type, not a declaration"))
                continue
        elif kw in ("receive", "fallback", "constructor"):
            if nxt >= len(masked) or masked[nxt] != "(":
                continue
        elif kw == "modifier":
            if nxt >= len(masked) or not IDENT.match(masked, nxt):
                continue
        he = find_header_end(masked, off)
        if he < 0:
            continue
        name, vis, mut, mods, _ = parse_header(masked, src, off, kw, he)
        sig = norm(src[off:he])
        if masked[he] == "{":
            close = match_brace(masked, he)
            body_nc = nocomment[he + 1:close]
            sha = hashlib.sha1(norm(body_nc).encode("utf-8")).hexdigest()
            blines = [line_of(starts, he), line_of(starts, close)]
        else:
            sha = ""
            blines = []
        nodes.append({
            "contract": cname, "file": rel, "line": line_of(starts, off),
            "kind": kw, "name": name, "signature": sig, "visibility": vis,
            "mutability": mut, "modifiers": mods, "body_sha1": sha,
            "body_lines": blines,
        })
    return nodes, len(starts), notes


def grep_count(src_root, rel):
    r = subprocess.run(
        ["grep", "-cE", r"^[[:space:]]*(function|constructor|receive|fallback|modifier)\b", rel],
        cwd=src_root, capture_output=True, text=True)
    try:
        return int(r.stdout.strip() or 0)
    except ValueError:
        return 0


def grep_lines(src_root, rel):
    r = subprocess.run(
        ["grep", "-nE", r"^[[:space:]]*(function|constructor|receive|fallback|modifier)\b", rel],
        cwd=src_root, capture_output=True, text=True)
    return [int(l.split(":", 1)[0]) for l in r.stdout.splitlines() if l.strip()]


def build(src_root, out_dir, cluster, files):
    nodes, fmap, notes = [], {}, []
    for rel in files:
        ns, lc, nt = scan_file(src_root, rel)
        nodes.extend(ns)
        fmap[rel] = lc
        notes.extend(nt)
    nodes.sort(key=lambda n: (n["file"], n["line"]))
    doc = {"cluster": cluster, "source_root": os.path.abspath(src_root),
           "generated": time.strftime("%Y-%m-%dT%H:%M:%S"), "files": fmap,
           "nodes": nodes}
    d = os.path.join(out_dir, "skeleton")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, cluster + ".json"), "w") as fh:
        json.dump(doc, fh, indent=1)
    return doc, notes


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: skeleton.py <src_root> <out_dir> [cluster]")
    src_root, out_dir = sys.argv[1], sys.argv[2]
    clusters = json.load(open(CLUSTERS_JSON))
    want = [sys.argv[3]] if len(sys.argv) > 3 else list(clusters)
    bad = 0
    for cl in want:
        doc, notes = build(src_root, out_dir, cl, clusters[cl])
        print("=== cluster %s: %d nodes, %d files" % (cl, len(doc["nodes"]), len(clusters[cl])))
        print("  %-42s %6s %6s" % ("file", "parsed", "grep"))
        for rel in clusters[cl]:
            p = sum(1 for n in doc["nodes"] if n["file"] == rel)
            g = grep_count(src_root, rel)
            flag = "" if p == g else "   <-- MISMATCH"
            print("  %-42s %6d %6d%s" % (rel, p, g, flag))
            if p != g:
                bad += 1
                mine = {n["line"] for n in doc["nodes"] if n["file"] == rel}
                theirs = set(grep_lines(src_root, rel))
                for ln in sorted(theirs - mine):
                    why = [t for t in notes if t[0] == rel and t[1] == ln]
                    print("      NOTE %s:%d grep-only -- %s" % (
                        rel, ln, why[0][3] if why else "unexplained"))
                for ln in sorted(mine - theirs):
                    print("      NOTE %s:%d parser-only -- declaration does not start its line" % (rel, ln))
    print("\nfiles with a residual mismatch: %d" % bad)


if __name__ == "__main__":
    main()
