#!/usr/bin/env python3
"""Strip finding-ID tags (R-02, B-05, S02, Q-01, L-3, V-1 ...) from Solidity COMMENTS ONLY.

Never changes the number of lines. Never touches code, string literals, or identifiers.
Also runs the verification pass (identical line counts, no finding-shaped hits).

Usage:
  decontaminate.py strip  <blind_root> <log.json>
  decontaminate.py verify <real_root> <blind_root> <report.md>

<root> is the directory holding CauldronHook.sol (contracts/solidity). Symlinks (lib/) are
not followed. Only *.sol files are rewritten.
"""
import json
import os
import re
import sys

TAG = re.compile(r"\b([A-Z]{1,2})-?([0-9]{1,2})\b")
# Technical tokens that look like finding IDs but are not.
EXCLUDE = {
    "V2", "V3", "V4", "L1", "L2", "L3",
    "Q64", "Q96", "Q128", "X64", "X96", "X128", "X192",
    "U8", "U16", "U32", "U64", "U96", "I8", "I16", "I24", "I32", "I64",
    "G0", "G1", "G2", "G3",  # generation shorthand used in lifecycle prose
}
# Tokens preceded by these prefixes are standard identifiers, never findings.
PREFIX_EXCLUDE = re.compile(r"(EIP|ERC|BIP|CAIP|ISO|RFC|SLIP)[- ]?$")


def comment_spans(text):
    """Yield (start, end) offsets of every comment in Solidity source, skipping string literals."""
    i, n = 0, len(text)
    spans = []
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            q = c
            i += 1
            while i < n and text[i] != q:
                if text[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        if c == "/" and i + 1 < n:
            d = text[i + 1]
            if d == "/":
                j = text.find("\n", i)
                if j == -1:
                    j = n
                spans.append((i, j))
                i = j
                continue
            if d == "*":
                j = text.find("*/", i + 2)
                j = n if j == -1 else j + 2
                spans.append((i, j))
                i = j
                continue
        i += 1
    return spans


def strip_line(line, subs, path, lineno):
    """Remove finding tags from one comment line; record each substitution."""
    def repl(m):
        tok = m.group(0)
        norm = m.group(1) + m.group(2)
        if "-" not in tok and norm in EXCLUDE:
            return tok
        if PREFIX_EXCLUDE.search(line[: m.start()]):
            return tok
        subs.append({"file": path, "line": lineno, "tag": tok})
        return "\x00"

    out = TAG.sub(repl, line)
    if "\x00" not in out:
        return line
    # Tidy the hole the tag left, without touching anything else on the line.
    out = re.sub(r"\x00\s*[:/]\s*", "", out)            # "B-05: text" -> "text", "B-05/B-06" -> "B-06"
    out = re.sub(r"\(\s*\x00\s*\)", "", out)             # "(B-05)" -> ""
    out = re.sub(r"\[\s*\x00\s*\]", "", out)             # "[B-05]" -> ""
    out = re.sub(r"\(\s*\x00\s*,\s*", "(", out)          # "(B-05, B-06)" -> "(B-06)"
    out = re.sub(r",\s*\x00\s*\)", ")", out)             # "(B-05, B-06)" -> "(B-05)"
    out = re.sub(r",\s*\x00", "", out)                   # "x, B-05" -> "x"
    out = re.sub(r"\x00\s*,\s*", "", out)                # "B-05, x" -> "x"
    out = re.sub(r"\(\s*\x00\s+", "(", out)              # "(B-05 fix)" -> "(fix)"
    out = re.sub(r"\s+\x00\s*\)", ")", out)              # "(see B-05)" -> "(see)"
    out = re.sub(r"\s+\x00", "", out)                    # " B-05" -> ""
    out = re.sub(r"\x00\s*", "", out)                    # anything left
    out = re.sub(r"\(\s*\)", "", out)                    # empty parens left behind
    out = re.sub(r"\(\s*(fix|fixed|see)\s*\)", "", out)  # "(fix)" alone says nothing
    out = re.sub(r"(?<=\S)  +(?=\S)", " ", out)          # inner double spaces
    out = re.sub(r"[ \t]+$", "", out)                     # trailing space
    return out


def strip_file(path, subs):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    spans = comment_spans(text)
    if not spans:
        return False
    pieces, last = [], 0
    for s, e in spans:
        pieces.append(text[last:s])
        seg = text[s:e]
        lineno = text.count("\n", 0, s) + 1
        new_lines = []
        for k, ln in enumerate(seg.split("\n")):
            new_lines.append(strip_line(ln, subs, path, lineno + k))
        pieces.append("\n".join(new_lines))
        last = e
    pieces.append(text[last:])
    new = "".join(pieces)
    if new.count("\n") != text.count("\n"):
        raise SystemExit(f"LINE COUNT CHANGED in {path}: refusing to write")
    if new != text:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
        return True
    return False


def sol_files(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if not os.path.islink(os.path.join(d, x)) and x not in ("out", "cache", "lib")]
        for fn in files:
            if fn.endswith(".sol"):
                yield os.path.join(d, fn)


def cmd_strip(root, logpath):
    subs, changed = [], 0
    for p in sorted(sol_files(root)):
        if strip_file(p, subs):
            changed += 1
    freq = {}
    for s in subs:
        freq[s["tag"]] = freq.get(s["tag"], 0) + 1
    with open(logpath, "w") as f:
        json.dump({"files_changed": changed, "substitutions": len(subs), "tag_frequency": freq, "subs": subs}, f, indent=1)
    print(f"files changed: {changed}; substitutions: {len(subs)}")
    for t, c in sorted(freq.items(), key=lambda x: -x[1]):
        print(f"  {t:8s} {c}")


def all_text_files(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if not os.path.islink(os.path.join(d, x)) and x not in ("out", "cache", "lib", "node_modules")]
        for fn in files:
            p = os.path.join(d, fn)
            if os.path.islink(p):
                continue
            if fn.endswith((".sol", ".md", ".txt", ".toml", ".json", ".ts", ".mjs", ".sh", ".py")):
                yield p


def cmd_verify(real, blind, report):
    lines = []
    ok = True
    # 1. line counts identical for every .sol present in both trees
    real_counts = {os.path.relpath(p, real): sum(1 for _ in open(p, encoding="utf-8")) for p in sol_files(real)}
    blind_counts = {os.path.relpath(p, blind): sum(1 for _ in open(p, encoding="utf-8")) for p in sol_files(blind)}
    mismatch = [(k, real_counts[k], blind_counts[k]) for k in blind_counts if k in real_counts and real_counts[k] != blind_counts[k]]
    only_real = sorted(k for k in real_counts if k not in blind_counts)
    only_blind = sorted(k for k in blind_counts if k not in real_counts)
    lines.append(f"## Line counts\n- .sol files in real tree: {len(real_counts)}; in blind tree: {len(blind_counts)}")
    lines.append(f"- files with differing line counts: {len(mismatch)}")
    for k, a, b in mismatch:
        lines.append(f"  - MISMATCH {k}: real {a} vs blind {b}")
        ok = False
    lines.append(f"- files only in real tree (quarantined/excluded): {len(only_real)}")
    for k in only_real:
        lines.append(f"  - {k}")
    if only_blind:
        lines.append(f"- files only in blind tree (unexpected): {only_blind}")
        ok = False
    # 2. finding-shaped hits anywhere in the blind tree
    hy = re.compile(r"\b[A-Z]{1,2}-[0-9]{1,2}\b")
    hits_h, hits_nh, hits_code = [], [], []
    for p in all_text_files(blind):
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        in_comment = None
        if p.endswith(".sol"):
            spans = comment_spans(text)
            def in_comment(off, spans=spans):
                return any(s <= off < e for s, e in spans)
        off = 0
        for i, ln in enumerate(text.split("\n"), 1):
            for m in hy.finditer(ln):
                if PREFIX_EXCLUDE.search(ln[: m.start()]):
                    continue
                rec = (os.path.relpath(p, blind), i, m.group(0), ln.strip()[:120])
                if in_comment is not None and not in_comment(off + m.start()):
                    hits_code.append(rec)      # inside code or a string literal: cannot strip
                else:
                    hits_h.append(rec)
            for m in TAG.finditer(ln):
                tok = m.group(0)
                if "-" in tok:
                    continue
                norm = m.group(1) + m.group(2)
                if norm in EXCLUDE or PREFIX_EXCLUDE.search(ln[: m.start()]):
                    continue
                hits_nh.append((os.path.relpath(p, blind), i, tok, ln.strip()[:120]))
            off += len(ln) + 1
    lines.append(f"\n## Hyphenated finding-shaped hits in comments/prose (must be 0): {len(hits_h)}")
    for h in hits_h[:200]:
        lines.append(f"  - {h[0]}:{h[1]} `{h[2]}` :: {h[3]}")
    if hits_h:
        ok = False
    lines.append(f"\n## Hyphenated hits inside code or string literals (residual leak, not stripped): {len(hits_code)}")
    for h in hits_code[:100]:
        lines.append(f"  - {h[0]}:{h[1]} `{h[2]}` :: {h[3]}")
    freq = {}
    for h in hits_nh:
        freq[h[2]] = freq.get(h[2], 0) + 1
    lines.append(f"\n## Hyphenless letter+digit tokens remaining (residual, classify each): {len(hits_nh)}")
    for t, c in sorted(freq.items(), key=lambda x: -x[1])[:60]:
        ex = next(h for h in hits_nh if h[2] == t)
        lines.append(f"  - `{t}` x{c}  e.g. {ex[0]}:{ex[1]} :: {ex[3]}")
    # 3. file names carrying tags
    named = sorted({os.path.relpath(p, blind) for p in all_text_files(blind) if TAG.search(os.path.basename(p)) and not any(x in os.path.basename(p) for x in EXCLUDE)})
    lines.append(f"\n## File names carrying a letter+digit prefix (residual leak, cannot be renamed without breaking citations): {len(named)}")
    for k in named:
        lines.append(f"  - {k}")
    lines.insert(0, f"# Decontamination verification\n\nRESULT: {'PASS' if ok else 'FAIL'}\n")
    with open(report, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("PASS" if ok else "FAIL", f"line-mismatch={len(mismatch)} comment-hits={len(hits_h)} code-hits={len(hits_code)} hyphenless-residual={len(hits_nh)}")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "strip":
        cmd_strip(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == "verify":
        sys.exit(cmd_verify(sys.argv[2], sys.argv[3], sys.argv[4]))
    else:
        print(__doc__)
        sys.exit(2)
