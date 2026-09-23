#!/usr/bin/env python3
"""verify_deployed_bytecode.py <rpc> <name=address> ...

Compares each deployed runtime bytecode with the local artifact of that name
(contracts/solidity/out, the tree the deploy force-built). Immutable slots and
library link slots are masked on both sides, since they hold per-deployment
values; everything else, including the CBOR metadata hash that pins the exact
source and compiler settings, must match byte for byte. A name with several
artifacts (two solc versions) passes if any one matches.
Prints one line per contract and exits 1 on any mismatch.
"""
import glob
import json
import os
import subprocess
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "contracts", "solidity", "out")


def artifacts(name):
    hits = []
    for p in glob.glob(os.path.join(OUT, "*.sol", name + ".json")) + glob.glob(os.path.join(OUT, "*.sol", name + ".*.json")):
        d = json.load(open(p)).get("deployedBytecode") or {}
        code = (d.get("object") or "").lower().replace("0x", "")
        if code:
            masks = [(r["start"], r["length"]) for refs in (d.get("immutableReferences") or {}).values() for r in refs]
            masks += [(r["start"], r["length"]) for f in (d.get("linkReferences") or {}).values() for refs in f.values() for r in refs]
            hits.append((os.path.relpath(p, OUT), code, masks))
    return hits


def masked(hexcode, masks):
    b = bytearray.fromhex(hexcode)
    for s, n in masks:
        b[s:s + n] = bytes(n)
    return bytes(b)


def onchain(rpc, addr):
    r = subprocess.run(["cast", "code", addr, "--rpc-url", rpc], capture_output=True, text=True,
                       env=dict(os.environ, FOUNDRY_DISABLE_NIGHTLY_WARNING="1"))
    return r.stdout.strip().splitlines()[-1].lower().replace("0x", "") if r.stdout.strip() else ""


def main():
    rpc, pairs = sys.argv[1], sys.argv[2:]
    bad = 0
    for pair in pairs:
        name, addr = pair.split("=", 1)
        live = onchain(rpc, addr)
        arts = artifacts(name)
        if not live:
            print("NO CODE   %-22s %s" % (name, addr)); bad += 1; continue
        if not arts:
            print("NO ARTIFACT %-20s %s" % (name, addr)); bad += 1; continue
        ok = None
        for rel, code, masks in arts:
            art = code
            while "__$" in art:
                i = art.index("__$")
                art = art[:i] + "0" * 40 + art[i + 40:]
            if len(art) == len(live) and masked(art, masks) == masked(live, masks):
                ok = rel
                break
        if ok:
            print("MATCH     %-22s %s  (%s, %d bytes)" % (name, addr, ok, len(live) // 2))
        else:
            print("MISMATCH  %-22s %s  (live %d bytes; artifacts %s)" % (
                name, addr, len(live) // 2, ", ".join("%s %d" % (r, len(c) // 2) for r, c, _ in arts)))
            bad += 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
