"""Final mechanical gates. Writes remediation/FINAL_GATES.json; never infers semantic sign-off."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parent.parent
SOL = ROOT / "contracts/solidity"
BASE = json.loads((REPORT / "BASELINE.json").read_text())
SKIP = set(BASE["excluded_path_parts"])


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


out = {}

# 1. Frozen snapshot integrity: every baseline hash must still match its snapshot copy.
bad = [rel for rel, h in BASE["sha256"].items()
       if not (REPORT / "snapshot" / rel).is_file() or sha(REPORT / "snapshot" / rel) != h]
out["snapshot_integrity"] = {"files": len(BASE["sha256"]), "mismatched_or_missing": bad}

# 2. Working tree versus frozen baseline (same exclusions as freeze.py).
current = {}
for top in ("contracts/solidity", "compressed-traits"):
    for p in sorted((ROOT / top).rglob("*")):
        rel = p.relative_to(ROOT)
        if any(part in SKIP or part.startswith(".env") for part in rel.parts) or not p.is_file():
            continue
        current[str(rel)] = sha(p)
changed = sorted(r for r in BASE["sha256"] if r in current and current[r] != BASE["sha256"][r])
removed = sorted(r for r in BASE["sha256"] if r not in current)
added = sorted(r for r in current if r not in BASE["sha256"])
fp = set(BASE["first_party_solidity"])
out["tree_vs_baseline"] = {
    "first_party_changed": [r for r in changed if r in fp],
    "other_changed": [r for r in changed if r not in fp],
    "removed": removed,
    "added_solidity": [r for r in added if r.endswith(".sol")],
    "added_other_count": len([r for r in added if not r.endswith(".sol")]),
    "first_party_current_sha256": {r: current[r] for r in sorted(fp)},
}

# 3. Consumer selector parity against LOCAL source-matched artifacts (no RPC).
inv = json.loads((REPORT / "remediation/CANDIDATE_ARTIFACT_INVENTORY.json").read_text())
fresh = {(a["contract"], a["source"]): a for a in inv["artifacts"] if a["all_metadata_inputs_match"]}


def artifact(contract):
    hits = [a for (c, _), a in fresh.items() if c == contract and not a["artifact"].count("/") > 2]
    hits = hits or [a for (c, _), a in fresh.items() if c == contract]
    if not hits:
        return None
    return json.loads((SOL / hits[0]["artifact"]).read_text())


def sel(sig):
    return subprocess.check_output(["cast", "sig", sig], text=True).strip()[2:].lower()


REQUIRED = {  # scripts/verify-selectors.mjs REQUIRED, keyed by implementing contract
    "CauldronGachaRouter": ["play(uint256,uint256,uint256,uint256,uint256)",
                            "playChurn(uint256,uint256,uint256,uint256)", "openReady(uint256)"],
    "NativeQuoteZap": ["zap((address,address,uint24,int24,address),uint256)"],
    "CauldronCollection": ["reveal(uint256)", "revealBatch(uint256[])"],
    "CauldronVault": ["redeem(uint256)"],
    "CauldronRegistry": ["currentGeneration()", "currentToken()", "generationQuote(uint256)",
                         "generationPoolId(uint256)", "relaunch()", "claimByBurn(uint256,uint256)",
                         "redeemOgFren(uint256)", "recycleCollectionNFT(uint256,uint256)",
                         "buyCollectionNFT(uint256,uint256)",
                         "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))"],
    "CauldronGovernor": [["propose(string,string,uint8,string,address,string,string,uint256,uint256,address)",
                          "propose(string,string,uint8,string,address,string,string,string,string,uint256,uint256,address)",
                          "propose(string,string,uint8,string,address,string,string,uint256,uint256)"],
                         "vote(uint256)", "getProposal(uint256)"],
    "TreasuryGovernor": ["propose(address,uint16)", "vote(uint256,bool)", "execute(uint256)"],
    "MiFrensDividend": ["claim(uint256)", "castSpell(uint256)", "claimMany(uint256[])", "castMany(uint256[])",
                        "claimTokens(uint256)", "withdrawOwedToken(address)", "withdrawOwed()"],
    "PerpEngine": ["openLong(uint8,uint256,uint256,uint256)", "openShort(uint8,uint256,uint256,uint256)",
                   "close(uint256,uint256)", "claimLiquidatorBadges(uint256)"],
    "PerpVault": ["depositEth()", "deposit(uint256)", "withdrawEth(uint256)", "withdrawToken(uint256)",
                  "depositToken(uint256)", "claimPendingEth()", "claimPendingToken()", "claimTokYield()"],
    "MiFrensGenesis": ["mint(uint256)"],
}
sel_rows = []
for contract, sigs in REQUIRED.items():
    a = artifact(contract)
    ids = set((a or {}).get("methodIdentifiers", {}).keys())
    for s in sigs:
        alts = s if isinstance(s, list) else [s]
        sel_rows.append({"contract": contract, "signature": alts, "fresh_artifact": a is not None,
                         "present": any(x in ids for x in alts)})
out["frontend_selectors"] = {"checked": len(sel_rows),
                             "missing": [r for r in sel_rows if not r["present"]]}


# 4. Consumer ABI JSON subset check (every consumer entry must exist in compiled ABI).
def canon(item):
    def t(i):
        if i["type"].startswith("tuple"):
            return "(" + ",".join(t(c) for c in i["components"]) + ")" + i["type"][5:]
        return i["type"]
    if item.get("type") in ("function", "event", "error"):
        extra = ""
        if item["type"] == "event":
            extra = "|" + ",".join("i" if x.get("indexed") else "-" for x in item.get("inputs", []))
        return f'{item["type"]} {item["name"]}(' + ",".join(t(i) for i in item.get("inputs", [])) + ")" + extra
    return None


abi_rows = []
for f in sorted((ROOT / "contracts/abis").glob("*.abi.json")):
    name = f.name.removesuffix(".abi.json")
    a = artifact(name)
    if a is None:
        abi_rows.append({"consumer": str(f.relative_to(ROOT)), "status": "no first-party fresh artifact of that name"})
        continue
    raw = json.loads(f.read_text())
    raw = raw.get("abi", raw) if isinstance(raw, dict) else raw
    if not all(isinstance(i, dict) for i in raw):
        abi_rows.append({"consumer": str(f.relative_to(ROOT)), "status": "non-JSON-fragment ABI format; not compared"})
        continue
    have = {canon(i) for i in a["abi"]} - {None}
    want = {canon(i) for i in raw} - {None}
    abi_rows.append({"consumer": str(f.relative_to(ROOT)), "status": "checked",
                     "missing_in_compiled": sorted(want - have)})
out["consumer_abi_json"] = abi_rows

# 5. Whitespace/conflict check over the working tree diff.
chk = subprocess.run(["git", "-C", str(ROOT), "diff", "--check"], capture_output=True, text=True)
out["git_diff_check"] = {"exit": chk.returncode, "output": chk.stdout[-2000:]}

# 6. Redacted secret scan over audit outputs, new tests and changed first-party files.
pat = [re.compile(r"(?i)private[_-]?key\s*[:=]\s*['\"]?0x[0-9a-f]{64}"),
       re.compile(r"(?i)https?://[^\s'\"]*(alchemy|infura|quiknode|ankr|drpc)[^\s'\"]*/[A-Za-z0-9_-]{20,}"),
       re.compile(r"(?i)(api[_-]?key|secret)\s*[:=]\s*['\"][A-Za-z0-9_-]{24,}")]
targets = [p for p in REPORT.rglob("*") if p.is_file() and "snapshot" not in p.parts
           and "renderer-artifacts" not in p.parts and "renderer-cache" not in p.parts]
targets += [ROOT / r for r in out["tree_vs_baseline"]["added_solidity"]]
targets += [ROOT / r for r in changed]
hits = []
for p in targets:
    try:
        text = p.read_text(errors="ignore")
    except Exception:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if any(x.search(line) for x in pat):
            hits.append(f"{p.relative_to(ROOT)}:{n} <redacted>")
out["secret_scan"] = {"files_scanned": len(targets), "hits": hits}

(REPORT / "remediation/FINAL_GATES.json").write_text(json.dumps(out, indent=2) + "\n")
summary = {
    "snapshot_mismatches": len(bad),
    "first_party_changed": out["tree_vs_baseline"]["first_party_changed"],
    "removed": len(removed),
    "added_solidity": len(out["tree_vs_baseline"]["added_solidity"]),
    "selectors_checked": len(sel_rows), "selectors_missing": out["frontend_selectors"]["missing"],
    "consumer_abi": [(r["consumer"], r.get("missing_in_compiled", r["status"])) for r in abi_rows],
    "git_diff_check_exit": chk.returncode, "secret_hits": len(hits),
}
print(json.dumps(summary, indent=2))
