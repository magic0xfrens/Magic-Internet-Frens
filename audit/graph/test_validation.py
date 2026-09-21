#!/usr/bin/env python3
"""Focused, build-free regression tests for graph validation and joining."""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate = load_module("graph_validate", "validate.py")
join = load_module("graph_join", "join.py")


class ResolutionTests(unittest.TestCase):
    def test_lowlevel_names_do_not_bypass_target_identity(self):
        for method in ("call", "delegatecall", "staticcall", "transfer", "send"):
            for resolver in (validate.edge_target_resolves, join.edge_target_resolves):
                self.assertFalse(resolver("Unknown", method, "out-of-cluster", {}, {}, {}))
        self.assertTrue(validate.edge_target_resolves(
            "Token", "transfer", "out-of-cluster", {"Token": {"transfer"}}, {}, {}))
        self.assertEqual("node", join.edge_target_resolves(
            "Token", "transfer", "out-of-cluster", {("Token", "transfer"): "token"}, {}, {}))

    def test_dotted_solidity_script_filename_is_accepted(self):
        self.assertIsNotNone(validate.RE_FILEREF.search("`run` DeployLaunchpad.s.sol:42"))
        self.assertIsNotNone(validate.RE_GATE.match("onlyOwner (DeployLaunchpad.s.sol:42)"))
        self.assertIsNotNone(validate.RE_EDGE.match(
            "DeployLaunchpad.run (DeployLaunchpad.s.sol:42), TRUSTED, out-of-cluster"))

    def test_wrong_contract_does_not_resolve_by_global_method_name(self):
        contracts = {"RightContract": {"configure"}, "WrongContract": {"other"}}
        self.assertTrue(validate.edge_target_resolves(
            "RightContract", "configure", "out-of-cluster", contracts, {}, set()))
        self.assertFalse(validate.edge_target_resolves(
            "WrongContract", "configure", "out-of-cluster", contracts, {}, set()))
        self.assertEqual("node", join.edge_target_resolves(
            "RightContract", "configure", "out-of-cluster",
            {("RightContract", "configure"): "core"}, {}, set()))
        self.assertIsNone(join.edge_target_resolves(
            "WrongContract", "configure", "out-of-cluster",
            {("RightContract", "configure"): "core"}, {}, set()))

    def test_compiler_getters_and_explicit_dependencies_remain_supported(self):
        self.assertTrue(validate.edge_target_resolves(
            "Registry", "owner", "out-of-cluster", {}, {"Registry": {"owner"}}, set()))
        self.assertTrue(validate.edge_target_resolves(
            "SafeTransferLib", "safeTransfer", "library", {}, {}, {"SafeTransferLib": ["safeTransfer"]}))
        self.assertFalse(validate.edge_target_resolves(
            "Unrelated", "safeTransfer", "library", {}, {}, {"safeTransfer"}))

    def test_dependency_method_must_belong_to_named_type(self):
        methods = {"SafeTransferLib": ["safeTransfer"]}
        for resolver in (validate.edge_target_resolves, join.edge_target_resolves):
            self.assertFalse(resolver("TickMath", "safeTransfer", "library", {}, {}, methods))
            self.assertTrue(resolver("SafeTransferLib", "safeTransfer", "library", {}, {}, methods))
            self.assertFalse(resolver("SafeTransferLib", "safeTransfer", "library", {}, {}, {"safeTransfer"}))
            self.assertFalse(resolver("SafeTransferLib", "safeTransfer", "library", {}, {}, {"SafeTransferLib": "safeTransfer"}))


class JoinExitStatusTests(unittest.TestCase):
    def test_compiler_mode_cannot_fall_back_to_legacy_names(self):
        with tempfile.TemporaryDirectory() as td:
            self.write_json(os.path.join(td, "clusters.json"), {"one": []})
            self.write_json(os.path.join(td, "one.json"), {"nodes": [
                self.node("Caller", "call", [
                    "Known.act (Missing.sol:99), TRUSTED, in-cluster"]),
                self.node("Known", "act")]})
            compiler = os.path.join(td, "compiler.json")
            self.write_json(compiler, {"sourceHashes": {}, "edges": []})
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(1, join.run(td, compiler, td))

    @staticmethod
    def write_json(path, value):
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(value, fh)

    @staticmethod
    def node(contract, name, edges=None):
        return {"contract": contract, "name": name, "kind": "function", "edges": edges or []}

    def run_quietly(self, directory):
        with contextlib.redirect_stdout(io.StringIO()):
            return join.run(directory)

    def test_missing_cluster_is_failure(self):
        with tempfile.TemporaryDirectory() as td:
            self.write_json(os.path.join(td, "clusters.json"), {"one": [], "missing": []})
            self.write_json(os.path.join(td, "one.json"), {"nodes": []})
            self.assertEqual(1, self.run_quietly(td))

    def test_malformed_edge_is_failure(self):
        with tempfile.TemporaryDirectory() as td:
            self.write_json(os.path.join(td, "clusters.json"), {"one": []})
            self.write_json(os.path.join(td, "one.json"), {
                "nodes": [self.node("Caller", "call", ["not a valid edge"])]})
            self.assertEqual(1, self.run_quietly(td))

    def test_join_rejects_wrong_contract_even_when_method_exists_elsewhere(self):
        with tempfile.TemporaryDirectory() as td:
            self.write_json(os.path.join(td, "clusters.json"), {"one": [], "two": []})
            self.write_json(os.path.join(td, "one.json"), {"nodes": [
                self.node("Caller", "call", [
                    "WrongContract.configure (Caller.sol:1), TRUSTED, out-of-cluster"])]})
            self.write_json(os.path.join(td, "two.json"), {"nodes": [
                self.node("RightContract", "configure")]})
            self.assertEqual(1, self.run_quietly(td))

    def test_join_rejects_bogus_in_cluster_target(self):
        with tempfile.TemporaryDirectory() as td:
            self.write_json(os.path.join(td, "clusters.json"), {"one": []})
            self.write_json(os.path.join(td, "one.json"), {"nodes": [
                self.node("Caller", "call", [
                    "Unknown.act (Caller.sol:1), TRUSTED, in-cluster"]),
                self.node("Known", "act"),
            ]})
            self.assertEqual(1, self.run_quietly(td))

    def test_error_cache_entry_is_not_a_compiler_getter(self):
        with tempfile.TemporaryDirectory() as td:
            os.mkdir(os.path.join(td, "cache"))
            self.write_json(os.path.join(td, "clusters.json"), {"one": []})
            self.write_json(os.path.join(td, "one.json"), {"nodes": [
                self.node("Caller", "call", [
                    "Broken.__error__ (Caller.sol:1), TRUSTED, out-of-cluster"])]})
            self.write_json(os.path.join(td, "cache", "Broken.methodIdentifiers.json"), {
                "__error__": "forge inspect failed"})
            self.assertEqual(1, self.run_quietly(td))

    def test_complete_exact_graph_returns_zero(self):
        with tempfile.TemporaryDirectory() as td:
            self.write_json(os.path.join(td, "clusters.json"), {"one": [], "two": []})
            self.write_json(os.path.join(td, "one.json"), {"nodes": [
                self.node("Caller", "call", [
                    "RightContract.configure (Caller.sol:1), TRUSTED, out-of-cluster"])]})
            self.write_json(os.path.join(td, "two.json"), {"nodes": [
                self.node("RightContract", "configure")]})
            self.assertEqual(0, self.run_quietly(td))


if __name__ == "__main__":
    unittest.main()
