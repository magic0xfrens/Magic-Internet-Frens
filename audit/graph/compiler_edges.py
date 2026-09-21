"""Conservative source-pinned classification of address operations, not callees."""
import hashlib
from pathlib import Path
import re


def norm(signature):
    return re.sub(r"\s+", " ", signature).strip().rstrip(";")


class AddressOperations:
    def __init__(self, graph, source_root):
        self.graph = graph
        self.root = Path(source_root).resolve()
        self.declarations = {d["id"]: d for d in graph.get("declarations", [])}
        self.sources = {}
        for file, expected in graph.get("sourceHashes", {}).items():
            path = (self.root / file).resolve()
            if not path.is_relative_to(self.root):
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue
            if hashlib.sha256(data).hexdigest() == expected:
                self.sources[file] = data
        # Imported inheritance/types can change call resolution without a change
        # to the caller text. Require the entire compiler input snapshot current.
        self.current = bool(graph.get("sourceHashes")) and len(self.sources) == len(graph["sourceHashes"])

    def _candidates(self, node, expression, citation_file, line):
        if not self.current:
            return []
        file = node.get("file")
        data = self.sources.get(file)
        if data is None or citation_file not in (file, Path(file).name):
            return []
        candidates = []
        for edge in self.graph.get("edges", []):
            source = edge.get("source", {})
            parent = self.declarations.get(edge.get("parent"), {})
            exact_expression = edge.get("expression") == expression
            target = self.graph.get("targets", {}).get(edge.get("target"), {})
            # Prose graphs spell internal calls Contract.function; source uses
            # the bare identifier. Compiler target identity disambiguates it.
            internal_expression = (target.get("kind") == "FunctionDefinition"
                                   and edge.get("expression") == target.get("name")
                                   and expression == target.get("contract", "") + "." + target.get("name", ""))
            if (source.get("file") != file or source.get("line") != line
                    or not (exact_expression or internal_expression)
                    or parent.get("file") != file
                    or parent.get("contract") != node.get("contract", "").split(" (declared in ")[0]
                    or norm(parent.get("signature", "")) != norm(node.get("signature", ""))):
                continue
            offset, length = source.get("offset"), source.get("length")
            if not isinstance(offset, int) or not isinstance(length, int) or offset < 0 or length <= 0:
                continue
            if data[offset:offset + length].decode("utf-8") != source.get("text"):
                continue
            if data[:offset].count(b"\n") + 1 != line:
                continue
            candidates.append(edge)
        return candidates

    def matches(self, node, expression, citation_file, line):
        candidates = self._candidates(node, expression, citation_file, line)
        if len(candidates) != 1:
            return False
        edge = candidates[0]
        return (edge.get("target") is None
                and (edge.get("receiver") or {}).get("type") in ("address", "address payable")
                and edge.get("memberName") in ("call", "staticcall", "delegatecall", "send", "transfer"))

    def declaration(self, node, expression, citation_file, line):
        """Static declaration only; an interface is not a runtime implementation."""
        candidates = self._candidates(node, expression, citation_file, line)
        if len(candidates) != 1:
            return None
        edge = candidates[0]
        target = self.graph.get("targets", {}).get(edge.get("target"), {})
        if (target.get("source", {}).get("file") not in self.sources
                or target.get("kind") not in ("FunctionDefinition", "VariableDeclaration")):
            return None
        return edge["target"]
