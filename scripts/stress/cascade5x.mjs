#!/usr/bin/env node
/**
 * cascade5x.mjs — drive a REAL cascade through the 5x cluster and separate
 * spot-liquidatable from PROJECTED-price (pre-emptive) liquidatable.
 *
 * THE AMMUNITION PROBLEM, AND WHY SHORTS SOLVE IT
 *   A CPMM round trip is price-neutral: buy N ETH of token, dump it, and spot
 *   returns to where it started (minus fees). So a trader who starts with no bag
 *   cannot push spot DOWN on net — which is why the previous run condemned nobody.
 *   `openShort` borrows from `plvToken` (PerpEngine.sol:1053) and SELLS those
 *   borrowed tokens into the pool. That is genuine, un-reversed downward pressure
 *   that costs only ETH collateral. Better still, `_liqSweep` returns early when
 *   `sender == perpEngine` (CauldronHook.sol:833), so an engine-routed short moves
 *   the price WITHOUT firing the sweep — it loads the book right up to the edge
 *   while leaving every long alive to be measured.
 *
 * THE MEASUREMENT
 *   1. shorts walk spot down until the thinnest long cushion is just above the
 *      15% maintenance floor, with NOTHING liquidatable at spot;
 *   2. a router BUY lifts spot back up (and is how we acquire a token bag at all),
 *      so every long reads isLiquidatable == FALSE with room to spare;
 *   3. ONE dump of that whole bag. Its PROJECTED post-swap price is far below the
 *      spot the table was read at. Any id that read false in step 2 and is dead
 *      after step 3 was condemned by the projection, not by spot.
 *
 * Appends to the SAME append-only JSONL. Never truncates. Key read at runtime,
 * never printed, never written.
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
const JSONL = path.join(ROOT, 'audit/STRESS_2026-09-22/cascade-actions.jsonl');

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const RUN = arg('run', 'live-5X-cascade');
const RPC = arg('rpc', process.env.STRESS_RPC || 'https://ethereum-sepolia-rpc.publicnode.com');
const MAX_SHORTS = Number(arg('shorts', 8));
const SHORT_COLL = arg('shortcoll', '0.02');
const BUY = arg('buy', '0.55');

const ROUND = JSON.parse(fs.readFileSync(path.join(ROOT, 'indexer/deployments/round.json'), 'utf8'));
const C = ROUND.contracts;
const A = { hook: getAddress(C.hook), engine: getAddress(C.perpEngine), vault: getAddress(C.perpVault),
            router: getAddress(C.gachaRouter), collection: getAddress(C.collection), token: null };

function art(n) {
  const d = path.join(OUT, n + '.sol');
  const f = fs.readdirSync(d).filter(x => x.startsWith(n + '.') && x.endsWith('.json')).sort().reverse()[0];
  return JSON.parse(fs.readFileSync(path.join(d, f), 'utf8'));
}
const ENGINE = art('PerpEngine').abi, VAULT = art('PerpVault').abi;
const ROUTER = art('CauldronGachaRouter').abi, HOOK = art('CauldronHook').abi;
const COLL_ABI = art('CauldronCollection').abi;
const ERC20 = parseAbi(['function balanceOf(address) view returns (uint256)', 'function approve(address,uint256) returns (bool)']);
const V4_WRAPPED = parseAbi(['error WrappedError(address target, bytes4 selector, bytes reason, bytes details)']);
const ALL_ERRORS = [...ENGINE, ...VAULT, ...ROUTER, ...HOOK, ...V4_WRAPPED].filter(x => x.type === 'error');

const transport = http(RPC, { retryCount: 8, retryDelay: 900, timeout: 90_000, batch: false });
const pc = createPublicClient({ chain: sepolia, transport });
const sleep = ms => new Promise(r => setTimeout(r, ms));

function unwrapV4(data, depth = 0) {
  if (!data || data === '0x' || depth > 5) return null;
  try {
    const w = decodeErrorResult({ abi: V4_WRAPPED, data });
    const inner = unwrapV4(w.args[2], depth + 1);
    return inner ? `${inner} [unwrapped from v4 WrappedError(target=${w.args[0]}, hookFn=${w.args[1]})]`
                 : `WrappedError(target=${w.args[0]}, hookFn=${w.args[1]}, inner=${String(w.args[2]).slice(0, 12)})`;
  } catch { }
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
let SEQ = 0;
function put(o) {
  fs.appendFileSync(JSONL, JSON.stringify({ run: RUN, seq: ++SEQ, at: new Date().toISOString(), ...o },
    (_, v) => typeof v === 'bigint' ? v.toString() : v) + '\n');
  return o;
}
function rec(phase, action, ok, extra = {}) {
  const r = put({ kind: 'action', phase, action, ok, ...extra });
  console.log(`  [${ok ? 'OK ' : 'REV'}] ${phase}/${action}` + (r.tx ? ` tx=${r.tx}` : '') +
    (r.gasUsed ? ` gas=${r.gasUsed}` : '') + (r.reason ? ` :: ${r.reason}` : ''));
  return r;
}
const R = (fn, args = []) => pc.readContract({ address: A.engine, abi: ENGINE, functionName: fn, args });
const V = (fn, args = []) => pc.readContract({ address: A.vault, abi: VAULT, functionName: fn, args });
const H = (fn, args = []) => pc.readContract({ address: A.hook, abi: HOOK, functionName: fn, args });

async function snapshot(label, F) {
  const g = async (f, fn, a) => { try { return await f(fn, a); } catch { return null; } };
  const [depth, plv, plvTok, freeEth, totalEth, ins, unabs, longOi, shortOi, open, mark, payout, badges] =
    await Promise.all(['activeEthDepth', 'plv', 'plvToken', 'freeEth', 'totalEth', 'insuranceEth',
      'unabsorbedEth', 'longOiEth', 'shortOiToken', 'openCount', 'markSqrtPriceX96', 'payoutOwedTotal']
      .map(f => g(R, f)).concat([g(R, 'badgesOwed', [F])]));
  const minted = await pc.readContract({ address: A.collection, abi: COLL_ABI, functionName: 'liquidatorMinted' }).catch(() => null);
  const [vol, dead] = await Promise.all([g(H, 'cumulativeVolume'), g(H, 'isDead', [ROUND.poolIds[0]])]);
  const s = { kind: 'snapshot', label,
    engine: { activeEthDepth: depth, plv, plvToken: plvTok, freeEth, totalEth, insuranceEth: ins,
              unabsorbedEth: unabs, longOiEth: longOi, shortOiToken: shortOi, openCount: open,
              markSqrtPriceX96: mark, payoutOwedTotal: payout, badgesOwedFunder: badges },
    vault: { assetsEth: await g(V, 'assetsEth'), assetsTok: await g(V, 'assetsTok') },
    market: { cumulativeVolume: vol, isDead: dead, liquidatorMinted: minted } };
  put(s);
  console.log(`\n── ${label}\n   mark=${mark} depth=${formatEther(depth)} plv=${formatEther(plv)} longOi=${formatEther(longOi)} shortOiTok=${shortOi}`);
  console.log(`   open=${open} UNABSORBED=${formatEther(unabs)} ins=${formatEther(ins)} minted=${minted} badges=${badges} dead=${dead}`);
  return s;
}

/** The deliverable's raw material: per-id spot health with the exact cushion. */
async function table(label, ids) {
  const rows = [];
  for (const id of ids) {
    const p = await R('positions', [id]).catch(() => null);
    const alive = !!(p && p[0] !== '0x0000000000000000000000000000000000000000');
    let liq = null, h = null, cushion = null;
    if (alive) {
      liq = await R('isLiquidatable', [id]).catch(() => null);
      h = await R('positionHealth', [id]).catch(() => null);
      if (h && h[1] > 0n) cushion = Number((h[1] - h[2]) * 10000n / h[1]) / 100; // % equity/markValue
    }
    rows.push({ id: String(id), alive, isLiquidatable: liq, markValueEth: h ? String(h[1]) : null,
                debtEth: h ? String(h[2]) : null, cushionPct: cushion });
  }
  const mark = await R('markSqrtPriceX96');
  put({ kind: 'liq-table', label, markSqrtPriceX96: mark, rows });
  const alive = rows.filter(r => r.alive);
  const t = alive.filter(r => r.isLiquidatable).length;
  const cs = alive.map(r => r.cushionPct).filter(x => x !== null);
  console.log(`  [${label}] alive=${alive.length} liquidatable=${t} cushion min=${cs.length ? Math.min(...cs).toFixed(2) : '-'}% max=${cs.length ? Math.max(...cs).toFixed(2) : '-'}%`);
  return rows;
}

async function act(phase, action, wc, req, { expect, note, value } = {}) {
  let sim;
  try { sim = await pc.simulateContract({ ...req, account: wc.account, value }); }
  catch (e) {
    const rs = reason(e); const hit = expect && rs.includes(expect);
    return rec(phase, action, !!hit, { reason: rs, note: (hit ? 'PREDICTED: ' : '') + (note || ''), stage: 'simulate', gasSupplied: req.gas ? String(req.gas) : null });
  }
  try {
    const hash = await wc.writeContract({ ...sim.request, gas: req.gas ?? sim.request.gas });
    const r = await pc.waitForTransactionReceipt({ hash, timeout: 240_000 });
    await sleep(250);
    return rec(phase, action, r.status === 'success', { tx: hash, gasUsed: String(r.gasUsed),
      gasSupplied: req.gas ? String(req.gas) : null, block: String(r.blockNumber), note,
      reason: r.status === 'success' ? undefined : 'ON-CHAIN REVERT (simulate passed)', result: sim.result });
  } catch (e) { return rec(phase, action, false, { reason: reason(e), note, stage: 'send', gasSupplied: req.gas ? String(req.gas) : null }); }
}

(async () => {
  const m = fs.readFileSync(path.join(ROOT, 'contracts/solidity/.env'), 'utf8')
    .match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  const acct = privateKeyToAccount('0x' + m[2]);
  const wc = createWalletClient({ account: acct, chain: sepolia, transport });
  const F = acct.address;
  A.token = getAddress(await R('syncedToken'));
  const bal0 = await pc.getBalance({ address: F });
  put({ kind: 'note', note: `cascade5x start: funder ${F} bal ${formatEther(bal0)} token ${A.token} maxLeverage=${await R('maxLeverage')}` });

  // the cluster, replayed from the append-only log
  const seen = new Map();
  for (const l of fs.readFileSync(JSONL, 'utf8').split('\n')) {
    if (!l.trim()) continue;
    try { const o = JSON.parse(l); if (o.kind === 'position' && o.run === 'live-5X-setup') seen.set(o.id, o); } catch { }
  }
  const ids = [...seen.keys()].map(BigInt).sort((a, b) => a < b ? -1 : 1);
  put({ kind: 'note', note: `cluster replayed from JSONL: ${ids.length} ids ${ids.join(',')}` });
  console.log(`cluster: ${ids.length} ids ${ids.join(',')}`);

  const s0 = await snapshot('5x/t0 cluster open', F);
  await table('t0 after cluster', ids);

  // ── 1. SHORTS walk spot down WITHOUT firing the sweep (sender == engine) ──
  console.log('\n── PHASE shorts (engine-routed: moves price, sweep is skipped)');
  const shortIds = [];
  const coll = parseEther(SHORT_COLL);
  for (let i = 0; i < MAX_SHORTS; i++) {
    const lev = await R('maxLeverage');
    const r = await act('shorts', `openShort#${i} lev${lev} ${SHORT_COLL}E`, wc,
      { address: A.engine, abi: ENGINE, functionName: 'openShort', args: [lev, 0n, 0n, coll], gas: 3_000_000n },
      { value: coll, expect: 'PlvInsufficient', note: 'ceilings: PlvInsufficient | OiCapped | DustPosition are PASSES' });
    if (!r.ok || !r.tx) { put({ kind: 'note', note: `shorts stopped at i=${i}: ${r.reason}` }); break; }
    if (r.result !== undefined && r.result !== null) shortIds.push(BigInt(r.result));
    const rows = await table(`after short#${i}`, ids);
    const alive = rows.filter(x => x.alive);
    const anyLiq = alive.some(x => x.isLiquidatable);
    const minC = Math.min(...alive.map(x => x.cushionPct).filter(x => x !== null));
    put({ kind: 'short-step', i, shortId: shortIds.length ? String(shortIds[shortIds.length - 1]) : null,
          minCushionPct: minC, anyLiquidatable: anyLiq, mark: String(await R('markSqrtPriceX96')) });
    // stop the moment the thinnest long is at the edge: we want the table read with
    // NOTHING liquidatable at spot, so the kill can only come from the projection.
    if (anyLiq || minC < 16.5) { put({ kind: 'note', note: `shorts halted: minCushion=${minC}% anyLiquidatable=${anyLiq}` }); break; }
  }
  await snapshot('5x/after shorts', F);

  // ── 2. BUY the bag. Lifts spot so every long reads false, AND is the only way
  //      to hold token to dump. This buy fires a sweep with isBuy=true (projects UP).
  console.log('\n── PHASE buy (acquire the bag; native quote => quoteIn MUST be 0, ETH via msg.value)');
  const rb = await act('buy', `buy ${BUY} ETH of token (quoteIn=0 + msg.value)`, wc,
    { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, 0n, 0n, 0n, 0n], gas: 8_000_000n },
    { value: parseEther(BUY), note: 'previous run passed quoteIn=value and got NativeQuoteTakesValue (CauldronGachaRouter.sol:275)' });
  const bag = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });
  put({ kind: 'note', note: `bag acquired: ${bag} token units, buy ok=${rb.ok}` });
  await snapshot('5x/after buy', F);

  // ── 3. THE TABLE: spot readings immediately before the one trade ──────────
  const preRows = await table('PRE-SWAP (spot, immediately before the dump)', ids);
  put({ kind: 'finding', topic: 'preemptive-pre', note: 'isLiquidatable() at SPOT immediately before the cascade swap', rows: preRows });

  // ── 4. gas dose-response: same call, many limits, simulated (free) ─────────
  await act('cascade', 'approve router for full bag', wc,
    { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, bag], gas: 120_000n });
  const doses = [500_000n, 1_000_000n, 2_000_000n, 3_000_000n, 4_000_000n, 6_000_000n, 8_000_000n, 16_000_000n, 30_000_000n];
  const dose = []; let fillGas = null;
  for (const g of doses) {
    let row;
    try {
      await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play', args: [0n, bag, 0n, 0n, 0n], account: acct, gas: g });
      row = { gasSupplied: String(g), outcome: 'FILLS', error: null }; if (!fillGas) fillGas = g;
    } catch (e) { row = { gasSupplied: String(g), outcome: 'REFUSED', error: reason(e) }; }
    dose.push(row); put({ kind: 'dose', phase: 'cascade-5x', ...row });
    console.log(`    gas ${Number(g) / 1e6}M -> ${row.outcome}${row.error ? ' :: ' + row.error : ''}`);
  }
  put({ kind: 'finding', topic: 'gas-dose-response-5x', table: dose, lowestFill: fillGas ? String(fillGas) : null });

  // ── 5. ONE TRADE ─────────────────────────────────────────────────────────
  const before = await snapshot('5x/pre-cascade', F);
  const sendGas = 16_000_000n;   // generous on purpose: we want gas USED, not a starve
  const rc = await act('cascade', `ONE DUMP of the whole bag @ ${Number(sendGas) / 1e6}M gas`, wc,
    { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, bag, 0n, 0n, 0n], gas: sendGas },
    { note: 'the single trade the cluster is measured across' });
  const after = await snapshot('5x/post-cascade', F);
  const postRows = await table('POST-SWAP', ids);

  const merged = preRows.map((p, i) => ({ id: p.id, spotLiquidatableBefore: p.isLiquidatable,
    cushionPctBefore: p.cushionPct, aliveBefore: p.alive, aliveAfter: postRows[i].alive,
    killedBySweep: p.alive && !postRows[i].alive,
    PROJECTED_ONLY: p.alive && !postRows[i].alive && p.isLiquidatable === false }));
  const died = merged.filter(x => x.killedBySweep).map(x => x.id);
  const projectedOnly = merged.filter(x => x.PROJECTED_ONLY).map(x => x.id);
  put({ kind: 'finding', topic: 'CASCADE-RESULT', tx: rc.tx, ok: rc.ok, reason: rc.reason,
    gasSupplied: String(sendGas), gasUsed: rc.gasUsed, killCount: died.length, died, projectedOnly,
    gasPerKill: rc.gasUsed && died.length ? String(BigInt(rc.gasUsed) / BigInt(died.length)) : null,
    openCountBefore: before.engine.openCount, openCountAfter: after.engine.openCount,
    liquidatorMintedBefore: before.market.liquidatorMinted, liquidatorMintedAfter: after.market.liquidatorMinted,
    badgesOwedBefore: before.engine.badgesOwedFunder, badgesOwedAfter: after.engine.badgesOwedFunder,
    plvBefore: before.engine.plv, plvAfter: after.engine.plv,
    insuranceBefore: before.engine.insuranceEth, insuranceAfter: after.engine.insuranceEth,
    unabsorbedBefore: before.engine.unabsorbedEth, unabsorbedAfter: after.engine.unabsorbedEth,
    unabsorbedMoved: String(before.engine.unabsorbedEth) !== String(after.engine.unabsorbedEth),
    table: merged });
  console.log(`\n  KILLED ${died.length}: ${died.join(',') || 'none'}`);
  console.log(`  PROJECTED-ONLY (read false at spot, condemned anyway): ${projectedOnly.join(',') || 'none'}`);
  console.log(`  gasUsed=${rc.gasUsed} openCount ${before.engine.openCount}->${after.engine.openCount} UNABSORBED ${before.engine.unabsorbedEth}->${after.engine.unabsorbedEth}`);

  put({ kind: 'note', note: `cascade5x done; shortIds=${shortIds.join(',')}; funder bal ${formatEther(await pc.getBalance({ address: F }))}` });
})().catch(e => { console.error('FATAL', e); put({ kind: 'fatal', where: 'cascade5x', error: String(e?.shortMessage || e?.message || e).slice(0, 400) }); process.exit(1); });
