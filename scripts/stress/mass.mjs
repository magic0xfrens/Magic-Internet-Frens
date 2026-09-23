#!/usr/bin/env node
/**
 * mass.mjs — MASS cascade liquidation: one trade, many kills, measured live.
 *
 * WHY THE PREVIOUS TWO RUNS KILLED ZERO (mechanism, not effort)
 *   {PerpEngine._liqTest} (:1816) trips on the WORSE of two tests:
 *     (a) the TWAP MARK with the `maintenanceBps` (15%) buffer — `val < principal*1.15`
 *     (b) live SPOT, or inside a sweep the PROJECTED post-trade spot, with ZERO
 *         buffer — `val < principal` (insolvency).
 *   A single-block dump CANNOT move a 5-minute TWAP, so leg (a) is frozen for the
 *   duration of the trade. Only leg (b) can fire. Leg (b) has no buffer, so a 5x
 *   long (principal = 4C, mark value = 5C) needs its value to fall to 4C — a 20%
 *   drop — not the ~5% the maintenance arithmetic suggests. Both prior runs sized
 *   the dump for the 5% number and moved spot a few percent. Nothing died.
 *
 * WHY THE ORDER OF OPERATIONS IS THE WHOLE TEST
 *   A CPMM round trip is price-neutral: buy N ETH of token then dump it and spot
 *   returns to where it started. So longs opened BEFORE the bag buy can never be
 *   reached by dumping that same bag — the dump lands exactly back on their entry.
 *   The longs must be opened AFTER the buy, at the elevated price, so the dump
 *   carries spot back down THROUGH them.
 *
 *   But opening them immediately after the buy kills them on the spot: the mark is
 *   still at the pre-buy price, so `_quoteMark(size)` values a fresh long far below
 *   its own principal and `_sweepAfterOpen` liquidates it inside the open. So the
 *   full `twapWindow` must elapse between the buy and the first open.
 *
 *   The opens themselves push spot up ~1% each while the mark lags, so they are
 *   SPACED — 15 opens fired back to back drift spot ~16.5% above the mark, past the
 *   13.04% cushion at which leg (a) trips, and the later ones self-liquidate too.
 *
 * Appends to the SAME append-only JSONL. Never truncates. Key read at runtime from
 * contracts/solidity/.env, never printed, never written.
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
const RUN = arg('run', 'mass-cascade');
const RPC = arg('rpc', process.env.STRESS_RPC || 'https://ethereum-sepolia-rpc.publicnode.com');
const PHASES = new Set(arg('phases', 'prep,bag,cluster,dump').split(',').map(s => s.trim()));
const want = p => PHASES.has(p) || PHASES.has('all');

const DEPOSIT = arg('deposit', '0.5');   // restores plv; every openLong reverts PlvInsufficient until then
const BAG     = arg('bag', '0.7');       // the ammunition AND the price elevation the longs open at
const N       = Number(arg('n', 15));
const COLL    = arg('coll', '0.0035');   // openFeeBps = 690, so 0.0035 → 0.003259 collateral > minCollateral 0.003
const WAIT1   = Number(arg('wait1', 330));  // twapWindow (300s) + margin: mark must reach the post-buy price
const SPACE   = Number(arg('space', 30));   // between opens, so the mark tracks the opens' own drift
const WAIT2   = Number(arg('wait2', 330));  // mark settles on the post-cluster price before we MEASURE
const DUMPGAS = BigInt(arg('dumpgas', '16000000'));

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

/** price = (sqrtP/2^96)^2 — only ever used as a RATIO, so the scale cancels. */
const Q96 = 2n ** 96n;
const px = sp => { const x = Number(sp) / Number(Q96); return x * x; };

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
  console.log(`\n── ${label}\n   mark=${mark} depth=${formatEther(depth ?? 0n)} plv=${formatEther(plv ?? 0n)} longOi=${formatEther(longOi ?? 0n)}`);
  console.log(`   open=${open} UNABSORBED=${formatEther(unabs ?? 0n)} ins=${formatEther(ins ?? 0n)} minted=${minted} badges=${badges} dead=${dead}`);
  return s;
}

/**
 * The deliverable's raw material: per-id health at the CURRENT mark.
 * `cushionPct` = (markValue − principal)/markValue.
 *   • leg (a), the mark's maintenance test, trips at cushion < 15/115 = 13.04%
 *   • leg (b), the spot/projected insolvency test, trips at cushion < 0%
 * So "cushion" is BOTH the distance to an ordinary liquidation AND the exact %
 * spot drop this position can absorb before a sweep's projection condemns it.
 */
async function table(label, ids) {
  const rows = [];
  for (const id of ids) {
    const p = await R('positions', [id]).catch(() => null);
    const alive = !!(p && p[0] !== '0x0000000000000000000000000000000000000000');
    let liq = null, h = null, cushion = null;
    if (alive) {
      liq = await R('isLiquidatable', [id]).catch(() => null);
      h = await R('positionHealth', [id]).catch(() => null);
      if (h && h[1] > 0n) cushion = Number((h[1] - h[2]) * 10000n / h[1]) / 100;
    }
    rows.push({ id: String(id), alive, isLiquidatable: liq, markValueEth: h ? String(h[1]) : null,
                debtEth: h ? String(h[2]) : null, cushionPct: cushion });
  }
  const mark = await R('markSqrtPriceX96');
  const spot = await R('activeEthDepth');
  put({ kind: 'liq-table', label, markSqrtPriceX96: mark, activeEthDepth: spot, rows });
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
    const hash = await wc.writeContract({ ...sim.request, gas: req.gas ?? sim.request.gas, value });
    const r = await pc.waitForTransactionReceipt({ hash, timeout: 240_000 });
    await sleep(250);
    return rec(phase, action, r.status === 'success', { tx: hash, gasUsed: String(r.gasUsed),
      gasSupplied: req.gas ? String(req.gas) : null, block: String(r.blockNumber), note,
      reason: r.status === 'success' ? undefined : 'ON-CHAIN REVERT (simulate passed)', result: sim.result });
  } catch (e) { return rec(phase, action, false, { reason: reason(e), note, stage: 'send', gasSupplied: req.gas ? String(req.gas) : null }); }
}

/** Wall-clock wait with progress, so a background log shows liveness. */
async function hold(sec, why) {
  put({ kind: 'note', note: `WAIT ${sec}s — ${why}` });
  console.log(`\n⏳ waiting ${sec}s — ${why}`);
  const t0 = Date.now();
  while ((Date.now() - t0) / 1000 < sec) {
    await sleep(30_000);
    const mk = await R('markSqrtPriceX96').catch(() => 0n);
    const sp = await R('markSqrtPriceX96').catch(() => 0n);
    console.log(`     +${Math.round((Date.now() - t0) / 1000)}s mark=${mk}`);
    if (sp === 0n) break;
  }
}

(async () => {
  const m = fs.readFileSync(path.join(ROOT, 'contracts/solidity/.env'), 'utf8')
    .match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  const acct = privateKeyToAccount('0x' + m[2]);
  const wc = createWalletClient({ account: acct, chain: sepolia, transport });
  const F = acct.address;
  A.token = getAddress(await R('syncedToken'));
  const bal0 = await pc.getBalance({ address: F });
  const lev0 = await R('maxLeverage');
  put({ kind: 'note', note: `mass.mjs start: funder ${F} bal ${formatEther(bal0)} token ${A.token} maxLeverage=${lev0} phases=${[...PHASES]}` });
  console.log(`funder ${F} bal ${formatEther(bal0)} maxLeverage=${lev0}`);

  // Hard gate: the whole point of the tier raise is 5x. 2x needs a 42.5% drop.
  if (want('cluster') && Number(lev0) < 5) {
    put({ kind: 'fatal', error: `maxLeverage()=${lev0}, refusing to open the cluster — raise the tiers first` });
    console.error(`REFUSING: maxLeverage()=${lev0}, need 5`); process.exit(3);
  }

  const s0 = await snapshot('mass/t0', F);
  const spend = { deposit: 0n, bag: 0n, collateral: 0n };

  // ── 1. restore plv ────────────────────────────────────────────────────────
  if (want('prep')) {
    console.log('\n── PHASE prep (restore plv: openLong reverts PlvInsufficient while it is drained)');
    const v = parseEther(DEPOSIT);
    const r = await act('prep', `PerpVault.depositEth ${DEPOSIT}`, wc,
      { address: A.vault, abi: VAULT, functionName: 'depositEth', gas: 900_000n }, { value: v });
    if (r.ok) spend.deposit += v;
    const free = await R('freeEth'), plv = await R('plv');
    put({ kind: 'finding', topic: 'plv-restored', freeEth: free, plv, ok: free > parseEther('0.3') });
    console.log(`  freeEth=${formatEther(free)} plv=${formatEther(plv)}`);
    if (free < parseEther('0.3')) { put({ kind: 'fatal', error: 'plv restore failed' }); process.exit(4); }
  }

  // ── 2. the bag — AND the price elevation the cluster will be opened at ────
  //   Buying FIRST is what makes the dump reach the longs at all: a round trip is
  //   price-neutral, so a bag bought AFTER the opens lands the dump exactly back
  //   on their entry price and condemns nobody. Bought BEFORE, the dump carries
  //   spot back down THROUGH every entry.
  let bag = 0n;
  if (want('bag')) {
    console.log('\n── PHASE bag (buy FIRST; native quote ⇒ quoteIn = 0, ETH via msg.value)');
    const spotBefore = await R('markSqrtPriceX96');
    const dBefore = await R('activeEthDepth');
    const v = parseEther(BAG);
    const r = await act('bag', `buy ${BAG} ETH of token`, wc,
      { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, 0n, 0n, 0n, 0n], gas: 8_000_000n },
      { value: v, note: 'quoteIn MUST be 0 on a native book (cascade.mjs inv phase passes both → NativeQuoteTakesValue)' });
    if (r.ok) spend.bag += v;
    bag = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });
    const dAfter = await R('activeEthDepth');
    put({ kind: 'finding', topic: 'bag', bagTokenUnits: bag, ethSpent: v,
          activeEthDepthBefore: dBefore, activeEthDepthAfter: dAfter,
          markBefore: spotBefore, note: 'mark is NOT expected to move yet — it is a 5-minute average' });
    console.log(`  bag = ${bag} units; depth ${formatEther(dBefore)} → ${formatEther(dAfter)}`);
    await snapshot('mass/after bag buy', F);

    // THE WAIT THAT THE LAST TWO RUNS SKIPPED. Until the mark reaches the post-buy
    // price, `_quoteMark(size)` values a fresh long BELOW its own principal and
    // `_sweepAfterOpen` liquidates it inside the open that created it.
    await hold(WAIT1, 'twapWindow: the mark must reach the post-buy price or every open self-liquidates');
    await snapshot('mass/mark settled on post-buy price', F);
  }

  // ── 3. the cluster — tiny, 5x, SPACED ────────────────────────────────────
  const OPENED = [];
  if (want('cluster')) {
    console.log('\n── PHASE cluster');
    const LEV = Number(await R('maxLeverage'));
    const coll = parseEther(COLL);
    const depth = await R('activeEthDepth');
    put({ kind: 'plan', note: 'cluster sizing', n: N, lev: LEV, sendEach: coll, depth,
          expectCollateralAfterFee: (coll * 9310n) / 10_000n, spacingSec: SPACE });
    console.log(`  plan: ${N} longs @ ${LEV}x, send ${COLL} ETH each, ${SPACE}s apart`);

    for (let i = 0; i < N; i++) {
      const r = await act('cluster', `openLong#${i} ${LEV}x ${COLL}E`, wc,
        { address: A.engine, abi: ENGINE, functionName: 'openLong', args: [LEV, 0n, 0n, coll], gas: 3_000_000n },
        { value: coll, expect: 'PlvInsufficient', note: 'ceilings PlvInsufficient | OiCapped | UtilCapped | DustPosition are PASSES' });
      if (!r.ok || !r.tx) { put({ kind: 'note', note: `cluster stopped at i=${i}: ${r.reason}` }); break; }
      spend.collateral += coll;
      const id = r.result !== undefined && r.result !== null ? BigInt(r.result) : null;
      if (id === null) { put({ kind: 'note', note: `open #${i} gave no id` }); continue; }
      const p = await R('positions', [id]).catch(() => null);
      const h = await R('positionHealth', [id]).catch(() => null);
      const liq = await R('isLiquidatable', [id]).catch(() => null);
      const cushion = h && h[1] > 0n ? Number((h[1] - h[2]) * 10000n / h[1]) / 100 : null;
      const o = { id: String(id), collateral: p ? String(p[2]) : null, size: p ? String(p[3]) : null,
                  principal: p ? String(p[4]) : null, leverage: p ? String(p[6]) : null,
                  isLiquidatableAtOpen: liq, cushionAtOpenPct: cushion,
                  markAtOpen: String(await R('markSqrtPriceX96')), tx: r.tx };
      OPENED.push(o); put({ kind: 'position', ...o });
      console.log(`    #${id} coll=${p ? formatEther(p[2]) : '?'} liqAtOpen=${liq} cushion=${cushion}%`);

      // DRIFT GUARD: the opens push spot up while the mark lags. If the lag reaches
      // the 13.04% maintenance trip the NEXT open is liquidated by its own sweep.
      // Stop early and keep the cluster alive rather than feed positions to it.
      const rows = await table(`after open#${i}`, OPENED.map(x => BigInt(x.id)));
      const cs = rows.filter(x => x.alive).map(x => x.cushionPct).filter(x => x !== null);
      const minC = cs.length ? Math.min(...cs) : 100;
      const anyLiq = rows.some(x => x.isLiquidatable);
      put({ kind: 'cluster-step', i, minCushionPct: minC, anyLiquidatable: anyLiq, aliveCount: rows.filter(x => x.alive).length });
      if (anyLiq || minC < 14.5) {
        put({ kind: 'note', note: `cluster halted at i=${i}: minCushion=${minC}% anyLiquidatable=${anyLiq} — mark/spot drift reached the maintenance trip` });
        break;
      }
      if (i < N - 1) await sleep(SPACE * 1000);
    }
    put({ kind: 'note', note: `cluster opened ${OPENED.length}/${N}: ids ${OPENED.map(o => o.id).join(',')}` });
    await snapshot('mass/after cluster', F);

    // Let the mark settle ON the post-cluster price, so the pre-dump table is read
    // against a SETTLED average and every `false` in it is an honest false.
    await hold(WAIT2, 'twapWindow: settle the mark on the post-cluster price before MEASURING');
  }

  // ── 4. measure, then ONE trade ───────────────────────────────────────────
  if (want('dump')) {
    console.log('\n── PHASE dump');
    if (!OPENED.length) {
      const seen = new Map();
      for (const l of fs.readFileSync(JSONL, 'utf8').split('\n')) {
        if (!l.trim()) continue;
        try { const o = JSON.parse(l); if (o.kind === 'position' && o.run === RUN) seen.set(o.id, o); } catch { }
      }
      OPENED.push(...seen.values());
      put({ kind: 'note', note: `dump resumed: replayed ${OPENED.length} positions from the JSONL` });
    }
    const ids = OPENED.map(o => BigInt(o.id));
    if (!bag) bag = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });

    const preRows = await table('PRE-DUMP (settled mark, immediately before the one trade)', ids);
    const alive = preRows.filter(r => r.alive);
    const cs = alive.map(r => r.cushionPct).filter(x => x !== null);
    const minC = cs.length ? Math.min(...cs) : null, maxC = cs.length ? Math.max(...cs) : null;
    put({ kind: 'finding', topic: 'PRE-DUMP-TABLE',
          note: 'cushionPct = (markValue−principal)/markValue. Leg (a) the mark maintenance test trips below 13.04%; leg (b) the projected-spot insolvency test trips below 0%. The dump can only fire leg (b), so cushionPct IS the % spot drop each position can absorb.',
          minCushionPct: minC, maxCushionPct: maxC, liquidatableAtSpot: alive.filter(r => r.isLiquidatable).length,
          aliveCount: alive.length, rows: preRows });
    console.log(`  PRE-DUMP: ${alive.length} alive, ${alive.filter(r => r.isLiquidatable).length} liquidatable, cushion ${minC}%..${maxC}%`);
    console.log(`  the dump must drive spot down MORE than ${maxC}% to condemn the whole cluster`);

    await act('dump', 'approve router for the full bag', wc,
      { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, bag], gas: 120_000n });

    // gas dose-response: an eth_call honours `gas`, so a refusal is free and still
    // yields the hook's real error once the v4 WrappedError is unwrapped.
    const doses = [1_000_000n, 2_000_000n, 3_000_000n, 4_000_000n, 6_000_000n, 8_000_000n, 12_000_000n, 16_000_000n, 24_000_000n];
    const dose = []; let fillGas = null;
    for (const g of doses) {
      let row;
      try {
        await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play', args: [0n, bag, 0n, 0n, 0n], account: acct, gas: g });
        row = { gasSupplied: String(g), outcome: 'FILLS', error: null }; if (!fillGas) fillGas = g;
      } catch (e) { row = { gasSupplied: String(g), outcome: 'REFUSED', error: reason(e) }; }
      dose.push(row); put({ kind: 'dose', phase: 'mass-dump', ...row });
      console.log(`    gas ${Number(g) / 1e6}M -> ${row.outcome}${row.error ? ' :: ' + row.error : ''}`);
    }
    put({ kind: 'finding', topic: 'gas-dose-response-mass', table: dose, lowestFill: fillGas ? String(fillGas) : null });

    const before = await snapshot('mass/pre-dump', F);
    const rc = await act('dump', `ONE DUMP of the whole bag @ ${Number(DUMPGAS) / 1e6}M gas`, wc,
      { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, bag, 0n, 0n, 0n], gas: DUMPGAS },
      { note: 'the single trade the whole cluster is measured across' });
    const after = await snapshot('mass/post-dump', F);
    const postRows = await table('POST-DUMP', ids);

    const merged = preRows.map((p, i) => ({
      id: p.id,
      isLiquidatableAtSpotBefore: p.isLiquidatable,
      cushionPctBefore: p.cushionPct,
      markValueEthBefore: p.markValueEth, debtEthBefore: p.debtEth,
      aliveBefore: p.alive, aliveAfter: postRows[i].alive,
      killedBySweep: p.alive && !postRows[i].alive,
      PROJECTED_ONLY: p.alive && !postRows[i].alive && p.isLiquidatable === false,
    }));
    const died = merged.filter(x => x.killedBySweep).map(x => x.id);
    const projectedOnly = merged.filter(x => x.PROJECTED_ONLY).map(x => x.id);
    const gasPerKill = rc.gasUsed && died.length ? String(BigInt(rc.gasUsed) / BigInt(died.length)) : null;
    put({ kind: 'finding', topic: 'MASS-CASCADE-RESULT', tx: rc.tx, ok: rc.ok, reason: rc.reason,
      gasSupplied: String(DUMPGAS), gasUsed: rc.gasUsed, killCount: died.length, died, projectedOnly, gasPerKill,
      openCountBefore: before.engine.openCount, openCountAfter: after.engine.openCount,
      liquidatorMintedBefore: before.market.liquidatorMinted, liquidatorMintedAfter: after.market.liquidatorMinted,
      badgesOwedBefore: before.engine.badgesOwedFunder, badgesOwedAfter: after.engine.badgesOwedFunder,
      plvBefore: before.engine.plv, plvAfter: after.engine.plv,
      insuranceBefore: before.engine.insuranceEth, insuranceAfter: after.engine.insuranceEth,
      unabsorbedBefore: before.engine.unabsorbedEth, unabsorbedAfter: after.engine.unabsorbedEth,
      unabsorbedMoved: String(before.engine.unabsorbedEth) !== String(after.engine.unabsorbedEth),
      markBefore: before.engine.markSqrtPriceX96, markAfter: after.engine.markSqrtPriceX96,
      depthBefore: before.engine.activeEthDepth, depthAfter: after.engine.activeEthDepth,
      table: merged });
    console.log(`\n  ╔══ KILLED ${died.length}/${alive.length}: ${died.join(',') || 'none'}`);
    console.log(`  ║  PROJECTED-ONLY (read false at spot, condemned by the projection): ${projectedOnly.join(',') || 'none'}`);
    console.log(`  ║  gasUsed=${rc.gasUsed}  gasPerKill=${gasPerKill}`);
    console.log(`  ║  openCount ${before.engine.openCount}→${after.engine.openCount}  insurance ${formatEther(before.engine.insuranceEth)}→${formatEther(after.engine.insuranceEth)}`);
    console.log(`  ╚══ UNABSORBED ${before.engine.unabsorbedEth} → ${after.engine.unabsorbedEth}  (moved: ${String(before.engine.unabsorbedEth) !== String(after.engine.unabsorbedEth)})`);
  }

  // ── 5. sweep back ────────────────────────────────────────────────────────
  if (want('sweep')) {
    console.log('\n── PHASE sweep');
    const survivors = [];
    for (const o of OPENED) {
      const p = await R('positions', [BigInt(o.id)]).catch(() => null);
      if (p && p[0] !== '0x0000000000000000000000000000000000000000') survivors.push(o.id);
    }
    for (const id of survivors) {
      await act('sweep', `close survivor #${id}`, wc,
        { address: A.engine, abi: ENGINE, functionName: 'close', args: [BigInt(id), 0n], gas: 3_000_000n });
    }
    const tb = await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] });
    if (tb > 0n) {
      await act('sweep', 'approve router (residual token)', wc, { address: A.token, abi: ERC20, functionName: 'approve', args: [A.router, tb], gas: 120_000n });
      await act('sweep', 'sell residual token back to ETH', wc, { address: A.router, abi: ROUTER, functionName: 'play', args: [0n, tb, 0n, 0n, 0n], gas: 8_000_000n });
    }
    const sh = await V('ethShareOf', [F]).catch(() => 0n);
    if (sh > 0n) await act('sweep', 'withdrawEth(all funder shares)', wc, { address: A.vault, abi: VAULT, functionName: 'withdrawEth', args: [sh], gas: 1_200_000n });
    const owed = await V('pendingEthOf', [F]).catch(() => 0n);
    if (owed > 0n) await act('sweep', 'claimPendingEth', wc, { address: A.vault, abi: VAULT, functionName: 'claimPendingEth', gas: 900_000n });
    const pay = await R('payoutOwedTotal').catch(() => 0n);
    if (pay > 0n) await act('sweep', 'claimPayout', wc, { address: A.engine, abi: ENGINE, functionName: 'claimPayout', gas: 500_000n });
  }

  const sF = await snapshot('mass/final', F);
  const balF = await pc.getBalance({ address: F });
  const stranded = { vaultShares: String(await V('ethShareOf', [F]).catch(() => 0n)),
                     pendingEth: String(await V('pendingEthOf', [F]).catch(() => 0n)),
                     openPositions: String(await R('openCount')),
                     residualToken: String(await pc.readContract({ address: A.token, abi: ERC20, functionName: 'balanceOf', args: [F] })) };
  put({ kind: 'reconciliation', run: RUN, funderBalanceStart: bal0, funderBalanceEnd: balF, netEth: balF - bal0,
        deposit: spend.deposit, bag: spend.bag, collateral: spend.collateral,
        grossDeployed: spend.deposit + spend.bag + spend.collateral, stranded,
        unabsorbedT0: s0.engine.unabsorbedEth, unabsorbedFinal: sF.engine.unabsorbedEth,
        insuranceT0: s0.engine.insuranceEth, insuranceFinal: sF.engine.insuranceEth,
        plvT0: s0.engine.plv, plvFinal: sF.engine.plv });
  console.log(`\nRECONCILE deployed ${formatEther(spend.deposit + spend.bag + spend.collateral)} ETH, funder net ${formatEther(balF - bal0)} ETH`, stranded);
})().catch(e => { console.error('FATAL', e); put({ kind: 'fatal', where: 'mass.mjs', error: String(e?.shortMessage || e?.message || e).slice(0, 400) }); process.exit(1); });
