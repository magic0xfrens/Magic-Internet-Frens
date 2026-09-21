import json
import hashlib
from pathlib import Path
import tempfile
import unittest

from coverage import generate


class CoverageLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.src, self.graph, self.report = root / "src", root / "graph", root / "report"
        for path in (self.src, self.graph, self.report):
            path.mkdir()
        (self.graph / "clusters.json").write_text(json.dumps({"fixture": ["C.sol"]}))
        self.code = """pragma solidity ^0.8.30;
contract C {
    uint256 public amount;
    function act(address target) external {
        assembly { mstore(0, 0) }
        target.delegatecall("");
    }
}
"""
        (self.src / "C.sol").write_text(self.code)
        source_hash = hashlib.sha256(self.code.encode()).hexdigest()
        (self.report / "COMPILER_GRAPH.json").write_text(json.dumps({
            "sourceHashes": {"C.sol": source_hash},
            "declarations": [], "edges": [], "sites": [],
            "unresolved": [], "unresolvedSelectors": [],
            "targets": {
                "fixture:act": {"name": "act", "kind": "FunctionDefinition", "contract": "C",
                                "source": {"file": "C.sol", "line": 4}},
                "fixture:amount": {"name": "amount", "kind": "VariableDeclaration", "contract": "Base",
                                   "source": {"file": "Base.sol", "line": 2}, "stateVariable": True},
            },
            "contractSurfaces": [{
                "file": "C.sol", "contract": "C", "compiler": "fixture",
                "source_sha256": source_hash,
                "methodIdentifiers": {"act(address)": "11111111", "amount()": "22222222"},
                "selectorBindings": {"act(address)": "fixture:act", "amount()": "fixture:amount"},
            }],
        }))

    def run_ledger(self):
        return generate(self.src, self.graph, self.report)

    def test_getters_and_sensitive_sites_are_not_silently_dropped(self):
        result = self.run_ledger()
        self.assertEqual(len(result["nodes"]), 5)
        self.assertEqual({n["kind"] for n in result["nodes"]},
                         {"function", "assembly", "delegatecall", "selector"})
        self.assertTrue(all(n["coverage_status"] == "GAP" for n in result["nodes"]))
        self.assertFalse(result["scope_issues"])

    def test_inherited_getter_retains_exact_compiler_binding_without_claiming_review(self):
        result = self.run_ledger()
        getter = next(n for n in result["nodes"] if n["signature"] == "amount()")
        self.assertEqual(getter["compiler_binding"], "fixture:amount")
        self.assertEqual(getter["compiler_target"]["contract"], "Base")
        self.assertTrue(getter["inherited"])
        self.assertEqual(getter["coverage_status"], "GAP")

    def test_unclustered_source_is_an_explicit_issue(self):
        (self.src / "Missed.sol").write_text("contract Missed {}")
        self.assertIn("Unclustered Solidity source: Missed.sol", self.run_ledger()["scope_issues"])

    def test_partial_evidence_cannot_claim_coverage(self):
        node = self.run_ledger()["nodes"][0]
        (self.report / "coverage_evidence.json").write_text(json.dumps({node["id"]: {"property": "safe"}}))
        self.assertEqual(self.run_ledger()["nodes"][0]["coverage_status"], "GAP")

    def test_source_edit_invalidates_complete_evidence(self):
        result = self.run_ledger()
        node = result["nodes"][0]
        entry = {k: "fixture" for k in ("reviewer", "property", "source_citations", "tests",
                                        "result", "consumers", "limitations")}
        entry["source_sha256"] = result["source_files"]["C.sol"]["sha256"]
        (self.report / "coverage_evidence.json").write_text(json.dumps({node["id"]: entry}))
        self.assertEqual(self.run_ledger()["nodes"][0]["coverage_status"], "EVIDENCE_RECORDED")
        (self.src / "C.sol").write_text(self.code + "\n// changed\n")
        stale = self.run_ledger()
        self.assertEqual(stale["nodes"][0]["coverage_status"], "GAP")
        self.assertTrue(any(issue.startswith("Stale/missing compiler source: C.sol")
                            for issue in stale["scope_issues"]))
        self.assertFalse(any(n["kind"] == "selector" for n in stale["nodes"]))


if __name__ == "__main__":
    unittest.main()
