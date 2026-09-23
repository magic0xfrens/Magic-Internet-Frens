"""Capture isolated audit inputs and hashes; refuse to replace an existing snapshot."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parent.parent
DEST = REPORT / "snapshot"
SKIP = {".git", "out", "cache", "broadcast", "node_modules", "render-out", "__pycache__"}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if DEST.exists():
        raise SystemExit("Snapshot already exists; refusing to overwrite baseline")
    head = git("rev-parse", "HEAD")
    submodules = git("submodule", "status", "--recursive")
    status = git("status", "--short")
    DEST.mkdir()
    manifest = {}
    for top in ("contracts/solidity", "compressed-traits"):
        source = ROOT / top
        if not source.is_dir():
            raise SystemExit(f"Required input missing: {top}")
        for path in sorted(source.rglob("*")):
            rel = path.relative_to(ROOT)
            if any(part in SKIP or part.startswith(".env") for part in rel.parts):
                continue
            if path.is_symlink():
                raise SystemExit(f"Resolve snapshot symlink explicitly: {rel}")
            if not path.is_file():
                continue
            target = DEST / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            before = digest(path)
            shutil.copy2(path, target)
            if digest(target) != before or digest(path) != before:
                raise SystemExit(f"Concurrent source change: {rel}")
            manifest[str(rel)] = before
    for rel, expected in manifest.items():
        if digest(ROOT / rel) != expected:
            raise SystemExit(f"Source changed during capture: {rel}")
    if git("rev-parse", "HEAD") != head or git("submodule", "status", "--recursive") != submodules:
        raise SystemExit("Git identity changed during capture")
    first_party = [p for p in manifest if p.startswith("contracts/solidity/")
                   and p.endswith(".sol") and not {"lib", "test"}.intersection(Path(p).parts)]
    tests = [p for p in manifest if p.startswith("contracts/solidity/test/") and p.endswith(".sol")]
    result = {"head": head, "initial_status": status, "submodule_status": submodules,
              "excluded_path_parts": sorted(SKIP), "excluded_name_prefixes": [".env"],
              "first_party_solidity": first_party, "test_sources": tests, "sha256": manifest}
    (REPORT / "BASELINE.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"head": head, "captured_files": len(manifest),
                      "first_party_solidity": len(first_party), "test_sources": len(tests)}))


if __name__ == "__main__":
    main()
