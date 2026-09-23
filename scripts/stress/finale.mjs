#!/usr/bin/env node
/**
 * finale.mjs — let the 5-minute TWAP converge onto the post-dump spot, then fire
 * ONE trade and measure the cascade it triggers.
 *
 * WHY THE EARLIER DUMP KILLED ALMOST NOTHING
 *   `twapWindow` is 5 minutes (PerpEngine.sol:312) and `_liqTest` takes the WORSE
 *   of the TWAP mark and live spot. Acquiring a token bag requires BUYING it, and
 *   that buy drags the TWAP UP for the next five minutes — healing every long
 *   faster than the dump could hurt it. Measured: min cushion 13.42% before the
 *   dump, 43.34% after. The round trip is not merely price-neutral on spot, it is
 *   actively PROTECTIVE on the mark for a full twapWindow.
 *
 *   So: stop trading, let the average catch up to the crashed spot, and then fire
 *   one small swap purely as the sweep's trigger. The liquidations that follow are
 *   caused by the price the book already sat at, which is the honest scenario.
 *
 * Appends to the same append-only JSONL. Never truncates.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicClient, createWalletClient, http, parseEther, formatEther, parseAbi, getAddress, decodeErrorResult } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'contracts/solidity/out');
const JSONL = path.join(ROOT, 'audit/STRESS_2026-09-22/cascade-actions.jsonl');
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const RUN = arg('run', 'live-5X-finale');
const RPC = arg('rpc', 'https://ethereum-sepolia-rpc.publicnode.com');
const WAIT_MAX = Number(arg('waitmax', 12));      // polls, ~45s apart
const TRIGGER = arg('trigger', '0.03');           // ETH of the trigger buy

const ROUND = JSON.parse(fs.readFileSync(path.join(ROOT, 'indexer/deployments/round.json'), 'utf8'));
const C = ROUND.contracts;
const A = { hook: getAddress(C.hook), engine: getAddress(C.perpEngine), vault: getAddress(C.perpVault),
            router: getAddress(C.gachaRouter), collection: getAddress(C.collection), token: null };
function art(n) { const d = path.join(OUT, n + '.sol');
  const f = fs.readdirSync(d).filter(x => x.startsWith(n + '.') && x.endsWith('.json')).sort().reverse()[0];
  return JSON.parse(fs.readFileSync(path.join(d, f), 'utf8')); }
const ENGINE = art('PerpEngine').abi, VAULT = art('PerpVault').abi, ROUTER = art('CauldronGachaRouter').abi,
      HOOK = art('CauldronHook').abi, COLL_ABI = art('CauldronCollection').abi;
const V4_WRAPPED = parseAbi(['error WrappedError(address target, bytes4 selector, bytes reason, bytes details)']);
const ALL_ERRORS = [...ENGINE, ...VAULT, ...ROUTER, ...HOOK, ...V4_WRAPPED].filter(x => x.type === 'error');
const transport = http(RPC, { retryCount: 8, retryDelay: 900, timeout: 90_000, batch: false });
const pc = createPublicClient({ chain: sepolia, transport });
const sleep = ms => new Promise(r => setTimeout(r, ms));
function unwrapV4(d, k = 0) { if (!d || d === '0x' || k > 5) return null;
  try { const w = decodeErrorResult({ abi: V4_WRAPPED, data: d }); const i = unwrapV4(w.args[2], k + 1);
    return i ? `${i} [unwrapped from v4 WrappedError(target=${w.args[0]}, hookFn=${w.args[1]})]`
             : `WrappedError(target=${w.args[0]}, hookFn=${w.args[1]})`; } catch { }
  try { return decodeErrorResult({ abi: ALL_ERRORS, data: d }).errorName; } catch { } return `undecoded ${String(d).slice(0, 12)}`; }
function reason(e) { try { const rv = e?.walk?.(x => x?.name === 'ContractFunctionRevertedError');
  if (rv) { const raw = rv.raw ?? rv.data?.data; const u = raw && raw !== '0x' ? unwrapV4(raw) : null;
    if (u) return u; if (rv.data?.errorName) return rv.data.errorName; if (rv.reason) return 'revert: ' + rv.reason;
    if (!rv.raw || rv.raw === '0x') return 'EMPTY revert data'; } } catch { }
  return String(e?.shortMessage || e?.message || e).split('\n')[0].slice(0, 200); }
let SEQ = 0;
const put = o => { fs.appendFileSync(JSONL, JSON.stringify({ run: RUN, seq: ++SEQ, at: new Date().toISOString(), ...o },
  (_, v) => typeof v === 'bigint' ? v.toString() : v) + '\n'); return o; };
const R = (fn, a = []) => pc.readContract({ address: A.engine, abi: ENGINE, functionName: fn, args: a });
const H = (fn, a = []) => pc.readContract({ address: A.hook, abi: HOOK, functionName: fn, args: a });

async function snapshot(label, F) {
  const g = async (fn, a) => { try { return await R(fn, a); } catch { return null; } };
  const [depth, plv, ins, unabs, longOi, shortOi, open, mark, badges] = await Promise.all(
    ['activeEthDepth', 'plv', 'insuranceEth', 'unabsorbedEth', 'longOiEth', 'shortOiToken', 'openCount', 'markSqrtPriceX96']
      .map(f => g(f)).concat([g('badgesOwed', [F])]));
  const minted = await pc.readContract({ address: A.collection, abi: COLL_ABI, functionName: 'liquidatorMinted' }).catch(() => null);
  const dead = await H('isDead', [ROUND.poolIds[0]]).catch(() => null);
  const s = { kind: 'snapshot', label, engine: { activeEthDepth: depth, plv, insuranceEth: ins, unabsorbedEth: unabs,
    longOiEth: longOi, shortOiToken: shortOi, openCount: open, markSqrtPriceX96: mark, badgesOwedFunder: badges },
    market: { liquidatorMinted: minted, isDead: dead } };
  put(s);
  console.log(`\n── ${label}\n   open=${open} mark=${mark} depth=${formatEther(depth)} plv=${formatEther(plv)}`);
  console.log(`   UNABSORBED=${formatEther(unabs)} ins=${formatEther(ins)} minted=${minted} badges=${badges} dead=${dead}`);
  return s;
}
async function table(label, ids) {
  const rows = [];
  for (const id of ids) {
    const p = await R('positions', [id]).catch(() => null);
    const alive = !!(p && p[0] !== '0x0000000000000000000000000000000000000000');
    let liq = null, h = null, cushion = null, trip = null;
    if (alive) { liq = await R('isLiquidatable', [id]).catch(() => null);
      h = await R('positionHealth', [id]).catch(() => null);
      if (h && h[1] > 0n) { cushion = Number((h[1] - h[2]) * 10000n / h[1]) / 100;
        trip = Number(h[1] * 10000n / h[2]) / 100; } }   // markValue as % of debt; trips near 115%
    rows.push({ id: String(id), alive, isLiquidatable: liq, markValueEth: h ? String(h[1]) : null,
                debtEth: h ? String(h[2]) : null, cushionPct: cushion, markOverDebtPct: trip });
  }
  const mark = await R('markSqrtPriceX96');
  put({ kind: 'liq-table', label, markSqrtPriceX96: mark, rows });
  const al = rows.filter(r => r.alive); const t = al.filter(r => r.isLiquidatable).length;
  const cs = al.map(r => r.cushionPct).filter(x => x !== null);
  console.log(`  [${label}] alive=${al.length} LIQUIDATABLE=${t} cushion ${cs.length ? Math.min(...cs).toFixed(2) + '..' + Math.max(...cs).toFixed(2) : '-'}%`);
  return rows;
}

(async () => {
  const m = fs.readFileSync(path.join(ROOT, 'contracts/solidity/.env'), 'utf8').match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  const acct = privateKeyToAccount('0x' + m[2]);
  const wc = createWalletClient({ account: acct, chain: sepolia, transport });
  const F = acct.address;
  A.token = getAddress(await R('syncedToken'));
  const seen = new Set();
  for (const l of fs.readFileSync(JSONL, 'utf8').split('\n')) { if (!l.trim()) continue;
    try { const o = JSON.parse(l); if (o.kind === 'position' && o.run === 'live-5X-setup') seen.add(o.id); } catch { } }
  const ids = [...seen].map(BigInt).sort((a, b) => a < b ? -1 : 1);
  put({ kind: 'note', note: `finale: ${ids.length} cluster ids ${ids.join(',')}` });

  // ── wait for the 5-minute average to reach the crashed spot ───────────────
  let rows = await table('finale/t0', ids);
  for (let i = 0; i < WAIT_MAX; i++) {
    const n = rows.filter(r => r.alive && r.isLiquidatable).length;
    put({ kind: 'twap-converge', poll: i, liquidatableNow: n, mark: String(await R('markSqrtPriceX96')) });
    if (n >= 3) { put({ kind: 'note', note: `TWAP converged: ${n} liquidatable at poll ${i}` }); break; }
    await sleep(45_000);
    rows = await table(`finale/poll${i + 1}`, ids);
  }

  // ── the table, read at spot immediately before the one trade ──────────────
  const pre = await table('FINALE PRE-SWAP (spot, immediately before the trigger)', ids);
  put({ kind: 'finding', topic: 'preemptive-pre-finale', rows: pre });
  const s1 = await snapshot('finale/pre-cascade', F);

  // ── gas dose-response on a LOADED book ────────────────────────────────────
  const doses = [500_000n, 1_000_000n, 2_000_000n, 3_000_000n, 4_000_000n, 6_000_000n, 8_000_000n, 16_000_000n, 30_000_000n];
  const dose = []; let fill = null;
  for (const g of doses) {
    let row;
    try { await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play', args: [0n, 0n, 0n, 0n, 0n],
      account: acct, gas: g, value: parseEther(TRIGGER) });
      row = { gasSupplied: String(g), outcome: 'FILLS', error: null }; if (!fill) fill = g; }
    catch (e) { row = { gasSupplied: String(g), outcome: 'REFUSED', error: reason(e) }; }
    dose.push(row); put({ kind: 'dose', phase: 'finale', liveLiquidatable: pre.filter(r => r.alive && r.isLiquidatable).length, ...row });
    console.log(`    gas ${Number(g) / 1e6}M -> ${row.outcome}${row.error ? ' :: ' + row.error : ''}`);
  }
  put({ kind: 'finding', topic: 'gas-dose-response-finale', table: dose, lowestFill: fill ? String(fill) : null,
        liquidatableAtDose: pre.filter(r => r.alive && r.isLiquidatable).length });

  // ── ONE TRADE ─────────────────────────────────────────────────────────────
  let rc;
  try {
    const sim = await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play', args: [0n, 0n, 0n, 0n, 0n],
      account: acct, gas: 16_000_000n, value: parseEther(TRIGGER) });
    const hash = await wc.writeContract({ ...sim.request, gas: 16_000_000n });
    const r = await pc.waitForTransactionReceipt({ hash, timeout: 240_000 });
    rc = { ok: r.status === 'success', tx: hash, gasUsed: String(r.gasUsed), block: String(r.blockNumber) };
  } catch (e) { rc = { ok: false, reason: reason(e) }; }
  put({ kind: 'action', phase: 'finale', action: `ONE trigger trade ${TRIGGER} ETH @16M gas`, ...rc });
  console.log(`  trigger: ok=${rc.ok} tx=${rc.tx} gas=${rc.gasUsed} ${rc.reason || ''}`);

  const s2 = await snapshot('finale/post-cascade', F);
  const post = await table('FINALE POST-SWAP', ids);
  const merged = pre.map((p, i) => ({ id: p.id, aliveBefore: p.alive, spotLiquidatableBefore: p.isLiquidatable,
    cushionPctBefore: p.cushionPct, markOverDebtPctBefore: p.markOverDebtPct, aliveAfter: post[i].alive,
    killedBySweep: p.alive && !post[i].alive,
    PROJECTED_ONLY: p.alive && !post[i].alive && p.isLiquidatable === false }));
  const died = merged.filter(x => x.killedBySweep).map(x => x.id);
  const proj = merged.filter(x => x.PROJECTED_ONLY).map(x => x.id);
  put({ kind: 'finding', topic: 'FINALE-CASCADE-RESULT', ...rc, killCount: died.length, died, projectedOnly: proj,
    gasPerKill: rc.gasUsed && died.length ? String(BigInt(rc.gasUsed) / BigInt(died.length)) : null,
    openCountBefore: s1.engine.openCount, openCountAfter: s2.engine.openCount,
    liquidatorMintedBefore: s1.market.liquidatorMinted, liquidatorMintedAfter: s2.market.liquidatorMinted,
    badgesOwedBefore: s1.engine.badgesOwedFunder, badgesOwedAfter: s2.engine.badgesOwedFunder,
    plvBefore: s1.engine.plv, plvAfter: s2.engine.plv,
    insuranceBefore: s1.engine.insuranceEth, insuranceAfter: s2.engine.insuranceEth,
    unabsorbedBefore: s1.engine.unabsorbedEth, unabsorbedAfter: s2.engine.unabsorbedEth,
    unabsorbedMoved: String(s1.engine.unabsorbedEth) !== String(s2.engine.unabsorbedEth), table: merged });
  console.log(`\n  KILLED ${died.length}: ${died.join(',') || 'none'}`);
  console.log(`  PROJECTED-ONLY: ${proj.join(',') || 'none'}`);
  console.log(`  gasUsed=${rc.gasUsed} per kill=${rc.gasUsed && died.length ? Number(rc.gasUsed) / died.length : '-'}`);
  console.log(`  UNABSORBED ${s1.engine.unabsorbedEth} -> ${s2.engine.unabsorbedEth}`);
})().catch(e => { console.error('FATAL', e); put({ kind: 'fatal', where: 'finale', error: String(e?.shortMessage || e?.message || e).slice(0, 400) }); process.exit(1); });
