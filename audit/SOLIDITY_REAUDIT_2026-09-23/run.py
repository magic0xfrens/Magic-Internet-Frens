"""Run one bounded audit command in the snapshot; retain full logs and exit status."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

report = Path(__file__).resolve().parent
args = sys.argv[1:]
worktree = bool(args and args[0] == "--worktree")
if worktree:
    args = args[1:]
label, *command = args
if not label.replace("-", "").isalnum() or not command:
    raise SystemExit("usage: run.py LABEL COMMAND [ARG ...]")
logs = report / "logs"
logs.mkdir(exist_ok=True)
record = logs / f"{label}.json"
if record.exists():
    raise SystemExit("Refusing to overwrite an existing run")
cwd = report.parent.parent / "contracts/solidity" if worktree else report / "snapshot/contracts/solidity"
start = time.time()
state = {"command": command, "cwd": str(cwd), "profile": "cauldron", "worktree": worktree,
         "started_at": start, "status": "running"}
record.write_text(json.dumps(state, indent=2) + "\n")
print(json.dumps(state), flush=True)
env = dict(os.environ, FOUNDRY_PROFILE="cauldron")
with (logs / f"{label}.log").open("w") as log:
    proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    code = proc.wait()
state.update(status="finished", exit_code=code, elapsed_seconds=round(time.time()-start, 2))
record.write_text(json.dumps(state, indent=2) + "\n")
print(json.dumps(state), flush=True)
print("\n".join((logs / f"{label}.log").read_text().splitlines()[-45:]))
raise SystemExit(code)
