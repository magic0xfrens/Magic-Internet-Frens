"""Inventory source-matched first-party artifacts; never infer semantic sign-off."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

report = Path(__file__).resolve().parent
root = report.parent.parent / 'contracts/solidity'
scope = [s.removeprefix('contracts/solidity/') for s in json.loads((report/'BASELINE.json').read_text())['first_party_solidity']]
cache = {}
def source_hash(name):
    if name not in cache:
        p = root/name
        if not p.is_file():
            cache[name] = None
        else:
            cache[name] = subprocess.check_output(['cast', 'keccak'], input=p.read_bytes(), env={**os.environ, 'FOUNDRY_DISABLE_NIGHTLY_WARNING': '1'}).decode().strip()
    return cache[name]

artifact_roots = [root/'out', report/'remediation/renderer-artifacts']
rows = []
for source in scope:
    for artifact in sorted(a for directory in artifact_roots for a in (directory/Path(source).name).glob('*.json')):
        a = json.loads(artifact.read_text())
        m = a.get('metadata', {})
        if isinstance(m, str): m = json.loads(m)
        target = m.get('settings', {}).get('compilationTarget', {})
        if source not in target: continue
        mismatches, missing = [], []
        for dependency, identity in m.get('sources', {}).items():
            local = source_hash(dependency)
            if local is None: missing.append(dependency)
            elif local != identity.get('keccak256'): mismatches.append(dependency)
        def size(field):
            obj = a.get(field, {}).get('object', '').removeprefix('0x')
            return len(obj)//2
        rows.append({'source': source, 'contract': target[source],
            'artifact': os.path.relpath(artifact, root),
            'artifact_sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
            'compiler': m.get('compiler', {}).get('version'),
            'optimizer': m.get('settings', {}).get('optimizer'),
            'viaIR': m.get('settings', {}).get('viaIR'),
            'evmVersion': m.get('settings', {}).get('evmVersion'),
            'source_sha256': hashlib.sha256((root/source).read_bytes()).hexdigest(),
            'all_metadata_inputs_match': not mismatches and not missing,
            'mismatched_inputs': mismatches, 'unavailable_inputs': missing,
            'runtime_bytes': size('deployedBytecode'), 'initcode_bytes_without_args': size('bytecode'),
            'runtime_headroom': 24576-size('deployedBytecode'),
            'initcode_headroom_without_args': 49152-size('bytecode'),
            'link_references': a.get('bytecode', {}).get('linkReferences', {})})
matched = {r['source'] for r in rows if r['all_metadata_inputs_match']}
result = {'scope_files': len(scope), 'files_with_matching_artifacts': len(matched),
          'files_without_matching_artifacts': sorted(set(scope)-matched), 'artifacts': rows,
          'limitations': ['Matching compiler inputs and size do not establish semantic safety.',
            'Initcode measurement excludes constructor arguments; final limit must include them.',
            'Linked addresses, deployment transactions and onchain bytecode parity not verified.',
            'Script/test harness size must be distinguished from contracts deployed by scripts.']}
(report/'remediation/CANDIDATE_ARTIFACT_INVENTORY.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k != 'artifacts'},indent=2))
print('Matching runtime artifacts above EIP-170:')
for r in rows:
    if r['all_metadata_inputs_match'] and r['runtime_headroom'] < 0:
        print(r['source'],r['contract'],r['runtime_bytes'])
