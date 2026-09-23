#!/usr/bin/env node
/**
 * stress-market.mjs — live-market stress test against the r45 Sepolia deployment.
 *
 *   node scripts/stress/stress-market.mjs [--wallets N] [--fund 0.04]
 *                                         [--phases fund,trade,gacha,stake,perp,liq,edge]
 *                                         [--dry] [--rpc URL]
 *
 * SAFETY / SECRETS
 *   - The funder key is read from contracts/solidity/.env at RUNTIME and is never
 *     printed, logged, or written to any output file.
 *   - Stress wallets are derived deterministically so a run is reproducible and the
 *     leftovers are refundable. The seed mnemonic is EITHER $STRESS_MNEMONIC or is
 *     derived from the funder key (keccak(key||tag) -> BIP39 entropy). It is never
 *     persisted: re-running with the same funder key re-derives the same wallets.
 *   - State (addresses + what completed) lives in scripts/stress/.state/ so a re-run
 *     does not re-fund wallets that are already funded. No key material in there.
 *
 * DISCIPLINE
 *   - Every action is simulated first. A simulate-revert costs no gas and yields a
 *     decoded error name; that is recorded as a revert with its reason.
 *   - Nothing here is a fix. Findings are observations with a tx hash or a revert string.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createPublicClient, createWalletClient, http, parseEther, formatEther,
  keccak256, toHex, concatHex, stringToHex, encodeAbiParameters, parseAbi,
  toFunctionSelector, getAddress, decodeErrorResult,
} from 'viem';
import { privateKeyToAccount, mnemonicToAccount, english } from 'viem/accounts';
import { entropyToMnemonic } from '@scure/bip39';
import { sepolia } from 'viem/chains';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'contracts/solidity/out');
const STATE_DIR = path.join(__dirname, '.state');
const REPORT_DIR = path.join(ROOT, 'audit/STRESS_2026-09-22');

// ─────────────────────────── config ───────────────────────────
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const flag = (k) => argv.includes('--' + k);

const RPC = arg('rpc', process.env.STRESS_RPC || 'https://ethereum-sepolia-rpc.publicnode.com');
const N_WALLETS = Number(arg('wallets', 40));
const FUND_ETH = arg('fund', '0.04');
const MAX_SPEND_ETH = Number(arg('maxspend', 4));
const DRY = flag('dry');
const PHASES = new Set((arg('phases', 'fund,prime,trade,gacha,stake,perp,liq,edge')).split(','));
const PACE_MS = Number(arg('pace', 250));
const CONC = Number(arg('conc', 4));

//  ADDRESSES COME FROM THE MANIFEST, NOT FROM THIS FILE. The perp stack was
//  redeployed mid-review; anything hardcoded here would have gone stale silently.
//  indexer/deployments/round.json is the committed single source of truth.
const ROUND = JSON.parse(fs.readFileSync(path.join(ROOT, 'indexer/deployments/round.json'), 'utf8'));
if (ROUND.chainId !== sepolia.id) { console.error(`round.json targets chain ${ROUND.chainId}, this harness is Sepolia-only`); process.exit(1); }
const C = ROUND.contracts;
const A = {
  registry:    getAddress(C.registry),
  hook:        getAddress(C.hook),
  collection:  getAddress(C.collection),
  router:      getAddress(C.gachaRouter),
  engine:      getAddress(C.perpEngine),
  vault:       getAddress(C.perpVault),
  poolManager: getAddress(C.poolManager),
  token:       null,   // resolved from the engine at runtime (syncedToken)
};
const EXPECTED_POOL_ID = ROUND.poolIds[0];
// The app pins 8,000,000 on every swap. A stress wallet holding 0.04 ETH cannot
// afford an 8M *reservation* at 1 gwei alongside its trade, so wallet swaps pin 4M
// (a measured empty-book play is 426k; the pre-trade sweep needs ~1.05M more) and
// the funder — who carries the whole book on the crash dump — pins the full 8M.
const SWAP_GAS = 4_000_000n;
const FUNDER_SWAP_GAS = 8_000_000n;
const PERP_GAS = 3_000_000n;

// ─────────────────────────── abi loading ───────────────────────────
function findArtifact(name) {
  const dir = path.join(OUT, name + '.sol');
  if (!fs.existsSync(dir)) return null;
  const files = fs.readdirSync(dir).filter(f => f.startsWith(name + '.') && f.endsWith('.json'));
  if (!files.length) return null;
  files.sort().reverse(); // prefer highest solc version suffix
  return JSON.parse(fs.readFileSync(path.join(dir, files[0]), 'utf8'));
}
const ENGINE_ABI = findArtifact('PerpEngine').abi;
const VAULT_ABI  = findArtifact('PerpVault').abi;
const ROUTER_ABI = (findArtifact('CauldronGachaRouter') || {}).abi || parseAbi([
  'function play(uint256,uint256,uint256,uint256,uint256) payable returns (uint256)',
  'function playChurn(uint256,uint256,uint256,uint256) payable returns (uint256)',
  'function openReady(uint256) returns (uint256)',
]);
const HOOK_ABI = (findArtifact('CauldronHook') || {}).abi || [];
const ERC20 = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address,address) view returns (uint256)',
  'function approve(address,uint256) returns (bool)',
  'function transfer(address,uint256) returns (bool)',
  'function decimals() view returns (uint8)',
]);
const COLLECTION = parseAbi([
  'function liquidatorMinted() view returns (uint256)',
  'function balanceOf(address) view returns (uint256)',
]);
// One merged ABI so viem can name ANY custom error it meets, whoever threw it.
// v4 re-throws a hook revert inside CustomRevert.WrappedError, so a bare decode
// yields the unhelpful selector 0x90bfb865 instead of the hook's real error.
const V4_WRAPPED = parseAbi(['error WrappedError(address target, bytes4 selector, bytes reason, bytes details)']);
const ALL_ERRORS = [...ENGINE_ABI, ...VAULT_ABI, ...ROUTER_ABI, ...HOOK_ABI, ...V4_WRAPPED].filter(x => x.type === 'error');

// ─────────────────────────── clients ───────────────────────────
const transport = http(RPC, { retryCount: 6, retryDelay: 800, timeout: 60_000, batch: false });
const pc = createPublicClient({ chain: sepolia, transport });

function readFunderKey() {
  const p = path.join(ROOT, 'contracts/solidity/.env');
  const m = fs.readFileSync(p, 'utf8').match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  if (!m) throw new Error('PRIVATE_KEY not found in contracts/solidity/.env');
  return '0x' + m[2];
}

// ─────────────────────────── bookkeeping ───────────────────────────
const RESULTS = [];   // {phase, action, ok, tx, gas, reason, note}
const NOTES = [];
const sleep = ms => new Promise(r => setTimeout(r, ms));

/** Peel v4's CustomRevert.WrappedError until the hook's own error is visible. */
function unwrapV4(data, depth = 0) {
  if (!data || data === '0x' || depth > 4) return null;
  try {
    const w = decodeErrorResult({ abi: V4_WRAPPED, data });
    return unwrapV4(w.args[2], depth + 1) || `WrappedError(target=${w.args[0]}, hook fn ${w.args[1]}, inner ${String(w.args[2]).slice(0, 12)})`;
  } catch { /* not a wrapper — try to name it directly */ }
  try { const d = decodeErrorResult({ abi: ALL_ERRORS, data }); return d.errorName + (depth ? ' (via v4 WrappedError)' : ''); } catch { }
  return depth ? `undecoded inner ${String(data).slice(0, 12)} (via v4 WrappedError)` : null;
}

function revertReason(err) {
  try {
    const rv = err?.walk?.(e => e?.name === 'ContractFunctionRevertedError');
    if (rv) {
      const raw = rv.raw ?? rv.data?.data;
      if (rv.data?.errorName === 'WrappedError' || (raw && String(raw).startsWith('0x90bfb865'))) {
        const inner = unwrapV4(raw);
        if (inner) return inner;
      }
      if (rv.data?.errorName) {
        const a = rv.data.args?.length ? '(' + rv.data.args.map(String).join(',') + ')' : '';
        return rv.data.errorName + a;
      }
      if (rv.reason) return 'revert: ' + rv.reason;
      if (rv.signature) return 'undecoded selector ' + rv.signature;
      if (rv.raw === '0x' || rv.raw === undefined) return 'EMPTY revert data (no reason, no selector)';
    }
    const out = err?.walk?.(e => e?.name === 'ContractFunctionZeroDataError');
    if (out) return 'EMPTY revert data (no reason, no selector)';
  } catch { /* fall through */ }
  const s = err?.shortMessage || err?.details || err?.message || String(err);
  return String(s).split('\n')[0].slice(0, 160);
}

function rec(phase, action, ok, extra = {}) {
  const r = { phase, action, ok, ...extra };
  RESULTS.push(r);
  const tag = ok ? 'OK  ' : 'REVERT';
  console.log(`  [${tag}] ${phase}/${action}` +
    (r.tx ? ` tx=${r.tx}` : '') + (r.gas ? ` gas=${r.gas}` : '') +
    (r.reason ? ` :: ${r.reason}` : '') + (r.note ? ` (${r.note})` : ''));
  return r;
}

/**
 * Simulate, then send. A simulate-revert costs nothing and decodes cleanly.
 * `expect` names a revert we PREDICTED — it is reported as a pass with its reason.
 */
async function act(phase, action, wc, req, { expect, note, value } = {}) {
  let sim;
  try {
    sim = await pc.simulateContract({ ...req, account: wc.account, value });
  } catch (e) {
    const reason = revertReason(e);
    const predicted = expect && reason.startsWith(expect);
    return rec(phase, action, !!predicted, {
      reason, note: (predicted ? 'PREDICTED: ' : '') + (note || ''), stage: 'simulate',
    });
  }
  if (DRY) return rec(phase, action, true, { note: 'dry-run, simulate only ' + (note || '') });
  try {
    const hash = await wc.writeContract({ ...sim.request, gas: req.gas ?? sim.request.gas });
    const rcpt = await pc.waitForTransactionReceipt({ hash, timeout: 180_000 });
    await sleep(PACE_MS);
    if (rcpt.status !== 'success') {
      return rec(phase, action, false, { tx: hash, gas: String(rcpt.gasUsed), reason: 'ON-CHAIN REVERT (simulate had passed)', note });
    }
    return rec(phase, action, true, { tx: hash, gas: String(rcpt.gasUsed), note, result: sim.result });
  } catch (e) {
    return rec(phase, action, false, { reason: revertReason(e), note, stage: 'send' });
  }
}

async function pool(items, n, fn) {
  const it = items[Symbol.iterator](); const running = [];
  const runner = async () => { for (;;) { const { value, done } = it.next(); if (done) return; await fn(value); } };
  for (let i = 0; i < n; i++) running.push(runner());
  await Promise.all(running);
}

// ─────────────────────────── state ───────────────────────────
function loadState() {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  const f = path.join(STATE_DIR, `run-${sepolia.id}.json`);
  return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : { funded: {}, fundedTotalWei: '0', phasesDone: [] };
}
function saveState(s) {
  fs.writeFileSync(path.join(STATE_DIR, `run-${sepolia.id}.json`), JSON.stringify(s, null, 2));
}

/**
 * THE SEED — the only thing standing between the funder and ~1.6 ETH of testnet
 * ETH scattered across N wallets. It is persisted (0600, inside the gitignored
 * .state/ directory) so `--sweep` can run from a cold process weeks later, and the
 * derived index range is persisted with it so no wallet can fall off the end.
 * It is NEVER printed and NEVER written to the report.
 *
 * Default derivation is from the funder key, so even a lost state file is
 * recoverable from the same .env — but the file is what makes that guarantee
 * independent of how the key is stored.
 */
function getSeed(funderKey, wantCount) {
  fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
  const f = path.join(STATE_DIR, `seed-${sepolia.id}.json`);
  let s = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null;
  if (!s) {
    const mnemonic = process.env.STRESS_MNEMONIC ||
      entropyToMnemonic(Buffer.from(keccak256(concatHex([funderKey, stringToHex('mifrens-stress-v1')])).slice(2), 'hex'), english);
    s = { mnemonic, count: wantCount, createdAt: new Date().toISOString(), note: 'SECRET. gitignored. never commit, never paste into a report.' };
  }
  // The range only ever grows: a later short run must not orphan earlier wallets.
  if (wantCount > s.count) s.count = wantCount;
  fs.writeFileSync(f, JSON.stringify(s, null, 2), { mode: 0o600 });
  try { fs.chmodSync(f, 0o600); } catch {}
  return s;
}

// ─────────────────────────── snapshots ───────────────────────────
const R = (fn, args = []) => pc.readContract({ address: A.engine, abi: ENGINE_ABI, functionName: fn, args });
const V = (fn, args = []) => pc.readContract({ address: A.vault,  abi: VAULT_ABI,  functionName: fn, args });

async function snapshot(label) {
  const [depth, plv, plvTok, freeEth, totalEth, ins, unabs, longOi, shortOi, openCount, mark, payoutTot] =
    await Promise.all(['activeEthDepth','plv','plvToken','freeEth','totalEth','insuranceEth','unabsorbedEth',
      'longOiEth','shortOiToken','openCount','markSqrtPriceX96','payoutOwedTotal'].map(f => R(f)));
  const [aEth, shares, backing, pend, aTok, tShares, qUnits] =
    await Promise.all(['assetsEth','ethShares','ethBackingMark','pendingEth','assetsTok','tokShares','ethQueueUnits'].map(f => V(f)));
  const snap = { label, at: new Date().toISOString(),
    engine: { activeEthDepth: depth, plv, plvToken: plvTok, freeEth, totalEth, insuranceEth: ins,
              unabsorbedEth: unabs, longOiEth: longOi, shortOiToken: shortOi, openCount, markSqrtPriceX96: mark, payoutOwedTotal: payoutTot },
    vault:  { assetsEth: aEth, ethShares: shares, ethBackingMark: backing, pendingEth: pend, assetsTok: aTok, tokShares: tShares, ethQueueUnits: qUnits } };
  console.log(`\n── snapshot: ${label}`);
  console.log(`   depth=${formatEther(depth)} plv=${formatEther(plv)} plvTok=${formatEther(plvTok)} freeEth=${formatEther(freeEth)} totalEth=${formatEther(totalEth)}`);
  console.log(`   ins=${formatEther(ins)} UNABSORBED=${formatEther(unabs)} longOi=${formatEther(longOi)} shortOiTok=${formatEther(shortOi)} open=${openCount}`);
  console.log(`   vault assetsEth=${formatEther(aEth)} shares=${shares} ethBackingMark=${formatEther(backing)} pendingEth=${formatEther(pend)} assetsTok=${formatEther(aTok)}`);
  SNAPS.push(snap);
  if (unabs > 0n) NOTES.push(`UNABSORBED ETH = ${formatEther(unabs)} at snapshot "${label}"`);
  // R2A pari-passu: the vault's mark should equal the engine backing it tracks.
  const engineBacking = totalEth;
  if (backing !== engineBacking) {
    NOTES.push(`ethBackingMark(${formatEther(backing)}) != engine.totalEth(${formatEther(engineBacking)}) at "${label}" (delta ${formatEther(backing - engineBacking)})`);
  }
  return snap;
}
const SNAPS = [];

// ─────────────────────────── sweep ───────────────────────────
/**
 * --sweep : return every derived wallet's residual ETH to the funder.
 *
 *  Order matters. ETH that is staked in PerpVault or posted as perp collateral is
 *  NOT in the wallet, so each wallet is unwound first: close positions, withdraw
 *  the vault stake, claim anything the queue owes. A withdrawal that QUEUES is not
 *  a failure — free liquidity was short, which is the vault working as designed —
 *  so it is recorded as stranded-but-claimable rather than counted as lost.
 *
 *  Per wallet, everything is caught: one bad nonce must not abandon the other 39.
 */
async function sweep(funder, fwc, wallets, wcs, state) {
  console.log('\n=== SWEEP — returning residual ETH to', funder.address, '===');
  A.token = A.token || getAddress(await R('syncedToken'));
  const rows = [];
  let sweptTotal = 0n, strandedVault = 0n, unrecovered = 0n;

  // one pass over the book so each wallet knows which positions are its own
  const owned = new Map();
  try {
    const next = await R('nextId');
    for (let id = 1n; id < next; id++) {
      const p = await R('positions', [id]);
      if (p[0] === '0x0000000000000000000000000000000000000000') continue;
      const o = getAddress(p[0]); if (!owned.has(o)) owned.set(o, []); owned.get(o).push(id);
    }
  } catch (e) { console.log('  position scan failed:', revertReason(e)); }

  const blk = await pc.getBlock();
  const base = blk.baseFeePerGas ?? (await pc.getGasPrice());
  const tip = 1_500_000_000n;                       // 1.5 gwei priority
  const maxFee = base * 2n + tip;                   // the worst case the tx can cost
  const reserve = 21000n * maxFee;                  // exact upper bound of a plain transfer
  console.log(`  baseFee ${Number(base) / 1e9} gwei | maxFeePerGas ${Number(maxFee) / 1e9} gwei | reserve ${formatEther(reserve)} ETH/wallet`);

  for (let i = 0; i < wallets.length; i++) {
    const a = wallets[i].address, w = wcs[i];
    const row = { i, address: a, closed: [], couldNotClose: [], withdrawn: 0n, queued: 0n, sent: 0n, token: 0n, nfts: 0n, note: '' };
    try {
      // 1. close any open perp position
      for (const id of (owned.get(a) || [])) {
        try {
          const s = await pc.simulateContract({ address: A.engine, abi: ENGINE_ABI, functionName: 'close', args: [id, 0n], account: wallets[i], gas: PERP_GAS });
          const h = await w.writeContract({ ...s.request, gas: PERP_GAS });
          await pc.waitForTransactionReceipt({ hash: h, timeout: 180_000 });
          row.closed.push(String(id));
        } catch (e) { row.couldNotClose.push(`#${id}: ${revertReason(e)}`); }
      }
      // 2. unstake the vault (ETH side, then token side), then bank any queued claim
      try {
        const sh = await V('ethShareOf', [a]);
        if (sh > 0n) {
          const s = await pc.simulateContract({ address: A.vault, abi: VAULT_ABI, functionName: 'withdrawEth', args: [sh], account: wallets[i], gas: 900_000n });
          row.withdrawn = s.result?.[0] ?? 0n; row.queued = s.result?.[1] ?? 0n;
          const h = await w.writeContract({ ...s.request, gas: 900_000n });
          await pc.waitForTransactionReceipt({ hash: h, timeout: 180_000 });
        }
      } catch (e) { row.note += `withdrawEth: ${revertReason(e)}; `; }
      try {
        const ts = await V('tokShareOf', [a]);
        if (ts > 0n) {
          const s = await pc.simulateContract({ address: A.vault, abi: VAULT_ABI, functionName: 'withdrawToken', args: [ts], account: wallets[i], gas: 900_000n });
          const h = await w.writeContract({ ...s.request, gas: 900_000n });
          await pc.waitForTransactionReceipt({ hash: h, timeout: 180_000 });
        }
      } catch (e) { row.note += `withdrawToken: ${revertReason(e)}; `; }
      try {
        if ((await V('pendingEthOf', [a])) > 0n) {
          const s = await pc.simulateContract({ address: A.vault, abi: VAULT_ABI, functionName: 'claimPendingEth', args: [], account: wallets[i], gas: 600_000n });
          const h = await w.writeContract({ ...s.request, gas: 600_000n });
          await pc.waitForTransactionReceipt({ hash: h, timeout: 180_000 });
        }
      } catch (e) { row.note += `claimPendingEth: ${revertReason(e)}; `; }
      // what is still not ETH-in-the-wallet, so nothing is abandoned silently
      row.queued = await V('pendingEthOf', [a]).catch(() => 0n);
      row.token  = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [a] }).catch(() => 0n);
      row.nfts   = await pc.readContract({ address: A.collection, abi: COLLECTION, functionName: 'balanceOf', args: [a] }).catch(() => 0n);
      strandedVault += row.queued;

      // 3. the ETH itself — the exact residual, never a guess
      const bal = await pc.getBalance({ address: a });
      if (bal <= reserve) { row.note += `residual ${formatEther(bal)} <= fee reserve, skipped`; rows.push(row); continue; }
      const value = bal - reserve;
      const hash = await w.sendTransaction({ to: funder.address, value, gas: 21000n, maxFeePerGas: maxFee, maxPriorityFeePerGas: tip });
      await pc.waitForTransactionReceipt({ hash, timeout: 180_000 });
      row.sent = value; sweptTotal += value; row.tx = hash;
    } catch (e) {
      row.note += 'SWEEP FAILED: ' + revertReason(e);
      unrecovered += await pc.getBalance({ address: a }).catch(() => 0n);
    }
    rows.push(row);
    console.log(`  #${i} ${a} sent=${formatEther(row.sent)} tok=${formatEther(row.token)} nft=${row.nfts} queued=${formatEther(row.queued)} ${row.note}`);
    await sleep(PACE_MS);
  }

  const funded = BigInt(state.fundedTotalWei || '0');
  const gasSpent = funded - sweptTotal - strandedVault - unrecovered;
  const recon =
`funded total      ${formatEther(funded)} ETH
swept back        ${formatEther(sweptTotal)} ETH
spent on gas      ${formatEther(gasSpent < 0n ? 0n : gasSpent)} ETH  (funded - swept - stranded - unrecovered; includes every wallet's trade slippage)
stranded in vault ${formatEther(strandedVault)} ETH (queued, claimable later via claimPendingEth)
unrecovered       ${formatEther(unrecovered)} ETH`;
  console.log('\n=== RECONCILIATION ===\n' + recon);
  const failed = rows.filter(r => r.note.includes('SWEEP FAILED') || r.couldNotClose.length);
  if (failed.length) { console.log('\nper-wallet reasons:'); failed.forEach(r => console.log(`  #${r.i} ${r.address}: ${r.note} ${r.couldNotClose.join(' ')}`)); }
  const stillTok = rows.reduce((s, r) => s + r.token, 0n), stillNft = rows.reduce((s, r) => s + r.nfts, 0n);
  console.log(`\nLEFT STRANDED ON PURPOSE (ETH was the stated priority, these were NOT swept):`);
  console.log(`  $GNOME  ${formatEther(stillTok)} across ${rows.filter(r => r.token > 0n).length} wallets`);
  console.log(`  NFTs    ${stillNft} across ${rows.filter(r => r.nfts > 0n).length} wallets (crystals + any Liquidatoor badges)`);
  console.log(`  queued  ${formatEther(strandedVault)} ETH of PerpVault exit claims`);

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  fs.writeFileSync(path.join(REPORT_DIR, 'sweep.json'),
    JSON.stringify({ recon, rows, sweptTotal, strandedVault, unrecovered, stillTok, stillNft },
      (_, v) => typeof v === 'bigint' ? v.toString() : v, 2));
  return { recon, rows, sweptTotal, strandedVault, unrecovered, stillTok, stillNft };
}

// ─────────────────────────── main ───────────────────────────
(async () => {
  console.log('=== Cauldron r45 live stress test — chain 11155111 ===');
  console.log('RPC', RPC, DRY ? '(DRY RUN)' : '');

  const funderKey = readFunderKey();
  const funder = privateKeyToAccount(funderKey);
  const fwc = createWalletClient({ account: funder, chain: sepolia, transport });
  console.log('funder', funder.address);

  const state = loadState();
  // Deterministic + PERSISTED: a sweep must be runnable from a cold process.
  const seed = getSeed(funderKey, N_WALLETS);
  const count = flag('sweep') ? seed.count : N_WALLETS;   // sweeping always walks the FULL recorded range
  const wallets = Array.from({ length: count }, (_, i) => mnemonicToAccount(seed.mnemonic, { addressIndex: i }));
  const wcs = wallets.map(a => createWalletClient({ account: a, chain: sepolia, transport }));
  console.log(`wallets: ${count} derived (indices 0..${count - 1}); seed persisted at scripts/stress/.state/seed-${sepolia.id}.json (gitignored, 0600)`);

  if (flag('sweep')) { await sweep(funder, fwc, wallets, wcs, state); return; }

  // ── preflight ────────────────────────────────────────────────
  console.log('\n── PREFLIGHT');
  A.token = getAddress(await R('syncedToken'));
  console.log('  addresses from indexer/deployments/round.json (round', ROUND.round + ', schema', ROUND.schema + ')');
  console.log('  engine', A.engine, '| vault', A.vault, '| token (engine.syncedToken)', A.token);
  const poolId = keccak256(encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }, { type: 'uint24' }, { type: 'int24' }, { type: 'address' }],
    ['0x0000000000000000000000000000000000000000', A.token, 0, 200, A.hook]));
  console.log('  poolId derived', poolId, poolId === EXPECTED_POOL_ID ? '(matches round.json)' : `(MISMATCH, round.json=${EXPECTED_POOL_ID})`);
  if (poolId !== EXPECTED_POOL_ID) NOTES.push(`poolId mismatch: derived ${poolId} vs round.json ${EXPECTED_POOL_ID}`);
  const POOLKEY = { currency0: '0x0000000000000000000000000000000000000000', currency1: A.token, fee: 0, tickSpacing: 200, hooks: A.hook };

  const code = await pc.getCode({ address: A.router });
  const churnSel = toFunctionSelector('playChurn(uint256,uint256,uint256,uint256)');
  const hasChurn = code.includes(churnSel.slice(2));
  console.log(`  router runtime ${(code.length - 2) / 2} B; playChurn selector ${churnSel} present=${hasChurn}`);
  NOTES.push(`router runtime ${(code.length - 2) / 2} bytes, playChurn selector present=${hasChurn} (r43/r44 shipped 8580 B with it MISSING)`);

  const gasPrice = await pc.getGasPrice();
  const funderBal = await pc.getBalance({ address: funder.address });
  const perWallet = parseEther(FUND_ETH);
  const fundTotal = perWallet * BigInt(N_WALLETS);
  const funderOps = parseEther('1.2');   // staking + the price-crash round trip + edge cases
  const planned = fundTotal + funderOps;
  console.log(`  gasPrice ${Number(gasPrice) / 1e9} gwei | funder balance ${formatEther(funderBal)} ETH`);
  console.log(`  PLAN: ${N_WALLETS} wallets x ${FUND_ETH} ETH = ${formatEther(fundTotal)} ETH funding`);
  console.log(`      + ~${formatEther(funderOps)} ETH funder-side (vault stake, crash round trip, edge cases)`);
  console.log(`      = ESTIMATED TOTAL AT RISK ${formatEther(planned)} ETH (cap ${MAX_SPEND_ETH} ETH)`);
  if (Number(formatEther(planned)) > MAX_SPEND_ETH) { console.error('  ABORT: plan exceeds --maxspend'); process.exit(1); }
  if (funderBal < planned) { console.error('  ABORT: funder cannot cover the plan'); process.exit(1); }

  const s0 = await snapshot('t0 / before anything');

  // ── PHASE fund ───────────────────────────────────────────────
  if (PHASES.has('fund') && !DRY) {
    console.log('\n── PHASE fund (resumable: already-funded wallets are skipped)');
    let nonce = await pc.getTransactionCount({ address: funder.address });
    const sent = [];
    for (let i = 0; i < wallets.length; i++) {
      const a = wallets[i].address;
      const bal = await pc.getBalance({ address: a });
      if (bal >= perWallet / 2n) { console.log(`  skip #${i} ${a} already holds ${formatEther(bal)}`); state.funded[a] = true; continue; }
      const hash = await fwc.sendTransaction({ to: a, value: perWallet, nonce: nonce++ });
      sent.push({ i, a, hash });
      if (sent.length % 8 === 0) await sleep(400);
    }
    if (sent.length) {
      await pc.waitForTransactionReceipt({ hash: sent[sent.length - 1].hash, timeout: 300_000 });
      for (const s of sent) state.funded[s.a] = true;
      state.fundedTotalWei = (BigInt(state.fundedTotalWei || '0') + perWallet * BigInt(sent.length)).toString();
      rec('fund', `funded ${sent.length} wallets @ ${FUND_ETH} ETH`, true, { tx: sent[sent.length - 1].hash, note: `cumulative funded ${formatEther(BigInt(state.fundedTotalWei))} ETH` });
    } else rec('fund', 'all wallets already funded (resume)', true);
    saveState(state);
  }

  const buy = (val, openMax = 0n, gas = SWAP_GAS) => ({
    address: A.router, abi: ROUTER_ABI, functionName: 'play',
    args: [0n, 0n, 0n, 0n, openMax], gas, value: val,
  });
  const H = (fn, args = []) => pc.readContract({ address: A.hook, abi: HOOK_ABI, functionName: fn, args });

  // ── PHASE prime ──────────────────────────────────────────────
  //  At t0 this deployment reads DEAD: getVolume24h < deathThreshold, so
  //  PerpEngine._isDead() is true and EVERY perp entrypoint reverts TokenDead.
  //  _isDead is a live read of hook.isDead(poolId), not a latch, so volume alone
  //  revives it. playChurn is the cheapest volume per wei spent: each of its
  //  buy/sell legs is credited, so one stake bought `loops` legs of volume.
  if (PHASES.has('prime')) {
    console.log('\n── PHASE prime — trade the pool back above the death threshold so perps are reachable');
    const thr = await H('deathThreshold');
    let vol = await H('getVolume24h', [poolId]);
    console.log(`  deathThreshold=${formatEther(thr)} getVolume24h=${formatEther(vol)} isDead=${await H('isDead', [poolId])}`);
    NOTES.push(`t0 DEAD STATE: hook.isDead(pool)=true, getVolume24h=${formatEther(vol)} ETH < deathThreshold=${formatEther(thr)} ETH; every perp entrypoint reverts TokenDead. round.json declares deathThresholdEth: 0, the chain holds ${formatEther(thr)}.`);
    const target = thr + thr / 4n;
    const balBefore = await pc.getBalance({ address: funder.address });
    for (let k = 0; k < 8 && vol < target; k++) {
      const v = parseEther('0.05');
      const r = await act('prime', `playChurn(loops=10) 0.05E #${k}`, fwc, {
        address: A.router, abi: ROUTER_ABI, functionName: 'playChurn',
        args: [0n, 10n, 0n, 0n], gas: FUNDER_SWAP_GAS, value: v,
      }, { value: v, note: 'volume generator' });
      const nv = await H('getVolume24h', [poolId]);
      console.log(`    getVolume24h ${formatEther(vol)} -> ${formatEther(nv)} (target ${formatEther(target)})`);
      if (!r.ok || nv === vol) { NOTES.push(`prime stalled at getVolume24h=${formatEther(nv)}: ${r.reason || 'volume did not move'}`); break; }
      vol = nv;
    }
    const dead = await H('isDead', [poolId]);
    const spent = balBefore - (await pc.getBalance({ address: funder.address }));
    console.log(`  isDead now = ${dead}; priming cost ${formatEther(spent)} ETH (churn slippage + gas)`);
    NOTES.push(`prime: getVolume24h reached ${formatEther(vol)} ETH, hook.isDead=${dead}, cost to the funder ${formatEther(spent)} ETH`);
    rec('prime', 'revive the market above deathThreshold', !dead, { note: `isDead=${dead}, vol=${formatEther(vol)}, cost=${formatEther(spent)} ETH` });
  }

  // ── PHASE trade ──────────────────────────────────────────────
  if (PHASES.has('trade')) {
    console.log('\n── PHASE trade — buys and sells through the pool, varied sizes');
    const sizes = ['0.002', '0.004', '0.006', '0.003', '0.005'];
    await pool(wcs.slice(0, Math.min(20, N_WALLETS)).map((w, i) => [w, i]), CONC, async ([w, i]) => {
      const v = parseEther(sizes[i % sizes.length]);
      await act('trade', `buy#${i} ${sizes[i % sizes.length]}E`, w, buy(v), { value: v });
    });
    // sells: approve the router, hand it tokenIn
    await pool(wcs.slice(0, Math.min(10, N_WALLETS)).map((w, i) => [w, i]), CONC, async ([w, i]) => {
      const bal = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [w.account.address] });
      if (bal === 0n) return rec('trade', `sell#${i}`, false, { reason: 'skipped: wallet holds 0 token (its buy reverted)' });
      const half = bal / 2n;
      await act('trade', `approve#${i}`, w, { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, bal] });
      await act('trade', `sell#${i} half`, w, { address: A.router, abi: ROUTER_ABI, functionName: 'play', args: [0n, half, 0n, 0n, 0n], gas: SWAP_GAS });
    });
    const vol = await pc.readContract({ address: A.hook, abi: HOOK_ABI, functionName: 'cumulativeVolume' }).catch(() => null);
    if (vol !== null) { console.log(`  hook cumulativeVolume = ${formatEther(vol)} ETH`); NOTES.push(`hook.cumulativeVolume after trade phase = ${formatEther(vol)} ETH`); }
    await snapshot('after trade');
  }

  // ── PHASE gacha ──────────────────────────────────────────────
  if (PHASES.has('gacha')) {
    console.log('\n── PHASE gacha — play / playChurn / openReady');
    for (let i = 0; i < Math.min(6, N_WALLETS); i++) {
      const v = parseEther('0.004');
      await act('gacha', `play(openMax=3)#${i}`, wcs[i], buy(v, 3n), { value: v });
    }
    // playChurn — NEVER EXECUTED ON ANY CHAIN before this run.
    for (const [i, loops] of [[6, 2n], [7, 3n], [8, 4n], [9, 1n]]) {
      if (i >= N_WALLETS) continue;
      const v = parseEther('0.005');
      await act('gacha', `playChurn(loops=${loops})#${i}`, wcs[i], {
        address: A.router, abi: ROUTER_ABI, functionName: 'playChurn',
        args: [0n, loops, 0n, 3n], gas: SWAP_GAS, value: v,
      }, { value: v, note: 'first playChurn execution on any chain' });
    }
    if (N_WALLETS > 10) {
      const v = parseEther('0.005');
      await act('gacha', 'playChurn(loops=0) expect BadLoops', wcs[10], {
        address: A.router, abi: ROUTER_ABI, functionName: 'playChurn', args: [0n, 0n, 0n, 0n], gas: SWAP_GAS, value: v,
      }, { value: v, expect: 'BadLoops' });
      await act('gacha', 'playChurn(loops=99) expect BadLoops', wcs[10], {
        address: A.router, abi: ROUTER_ABI, functionName: 'playChurn', args: [0n, 99n, 0n, 0n], gas: SWAP_GAS, value: v,
      }, { value: v, expect: 'BadLoops' });
    }
    for (let i = 0; i < Math.min(4, N_WALLETS); i++) {
      const ready = await pc.readContract({ address: A.hook, abi: HOOK_ABI, functionName: 'crystalsReady', args: [wallets[i].address] }).catch(() => 0n);
      const credit = await pc.readContract({ address: A.hook, abi: HOOK_ABI, functionName: 'creditOf', args: [wallets[i].address] }).catch(() => 0n);
      console.log(`  wallet#${i} creditOf=${credit} crystalsReady=${ready}`);
      if (ready > 0n) await act('gacha', `openReady#${i}`, wcs[i], { address: A.router, abi: ROUTER_ABI, functionName: 'openReady', args: [ready], gas: SWAP_GAS });
    }
    const minted = await pc.readContract({ address: A.collection, abi: COLLECTION, functionName: 'liquidatorMinted' }).catch(() => null);
    if (minted !== null) console.log(`  collection.liquidatorMinted=${minted}`);
    await snapshot('after gacha');
  }

  // ── PHASE stake ──────────────────────────────────────────────
  // PLV is 0 at t0, so this MUST run before any leveraged perp: openLong reverts
  // PlvInsufficient when borrow > plv, and plv only exists once the vault funds it.
  if (PHASES.has('stake')) {
    console.log('\n── PHASE stake — PerpVault depositEth / depositToken / withdraw queue / claimTokYield');
    const stakeA = parseEther('0.30'), stakeB = parseEther('0.10');
    await act('stake', 'funder depositEth 0.30', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'depositEth', args: [], value: stakeA, gas: 800_000n }, { value: stakeA, note: 'creates PLV' });
    if (N_WALLETS > 11) await act('stake', 'wallet#11 depositEth 0.01', wcs[11], { address: A.vault, abi: VAULT_ABI, functionName: 'depositEth', args: [], value: parseEther('0.01'), gas: 800_000n }, { value: parseEther('0.01'), note: 'the STAYING staker' });
    if (N_WALLETS > 12) await act('stake', 'wallet#12 depositEth 0.01', wcs[12], { address: A.vault, abi: VAULT_ABI, functionName: 'depositEth', args: [], value: parseEther('0.01'), gas: 800_000n }, { value: parseEther('0.01'), note: 'the QUEUEING staker' });
    await act('stake', 'depositEth(0) expect ZeroAmount', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'depositEth', args: [], value: 0n, gas: 300_000n }, { value: 0n, expect: 'ZeroAmount' });

    // token side: the funder buys, then stakes token so plvToken exists for shorts
    const tv = parseEther('0.20');
    await act('stake', 'funder buys token for the token-side stake', fwc, buy(tv), { value: tv });
    const tbal = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [funder.address] });
    console.log(`  funder token balance ${formatEther(tbal)}`);
    if (tbal > 0n) {
      const stakeTok = tbal / 2n;
      await act('stake', 'funder approve vault', fwc, { address: A.token, abi: ERC20, functionName: 'approve', args: [A.vault, tbal] });
      await act('stake', 'funder depositToken (half)', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'depositToken', args: [stakeTok], gas: 900_000n }, { note: 'creates plvToken for the short side' });
    }
    await act('stake', 'claimTokYield (no yield yet) expect ZeroAmount', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'claimTokYield', args: [], gas: 400_000n }, { expect: 'ZeroAmount' });
    await snapshot('after stake');
  }

  // ── PHASE perp ───────────────────────────────────────────────
  const OPENED = [];  // {id, wallet, idx, side}
  if (PHASES.has('perp')) {
    console.log('\n── PHASE perp — openLong / openShort / close / funding');
    const plv = await R('plv'), plvTok = await R('plvToken'), minCol = await R('minCollateral'), depth = await R('activeEthDepth');
    const maxNotional = (depth * (await R('maxNotionalBps'))) / 10000n;
    console.log(`  plv=${formatEther(plv)} plvToken=${formatEther(plvTok)} minCollateral=${formatEther(minCol)} maxNotional=${formatEther(maxNotional)}`);

    // 1x longs need no PLV; 2x longs borrow 1x collateral from PLV.
    const longIdx = [13, 14, 15, 16, 17, 18].filter(i => i < N_WALLETS);
    for (const i of longIdx) {
      const col = parseEther('0.012');
      await act('perp', `openLong 2x 0.012E #${i}`, wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [2, 0n, 0n, col], value: col, gas: PERP_GAS }, { value: col });
    }
    if (N_WALLETS > 19) {
      await act('perp', 'openLong 1x 0.008E #19 (no PLV borrow)', wcs[19], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [1, 0n, 0n, parseEther('0.008')], value: parseEther('0.008'), gas: PERP_GAS }, { value: parseEther('0.008') });
    }
    // shorts need plvToken
    const shortIdx = [20, 21].filter(i => i < N_WALLETS);
    for (const i of shortIdx) {
      const col = parseEther('0.010');
      await act('perp', `openShort 2x 0.010E #${i}`, wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openShort', args: [2, 0n, 0n, col], value: col, gas: PERP_GAS }, { value: col, note: 'needs plvToken from vault.depositToken' });
    }

    // catalogue what actually opened
    const next = await R('nextId');
    for (let id = 1n; id < next; id++) {
      const p = await R('positions', [id]);
      if (p[0] !== '0x0000000000000000000000000000000000000000') {
        const owner = getAddress(p[0]);
        const idx = wallets.findIndex(w => w.address === owner);
        OPENED.push({ id, owner, idx, isLong: p[1], collateral: p[3] });
      }
    }
    console.log(`  open positions: ${OPENED.map(o => `#${o.id}(${o.isLong ? 'L' : 'S'},w${o.idx})`).join(' ')}`);
    NOTES.push(`open positions after perp phase: ${OPENED.length} (ids ${OPENED.map(o => o.id).join(',')})`);

    // funding accrual: read fundingDelta on the first position, wait, read again
    if (OPENED.length) {
      const id = OPENED[0].id;
      const d0 = await R('fundingDelta', [id]);
      console.log(`  fundingDelta(#${id}) t0 = ${d0}`);
      await sleep(70_000);
      await act('perp', 'poke() to roll funding', fwc, { address: A.engine, abi: ENGINE_ABI, functionName: 'poke', args: [], gas: 600_000n });
      const d1 = await R('fundingDelta', [id]);
      console.log(`  fundingDelta(#${id}) t+70s = ${d1}`);
      NOTES.push(`funding accrual on position #${id}: ${d0} -> ${d1} over ~70s (rate ${await R('fundingRateBpsPerDay')} bps/day)`);
      rec('perp', `funding accrual #${id}`, d1 !== d0, { note: `${d0} -> ${d1}${d1 === d0 ? ' (UNCHANGED over 70s)' : ''}` });
    }

    // close one long round-trip
    const closeable = OPENED.find(o => o.isLong && o.idx >= 0);
    if (closeable) {
      await act('perp', `close #${closeable.id}`, wcs[closeable.idx], { address: A.engine, abi: ENGINE_ABI, functionName: 'close', args: [closeable.id, 0n], gas: PERP_GAS });
    }
    await snapshot('after perp');
  }

  // ── PHASE liq ────────────────────────────────────────────────
  if (PHASES.has('liq')) {
    console.log('\n── PHASE liq — crash the price so the IN-SWAP sweep fires');
    // A liq-only run has no OPENED from the perp phase: rescan the live book.
    if (!OPENED.length) {
      const next = await R('nextId');
      for (let id = 1n; id < next; id++) {
        const p = await R('positions', [id]);
        if (p[0] === '0x0000000000000000000000000000000000000000') continue;
        const owner = getAddress(p[0]);
        OPENED.push({ id, owner, idx: wallets.findIndex(w => w.address === owner), isLong: p[1], collateral: p[3] });
      }
      console.log(`  rescanned book: ${OPENED.length} open — ${OPENED.map(o => `#${o.id}(${o.isLong ? 'L' : 'S'},w${o.idx})`).join(' ')}`);
    }
    const before = await snapshot('pre-crash');
    const badgesBefore = await R('badgesOwed', [funder.address]);
    const mintedBefore = await pc.readContract({ address: A.collection, abi: COLLECTION, functionName: 'liquidatorMinted' }).catch(() => 0n);

    // buy a slug, then dump it in one swap — the dump is the swap that carries the sweep
    const crash = parseEther('0.55');
    await act('liq', 'funder buys 0.55E of token (ammo)', fwc, buy(crash, 0n, FUNDER_SWAP_GAS), { value: crash });
    const ammo = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [funder.address] });
    console.log(`  funder holds ${formatEther(ammo)} token as crash ammo`);
    await act('liq', 'funder approve router', fwc, { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, ammo] });
    const liqBefore = await Promise.all(OPENED.map(async o => [o.id, await R('isLiquidatable', [o.id]).catch(() => null)]));
    console.log('  isLiquidatable before dump:', liqBefore.map(([i, b]) => `#${i}=${b}`).join(' '));
    await act('liq', 'DUMP all ammo in one swap (in-swap sweep)', fwc, {
      address: A.router, abi: ROUTER_ABI, functionName: 'play', args: [0n, ammo, 0n, 0n, 0n], gas: FUNDER_SWAP_GAS,
    }, { note: 'single swap intended to condemn several positions at once' });

    const after = await snapshot('post-crash');
    const stillOpen = await R('openCount');
    const badgesAfter = await R('badgesOwed', [funder.address]);
    const mintedAfter = await pc.readContract({ address: A.collection, abi: COLLECTION, functionName: 'liquidatorMinted' }).catch(() => 0n);
    console.log(`  openCount ${before.engine.openCount} -> ${stillOpen}; badgesOwed(funder) ${badgesBefore} -> ${badgesAfter}; liquidatorMinted ${mintedBefore} -> ${mintedAfter}`);
    NOTES.push(`crash dump: openCount ${before.engine.openCount} -> ${stillOpen}, badgesOwed(funder) ${badgesBefore}->${badgesAfter}, liquidatorMinted ${mintedBefore}->${mintedAfter}, unabsorbedEth ${formatEther(before.engine.unabsorbedEth)} -> ${formatEther(after.engine.unabsorbedEth)}`);
    rec('liq', 'in-swap sweep liquidated positions', stillOpen < before.engine.openCount, { note: `open ${before.engine.openCount} -> ${stillOpen}` });
    rec('liq', 'liquidator badge accrued (badgesOwed or mint)', badgesAfter > badgesBefore || mintedAfter > mintedBefore, { note: `badgesOwed ${badgesBefore}->${badgesAfter}, minted ${mintedBefore}->${mintedAfter}` });
    if (badgesAfter > badgesBefore) await act('liq', 'claimLiquidatorBadges', fwc, { address: A.engine, abi: ENGINE_ABI, functionName: 'claimLiquidatorBadges', args: [badgesAfter], gas: 2_000_000n });

    // anything the sweep left behind, take with the permissionless liquidate()
    for (const o of OPENED) {
      const liq = await R('isLiquidatable', [o.id]).catch(() => null);
      if (liq === true) await act('liq', `liquidate #${o.id} (permissionless)`, fwc, { address: A.engine, abi: ENGINE_ABI, functionName: 'liquidate', args: [o.id], gas: PERP_GAS });
    }
    await act('liq', 'liquidate a healthy id expect Healthy/NotOpen', fwc, { address: A.engine, abi: ENGINE_ABI, functionName: 'liquidate', args: [9999n], gas: PERP_GAS }, { expect: 'NotOpen' });

    // who bore the loss — staying vs queued
    for (const [lbl, addr] of [['funder', funder.address], ['w11 staying', wallets[11]?.address], ['w12 queueing', wallets[12]?.address]]) {
      if (!addr) continue;
      const sh = await V('ethShareOf', [addr]);
      const pend = await V('pendingEthOf', [addr]);
      console.log(`  ${lbl}: ethShares=${sh} pendingEth=${formatEther(pend)}`);
      NOTES.push(`post-liq ${lbl}: ethShareOf=${sh} pendingEthOf=${formatEther(pend)}`);
    }
    // restore the price so the deployment is left usable
    const back = parseEther('0.45');
    await act('liq', 'buy back to restore price', fwc, buy(back, 0n, FUNDER_SWAP_GAS), { value: back });
    await snapshot('after price restore');
  }

  // ── PHASE edge ───────────────────────────────────────────────
  if (PHASES.has('edge')) {
    console.log('\n── PHASE edge — predicted reverts and the queue paths');
    const minCol = await R('minCollateral'), depth = await R('activeEthDepth');
    const i = Math.min(22, N_WALLETS - 1);
    // exactly minCollateral
    await act('edge', 'openLong 1x at EXACTLY minCollateral', wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [1, 0n, 0n, minCol], value: minCol, gas: PERP_GAS }, { value: minCol });
    // one wei under
    await act('edge', 'openLong 1x at minCollateral-1 expect DustPosition', wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [1, 0n, 0n, minCol - 1n], value: minCol - 1n, gas: PERP_GAS }, { value: minCol - 1n, expect: 'DustPosition' });
    // Over the per-position notional cap. Run from the FUNDER: the cap is ~0.13 ETH
    // of depth, which is more than a 0.04 ETH stress wallet can even put up, so from
    // a wallet this returns "insufficient funds" and never reaches the protocol.
    const tooBig = (depth * 500n) / 10000n + parseEther('0.02');
    await act('edge', 'openLong 2x over maxNotionalBps expect BadLeverage', fwc, { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [2, 0n, 0n, tooBig], value: tooBig, gas: PERP_GAS }, { value: tooBig, expect: 'BadLeverage' });
    // leverage above the tier
    await act('edge', 'openLong 5x expect BadLeverage', wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [5, 0n, 0n, parseEther('0.01')], value: parseEther('0.01'), gas: PERP_GAS }, { value: parseEther('0.01'), expect: 'BadLeverage' });
    // value/amount mismatch on a native book
    await act('edge', 'openLong amount != msg.value expect BadParam', wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [1, 0n, 0n, parseEther('0.02')], value: parseEther('0.01'), gas: PERP_GAS }, { value: parseEther('0.01'), expect: 'BadParam' });
    // unreachable slippage floor
    await act('edge', 'openLong with absurd minTokenOut expect Slippage', wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'openLong', args: [1, 2n ** 200n, 0n, parseEther('0.01')], value: parseEther('0.01'), gas: PERP_GAS }, { value: parseEther('0.01'), expect: 'Slippage' });
    // closing someone else's position
    if (OPENED.length) await act('edge', 'close a position you do not own expect NotTrader/NotOpen', wcs[i], { address: A.engine, abi: ENGINE_ABI, functionName: 'close', args: [OPENED[0].id, 0n], gas: PERP_GAS }, { expect: 'Not' });
    // router with neither value nor tokenIn
    await act('edge', 'play(0,0,..) expect NothingSupplied', wcs[i], { address: A.router, abi: ROUTER_ABI, functionName: 'play', args: [0n, 0n, 0n, 0n, 0n], gas: SWAP_GAS, value: 0n }, { value: 0n, expect: 'NothingSupplied' });
    // an unreachable swap floor
    await act('edge', 'play with absurd minTokenOut expect Slippage', wcs[i], { address: A.router, abi: ROUTER_ABI, functionName: 'play', args: [0n, 0n, 2n ** 200n, 0n, 0n], gas: SWAP_GAS, value: parseEther('0.003') }, { value: parseEther('0.003'), expect: 'Slippage' });
    // the gas-starvation boundary the app pins 8M to avoid
    if (Number(await R('openCount')) > 0) {
      await act('edge', 'swap with 300k gas expect LiqGasStarved', wcs[i], { address: A.router, abi: ROUTER_ABI, functionName: 'play', args: [0n, 0n, 0n, 0n, 0n], gas: 300_000n, value: parseEther('0.003') }, { value: parseEther('0.003'), expect: 'LiqGasStarved' });
    }

    // withdrawal larger than free liquidity -> the queue
    const sh12 = wallets[12] ? await V('ethShareOf', [wallets[12].address]) : 0n;
    const free = await R('freeEth');
    console.log(`  freeEth=${formatEther(free)}; w12 shares=${sh12}`);
    if (sh12 > 0n) {
      await act('edge', 'w12 withdrawEth ALL (queue path if free < owed)', wcs[12], { address: A.vault, abi: VAULT_ABI, functionName: 'withdrawEth', args: [sh12], gas: 900_000n });
      const pend = await V('pendingEthOf', [wallets[12].address]);
      console.log(`  w12 pendingEth after withdraw = ${formatEther(pend)}`);
      NOTES.push(`w12 withdrawEth(all): pendingEthOf=${formatEther(pend)} (queued remainder), vault pendingEth=${formatEther(await V('pendingEth'))}`);
      if (pend > 0n) {
        await act('edge', 'w12 claimPendingEth against the queue', wcs[12], { address: A.vault, abi: VAULT_ABI, functionName: 'claimPendingEth', args: [], gas: 600_000n });
        await act('edge', 'settlePendingEth(w12) permissionless', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'settlePendingEth', args: [wallets[12].address], gas: 600_000n });
      }
    }
    await act('edge', 'withdrawEth(0) expect ZeroShares', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'withdrawEth', args: [0n], gas: 400_000n }, { expect: 'ZeroShares' });
    await act('edge', 'withdrawEth(more than owned) expect InsufficientShares', fwc, { address: A.vault, abi: VAULT_ABI, functionName: 'withdrawEth', args: [2n ** 200n], gas: 400_000n }, { expect: 'InsufficientShares' });
    await snapshot('after edge');
  }

  // ── final invariants + report ────────────────────────────────
  const final = await snapshot('final');
  const unabs = final.engine.unabsorbedEth;
  console.log(`\n=== INVARIANT: unabsorbedEth = ${formatEther(unabs)} ETH ${unabs === 0n ? '(zero — no loss exceeded insurance + PLV)' : '<<< NON-ZERO'}`);
  console.log(`=== INVARIANT: vault.ethBackingMark = ${formatEther(final.vault.ethBackingMark)} vs engine.totalEth = ${formatEther(final.engine.totalEth)}`);

  writeReport({ funder: funder.address, wallets: wallets.map(w => w.address), poolId, hasChurn, gasPrice });
  printTable();
  console.log(`\nmachine report: ${path.join(REPORT_DIR, 'run-report.md')}`);
})().catch(e => { console.error('\nFATAL', e); try { printTable(); } catch {} process.exit(1); });

// ─────────────────────────── output ───────────────────────────
function group() {
  const byPhase = new Map();
  for (const r of RESULTS) {
    if (!byPhase.has(r.phase)) byPhase.set(r.phase, { attempted: 0, ok: 0, reverted: 0, reasons: new Map() });
    const g = byPhase.get(r.phase); g.attempted++;
    if (r.ok) g.ok++; else { g.reverted++; const k = r.reason || 'unknown'; g.reasons.set(k, (g.reasons.get(k) || 0) + 1); }
  }
  return byPhase;
}
function printTable() {
  console.log('\n================ SUMMARY ================');
  console.log('phase      attempted  succeeded  reverted   reasons');
  for (const [p, g] of group()) {
    const rs = [...g.reasons.entries()].map(([k, n]) => `${k} x${n}`).join('; ') || '-';
    console.log(`${p.padEnd(10)} ${String(g.attempted).padStart(9)} ${String(g.ok).padStart(10)} ${String(g.reverted).padStart(9)}   ${rs}`);
  }
  if (NOTES.length) { console.log('\nNOTES'); NOTES.forEach(n => console.log('  - ' + n)); }
}
function writeReport(meta) {
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const j = (o) => JSON.stringify(o, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2);
  fs.writeFileSync(path.join(REPORT_DIR, 'results.json'), j({ meta: { ...meta, gasPrice: meta.gasPrice?.toString() }, snapshots: SNAPS, results: RESULTS, notes: NOTES }));
  let md = `# Live-market stress test — Cauldron r45 on Sepolia (11155111)\n\n`;
  md += `Harness: \`scripts/stress/stress-market.mjs\`. Generated ${new Date().toISOString()}.\n\n`;
  md += `## Summary\n\n| phase | attempted | succeeded | reverted | revert reasons (grouped) |\n|---|---:|---:|---:|---|\n`;
  for (const [p, g] of group()) {
    const rs = [...g.reasons.entries()].map(([k, n]) => `\`${k}\` x${n}`).join('<br>') || '-';
    md += `| ${p} | ${g.attempted} | ${g.ok} | ${g.reverted} | ${rs} |\n`;
  }
  md += `\n## Notes\n\n` + (NOTES.map(n => '- ' + n).join('\n') || '- none') + '\n';
  md += `\n## Snapshots\n\n| point | activeEthDepth | plv | freeEth | totalEth | insurance | **unabsorbedEth** | openCount | vault.assetsEth | vault.ethBackingMark | vault.pendingEth |\n|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const s of SNAPS) {
    const e = s.engine, v = s.vault;
    md += `| ${s.label} | ${formatEther(e.activeEthDepth)} | ${formatEther(e.plv)} | ${formatEther(e.freeEth)} | ${formatEther(e.totalEth)} | ${formatEther(e.insuranceEth)} | **${formatEther(e.unabsorbedEth)}** | ${e.openCount} | ${formatEther(v.assetsEth)} | ${formatEther(v.ethBackingMark)} | ${formatEther(v.pendingEth)} |\n`;
  }
  md += `\n## Every action\n\n| phase | action | result | tx / reason | gas |\n|---|---|---|---|---|\n`;
  for (const r of RESULTS) {
    const detail = r.tx ? `[${r.tx.slice(0, 18)}…](https://sepolia.etherscan.io/tx/${r.tx})` : '`' + (r.reason || '') + '`';
    md += `| ${r.phase} | ${r.action} | ${r.ok ? 'ok' : 'REVERT'} | ${detail} | ${r.gas || ''} |\n`;
  }
  // run-report.md is MACHINE output, rewritten every run. FINDINGS.md is the
  // authored report and is deliberately never touched from here.
  fs.writeFileSync(path.join(REPORT_DIR, 'run-report.md'), md);
}
