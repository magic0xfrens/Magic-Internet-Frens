#!/usr/bin/env python3
"""join.py <graph_dir>

Resolves every edge across all cluster graphs to a graph node, compiler getter, low-level operation,
or allowlisted dependency method. Prints, per cluster: edges, scope-label counts, resolutions across
all scopes, unresolved, and malformed; then the unresolved list as `cluster | contract.fn | edge
text`. Missing/malformed/unresolved inputs return 1.
"""
import json
import os
import re
import sys
from compiler_edges import AddressOperations

RE_EDGE = re.compile(r"^\s*(.+?)\.([A-Za-z_$][\w$]*)\s*\(([\w./-]+\.sol):(\d+)\)\s*,\s*"
                     r"(TRUSTED|UNTRUSTED)\s*,\s*"
                     r"(in-cluster|out-of-cluster|delegatecall|library)\s*$")
LOWLEVEL = {"call", "delegatecall", "staticcall", "transfer", "send"}
DEPENDENCY_CONTRACTS = {
    "IPoolManager", "PoolManager", "IPositionManager", "PositionManager", "IHooks", "Hooks",
    "Currency", "CurrencyLibrary", "IERC20", "SafeERC20", "IERC721", "IERC1155",
    "IERC20Metadata", "SafeTransferLib", "Address", "Math", "FullMath", "FixedPointMathLib", "TickMath",
    "StateLibrary", "TransientStateLibrary", "LPFeeLibrary", "BalanceDeltaLibrary", "Permit2",
    "IAllowanceTransfer", "IUnlockCallback", "AggregatorV3Interface", "IWETH", "IWETH9",
    "IERC165", "ERC721", "ERC2981", "Ownable", "ReentrancyGuard", "Pausable", "EnumerableSet",
    "PoolIdLibrary", "LiquidityAmounts", "Base64", "Strings", "Vm", "IVotes",
}


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def edge_target_resolves(callee, fn, scope, by_cf, getters, libfns):
    """Return the resolution class, requiring an exact first-party contract match."""
    # A name such as transfer/call is not proof of an address operation. It may
    # be an ordinary contract method or a stale prose target; require identity.
    if (callee, fn) in by_cf:
        return "node"
    if fn in getters.get(callee, set()):
        return "node"
    # Scope is descriptive, not proof: require the named dependency type too.
    if (callee in DEPENDENCY_CONTRACTS and isinstance(libfns, dict)
            and isinstance(libfns.get(callee), (list, set, tuple))
            and fn in libfns[callee]):
        return "dependency"
    return None


def run(gdir, compiler_path=None, source_root=None):
    address_ops = None
    if compiler_path is not None and source_root is not None:
        address_ops = AddressOperations(load_json(compiler_path), source_root)
    try:
        clusters = load_json(os.path.join(gdir, "clusters.json"))
    except Exception as exc:
        print("FATAL: clusters.json does not parse: %s" % exc)
        return 1
    names = list(clusters)
    graphs = {}
    load_errors = []
    for c in names:
        p = os.path.join(gdir, c + ".json")
        if os.path.exists(p):
            try:
                graph = load_json(p)
                if not isinstance(graph, dict) or not isinstance(graph.get("nodes"), list):
                    raise ValueError("top-level object must contain a nodes list")
                graphs[c] = graph
            except Exception as exc:
                load_errors.append((c, str(exc)))
    libfns = {}
    lp = os.path.join(gdir, "cache", "libfns.json")
    if os.path.exists(lp):
        data = load_json(lp)
        # Legacy flat names cannot establish which dependency owns a method.
        libfns = data if isinstance(data, dict) else {}
    # public getters have no skeleton node: resolve them through the compiler's method identifiers
    getters = {}
    cdir = os.path.join(gdir, "cache")
    if os.path.isdir(cdir):
        for fn_ in os.listdir(cdir):
            if fn_.endswith(".methodIdentifiers.json"):
                cname = fn_[: -len(".methodIdentifiers.json")].split(":")[-1]
                try:
                    data = load_json(os.path.join(cdir, fn_))
                    if isinstance(data, dict) and "__error__" in data:
                        continue
                    keys = data.keys() if isinstance(data, dict) else data
                    getters[cname] = {k.split("(")[0] for k in keys}
                except Exception:
                    pass
    # Exact first-party index. A method name on contract A never resolves B.method.
    by_cf = {}
    for c, g in graphs.items():
        for n in g["nodes"]:
            cn = n["contract"].split(" (declared in ")[0]
            fn = n.get("name") or n.get("kind")
            by_cf[(cn, fn)] = c
    unresolved, rows = [], []
    for c, g in graphs.items():
        tot = inn = out = node = lib = ops = declarations = unres = malformed = 0
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
                else:
                    out += 1
                # Explicit compiler mode must not fall back to unpinned name or
                # getter caches when source/caller/location evidence is absent.
                resolved = (None if address_ops is not None else
                            edge_target_resolves(callee, fn, scope, by_cf, getters, libfns))
                if resolved is None and address_ops is not None and address_ops.declaration(
                        n, callee + "." + fn, fb, int(ln)):
                    declarations += 1
                    continue
                if resolved is None and address_ops is not None and address_ops.matches(
                        n, callee + "." + fn, fb, int(ln)):
                    # Classification only: runtime callee/selector still dynamic.
                    ops += 1
                    continue
                if resolved == "dependency":
                    lib += 1
                    continue
                if resolved == "node":
                    node += 1
                else:
                    unres += 1
                    unresolved.append((c, n["contract"], n.get("name"), str(e)[:120]))
        rows.append((c, tot, inn, out, node, lib, declarations, ops, unres, malformed))
    print("| cluster | edges | in-cluster label | other scope label | resolved to node | resolved to dependency | compiler declaration (implementation unverified) | typed address operation (runtime target unverified) | unresolved | malformed |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    missing = [c for c in names if c not in graphs]
    if missing:
        print("\nclusters without a graph yet: " + ", ".join(missing))
    if load_errors:
        print("\nclusters with invalid graph JSON:")
        for c, why in load_errors:
            print("- %s | %s" % (c, why))
    print("\nUnresolved edges (%d):" % len(unresolved))
    for c, cn, fn, e in unresolved:
        print("- %s | %s.%s | %s" % (c, cn, fn, e))
    return 1 if missing or load_errors or unresolved else 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    gdir = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
    return run(gdir, argv[1] if len(argv) > 1 else None,
               argv[2] if len(argv) > 2 else None)


if __name__ == "__main__":
    sys.exit(main())
