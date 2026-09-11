#!/usr/bin/env python3
"""validate.py <src_root> <graph_dir> <cluster> [--skeleton-only] [--partial]
  --partial: nodes whose `authority` is still empty are skipped for R2-R8 (R1 still runs on all);
             use it after each contract chunk, and run without it before you finish.

Validates a filled function graph against the mechanically-extracted skeleton.
Rules R1..R8; each failure prints `entry index | rule | why`; exit 1 if any.
"""
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CLUSTERS = json.load(open(os.path.join(HERE, "clusters.json")))

SKEL_FIELDS = ["contract", "file", "line", "kind", "name", "signature",
               "visibility", "mutability", "modifiers", "body_sha1"]
SEM_FIELDS = ["authority", "authority_gate_quote", "reads", "writes", "value",
              "edges", "reachability", "observations"]
PROSE_FIELDS = ["authority", "reachability", "observations", "value", "edges"]

ELEMENTARY = {"address", "bool", "string", "bytes"}
ELEMENTARY |= {"uint%d" % b for b in range(8, 264, 8)}
ELEMENTARY |= {"int%d" % b for b in range(8, 264, 8)}
ELEMENTARY |= {"bytes%d" % b for b in range(1, 33)}

EXT_ALLOW = {"IPoolManager", "PoolManager", "IPositionManager", "PositionManager",
             "IHooks", "Hooks", "Currency", "CurrencyLibrary", "IERC20", "SafeERC20",
             "IERC721", "IERC1155", "IERC20Metadata", "SafeTransferLib", "Address",
             "Math", "FixedPointMathLib", "TickMath", "StateLibrary",
             "TransientStateLibrary", "LPFeeLibrary", "BalanceDeltaLibrary", "Permit2",
             "IAllowanceTransfer", "IUnlockCallback", "AggregatorV3Interface", "IWETH",
             "IWETH9", "IERC165", "Ownable", "ReentrancyGuard", "Pausable", "EnumerableSet"}
LOWLEVEL = {"call", "delegatecall", "transfer", "send", "staticcall"}
ID_EXCL = {"V2", "V3", "V4", "L1", "L2", "Q64", "Q96", "Q128", "X96", "X128", "X192"}

RE_LINEREF = re.compile(r"\(line\s+(\d+)(?:\s*,\s*(immutable|constant))?\)")
RE_FILEREF = re.compile(r"([A-Za-z0-9_$]+\.sol):(\d+)")
RE_EDGE = re.compile(r"^(.+?)\s*\(([A-Za-z0-9_$]+\.sol):(\d+)\)\s*,\s*"
                     r"(TRUSTED|UNTRUSTED)\s*,\s*"
                     r"(in-cluster|out-of-cluster|delegatecall|library)\s*$")
RE_GATE = re.compile(r"^(.*)\s*\(([A-Za-z0-9_$]+\.sol):(\d+)\)\s*$", re.S)
RE_TAG = re.compile(r"\b([A-Z]{1,2})(-?)([0-9]{1,2})\b")
RE_ID = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
RE_IMMCONST = re.compile(r"\b(?:immutable|constant)\s+([A-Za-z_$][A-Za-z0-9_$]*)")
RE_UNITKIND = re.compile(r"\b(abstract\s+contract|contract|library|interface)\s+%s\b")


def norm(s):
    return re.sub(r"\s+", " ", s or "").strip()


class Ctx(object):
    def __init__(self, src_root, graph_dir, cluster):
        self.root = os.path.abspath(src_root)
        self.gdir = os.path.abspath(graph_dir)
        self.cluster = cluster
        self.cache = os.path.join(self.gdir, "cache")
        os.makedirs(self.cache, exist_ok=True)
        self._lines = {}
        self._files = None
        self._libfns = None
        self._srcfns = None
        self._immconst = {}
        self._mi = {}
        self._sl = {}
        self._unitkind = {}

    # ---- files
    def index(self):
        if self._files is None:
            idx = {}
            skip = ("/lib/", "/out/", "/cache/", "/broadcast/", "/test/", "/audit/")
            for dp, dn, fn in os.walk(self.root):
                rel = "/" + os.path.relpath(dp, self.root).replace(os.sep, "/") + "/"
                if any(s in rel for s in skip):
                    continue
                for f in fn:
                    if f.endswith(".sol"):
                        idx.setdefault(f, os.path.join(dp, f))
            # cluster files win on ambiguity
            for r in CLUSTERS[self.cluster]:
                idx[os.path.basename(r)] = os.path.join(self.root, r)
            self._files = idx
        return self._files

    def resolve(self, base):
        return self.index().get(base)

    def lines(self, path):
        if path not in self._lines:
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    self._lines[path] = fh.read().split("\n")
            except IOError:
                self._lines[path] = None
        return self._lines[path]

    def line(self, path, n):
        ls = self.lines(path)
        if ls is None or n < 1 or n > len(ls):
            return None
        return ls[n - 1]

    def word_on(self, path, n, word):
        ln = self.line(path, n)
        if ln is None:
            return False
        return re.search(r"(?<![A-Za-z0-9_$])%s(?![A-Za-z0-9_$])" % re.escape(word), ln) is not None

    # ---- greps (cached once)
    def libfns(self):
        if self._libfns is None:
            cache = os.path.join(self.gdir, "cache", "libfns.json")
            if os.path.exists(cache):
                self._libfns = set(json.load(open(cache)))
                return self._libfns
            libdir = os.path.realpath(os.path.join(self.root, "lib"))  # lib may be a symlink
            r = subprocess.run(["grep", "-RhoE",
                                r"\b(function|modifier) +[A-Za-z_$][A-Za-z0-9_$]*",
                                libdir, "--include=*.sol"],
                               capture_output=True, text=True)
            self._libfns = {l.split()[-1] for l in r.stdout.splitlines() if l.split()}
            if self._libfns:
                json.dump(sorted(self._libfns), open(cache, "w"))
        return self._libfns

    def srcfns(self):
        if self._srcfns is None:
            s = set()
            for base, path in self.index().items():
                txt = "\n".join(self.lines(path) or [])
                for m in re.finditer(r"\b(function|modifier)\s+([A-Za-z_$][A-Za-z0-9_$]*)", txt):
                    s.add(m.group(2))
            self._srcfns = s
        return self._srcfns

    def immconst(self, path):
        if path not in self._immconst:
            txt = "\n".join(self.lines(path) or [])
            self._immconst[path] = set(RE_IMMCONST.findall(txt))
        return self._immconst[path]

    def unitkind(self, path, name):
        k = (path, name)
        if k not in self._unitkind:
            txt = "\n".join(self.lines(path) or [])
            m = re.search(RE_UNITKIND.pattern % re.escape(name), txt)
            self._unitkind[k] = (m.group(1).split()[-1] if m else "contract",
                                 "abstract" in (m.group(1) if m else ""))
        return self._unitkind[k]

    # ---- forge
    def forge(self, relpath, name, what):
        key = "%s.%s.json" % (name, what)
        p = os.path.join(self.cache, key)
        if os.path.exists(p):
            try:
                return json.load(open(p))
            except ValueError:
                pass
        env = dict(os.environ, FOUNDRY_PROFILE="cauldron")
        r = subprocess.run(["forge", "inspect", "%s:%s" % (relpath, name), what, "--json"],
                           cwd=self.root, capture_output=True, text=True, env=env)
        try:
            out = json.loads(r.stdout)
        except ValueError:
            out = {"__error__": (r.stderr or r.stdout)[:200]}
        with open(p, "w") as fh:
            json.dump(out, fh, indent=1)
        return out

    def method_ids(self, relpath, name):
        k = (relpath, name)
        if k not in self._mi:
            d = self.forge(relpath, name, "methodIdentifiers")
            self._mi[k] = {} if "__error__" in d else d
        return self._mi[k]

    def layout(self, relpath, name):
        k = (relpath, name)
        if k not in self._sl:
            d = self.forge(relpath, name, "storageLayout")
            self._sl[k] = set() if "__error__" in d else {
                e.get("label") for e in (d.get("storage") or [])}
        return self._sl[k]


# ------------------------------------------------------------------ helpers
def split_top(s):
    out, d, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        if ch == "," and d == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out if x.strip()]


def params_of(sig):
    i = sig.find("(")
    if i < 0:
        return []
    d, j = 0, i
    while j < len(sig):
        if sig[j] == "(":
            d += 1
        elif sig[j] == ")":
            d -= 1
            if d == 0:
                break
        j += 1
    return split_top(sig[i + 1:j])


def canon_type(p):
    p = re.sub(r"\b(memory|calldata|storage)\b", " ", p)
    p = re.sub(r"\s*(\[[^\]]*\])\s*", r"\1 ", p)
    toks = p.split()
    if not toks:
        return None
    if len(toks) > 1 and RE_ID.fullmatch(toks[-1]) and toks[-1] != "payable":
        toks = toks[:-1]
    if len(toks) > 1 and toks[-1] == "payable":
        toks = toks[:-1]
    if len(toks) != 1:
        return None
    t = toks[0]
    base = re.sub(r"(\[[^\]]*\])+$", "", t)
    arr = t[len(base):]
    if base == "uint":
        base = "uint256"
    elif base == "int":
        base = "int256"
    elif base == "byte":
        base = "bytes1"
    if base not in ELEMENTARY:
        return None
    return base + arr


def sentences(text):
    return re.split(r"(?<=[.;!?])\s+", text)


def prose_of(v):
    if isinstance(v, list):
        return "\n".join(str(x) for x in v)
    return str(v or "")


# -------------------------------------------------------------------- rules
def run(src_root, graph_dir, cluster, skeleton_only, partial=False):
    ctx = Ctx(src_root, graph_dir, cluster)
    sk_path = os.path.join(graph_dir, "skeleton", cluster + ".json")
    gr_path = sk_path if skeleton_only else os.path.join(graph_dir, cluster + ".json")
    fails = []

    def fail(idx, rule, why):
        fails.append((idx, rule, why))

    # ---- R8a: parses
    try:
        sk = json.load(open(sk_path))
    except Exception as e:
        print("FATAL: skeleton does not parse: %s" % e)
        return 1
    try:
        gr = json.load(open(gr_path))
    except Exception as e:
        print("- | R8 | graph JSON does not parse: %s" % e)
        return 1

    snodes, gnodes = sk["nodes"], gr["nodes"]

    # ---- R1 bijection
    def key(n):
        return (n["contract"], n["line"], norm(n["signature"]))
    smap = {}
    for n in snodes:
        smap.setdefault(key(n), []).append(n)
    seen = {}
    for i, g in enumerate(gnodes):
        k = key(g)
        if k not in smap:
            fail(i, "R1", "graph node not in skeleton: %s L%d %s" % (k[0], k[1], k[2][:70]))
            continue
        seen[k] = seen.get(k, 0) + 1
        if seen[k] > len(smap[k]):
            fail(i, "R1", "duplicate graph node for %s L%d" % (k[0], k[1]))
            continue
        s = smap[k][seen[k] - 1]
        for f in SKEL_FIELDS:
            if f not in g:
                fail(i, "R1", "missing skeleton field %r" % f)
            elif g[f] != s[f]:
                fail(i, "R1", "skeleton field %r altered: %r != %r" % (f, g[f], s[f]))
    for k, lst in smap.items():
        if seen.get(k, 0) < len(lst):
            fail("-", "R1", "skeleton node absent from graph: %s L%d %s" % (k[0], k[1], k[2][:70]))

    # index nodes by contract for layout lookups
    cluster_contracts = {}
    for n in snodes:
        nm = n["contract"].split(" (declared in ")[0]
        if nm == "<free>":
            continue
        cluster_contracts.setdefault((n["file"], nm), True)

    unresolved_edges = []

    for i, g in enumerate(gnodes):
        nfile = g.get("file", "")
        npath = os.path.join(ctx.root, nfile)
        cname = g.get("contract", "").split(" (declared in ")[0]

        if partial and not norm(prose_of(g.get("authority"))):
            continue  # unfilled chunk: R1 already checked it, semantic rules wait

        # ---- R8 semantic fields
        empty_ok = skeleton_only
        for f in SEM_FIELDS:
            if f not in g:
                if not empty_ok:
                    fail(i, "R8", "missing semantic field %r" % f)
                continue
            if f in ("reads", "writes", "edges", "observations") and not isinstance(g[f], list):
                fail(i, "R8", "%r must be a list" % f)
        if not empty_ok:
            if not norm(prose_of(g.get("reachability"))):
                fail(i, "R8", "reachability must be non-empty prose")
            if not norm(prose_of(g.get("authority"))):
                fail(i, "R8", "authority must be non-empty")

        if not skeleton_only:
            # ---- R3 gate quote
            gq = norm(prose_of(g.get("authority_gate_quote")))
            if gq and gq != "UNGATED":
                m = RE_GATE.match(gq)
                if not m:
                    fail(i, "R3", "gate quote is neither UNGATED nor `<quote> (File.sol:N)`: %r" % gq[:80])
                else:
                    q, fb, ln = norm(m.group(1)), m.group(2), int(m.group(3))
                    p = ctx.resolve(fb)
                    if p is None:
                        fail(i, "R3", "gate quote file %s not found" % fb)
                    else:
                        ctxt = norm(" ".join(
                            [ctx.line(p, x) or "" for x in (ln - 1, ln, ln + 1)]))
                        if q not in ctxt:
                            fail(i, "R3", "gate quote %r not found in %s:%d+/-1" % (q[:60], fb, ln))
            elif not gq and not empty_ok:
                fail(i, "R8", "authority_gate_quote empty (use UNGATED)")

            # ---- R2/R5 reads & writes
            for fld in ("reads", "writes"):
                for ent in (g.get(fld) or []):
                    ent = str(ent)
                    m = RE_LINEREF.search(ent)
                    if not m:
                        fail(i, "R2", "%s entry lacks `(line N)`: %r" % (fld, ent[:70]))
                        continue
                    ln, tag = int(m.group(1)), m.group(2)
                    nm = ent[:m.start()].strip().rstrip(",")
                    last = nm.split(".")[-1].split("[")[0].strip()
                    first = nm.split(".")[0].split("[")[0].strip()
                    if not ctx.word_on(npath, ln, last):
                        fail(i, "R2", "%s: %r not on %s:%d" % (fld, last, nfile, ln))
                    # R5
                    if first in ("msg", "block", "tx", "abi", "this", "address"):
                        fail(i, "R5", "%s: %r is not storage" % (fld, nm))
                        continue
                    ok = first in ctx.immconst(npath)
                    if not ok:
                        kind, _abstract = ctx.unitkind(npath, cname) if cname else ("contract", False)
                        if kind == "contract" and not _abstract:
                            ok = first in ctx.layout(nfile, cname)
                        else:
                            for (cf_, cn) in cluster_contracts:
                                if first in ctx.layout(cf_, cn):
                                    ok = True
                                    break
                    if not ok:
                        fail(i, "R5", "%s: %r not in storage layout of %s (nor immutable/constant in %s)"
                             % (fld, first, cname or "<free>", os.path.basename(nfile)))

            # ---- R2/R4 edges
            for ent in (g.get("edges") or []):
                ent = str(ent).strip()
                m = RE_EDGE.match(ent)
                if not m:
                    fail(i, "R4", "edge malformed: %r" % ent[:90])
                    continue
                callee_fn, fb, ln = m.group(1).strip(), m.group(2), int(m.group(3))
                if "." in callee_fn:
                    callee, fn = callee_fn.rsplit(".", 1)
                else:
                    callee, fn = "", callee_fn
                p = ctx.resolve(fb)
                if p is None and fn not in LOWLEVEL:
                    fail(i, "R2", "edge file %s not found" % fb)
                elif p is not None and not ctx.word_on(p, ln, fn):
                    fail(i, "R2", "edge: %r not on %s:%d" % (fn, fb, ln))
                # R4 resolution
                if fn in LOWLEVEL:
                    ok = True
                elif fn in ctx.srcfns():
                    ok = True
                elif fn in ctx.libfns():
                    ok = True
                elif callee in EXT_ALLOW and fn in ctx.libfns():
                    ok = True
                else:
                    ok = False
                if not ok:
                    fail(i, "R4", "edge callee %s.%s unresolved" % (callee, fn))
                    unresolved_edges.append("%s.%s" % (callee, fn))

            # ---- R2 prose refs
            for fld in ("reachability", "observations", "value"):
                txt = prose_of(g.get(fld))
                for sent in sentences(txt):
                    for m in RE_FILEREF.finditer(sent):
                        fb, ln = m.group(1), int(m.group(2))
                        before = sent[:m.start()]
                        ticks = re.findall(r"`([^`]+)`", before)
                        if not ticks:
                            fail(i, "R2", "%s: prose reference has no identifier (%s:%d)" % (fld, fb, ln))
                            continue
                        ident = RE_ID.findall(ticks[-1])
                        ident = ident[-1] if ident else ticks[-1]
                        p = ctx.resolve(fb)
                        if p is None:
                            fail(i, "R2", "%s: prose file %s not found" % (fld, fb))
                        elif not ctx.word_on(p, ln, ident):
                            fail(i, "R2", "%s: %r not on %s:%d" % (fld, ident, fb, ln))
                    for m in RE_LINEREF.finditer(sent):
                        ln = int(m.group(1))
                        ticks = re.findall(r"`([^`]+)`", sent[:m.start()])
                        if not ticks:
                            fail(i, "R2", "%s: prose reference has no identifier (line %d)" % (fld, ln))
                            continue
                        ident = RE_ID.findall(ticks[-1])
                        ident = ident[-1] if ident else ticks[-1]
                        if not ctx.word_on(npath, ln, ident):
                            fail(i, "R2", "%s: %r not on %s:%d" % (fld, ident, nfile, ln))

            # ---- R7 finding-ID tags
            for fld in PROSE_FIELDS:
                txt = prose_of(g.get(fld))
                for m in RE_TAG.finditer(txt):
                    tok = m.group(0)
                    if tok in ID_EXCL:
                        continue
                    pre = txt[max(0, m.start() - 4):m.start()]
                    if re.search(r"(EIP|ERC|BIP)-$", pre):
                        continue
                    fail(i, "R7", "%s: finding-ID tag %r" % (fld, tok))

    # ---- R6 selectors
    targets = {}
    for i, n in enumerate(gnodes):
        cn = n.get("contract", "").split(" (declared in ")[0]
        if cn == "<free>" or not n.get("file"):
            continue
        targets.setdefault((n["file"], cn), []).append((i, n))
    with cf.ThreadPoolExecutor(8) as ex:
        list(ex.map(lambda k: ctx.method_ids(k[0], k[1]), list(targets)))
    info_unmatched = {}
    for (relf, cn), ns in sorted(targets.items()):
        mids = ctx.method_ids(relf, cn)
        matched = set()
        for i, n in ns:
            if n.get("kind") != "function" or n.get("visibility") not in ("external", "public"):
                continue
            ps = params_of(n["signature"])
            types = [canon_type(p) for p in ps]
            if all(types):
                cand = "%s(%s)" % (n["name"], ",".join(types))
                if cand in mids:
                    matched.add(cand)
                    continue
                hits = [k for k in mids if k.split("(")[0] == n["name"]
                        and len(split_top(k[k.find("(") + 1:-1])) == len(ps)]
                if hits:
                    matched.update(hits)
                    fail(i, "R6", "%s.%s: exact selector %s absent; name/arity match %s"
                         % (cn, n["name"], cand, hits))
                else:
                    fail(i, "R6", "%s.%s: no methodIdentifiers entry (tried %s)" % (cn, n["name"], cand))
            else:
                hits = [k for k in mids if k.split("(")[0] == n["name"]
                        and len(split_top(k[k.find("(") + 1:-1])) == len(ps)]
                if hits:
                    matched.update(hits)
                else:
                    fail(i, "R6", "%s.%s: no methodIdentifiers entry by name+arity(%d)"
                         % (cn, n["name"], len(ps)))
        left = sorted(set(mids) - matched)
        if left:
            info_unmatched[cn] = left

    # ---------------------------------------------------------- report
    for idx, rule, why in fails:
        print("%s | %s | %s" % (idx, rule, why))
    if info_unmatched:
        tot = sum(len(v) for v in info_unmatched.values())
        print("\nINFO: %d methodIdentifiers entries unmatched by any node (public state-var getters):" % tot)
        for cn in sorted(info_unmatched):
            print("  %-28s %s" % (cn, ", ".join(info_unmatched[cn])))
    if unresolved_edges:
        print("\nUNRESOLVED EDGE CALLEES: %s" % ", ".join(sorted(set(unresolved_edges))))

    print("\n%-46s %5s %5s %5s %5s %8s" % ("contract", "skel", "graph", "reach", "edges", "DERIVED"))
    order = []
    for n in snodes:
        if n["contract"] not in order:
            order.append(n["contract"])
    for c in order:
        s = sum(1 for n in snodes if n["contract"] == c)
        gs = [n for n in gnodes if n.get("contract") == c]
        r = sum(1 for n in gs if norm(prose_of(n.get("reachability"))))
        e = sum(1 for n in gs if n.get("edges"))
        dv = sum(len(re.findall(r"\bDERIVED\b", " ".join(prose_of(n.get(f)) for f in PROSE_FIELDS)))
                 for n in gs)
        print("%-46s %5d %5d %5d %5d %8d" % (c[:46], s, len(gs), r, e, dv))
    print("COVERAGE %s: %d/%d nodes, %d failures" % (cluster, len(gnodes), len(snodes), len(fails)))
    return 1 if fails else 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if len(args) < 3:
        sys.exit("usage: validate.py <src_root> <graph_dir> <cluster> [--skeleton-only] [--partial]")
    sys.exit(run(args[0], args[1], args[2], "--skeleton-only" in flags, "--partial" in flags))


if __name__ == "__main__":
    main()
