import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const report = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(report, '../..');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const before = read(path.join(report, 'COMPILER_GRAPH.json'));
const after = read(path.join(report, 'remediation/COMPILER_GRAPH.json'));
const contract = process.argv[2] || 'QuoteOracle';
if (!['QuoteOracle', 'MigrationVesting', 'MiFrensDividend', 'CollectionLedger', 'CauldronHook', 'SurtaxLib', 'PoolOps', 'CauldronVault', 'PerpVault', 'PerpEngine'].includes(contract)) throw new Error('Unsupported contract');
const file = contract === 'CauldronHook' ? 'CauldronHook.sol' : `cauldron/${contract}.sol`;
const surface = g => g.contractSurfaces.find(s => s.file === file && s.contract === contract);
const a = surface(before), b = surface(after);
if (!a || !b) throw new Error('Missing compiler surface');
function canonical(x) {
  if (Array.isArray(x)) return x.map(canonical);
  if (x && typeof x === 'object') return Object.fromEntries(Object.keys(x).sort().map(k => [k, canonical(x[k])]));
  return x;
}
const encoded = x => JSON.stringify(canonical(x));
const abi = s => s.abi.map(encoded).sort();
function storage(s) {
  const types = s.storageLayout.types;
  function type(id) {
    const t = types[id];
    if (!t) throw new Error(`Missing storage type ${id}`);
    const result = {encoding: t.encoding, label: t.label, bytes: t.numberOfBytes};
    for (const field of ['base', 'key', 'value']) if (t[field]) result[field] = type(t[field]);
    if (t.members) result.members = t.members.map(member);
    return result;
  }
  function member(m) { return {label: m.label, slot: m.slot, offset: m.offset, type: type(m.type)}; }
  return s.storageLayout.storage.map(member);
}
const sourceHash = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'contracts/solidity', file))).digest('hex');
const expectedAbi = [...a.abi];
const expectedSelectors = {...a.methodIdentifiers};
if (contract === 'CollectionLedger') {
  expectedAbi.push({type: 'event', name: 'EntitlementReleased', anonymous: false, inputs: [
    {name: 'gen', type: 'uint256', internalType: 'uint256', indexed: true},
    {name: 'tokens', type: 'uint256', internalType: 'uint256', indexed: false}
  ]});
}
if (contract === 'MiFrensDividend') {
  expectedAbi.push({type: 'function', name: 'pushTokenIsolated', inputs: [
    {name: 'asset', type: 'address', internalType: 'address'},
    {name: 'to', type: 'address', internalType: 'address'},
    {name: 'amount', type: 'uint256', internalType: 'uint256'}
  ], outputs: [], stateMutability: 'nonpayable'});
  expectedSelectors['pushTokenIsolated(address,address,uint256)'] = 'e184e3bb';
}
const expectedStorage = storage(a);
if (contract === 'PerpVault') {
  const tail = expectedStorage.at(-1);
  if (tail.label !== 'tokYieldScale' || tail.type.bytes !== '32') throw new Error('Unexpected baseline tail');
  expectedStorage.push({label: '_settledTokYield', slot: String(BigInt(tail.slot) + 1n), offset: 0,
    type: {encoding: 'inplace', label: 'uint256', bytes: '32'}});
}
const checks = {
  sourceMatchesCurrentWorktree: b.source_sha256 === sourceHash,
  sameCompiler: a.compiler === b.compiler,
  abiMatchesExpected: encoded(abi({abi: expectedAbi})) === encoded(abi(b)),
  selectorsMatchExpected: encoded(expectedSelectors) === encoded(b.methodIdentifiers),
  storageMatchesExpected: encoded(expectedStorage) === encoded(storage(b)),
  noUnresolvedReferences: after.unresolved.length === 0 && after.unresolvedSelectors.length === 0
};
const result = {contract: file + ':' + contract, baselineSourceSha256: a.source_sha256,
  candidateSourceSha256: sourceHash, checks,
  intentionalAddition: contract === 'PerpVault' ? 'Appended private uint256 _settledTokYield; new deployments only' : contract === 'MiFrensDividend' ? 'pushTokenIsolated(address,address,uint256), self-call only' : contract === 'CollectionLedger' ? 'EntitlementReleased(uint256,uint256) event' : null,
  note: 'AST/type/ABI/storage verification only; does not prove deployed parity or passing regressions.'};
const output = {QuoteOracle: 'ORACLE_SURFACE_CHECK.json', MigrationVesting: 'VESTING_SURFACE_CHECK.json', MiFrensDividend: 'DIVIDEND_SURFACE_CHECK.json', CollectionLedger: 'LEDGER_SURFACE_CHECK.json', CauldronHook: 'HOOK_SURFACE_CHECK.json', SurtaxLib: 'SURTAX_SURFACE_CHECK.json', PoolOps: 'POOLOPS_SURFACE_CHECK.json', CauldronVault: 'VAULT_SURFACE_CHECK.json', PerpVault: 'PERPVAULT_SURFACE_CHECK.json', PerpEngine: 'PERPENGINE_SURFACE_CHECK.json'}[contract];
fs.writeFileSync(path.join(report, 'remediation', output), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(result, null, 2));
if (Object.values(checks).some(v => !v)) process.exitCode = 1;
