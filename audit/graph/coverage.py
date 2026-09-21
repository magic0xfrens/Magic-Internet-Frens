#!/usr/bin/env python3
"""Build a current-source coverage ledger; never infer audited status from names.

Usage: coverage.py SRC GRAPH_DIR REPORT_DIR [--check]
The optional coverage_evidence.json is hand-reviewed evidence keyed by stable node
id. Every missing property/test/consumer mapping stays GAP. --check fails until
all entries have current-source evidence and all source/artifact gaps are closed.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

from skeleton import mask, scan_file


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def identity(kind, file, contract, signature):
    return kind + ":" + digest("|".join((file, contract, signature)))[:24]


def generate(src, graph, report):
    clusters = json.loads((graph / "clusters.json").read_text())
    evidence_path = report / "coverage_evidence.json"
    evidence = json.loads(evidence_path.read_text()) if evidence_path.exists() else {}
    rows, files, issues = [], {}, []
    compiler_path = report / "COMPILER_GRAPH.json"
    compiler = None
    if not compiler_path.exists():
        issues.append("Missing current-source compiler graph: " + str(compiler_path))
    else:
        try:
            compiler = json.loads(compiler_path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            issues.append("Unreadable compiler graph: " + str(exc))
    if compiler:
        for item in compiler.get("unresolved", []):
            issues.append("Unresolved compiler reference: " + json.dumps(item, sort_keys=True))
        for item in compiler.get("unresolvedSelectors", []):
            issues.append("Unresolved compiler selector: " + json.dumps(item, sort_keys=True))
    compiler_hashes = compiler.get("sourceHashes", {}) if compiler else {}
    surfaces_by_file = {}
    if compiler:
        for surface in compiler.get("contractSurfaces", []):
            surfaces_by_file.setdefault(surface.get("file"), []).append(surface)
    compiler_targets = compiler.get("targets", {}) if compiler else {}
    scope = [f for group in clusters.values() for f in group]
    if len(scope) != len(set(scope)):
        issues.append("Duplicate source file in cluster scope")
    actual = {str(p.relative_to(src)) for p in src.rglob("*.sol")
              if not set(p.relative_to(src).parts) & {"lib", "out", "cache", "test", "broadcast"}}
    for file in sorted(actual - set(scope)):
        issues.append("Unclustered Solidity source: " + file)
    for file in sorted(set(scope) - actual):
        issues.append("Missing scoped Solidity source: " + file)

    def append(row):
        key = identity(row["kind"], row["file"], row["contract"], row["signature"])
        row["id"] = key
        entry = evidence.get(key)
        row["evidence"] = entry
        # Conservatively invalidates all evidence for a file after any source edit.
        current = bool(entry and entry.get("source_sha256") == files[row["file"]]["sha256"])
        fields = ("reviewer", "property", "source_citations", "tests", "result", "consumers", "limitations")
        complete = current and all(entry.get(k) for k in fields)
        row["coverage_status"] = "EVIDENCE_RECORDED" if complete else "GAP"
        row["gap"] = None if complete else (
            "stale/incomplete evidence" if entry else "no explicit property/assertion/consumer evidence"
        )
        rows.append(row)

    for cluster, paths in clusters.items():
        previous_path = graph / (cluster + ".json")
        previous = json.loads(previous_path.read_text())["nodes"] if previous_path.exists() else []
        index = {(n["file"], n["contract"], n["signature"]): n for n in previous}
        for file in paths:
            path = src / file
            if not path.exists():
                continue
            source = path.read_text()
            source_hash = digest(source)
            compiler_current = compiler_hashes.get(file) == source_hash
            files[file] = {"sha256": source_hash, "cluster": cluster,
                           "compiler_source_current": compiler_current}
            if not compiler_current:
                got = compiler_hashes.get(file, "MISSING")
                issues.append(f"Stale/missing compiler source: {file}: compiler={got} current={source_hash}")
            declarations, _, _ = scan_file(str(src), file)
            _, masked = mask(source)
            for node in declarations:
                prior = index.get((file, node["contract"], node["signature"]))
                current = bool(prior and prior["body_sha1"] == node["body_sha1"]
                               and prior["line"] == node["line"])
                append(dict(node, cluster=cluster, semantic_graph_current=current,
                            node_origin="source declaration"))
            for kind, pattern in (("assembly", r"\bassembly\b"),
                                  ("delegatecall", r"\.\s*delegatecall\b")):
                for occurrence, match in enumerate(re.finditer(pattern, masked)):
                    line = masked.count("\n", 0, match.start()) + 1
                    parents = [n for n in declarations if n["body_lines"]
                               and n["body_lines"][0] <= line <= n["body_lines"][1]]
                    if len(parents) != 1:
                        issues.append(f"Unresolved {kind} parent: {file}:{line}")
                    parent = parents[0] if len(parents) == 1 else None
                    append({"file": file, "contract": parent["contract"] if parent else "UNKNOWN",
                            "line": line, "kind": kind, "cluster": cluster,
                            "signature": f"{parent['signature'] if parent else ''}#{kind}-{occurrence}",
                            "parent_signature": parent["signature"] if parent else None,
                            "node_origin": "source sensitive site"})

            # Fresh compiler surfaces retain getters and inherited selectors, with
            # exact AST declaration bindings. A stale graph contributes no surface:
            # retaining stale selectors would turn a freshness failure into evidence.
            if compiler_current:
                compiler_surfaces = surfaces_by_file.get(file, [])
                if not compiler_surfaces:
                    issues.append("Missing compiler surfaces for current source: " + file)
                for surface in sorted(compiler_surfaces, key=lambda item: item.get("contract", "")):
                    contract = surface.get("contract", "UNKNOWN")
                    bindings = surface.get("selectorBindings", {})
                    for signature, selector in sorted(surface.get("methodIdentifiers", {}).items()):
                        binding = bindings.get(signature)
                        target = compiler_targets.get(binding) if binding else None
                        if not binding or not target:
                            issues.append(f"Unresolved compiler selector binding: {file}:{contract}:{signature}")
                        target_source = target.get("source") if target else None
                        append({"file": file, "contract": contract, "kind": "selector",
                                "cluster": cluster, "signature": signature, "selector": selector,
                                "line": target_source.get("line") if target_source else None,
                                "compiler_binding": binding,
                                "compiler_target": target,
                                "inherited": bool(target and target.get("contract") != contract),
                                "node_origin": "fresh compiler surface (getter/inheritance binding is structural only)",
                                "compiler_version": surface.get("compiler"),
                                "compiler_source_sha256": surface.get("source_sha256"),
                                "compiler_source_current": True})
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        issues.append("Duplicate stable node id")
    for stale in sorted(set(evidence) - set(ids)):
        issues.append("Evidence for absent node: " + stale)
    document = {"source_files": files, "scope_issues": issues, "nodes": rows,
                "limitations": [
                    "Evidence recorded is not automatic independent verification.",
                    "Compiler selectors include inherited and getter entries with AST bindings; those bindings are structural inventory, not review evidence.",
                    "Compiler graph source hashes must match every scoped current source; stale graph data is rejected rather than reused.",
                    "Compiler call edges and types do not establish authorization, asset conservation, or a reviewed property.",
                    "Assembly/delegatecall sites are explicit children, not additional Solidity function declarations.",
                    "Sensitive-site ids use file occurrence order and may change after edits.",
                ]}
    report.mkdir(parents=True, exist_ok=True)
    (report / "FUNCTION_COVERAGE.json").write_text(json.dumps(document, indent=2) + "\n")
    table = ["# Current-source function and property coverage", "",
             "Generated by `audit/graph/coverage.py`. Counts are inventory, not completed audit coverage.", "",
             "| Cluster | Declarations | Assembly/delegatecall | Compiler selectors | Explicit evidence | GAP |",
             "|---|---:|---:|---:|---:|---:|"]
    for cluster in clusters:
        ns = [r for r in rows if r["cluster"] == cluster]
        sensitive = sum(r["kind"] in ("assembly", "delegatecall") for r in ns)
        selectors = sum(r["kind"] == "selector" for r in ns)
        covered = sum(r["coverage_status"] == "EVIDENCE_RECORDED" for r in ns)
        table.append(f"| {cluster} | {len(ns)-sensitive-selectors} | {sensitive} | {selectors} | {covered} | {len(ns)-covered} |")
    stale = sum(r.get("semantic_graph_current") is False for r in rows)
    table += ["", f"Files: {len(files)}. Total inventory entries: {len(rows)}. Stale/missing semantic declaration annotations: {stale}.",
              "", "## Scope/build issues", ""]
    table += ["- " + issue for issue in issues] or ["None detected by file/target checks; artifact freshness remains unverified."]
    table += ["", "## Evidence policy", "",
              "Each entry begins as GAP until its stable id is mapped in `coverage_evidence.json` to a reviewer, property, source citations, exact tests/assertions, observed result, consumers, limitations, and current source SHA-256. Existing source-review reports and passing suites are retained, but not automatically credited to every node they mention.",
              "", "The selector surface is intentionally separate from declarations: getters and inherited methods must not disappear from scope. Exact compiler bindings identify their declarations, but do not prove that their properties were reviewed. These totals must not be reported as the number of unique functions audited.",
              "", "The full graph gate remains open until annotations, current compiler-source parity, cross-cluster edges, and evidence gaps are reconciled.", ""]
    (report / "FUNCTION_GRAPH.md").write_text("\n".join(table))
    (report / "TREE_SHA256_CURRENT.txt").write_text("".join(
        f"{info['sha256']}  contracts/solidity/{file}\n" for file, info in sorted(files.items())))
    print(f"files={len(files)} entries={len(rows)} gaps={sum(r['coverage_status']=='GAP' for r in rows)} stale_semantics={stale} scope_issues={len(issues)}")
    return document


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    result = generate(*(Path(p) for p in sys.argv[1:4]))
    if "--check" in sys.argv:
        sys.exit(1 if result["scope_issues"] or any(
            n["coverage_status"] == "GAP" or n.get("semantic_graph_current") is False
            or n.get("compiler_source_current") is False for n in result["nodes"]
        ) else 0)
