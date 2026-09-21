import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from compiler_edges import AddressOperations


class CompilerAddressTests(unittest.TestCase):
    def test_requires_exact_current_caller_location_and_address_type(self):
        data = b"a.call(data)"
        node = {"file": "A.sol", "contract": "A", "signature": "function go() external"}
        graph = {
            "sourceHashes": {"A.sol": hashlib.sha256(data).hexdigest()},
            "declarations": [{"id": "1", **node}],
            "edges": [{"parent": "1", "expression": "a.call", "memberName": "call",
                       "target": None, "receiver": {"type": "address"},
                       "source": {"file": "A.sol", "line": 1, "offset": 0,
                                  "length": len(data), "text": data.decode()}}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "A.sol"
            path.write_bytes(data)
            def matches(g=graph, n=node, exp="a.call", file="A.sol", line=1):
                return AddressOperations(g, directory).matches(n, exp, file, line)
            self.assertTrue(matches())
            # Even an import not named directly by this edge can change typing.
            with_import = copy.deepcopy(graph)
            with_import["sourceHashes"]["Import.sol"] = hashlib.sha256(b"old").hexdigest()
            imported = Path(directory) / "Import.sol"
            imported.write_bytes(b"old")
            self.assertTrue(matches(g=with_import))
            imported.write_bytes(b"changed")
            self.assertFalse(matches(g=with_import))
            self.assertFalse(matches(n={**node, "signature": "function other() external"}))
            self.assertFalse(matches(exp="b.call"))
            self.assertFalse(matches(file="Other.sol"))
            self.assertFalse(matches(line=2))
            wrong = copy.deepcopy(graph)
            wrong["edges"][0]["receiver"]["type"] = "contract Fake"
            self.assertFalse(matches(g=wrong))
            ambiguous = copy.deepcopy(graph)
            ambiguous["edges"] *= 2
            self.assertFalse(matches(g=ambiguous))
            wrong = copy.deepcopy(graph)
            wrong["edges"][0]["source"]["text"] = "forged"
            self.assertFalse(matches(g=wrong))
            path.write_bytes(data + b"\n")
            self.assertFalse(matches())

    def test_static_declaration_requires_fresh_target_source(self):
        data = b"reg.run()"
        target_source = b"interface Registry {}"
        node = {"file": "A.sol", "contract": "A", "signature": "function go() external"}
        graph = {
            "sourceHashes": {"A.sol": hashlib.sha256(data).hexdigest(),
                             "Registry.sol": hashlib.sha256(target_source).hexdigest()},
            "declarations": [{"id": "1", **node}],
            "targets": {"2": {"kind": "FunctionDefinition", "source": {"file": "Registry.sol"}}},
            "edges": [{"parent": "1", "expression": "reg.run", "target": "2",
                       "source": {"file": "A.sol", "line": 1, "offset": 0,
                                  "length": len(data), "text": data.decode()}}],
        }
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "A.sol").write_bytes(data)
            target = Path(directory) / "Registry.sol"
            target.write_bytes(target_source)
            self.assertEqual("2", AddressOperations(graph, directory).declaration(node, "reg.run", "A.sol", 1))
            target.write_bytes(target_source + b"\n")
            self.assertIsNone(AddressOperations(graph, directory).declaration(node, "reg.run", "A.sol", 1))

    def test_internal_spelling_requires_compiler_target_contract(self):
        data = b"run()"
        node = {"file": "A.sol", "contract": "A", "signature": "function go() external"}
        graph = {"sourceHashes": {"A.sol": hashlib.sha256(data).hexdigest()},
                 "declarations": [{"id": "1", **node}],
                 "targets": {"2": {"kind": "FunctionDefinition", "contract": "A",
                                   "name": "run", "source": {"file": "A.sol"}}},
                 "edges": [{"parent": "1", "expression": "run", "target": "2",
                            "source": {"file": "A.sol", "line": 1, "offset": 0,
                                       "length": len(data), "text": data.decode()}}]}
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "A.sol").write_bytes(data)
            matcher = AddressOperations(graph, directory)
            self.assertEqual("2", matcher.declaration(node, "A.run", "A.sol", 1))
            self.assertIsNone(matcher.declaration(node, "Wrong.run", "A.sol", 1))
