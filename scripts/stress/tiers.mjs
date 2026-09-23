#!/usr/bin/env node
/**
 * tiers.mjs — raise / restore PerpEngine leverage tiers THROUGH THE TIMELOCK.
 *
 * WHY A BATCH AND NOT JUST setTiers
 *   maxLeverage() ends with `if (lev > maxLeverageCeiling) lev = maxLeverageCeiling`
 *   (PerpEngine.sol:914). `maxLeverageCeiling` is INTERNAL with no getter; read from
 *   storage slot 10 it is **3**. setTiers alone therefore yields 3x, not 5x. Both
 *   setTiers and setRisk must move, so both go in ONE scheduleBatch/executeBatch —
 *   which also means the engine is never observed in a half-configured state.
 *
 * ORIGINALS (read from chain 2026-09-22, recorded before anything was scheduled):
 *   slot 26 tierDepthWei.length = 3; data = [25e18, 100e18, 300e18]
 *   slot 27 tierLevPacked       = 84148994 == 0x05040302 -> levs [2,3,4,5]
 *   slot 10 maxLeverageCeiling  = 3
 *   setRisk siblings: warmup=60 maintBps=1500 maxNotBps=500 maxOiBps=3000 funding=100
 *
 * Appends to the SAME append-only JSONL as cascade.mjs. Never truncates.
 * Key read from contracts/solidity/.env at runtime; never printed, never written.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createPublicClient, createWalletClient, http, parseAbi, getAddress,
  encodeFunctionData, keccak256, encodeAbiParameters, toHex, decodeErrorResult,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const JSONL = path.join(ROOT, 'audit/STRESS_2026-09-22/cascade-actions.jsonl');
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const MODE = arg('mode', 'read');                 // read | boost | restore
const RUN = arg('run', 'tiers-' + MODE);
const RPC = arg('rpc', process.env.STRESS_RPC || 'https://ethereum-sepolia-rpc.publicnode.com');

const ROUND = JSON.parse(fs.readFileSync(path.join(ROOT, 'indexer/deployments/round.json'), 'utf8'));
const ENGINE_A = getAddress(ROUND.contracts.perpEngine);
const TL = getAddress(ROUND.contracts.timelock);

const transport = http(RPC, { retryCount: 8, retryDelay: 900, timeout: 90_000, batch: false });
const pc = createPublicClient({ chain: sepolia, transport });
const sleep = ms => new Promise(r => setTimeout(r, ms));

const ENGINE_ABI = parseAbi([
  'function setTiers(uint256[] depths, uint8[] levs)',
  'function setRisk(uint256 warmup,uint256 ceiling,uint256 maintBps,uint256 maxNotBps,uint256 maxOiBps,uint256 fundingBpsDay)',
  'function maxLeverage() view returns (uint8)',
  'function activeEthDepth() view returns (uint256)',
  'function warmup() view returns (uint256)',
  'function maintenanceBps() view returns (uint256)',
  'function maxNotionalBps() view returns (uint256)',
  'error BadParam()',
]);
const TL_ABI = parseAbi([
  'function scheduleBatch(address[] targets,uint256[] values,bytes[] payloads,bytes32 predecessor,bytes32 salt,uint256 delay)',
  'function executeBatch(address[] targets,uint256[] values,bytes[] payloads,bytes32 predecessor,bytes32 salt) payable',
  'function hashOperationBatch(address[] targets,uint256[] values,bytes[] payloads,bytes32 predecessor,bytes32 salt) pure returns (bytes32)',
  'function getMinDelay() view returns (uint256)',
  'function isOperationReady(bytes32 id) view returns (bool)',
  'function isOperationDone(bytes32 id) view returns (bool)',
]);

let SEQ = 0;
function put(o) {
  fs.appendFileSync(JSONL, JSON.stringify({ run: RUN, seq: ++SEQ, at: new Date().toISOString(), ...o },
    (_, v) => typeof v === 'bigint' ? v.toString() : v) + '\n');
  return o;
}
function reason(e) {
  try {
    const rv = e?.walk?.(x => x?.name === 'ContractFunctionRevertedError');
    if (rv?.data?.errorName) return rv.data.errorName;
    if (rv?.reason) return 'revert: ' + rv.reason;
    const raw = rv?.raw ?? rv?.data?.data;
    if (raw && raw !== '0x') { try { return decodeErrorResult({ abi: ENGINE_ABI, data: raw }).errorName; } catch { return 'undecoded ' + raw.slice(0, 12); } }
  } catch { }
  return String(e?.shortMessage || e?.message || e).split('\n')[0].slice(0, 220);
}

/** Read the tier config straight out of storage — there are no getters for it. */
async function readTiers(label) {
  const slot = s => pc.getStorageAt({ address: ENGINE_A, slot: toHex(s, { size: 32 }) });
  const len = BigInt(await slot(26n));
  const base = BigInt(keccak256(encodeAbiParameters([{ type: 'uint256' }], [26n])));
  const depths = [];
  for (let i = 0n; i < len; i++) depths.push(BigInt(await slot(base + i)).toString());
  const packed = BigInt(await slot(27n));
  const ceiling = BigInt(await slot(10n));
  const levs = [];
  for (let i = 0; i < Number(len) + 1; i++) levs.push(Number((packed >> BigInt(i * 8)) & 0xffn));
  const [maxLev, depth, warmup, maint, maxNot] = await Promise.all(
    ['maxLeverage', 'activeEthDepth', 'warmup', 'maintenanceBps', 'maxNotionalBps']
      .map(f => pc.readContract({ address: ENGINE_A, abi: ENGINE_ABI, functionName: f })));
  const st = {
    kind: 'tier-state', label, tierDepthWeiLen: len.toString(), tierDepthWei: depths,
    tierLevPacked: packed.toString(), tierLevPackedHex: '0x' + packed.toString(16),
    levsUnpacked: levs, maxLeverageCeiling_slot10: ceiling.toString(),
    maxLeverage: maxLev, activeEthDepth: depth.toString(),
    warmup: warmup.toString(), maintenanceBps: maint.toString(), maxNotionalBps: maxNot.toString(),
  };
  put(st);
  console.log(`[${label}] depths=[${depths}] packed=${packed} levs=[${levs}] ceiling=${ceiling} => maxLeverage()=${maxLev} @depth ${depth}`);
  return st;
}

const PLAN = {
  boost: { depths: [10n ** 18n, 2n * 10n ** 18n, 3n * 10n ** 18n], levs: [3, 4, 5, 5], risk: [60n, 5n, 1500n, 500n, 3000n, 100n], expectLev: 5 },
  restore: { depths: [25n * 10n ** 18n, 100n * 10n ** 18n, 300n * 10n ** 18n], levs: [2, 3, 4, 5], risk: [60n, 3n, 1500n, 500n, 3000n, 100n], expectLev: 2 },
};

(async () => {
  const before = await readTiers(MODE + '/before');
  if (MODE === 'read') return;
  const p = PLAN[MODE];
  if (!p) throw new Error('mode must be read|boost|restore');

  const m = fs.readFileSync(path.join(ROOT, 'contracts/solidity/.env'), 'utf8')
    .match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  const acct = privateKeyToAccount('0x' + m[2]);
  const wc = createWalletClient({ account: acct, chain: sepolia, transport });

  const payloads = [
    encodeFunctionData({ abi: ENGINE_ABI, functionName: 'setTiers', args: [p.depths, p.levs] }),
    encodeFunctionData({ abi: ENGINE_ABI, functionName: 'setRisk', args: p.risk }),
  ];
  const targets = [ENGINE_A, ENGINE_A];
  const values = [0n, 0n];
  const PRED = '0x' + '00'.repeat(32);
  const salt = keccak256(toHex(`cascade-5x-${MODE}-${Date.now()}`));
  const delay = await pc.readContract({ address: TL, abi: TL_ABI, functionName: 'getMinDelay' });
  const opId = await pc.readContract({ address: TL, abi: TL_ABI, functionName: 'hashOperationBatch', args: [targets, values, payloads, PRED, salt] });
  put({ kind: 'timelock-plan', mode: MODE, targets, payloads, salt, opId, delay: delay.toString(), depths: p.depths.map(String), levs: p.levs, risk: p.risk.map(String) });
  console.log(`scheduleBatch op=${opId} delay=${delay}s`);

  const send = async (fn, args, gas) => {
    try {
      const sim = await pc.simulateContract({ address: TL, abi: TL_ABI, functionName: fn, args, account: acct });
      const hash = await wc.writeContract({ ...sim.request, gas });
      const r = await pc.waitForTransactionReceipt({ hash, timeout: 240_000 });
      put({ kind: 'action', phase: 'timelock', action: `${fn} (${MODE})`, ok: r.status === 'success', tx: hash, gasUsed: String(r.gasUsed), block: String(r.blockNumber), opId });
      console.log(`  [${r.status}] ${fn} tx=${hash} gas=${r.gasUsed}`);
      return r.status === 'success';
    } catch (e) {
      const rs = reason(e);
      put({ kind: 'action', phase: 'timelock', action: `${fn} (${MODE})`, ok: false, reason: rs, opId });
      console.log(`  [REV] ${fn} :: ${rs}`);
      return false;
    }
  };

  if (!await send('scheduleBatch', [targets, values, payloads, PRED, salt, delay], 600_000n)) process.exit(1);

  const waitMs = Number(delay) * 1000 + 25_000;
  console.log(`waiting ${waitMs / 1000}s for the timelock...`);
  await sleep(waitMs);
  const ready = await pc.readContract({ address: TL, abi: TL_ABI, functionName: 'isOperationReady', args: [opId] });
  put({ kind: 'note', note: `isOperationReady(${opId}) = ${ready}` });
  for (let i = 0; i < 12 && !ready; i++) { await sleep(20_000); if (await pc.readContract({ address: TL, abi: TL_ABI, functionName: 'isOperationReady', args: [opId] })) break; }

  if (!await send('executeBatch', [targets, values, payloads, PRED, salt], 800_000n)) process.exit(1);

  const after = await readTiers(MODE + '/after');
  const ok = Number(after.maxLeverage) === p.expectLev;
  put({ kind: 'finding', topic: 'tier-change', mode: MODE, expectedMaxLeverage: p.expectLev, actualMaxLeverage: after.maxLeverage, verified: ok, before, after });
  console.log(ok ? `VERIFIED maxLeverage() = ${after.maxLeverage}` : `MISMATCH: wanted ${p.expectLev}, got ${after.maxLeverage}`);
  if (!ok) process.exit(2);
})().catch(e => { console.error('FATAL', e); put({ kind: 'fatal', where: 'tiers.mjs/' + MODE, error: String(e?.shortMessage || e?.message || e).slice(0, 400) }); process.exit(1); });
