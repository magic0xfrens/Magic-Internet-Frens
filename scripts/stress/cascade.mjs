#!/usr/bin/env node
/**
 * cascade.mjs — live cascade-liquidation stress test, r45 Sepolia.
 *
 * WHY THIS EXISTS AND NOT stress-market.mjs
 *   stress-market.mjs accumulates every action in a module-level RESULTS array and
 *   writes it exactly once, at the very end of main(), via writeReport() — which
 *   TRUNCATES results.json and run-report.md. Every phase body is gated on
 *   `PHASES.has(...)`, so an invocation with a narrow --phases pushes only a few
 *   records and then overwrites the previous full run's file wholesale. That is how
 *   a genuine 92-action run ended up on disk as `results: 0` with an empty table:
 *   the evidence was destroyed by a later, narrower invocation. The recorder was
 *   never the bug; the last-invocation-wins WRITER was.
 *
 *   So here: every record is appended to a JSONL the instant the tx resolves
 *   (fs.appendFileSync, O_APPEND). A crash, a rate-limit or a kill -9 leaves a
 *   partial record, never an empty one. Nothing in this file ever truncates the
 *   JSONL, and nothing overwrites a prior run's records — each line carries its own
 *   `run` tag, so a later narrow run can only ever ADD. CASCADE.md is authored from
 *   that log; the log, not the prose, is the evidence of record.
 *
 * SECRETS: the funder key is read from contracts/solidity/.env at runtime and is
 * never printed or written anywhere. No mnemonic is used — every action is funder-
 * signed, so there is nothing to sweep out of derived wallets.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createPublicClient, createWalletClient, http, parseEther, formatEther,
  parseAbi, getAddress, decodeErrorResult,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'contracts/solidity/out');
const REPORT_DIR = path.join(ROOT, 'audit/STRESS_2026-09-22');
const JSONL = path.join(REPORT_DIR, 'cascade-actions.jsonl');
fs.mkdirSync(REPORT_DIR, { recursive: true });

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const flag = (k) => argv.includes('--' + k);
const RPC = arg('rpc', process.env.STRESS_RPC || 'https://ethereum-sepolia-rpc.publicnode.com');
const RUN = arg('run', new Date().toISOString());
const N_TARGET = Number(arg('n', 16));
// MEASURED, not assumed (preflight run):
//   maxLeverage() = 2  -> borrow == collateral, notional == 2x collateral
//   ethShareOf(funder) == ethShares  -> the funder ALREADY owns 100% of the vault's
//     ETH side (0.3043 ETH). totalEth = plv + longOiEth is conserved by an open, so
//     ANY longOiEth > 0 puts freeEth below a full-share withdrawal. The queue does not
//     need a big new stake to engage; the deposit below exists to test _markEth.
//   funder already holds ~8.2e25 token units of crash ammunition.
const STAKE = arg('stake', '0.02');       // small: this is the ethBackingMark re-baseline probe
const INVENTORY = arg('inv', '1.0');      // ETH of token bought as extra crash ammunition
const UTIL_TARGET = Number(arg('util', 0.72)); // fraction of totalEth to lend out (maxUtilBps is 8000)
const MAXSPEND = Number(arg('maxspend', 2.5));
const ONLY = arg('only', null);           // phase filter for RESUME only; never truncates

const ROUND = JSON.parse(fs.readFileSync(path.join(ROOT, 'indexer/deployments/round.json'), 'utf8'));
if (ROUND.chainId !== sepolia.id) { console.error('round.json is not Sepolia'); process.exit(1); }
const C = ROUND.contracts;
const A = {
  hook: getAddress(C.hook), engine: getAddress(C.perpEngine), vault: getAddress(C.perpVault),
  router: getAddress(C.gachaRouter), collection: getAddress(C.collection), registry: getAddress(C.registry),
  token: null,
};

function art(n) {
  const d = path.join(OUT, n + '.sol');
  const f = fs.readdirSync(d).filter(x => x.startsWith(n + '.') && x.endsWith('.json')).sort().reverse()[0];
  return JSON.parse(fs.readFileSync(path.join(d, f), 'utf8'));
}
const ENGINE = art('PerpEngine').abi;
const VAULT = art('PerpVault').abi;
const ROUTER = art('CauldronGachaRouter').abi;
const HOOK = art('CauldronHook').abi;
const COLL = art('CauldronCollection').abi;
const ERC20 = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function approve(address,uint256) returns (bool)',
  'function decimals() view returns (uint8)',
]);
const V4_WRAPPED = parseAbi(['error WrappedError(address target, bytes4 selector, bytes reason, bytes details)']);
const ALL_ERRORS = [...ENGINE, ...VAULT, ...ROUTER, ...HOOK, ...V4_WRAPPED].filter(x => x.type === 'error');

const transport = http(RPC, { retryCount: 8, retryDelay: 900, timeout: 90_000, batch: false });
const pc = createPublicClient({ chain: sepolia, transport });
const sleep = ms => new Promise(r => setTimeout(r, ms));

function funderKey() {
  const m = fs.readFileSync(path.join(ROOT, 'contracts/solidity/.env'), 'utf8')
    .match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  if (!m) throw new Error('PRIVATE_KEY not in contracts/solidity/.env');
  return '0x' + m[2];
}

/** Peel v4's CustomRevert.WrappedError until the hook's own error name is visible. */
function unwrapV4(data, depth = 0) {
  if (!data || data === '0x' || depth > 5) return null;
  try {
    const w = decodeErrorResult({ abi: V4_WRAPPED, data });
    const inner = unwrapV4(w.args[2], depth + 1);
    return inner ? `${inner} [unwrapped from v4 WrappedError(target=${w.args[0]}, hookFn=${w.args[1]})]`
                 : `WrappedError(target=${w.args[0]}, hookFn=${w.args[1]}, inner=${String(w.args[2]).slice(0, 12)})`;
  } catch { /* not a wrapper */ }
  try { return decodeErrorResult({ abi: ALL_ERRORS, data }).errorName; } catch { }
  return `undecoded ${String(data).slice(0, 12)}`;
}
function reason(e) {
  try {
    const rv = e?.walk?.(x => x?.name === 'ContractFunctionRevertedError');
    if (rv) {
      const raw = rv.raw ?? rv.data?.data ?? rv.signature;
      const u = raw && raw !== '0x' ? unwrapV4(raw) : null;
      if (u) return u;
      if (rv.data?.errorName) return rv.data.errorName;
      if (rv.reason) return 'revert: ' + rv.reason;
      if (rv.raw === '0x' || rv.raw === undefined) return 'EMPTY revert data';
    }
  } catch { }
  return String(e?.shortMessage || e?.details || e?.message || e).split('\n')[0].slice(0, 200);
}

// ───────────── append-only recorder: the ONE thing the last harness lacked ─────────────
let SEQ = 0;
function put(obj) {
  const line = JSON.stringify({ run: RUN, seq: ++SEQ, at: new Date().toISOString(), ...obj },
    (_, v) => typeof v === 'bigint' ? v.toString() : v);
  fs.appendFileSync(JSONL, line + '\n');   // O_APPEND, flushed per record. Never truncated.
  return obj;
}
function rec(phase, action, ok, extra = {}) {
  const r = put({ kind: 'action', phase, action, ok, ...extra });
  console.log(`  [${ok ? 'OK ' : 'REV'}] ${phase}/${action}` +
    (r.tx ? ` tx=${r.tx}` : '') + (r.gasUsed ? ` gas=${r.gasUsed}` : '') +
    (r.reason ? ` :: ${r.reason}` : '') + (r.note ? ` (${r.note})` : ''));
  return r;
}

const R = (fn, args = []) => pc.readContract({ address: A.engine, abi: ENGINE, functionName: fn, args });
const V = (fn, args = []) => pc.readContract({ address: A.vault, abi: VAULT, functionName: fn, args });
const H = (fn, args = []) => pc.readContract({ address: A.hook, abi: HOOK, functionName: fn, args });

async function snapshot(label, funder) {
  const g = async (f, fn, args) => { try { return await f(fn, args); } catch { return null; } };
  const [depth, plv, freeEth, totalEth, ins, unabs, longOi, shortOi, open, mark, payout, badges] =
    await Promise.all(['activeEthDepth', 'plv', 'freeEth', 'totalEth', 'insuranceEth', 'unabsorbedEth',
      'longOiEth', 'shortOiToken', 'openCount', 'markSqrtPriceX96', 'payoutOwedTotal']
      .map(f => g(R, f)).concat([g(R, 'badgesOwed', [funder])]));
  const [aEth, shares, backing, pend, pendMine, qUnits, qIdx, qEpoch, myShare, aTok] =
    await Promise.all(['assetsEth', 'ethShares', 'ethBackingMark', 'pendingEth'].map(f => g(V, f))
      .concat([g(V, 'pendingEthOf', [funder]), g(V, 'ethQueueUnits'), g(V, 'ethQueueIndex'),
               g(V, 'ethQueueEpoch'), g(V, 'ethShareOf', [funder]), g(V, 'assetsTok')]));
  const [vol, dead, minted] = await Promise.all([
    g(H, 'cumulativeVolume'), g(H, 'isDead', [ROUND.poolIds[0]]),
    pc.readContract({ address: A.collection, abi: COLL, functionName: 'liquidatorMinted' }).catch(() => null),
  ]);
  const s = {
    kind: 'snapshot', label,
    engine: { activeEthDepth: depth, plv, freeEth, totalEth, insuranceEth: ins, unabsorbedEth: unabs,
              longOiEth: longOi, shortOiToken: shortOi, openCount: open, markSqrtPriceX96: mark,
              payoutOwedTotal: payout, badgesOwedFunder: badges },
    vault: { assetsEth: aEth, ethShares: shares, ethBackingMark: backing, pendingEth: pend,
             pendingEthOfFunder: pendMine, ethQueueUnits: qUnits, ethQueueIndex: qIdx,
             ethQueueEpoch: qEpoch, ethShareOfFunder: myShare, assetsTok: aTok },
    market: { cumulativeVolume: vol, isDead: dead, liquidatorMinted: minted },
  };
  put(s);
  console.log(`\n── ${label}`);
  console.log(`   plv=${formatEther(plv)} freeEth=${formatEther(freeEth)} totalEth=${formatEther(totalEth)} longOi=${formatEther(longOi)} depth=${formatEther(depth)}`);
  console.log(`   ins=${formatEther(ins)} UNABSORBED=${formatEther(unabs)} open=${open} badges=${badges} minted=${minted} vol=${vol === null ? '?' : formatEther(vol)} dead=${dead}`);
  console.log(`   vault assets=${formatEther(aEth)} mark=${formatEther(backing)} (delta ${formatEther(backing - totalEth)}) pendingEth=${formatEther(pend)} mine=${formatEther(pendMine)} qUnits=${qUnits}`);
  return s;
}

/** Simulate then send; the record hits disk before this returns either way. */
async function act(phase, action, wc, req, { expect, note, value } = {}) {
  let sim;
  try {
    sim = await pc.simulateContract({ ...req, account: wc.account, value });
  } catch (e) {
    const rs = reason(e);
    const hit = expect && rs.includes(expect);
    return rec(phase, action, !!hit, { reason: rs, note: (hit ? 'PREDICTED: ' : '') + (note || ''), stage: 'simulate', gasSupplied: req.gas ? String(req.gas) : null });
  }
  try {
    const hash = await wc.writeContract({ ...sim.request, gas: req.gas ?? sim.request.gas });
    const rcpt = await pc.waitForTransactionReceipt({ hash, timeout: 240_000 });
    await sleep(300);
    const ok = rcpt.status === 'success';
    return rec(phase, action, ok, {
      tx: hash, gasUsed: String(rcpt.gasUsed), gasSupplied: req.gas ? String(req.gas) : null,
      block: String(rcpt.blockNumber), note, reason: ok ? undefined : 'ON-CHAIN REVERT (simulate passed)',
      result: sim.result,
    });
  } catch (e) {
    return rec(phase, action, false, { reason: reason(e), note, stage: 'send', gasSupplied: req.gas ? String(req.gas) : null });
  }
}

const want = p => !ONLY || ONLY.split(',').includes(p);

(async () => {
  console.log('=== CASCADE stress — Cauldron r45, Sepolia 11155111 ===');
  const acct = privateKeyToAccount(funderKey());
  const wc = createWalletClient({ account: acct, chain: sepolia, transport });
  const F = acct.address;
  console.log('funder', F, '\nJSONL', JSONL, '\nrun', RUN);

  // resolve the token from the CHAIN, not from this file
  for (const fn of ['syncedToken', 'token', 'tok', 'quoteToken']) {
    try { const t = await R(fn); if (t && t !== '0x0000000000000000000000000000000000000000') { A.token = getAddress(t); put({ kind: 'note', note: `token resolved from engine.${fn}() = ${A.token}` }); break; } } catch { }
  }
  if (!A.token) { for (const fn of ['token', 'memeToken']) { try { const t = await H(fn); if (t) { A.token = getAddress(t); put({ kind: 'note', note: `token resolved from hook.${fn}() = ${A.token}` }); break; } } catch { } } }
  if (!A.token) throw new Error('could not resolve token from chain');

  const bal0 = await pc.getBalance({ address: F });
  const gasPrice = await pc.getGasPrice();
  put({ kind: 'note', note: `funder balance ${formatEther(bal0)} ETH, gasPrice ${Number(gasPrice) / 1e9} gwei, token ${A.token}` });

  // ── risk params, read live ───────────────────────────────────
  const P = {};
  for (const f of ['minCollateral', 'maxLeverage', 'maxNotionalBps', 'maxLiqBps', 'MAX_OPEN_POSITIONS', 'maxFundingBps'])
    P[f] = await R(f).catch(() => null);
  put({ kind: 'params', params: P });
  console.log('params', Object.fromEntries(Object.entries(P).map(([k, v]) => [k, String(v)])));

  const s0 = await snapshot('t0 / before anything', F);
  if (s0.market.isDead) put({ kind: 'note', note: 'TokenDead at t0 — every perp entrypoint will revert TokenDead' });

  const LEV = Number(P.maxLeverage || 3n);
  const spend = { stake: 0n, collateral: 0n, inventory: 0n };

  // ── 1. ethBackingMark re-baseline test + the stake ───────────
  if (want('stake')) {
    console.log('\n── PHASE stake (also: does deposit re-baseline ethBackingMark via _markEth?)');
    const markBefore = await V('ethBackingMark'), totBefore = await R('totalEth');
    put({ kind: 'note', note: `markEth probe BEFORE deposit: ethBackingMark=${markBefore} totalEth=${totBefore} delta=${markBefore - totBefore}` });
    const v = parseEther(STAKE);
    const r = await act('stake', `depositEth ${STAKE}`, wc, { address: A.vault, abi: VAULT, functionName: 'depositEth', gas: 900_000n }, { value: v });
    if (r.ok) spend.stake += v;
    const markAfter = await V('ethBackingMark'), totAfter = await R('totalEth');
    put({ kind: 'finding', topic: 'ethBackingMark', note: `AFTER deposit: ethBackingMark=${markAfter} totalEth=${totAfter} delta=${markAfter - totAfter}`, rebaselined: markAfter === totAfter });
    console.log(`  markEth: delta before ${formatEther(markBefore - totBefore)} -> after ${formatEther(markAfter - totAfter)}  rebaselined=${markAfter === totAfter}`);
    await snapshot('after stake', F);
  }

  // ── 2. crash ammunition ──────────────────────────────────────
  if (want('inv')) {
    console.log('\n── PHASE inventory (buy token to sell into the cascade)');
    const v = parseEther(INVENTORY);
    const r = await act('inv', `buy ${INVENTORY} ETH of token`, wc,
      { address: A.router, abi: ROUTER, functionName: 'play', args: [v, 0n, 0n, 0n, 0n], gas: 8_000_000n }, { value: v });
    if (r.ok) spend.inventory += v;
    const tb = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });
    put({ kind: 'note', note: `funder token balance after inventory buy = ${tb}` });
  }

  // ── 3. the cluster ───────────────────────────────────────────
  const OPENED = [];
  if (want('cluster')) {
    console.log('\n── PHASE cluster');
    const plv = await R('plv'), tot = await R('totalEth'), depth = await R('activeEthDepth');
    // Size from the READ params, not from assumption. The binding ceiling is PLV:
    // _utilGate caps longOiEth at maxUtilBps (8000) of totalEth, and totalEth is only
    // 0.3043 ETH. Depth (2.85 ETH) and maxOiBps never come close to binding here — the
    // honest cluster size is ~16 positions, not 100, exactly as the brief predicted.
    const needBorrow = (tot * BigInt(Math.round(UTIL_TARGET * 10_000))) / 10_000n;
    const perBorrow = needBorrow / BigInt(N_TARGET);
    let coll = perBorrow / BigInt(LEV - 1);
    const minColl = P.minCollateral || parseEther('0.003');
    if (coll < (minColl * 115n) / 100n) coll = (minColl * 115n) / 100n;   // clear minCollateral AFTER the open fee
    const notionalCap = (depth * (P.maxNotionalBps || 500n)) / 10_000n;
    if (coll * BigInt(LEV) > notionalCap) coll = (notionalCap * 95n) / (100n * BigInt(LEV));
    put({ kind: 'plan', note: 'cluster sizing', plv, totalEth: tot, depth, lev: LEV, n: N_TARGET, collateralEach: coll, borrowEach: coll * BigInt(LEV - 1), notionalEach: coll * BigInt(LEV), notionalCap, needBorrow });
    console.log(`  plan: ${N_TARGET} longs, lev ${LEV}, collateral ${formatEther(coll)} each, borrow ${formatEther(coll * BigInt(LEV - 1))} each, notional cap ${formatEther(notionalCap)}`);

    let nonce = await pc.getTransactionCount({ address: F });
    for (let i = 0; i < N_TARGET; i++) {
      const idBefore = await R('nextId').catch(() => null);
      const r = await act('cluster', `openLong#${i} lev${LEV} ${formatEther(coll)}E`, wc,
        { address: A.engine, abi: ENGINE, functionName: 'openLong', args: [LEV, 0n, 0n, coll], gas: 3_000_000n },
        { value: coll, expect: 'PlvInsufficient', note: `expected ceilings: PlvInsufficient | OiCapped | UtilCapped | DustPosition` });
      if (!r.ok || !r.tx) { put({ kind: 'note', note: `cluster stopped at i=${i}: ${r.reason}` }); break; }
      spend.collateral += coll;
      const id = r.result !== undefined && r.result !== null ? BigInt(r.result) : (idBefore ?? 0n);
      const p = await R('positions', [id]).catch(() => null);
      const liq = await R('isLiquidatable', [id]).catch(() => null);
      const health = await R('positionHealth', [id]).catch(() => null);
      const o = { id: String(id), collateral: p ? String(p[2]) : null, size: p ? String(p[3]) : null,
                  principal: p ? String(p[4]) : null, leverage: p ? String(p[6]) : null,
                  isLiquidatableAtOpen: liq, health: health ? health.map(String) : null, tx: r.tx };
      OPENED.push(o);
      put({ kind: 'position', ...o });
      console.log(`    #${id} coll=${p ? formatEther(p[2]) : '?'} size=${p ? p[3] : '?'} liqAtOpen=${liq}`);
      nonce++;
    }
    put({ kind: 'note', note: `cluster opened ${OPENED.length}/${N_TARGET}: ids ${OPENED.map(o => o.id).join(',')}` });
    await snapshot('after cluster', F);
  }

  // ── 4. the unstaking queue ───────────────────────────────────
  if (want('queue')) {
    console.log('\n── PHASE queue');
    const free = await R('freeEth'), myShares = await V('ethShareOf', [F]), assets = await V('assetsEth'), tot = await V('ethShares');
    const myValue = tot > 0n ? (assets * myShares) / tot : 0n;
    put({ kind: 'plan', note: 'queue preconditions', freeEth: free, myShares, myValueEth: myValue, willQueue: myValue > free });
    console.log(`  freeEth=${formatEther(free)} my withdrawal worth ${formatEther(myValue)} -> queue expected: ${myValue > free}`);
    if (myShares === 0n) {
      put({ kind: 'finding', topic: 'queue', note: 'BLOCKED: funder holds 0 vault shares; nothing to withdraw', freeEth: free });
    } else {
      const r = await act('queue', 'withdrawEth(all funder shares)', wc,
        { address: A.vault, abi: VAULT, functionName: 'withdrawEth', args: [myShares], gas: 1_200_000n });
      put({ kind: 'finding', topic: 'queue', engaged: (await V('pendingEthOf', [F])) > 0n,
            result: r.result ? r.result.map(String) : null, pendingEth: await V('pendingEth'),
            pendingEthOfFunder: await V('pendingEthOf', [F]), ethQueueUnits: await V('ethQueueUnits'),
            ethQueueIndex: await V('ethQueueIndex'), ethQueueEpoch: await V('ethQueueEpoch'),
            ethBackingMark: await V('ethBackingMark'), freeEthAtWithdraw: free, tx: r.tx, reason: r.reason });
      console.log(`  queued: pendingEthOf=${formatEther(await V('pendingEthOf', [F]))} pendingEth=${formatEther(await V('pendingEth'))} qUnits=${await V('ethQueueUnits')}`);
    }
    await snapshot('after withdraw attempt', F);
  }

  // A resumed run has no in-memory cluster. Rebuild it from the append-only log —
  // which is the whole point of writing each record the instant it resolves.
  function replayPositions() {
    if (!fs.existsSync(JSONL)) return [];
    const seen = new Map();
    for (const l of fs.readFileSync(JSONL, 'utf8').split('\n')) {
      if (!l.trim()) continue;
      try { const o = JSON.parse(l); if (o.kind === 'position') seen.set(o.id, o); } catch { }
    }
    return [...seen.values()];
  }

  // ── 5. pre-emptive check + gas dose-response + the cascade ───
  if (want('cascade')) {
    console.log('\n── PHASE cascade');
    if (!OPENED.length) { OPENED.push(...replayPositions()); put({ kind: 'note', note: `cascade resumed: replayed ${OPENED.length} positions from the JSONL` }); }
    const ids = OPENED.length ? OPENED.map(o => BigInt(o.id)) : [];
    const pre = [];
    for (const id of ids) pre.push([String(id), await R('isLiquidatable', [id]).catch(() => null)]);
    put({ kind: 'finding', topic: 'preemptive', note: 'isLiquidatable() at SPOT immediately before the cascade swap', readings: pre });
    console.log('  isLiquidatable at spot pre-swap:', pre.map(([i, b]) => `${i}=${b}`).join(' '));

    const before = await snapshot('pre-cascade', F);
    const tb = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });
    console.log(`  crash ammunition: ${tb} token units`);
    await act('cascade', 'approve router for full token balance', wc,
      { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, tb], gas: 120_000n });

    // DOSE-RESPONSE: same call, four gas limits, simulated (an eth_call honours `gas`,
    // so a refusal costs nothing and still yields the hook's real error once unwrapped).
    const doses = [1_000_000n, 4_000_000n, 8_000_000n, 16_000_000n];
    const table = [];
    let fillGas = null;
    for (const g of doses) {
      let row;
      try {
        await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play',
          args: [0n, tb, 0n, 0n, 0n], account: acct, gas: g });
        row = { gasSupplied: String(g), outcome: 'FILLS', error: null };
        if (!fillGas) fillGas = g;
      } catch (e) {
        row = { gasSupplied: String(g), outcome: 'REFUSED', error: reason(e) };
      }
      table.push(row);
      put({ kind: 'dose', ...row });
      console.log(`    gas ${Number(g) / 1e6}M -> ${row.outcome}${row.error ? ' :: ' + row.error : ''}`);
    }
    put({ kind: 'finding', topic: 'gas-dose-response', table });

    const sendGas = fillGas || 16_000_000n;
    const r = await act('cascade', `ONE SELL of entire token balance @ gas ${Number(sendGas) / 1e6}M`, wc,
      { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, tb, 0n, 0n, 0n], gas: sendGas },
      { note: fillGas ? `lowest gas that simulated clean` : 'no dose simulated clean; sent at 16M anyway to record the on-chain refusal' });

    const after = await snapshot('post-cascade', F);
    const post = [];
    for (const id of ids) {
      const p = await R('positions', [id]).catch(() => null);
      post.push({ id: String(id), aliveAfter: !!(p && p[0] !== '0x0000000000000000000000000000000000000000'), owner: p ? p[0] : null, collateral: p ? String(p[2]) : null });
    }
    const died = post.filter(p => !p.aliveAfter).map(p => p.id);
    put({ kind: 'finding', topic: 'cascade', tx: r.tx, ok: r.ok, reason: r.reason,
          gasSupplied: String(sendGas), gasUsed: r.gasUsed,
          openCountBefore: before.engine.openCount, openCountAfter: after.engine.openCount,
          died, survived: post.filter(p => p.aliveAfter).map(p => p.id),
          liquidatorMintedBefore: before.market.liquidatorMinted, liquidatorMintedAfter: after.market.liquidatorMinted,
          badgesOwedBefore: before.engine.badgesOwedFunder, badgesOwedAfter: after.engine.badgesOwedFunder,
          plvBefore: before.engine.plv, plvAfter: after.engine.plv,
          insuranceBefore: before.engine.insuranceEth, insuranceAfter: after.engine.insuranceEth,
          unabsorbedBefore: before.engine.unabsorbedEth, unabsorbedAfter: after.engine.unabsorbedEth,
          preemptive: pre });
    console.log(`  DIED: ${died.join(',') || 'none'}   openCount ${before.engine.openCount} -> ${after.engine.openCount}   UNABSORBED ${formatEther(before.engine.unabsorbedEth)} -> ${formatEther(after.engine.unabsorbedEth)}`);
  }

  // ── 6. claim the queue ───────────────────────────────────────
  if (want('claim')) {
    console.log('\n── PHASE claim');
    const owed = await V('pendingEthOf', [F]);
    const free = await R('freeEth');
    put({ kind: 'plan', note: 'claim preconditions', pendingEthOfFunder: owed, freeEth: free });
    if (owed > 0n) {
      const b = await pc.getBalance({ address: F });
      const r = await act('claim', 'claimPendingEth', wc, { address: A.vault, abi: VAULT, functionName: 'claimPendingEth', gas: 900_000n });
      const b2 = await pc.getBalance({ address: F });
      put({ kind: 'finding', topic: 'claim', tx: r.tx, ok: r.ok, reason: r.reason, owedBefore: owed,
            paidResult: r.result !== undefined ? String(r.result) : null,
            walletDelta: b2 - b, pendingAfter: await V('pendingEthOf', [F]), pendingEthTotal: await V('pendingEth') });
    } else {
      put({ kind: 'finding', topic: 'claim', note: 'nothing pending to claim', pendingEthOfFunder: owed, freeEth: free });
    }
    // The queue drained plv to 0. An open must now be impossible — predicted revert.
    const mc = ((P.minCollateral || parseEther('0.003')) * 120n) / 100n;
    await act('claim', `openLong at plv=${formatEther(free)} (expect refusal)`, wc,
      { address: A.engine, abi: ENGINE, functionName: 'openLong', args: [LEV, 0n, 0n, mc], gas: 3_000_000n },
      { value: mc, expect: 'PlvInsufficient', note: 'PREDICTED: plv is 0, so borrow > plv must revert' });
  }

  // ── 7. unwind + reconcile ────────────────────────────────────
  if (want('unwind')) {
    console.log('\n── PHASE unwind');
    if (!OPENED.length) OPENED.push(...replayPositions());
    // Closing a long SELLS its token back, so each close walks spot DOWN and drags the
    // later (higher-entry) positions toward their liq price. The unwind is itself a
    // slow-motion cascade — watch openCount fall faster than the closes we send.
    for (const o of OPENED) {
      const p = await R('positions', [BigInt(o.id)]).catch(() => null);
      if (!p || p[0] === '0x0000000000000000000000000000000000000000') {
        put({ kind: 'note', note: `#${o.id} already gone before we closed it — liquidated during the unwind` }); continue;
      }
      const liq = await R('isLiquidatable', [BigInt(o.id)]).catch(() => null);
      const r = await act('unwind', `close #${o.id}`, wc, { address: A.engine, abi: ENGINE, functionName: 'close', args: [BigInt(o.id), 0n], gas: 3_000_000n });
      const [oc, minted, badges, unabs, plvNow] = await Promise.all([
        R('openCount'), pc.readContract({ address: A.collection, abi: COLL, functionName: 'liquidatorMinted' }).catch(() => null),
        R('badgesOwed', [F]), R('unabsorbedEth'), R('plv')]);
      put({ kind: 'unwind-step', id: o.id, isLiquidatableBeforeClose: liq, tx: r.tx, ok: r.ok, reason: r.reason,
            openCount: oc, liquidatorMinted: minted, badgesOwed: badges, unabsorbedEth: unabs, plv: plvNow });
      console.log(`    after #${o.id}: openCount=${oc} minted=${minted} badges=${badges} plv=${formatEther(plvNow)} UNABS=${formatEther(unabs)}`);
    }
    const sh = await V('ethShareOf', [F]);
    if (sh > 0n) await act('unwind', 'withdrawEth(remaining shares)', wc, { address: A.vault, abi: VAULT, functionName: 'withdrawEth', args: [sh], gas: 1_200_000n });
    const owed = await V('pendingEthOf', [F]);
    if (owed > 0n) await act('unwind', 'claimPendingEth (final)', wc, { address: A.vault, abi: VAULT, functionName: 'claimPendingEth', gas: 900_000n });
    const tb = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });
    if (tb > 0n) {
      await act('unwind', 'approve router (residual token)', wc, { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, tb], gas: 120_000n });
      await act('unwind', 'sell residual token back to ETH', wc, { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, tb, 0n, 0n, 0n], gas: 8_000_000n });
    }
    const pay = await R('payoutOwedTotal').catch(() => 0n);
    if (pay > 0n) await act('unwind', 'claimPayout', wc, { address: A.engine, abi: ENGINE, functionName: 'claimPayout', gas: 500_000n });
  }

  const sF = await snapshot('final', F);
  const balF = await pc.getBalance({ address: F });
  const stranded = { vaultShares: String(await V('ethShareOf', [F])), pendingEth: String(await V('pendingEthOf', [F])),
                     openPositions: String(await R('openCount')), residualToken: String(await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] })) };
  put({ kind: 'reconciliation', funderBalanceStart: bal0, funderBalanceEnd: balF,
        netEth: balF - bal0, stake: spend.stake, collateral: spend.collateral, inventory: spend.inventory,
        grossDeployed: spend.stake + spend.collateral + spend.inventory, stranded,
        unabsorbedT0: s0.engine.unabsorbedEth, unabsorbedFinal: sF.engine.unabsorbedEth,
        volumeT0: s0.market.cumulativeVolume, volumeFinal: sF.market.cumulativeVolume,
        insuranceT0: s0.engine.insuranceEth, insuranceFinal: sF.engine.insuranceEth,
        plvT0: s0.engine.plv, plvFinal: sF.engine.plv });
  console.log(`\nRECONCILE deployed ${formatEther(spend.stake + spend.collateral + spend.inventory)} ETH, funder net ${formatEther(balF - bal0)} ETH, stranded`, stranded);
  console.log(`\nJSONL: ${JSONL} (${fs.readFileSync(JSONL, 'utf8').split('\n').filter(Boolean).length} records)`);
})().catch(e => {
  console.error('\nFATAL', e);
  put({ kind: 'fatal', error: String(e?.shortMessage || e?.message || e).slice(0, 400) });
  process.exit(1);
});
