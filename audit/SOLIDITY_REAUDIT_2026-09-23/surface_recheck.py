"""Compare every contract in a changed first-party file against its frozen-baseline
compiler surface: selectors, events/errors and storage layout. Writes
remediation/FINAL_SURFACE_RECHECK.json. Structural only; not behavioral proof."""
import json
import os
import subprocess
from pathlib import Path

REPORT = Path(__file__).resolve().parent
SOL = REPORT.parent.parent / "contracts/solidity"
graph = json.loads((REPORT / "COMPILER_GRAPH.json").read_text())
gates = json.loads((REPORT / "remediation/FINAL_GATES.json").read_text())
inv = json.loads((REPORT / "remediation/CANDIDATE_ARTIFACT_INVENTORY.json").read_text())
changed = [p.removeprefix("contracts/solidity/") for p in gates["tree_vs_baseline"]["first_party_changed"]]


def canon(i):
    def t(x):
        if x["type"].startswith("tuple"):
            return "(" + ",".join(t(c) for c in x["components"]) + ")" + x["type"][5:]
        return x["type"]
    if i.get("type") in ("event", "error"):
        idx = "|" + ",".join("i" if x.get("indexed") else "-" for x in i.get("inputs", [])) if i["type"] == "event" else ""
        return f'{i["type"]} {i["name"]}(' + ",".join(t(x) for x in i.get("inputs", [])) + ")" + idx


def slots(layout):
    return [(s["label"], str(s["slot"]), int(s["offset"]),
             (s["type"]["label"] if isinstance(s["type"], dict) else layout.get("types", {}).get(s["type"], {}).get("label", s["type"])))
            for s in layout.get("storage", [])]


env = {**os.environ, "FOUNDRY_PROFILE": "cauldron", "FOUNDRY_DISABLE_NIGHTLY_WARNING": "1"}
rows = []
for base in graph["contractSurfaces"]:
    if base["file"] not in changed or base["compiler"] != "0.8.30":
        continue
    name = base["contract"]
    arts = [a for a in inv["artifacts"] if a["contract"] == name and a["source"] == base["file"] and a["all_metadata_inputs_match"]]
    if not arts:
        rows.append({"contract": name, "file": base["file"], "status": "NO FRESH ARTIFACT"})
        continue
    art = json.loads((SOL / arts[0]["artifact"]).read_text())
    new_ids, old_ids = set(art.get("methodIdentifiers", {})), set(base["methodIdentifiers"])
    new_ev, old_ev = {canon(i) for i in art["abi"]} - {None}, {canon(i) for i in base["abi"]} - {None}
    row = {"contract": name, "file": base["file"],
           "selectors_added": sorted(new_ids - old_ids), "selectors_removed": sorted(old_ids - new_ids),
           "events_errors_added": sorted(new_ev - old_ev), "events_errors_removed": sorted(old_ev - new_ev)}
    if base.get("storageLayout", {}).get("storage"):
        try:
            cur = json.loads(subprocess.check_output(
                ["forge", "inspect", "--offline", f"{base['file']}:{name}", "storageLayout", "--json"],
                cwd=SOL, env=env, text=True, stderr=subprocess.DEVNULL))
            a, b = slots(base["storageLayout"]), slots(cur)
            row["storage_identical"] = a == b
            if a != b:
                row["storage_baseline_len"], row["storage_current_len"] = len(a), len(b)
                row["storage_first_difference"] = next(
                    ([x, y] for x, y in zip(a, b) if x != y), [a[len(b):len(b) + 1], b[len(a):len(a) + 1]])
        except subprocess.CalledProcessError as e:
            row["storage_identical"] = f"inspect failed: exit {e.returncode}"
    rows.append(row)
(REPORT / "remediation/FINAL_SURFACE_RECHECK.json").write_text(json.dumps(rows, indent=2) + "\n")
for r in rows:
    diffs = {k: v for k, v in r.items() if k not in ("contract", "file") and v not in ([], True)}
    print(r["contract"], "OK" if not diffs else diffs)
