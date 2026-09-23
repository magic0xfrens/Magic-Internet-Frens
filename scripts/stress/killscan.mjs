#!/usr/bin/env node
/**
 * killscan.mjs — (1) attribute every liquidation in the window to the TRANSACTION
 * that caused it, so "one trade, many kills" is measured rather than asserted, and
 * (2) re-run the dump against the LIVE balance.
 *
 * The first dump reverted `transferFrom failed`: the approval and the sell amount
 * were both the bag as measured at buy time, but the funder's balance had since
 * been reduced by an out-of-band sell from the same wallet. Re-reading the balance
 * at send time is the fix; the amount is never cached across a wait.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createPublicClient, createWalletClient, http, formatEther, parseAbi, getAddress,
  decodeErrorResult, parseEventLogs,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'contracts/solidity/out');
const JSONL = path.join(ROOT, 'audit/STRESS_2026-09-22/cascade-actions.jsonl');
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const RUN = arg('run', 'mass-killscan');
const RPC = arg('rpc', process.env.STRESS_RPC || 'https://ethereum-sepolia-rpc.publicnode.com');
const DO_DUMP = argv.includes('--dump');
const DUMPGAS = BigInt(arg('dumpgas', '16000000'));
const FROM = BigInt(arg('from', '0'));

const ROUND = JSON.parse(fs.readFileSync(path.join(ROOT, 'indexer/deployments/round.json'), 'utf8'));
const C = ROUND.contracts;
const A = { engine: getAddress(C.perpEngine), vault: getAddress(C.perpVault),
            router: getAddress(C.gachaRouter), collection: getAddress(C.collection), hook: getAddress(C.hook) };
function art(n) {
  const d = path.join(OUT, n + '.sol');
  const f = fs.readdirSync(d).filter(x => x.startsWith(n + '.') && x.endsWith('.json')).sort().reverse()[0];
  return JSON.parse(fs.readFileSync(path.join(d, f), 'utf8'));
}
const ENGINE = art('PerpEngine').abi, ROUTER = art('CauldronGachaRouter').abi, HOOK = art('CauldronHook').abi;
const VAULT = art('PerpVault').abi;
const ERC20 = parseAbi(['function balanceOf(address) view returns (uint256)', 'function approve(address,uint256) returns (bool)']);
const V4_WRAPPED = parseAbi(['error WrappedError(address target, bytes4 selector, bytes reason, bytes details)']);
const ALL_ERRORS = [...ENGINE, ...ROUTER, ...HOOK, ...VAULT, ...V4_WRAPPED].filter(x => x.type === 'error');

const transport = http(RPC, { retryCount: 8, retryDelay: 900, timeout: 90_000, batch: false });
const pc = createPublicClient({ chain: sepolia, transport });
let SEQ = 0;
const put = o => { fs.appendFileSync(JSONL, JSON.stringify({ run: RUN, seq: ++SEQ, at: new Date().toISOString(), ...o },
  (_, v) => typeof v === 'bigint' ? v.toString() : v) + '\n'); return o; };
function unwrapV4(data, depth = 0) {
  if (!data || data === '0x' || depth > 5) return null;
  try { const w = decodeErrorResult({ abi: V4_WRAPPED, data });
    const inner = unwrapV4(w.args[2], depth + 1);
    return inner ? `${inner} [unwrapped from WrappedError(target=${w.args[0]}, hookFn=${w.args[1]})]`
                 : `WrappedError(target=${w.args[0]}, hookFn=${w.args[1]}, reason=${String(w.args[2]).slice(0, 26)})`; } catch { }
  try { return decodeErrorResult({ abi: ALL_ERRORS, data }).errorName; } catch { }
  return `undecoded ${String(data).slice(0, 12)}`;
}
function reason(e) {
  try { const rv = e?.walk?.(x => x?.name === 'ContractFunctionRevertedError');
    if (rv) { const raw = rv.raw ?? rv.data?.data; const u = raw && raw !== '0x' ? unwrapV4(raw) : null;
      if (u) return u; if (rv.data?.errorName) return rv.data.errorName; if (rv.reason) return 'revert: ' + rv.reason; } } catch { }
  return String(e?.shortMessage || e?.details || e?.message || e).split('\n')[0].slice(0, 200);
}
const R = (fn, args = []) => pc.readContract({ address: A.engine, abi: ENGINE, functionName: fn, args });

(async () => {
  const m = fs.readFileSync(path.join(ROOT, 'contracts/solidity/.env'), 'utf8')
    .match(/^\s*PRIVATE_KEY\s*=\s*(0x)?([0-9a-fA-F]{64})\s*$/m);
  const acct = privateKeyToAccount('0x' + m[2]);
  const wc = createWalletClient({ account: acct, chain: sepolia, transport });
  const F = acct.address;
  const token = getAddress(await R('syncedToken'));

  // ── 1. attribute liquidations to transactions ───────────────────────────
  const head = await pc.getBlockNumber();
  const from = FROM > 0n ? FROM : head - 400n;
  console.log(`scanning engine logs ${from}..${head}`);
  const raw = await pc.getLogs({ address: A.engine, fromBlock: from, toBlock: head });
  const parsed = parseEventLogs({ abi: ENGINE, logs: raw });
  const byName = {};
  for (const l of parsed) byName[l.eventName] = (byName[l.eventName] || 0) + 1;
  console.log('events in window:', byName);
  put({ kind: 'note', note: `engine events ${from}..${head}: ${JSON.stringify(byName)}` });

  const liqNames = [...new Set(parsed.map(l => l.eventName))].filter(n => /liquidat|settle|closed|position/i.test(n));
  const kills = parsed.filter(l => /liquidat/i.test(l.eventName));
  const perTx = new Map();
  for (const l of kills) {
    const k = l.transactionHash;
    if (!perTx.has(k)) perTx.set(k, { tx: k, block: l.blockNumber, ids: [], events: [] });
    const e = perTx.get(k);
    const id = l.args?.id ?? l.args?.positionId ?? null;
    if (id !== null && id !== undefined) e.ids.push(String(id));
    e.events.push(l.eventName);
  }
  const rows = [];
  for (const e of perTx.values()) {
    const rcpt = await pc.getTransactionReceipt({ hash: e.tx });
    const txo = await pc.getTransaction({ hash: e.tx });
    rows.push({ tx: e.tx, block: String(e.block), killCount: e.ids.length, ids: e.ids,
      from: txo.from, to: txo.to, gasUsed: String(rcpt.gasUsed), gasLimit: String(txo.gas),
      value: String(txo.value), selector: String(txo.input).slice(0, 10),
      isFunder: txo.from.toLowerCase() === F.toLowerCase(),
      gasPerKill: e.ids.length ? String(rcpt.gasUsed / BigInt(e.ids.length)) : null });
  }
  rows.sort((a, b) => Number(a.block) - Number(b.block));
  put({ kind: 'finding', topic: 'KILLS-BY-TRANSACTION', liqEventNames: liqNames, window: `${from}..${head}`, rows });
  console.log('\n── liquidations attributed to their transaction');
  for (const r of rows) console.log(`  block ${r.block} tx ${r.tx.slice(0, 12)}… from ${r.from.slice(0, 10)}… sel ${r.selector} kills=${r.killCount} gasUsed=${r.gasUsed} gasPerKill=${r.gasPerKill} funder=${r.isFunder} ids=${r.ids.join(',')}`);
  const best = rows.reduce((a, b) => (b.killCount > (a?.killCount ?? -1) ? b : a), null);
  if (best) {
    put({ kind: 'finding', topic: 'BIGGEST-SINGLE-TRADE-CASCADE', ...best });
    console.log(`\n  BIGGEST SINGLE TRADE: ${best.killCount} kills in ${best.tx} (gasUsed ${best.gasUsed}, gasPerKill ${best.gasPerKill})`);
  }

  // ── 2. re-run the dump against the LIVE balance ─────────────────────────
  if (DO_DUMP) {
    const ids = [];
    for (let i = 40n; i < 70n; i++) {
      const p = await R('positions', [i]).catch(() => null);
      if (p && p[0] !== '0x0000000000000000000000000000000000000000') ids.push(i);
    }
    console.log(`\nopen ids: ${ids.join(',')}`);
    const pre = [];
    for (const id of ids) {
      const h = await R('positionHealth', [id]).catch(() => null);
      const liq = await R('isLiquidatable', [id]).catch(() => null);
      pre.push({ id: String(id), isLiquidatable: liq, markValueEth: h ? String(h[1]) : null,
        debtEth: h ? String(h[2]) : null,
        cushionPct: h && h[1] > 0n ? Number((h[1] - h[2]) * 10000n / h[1]) / 100 : null });
    }
    put({ kind: 'finding', topic: 'PRE-DUMP2-TABLE', rows: pre });
    console.log('PRE-DUMP table:', pre.map(r => `#${r.id} liq=${r.isLiquidatable} cushion=${r.cushionPct}%`).join('  '));

    const bal = await pc.readContract({ address: token, abi: ERC20, functionName: 'balanceOf', args: [F] });
    console.log(`live bag = ${bal}`);
    put({ kind: 'note', note: `re-dump against LIVE balance ${bal} (first attempt used a cached, now-stale amount)` });
    // approve exactly the live balance
    const sa = await pc.simulateContract({ address: token, abi: ERC20, functionName: 'approve', args: [A.router, bal], account: acct });
    const ah = await wc.writeContract({ ...sa.request, gas: 120_000n });
    await pc.waitForTransactionReceipt({ hash: ah, timeout: 240_000 });
    put({ kind: 'action', phase: 'dump2', action: 'approve router for live balance', ok: true, tx: ah });

    const doses = [2_000_000n, 4_000_000n, 8_000_000n, 16_000_000n];
    const dose = [];
    for (const g of doses) {
      let row;
      try { await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play', args: [0n, bal, 0n, 0n, 0n], account: acct, gas: g });
            row = { gasSupplied: String(g), outcome: 'FILLS', error: null }; }
      catch (e) { row = { gasSupplied: String(g), outcome: 'REFUSED', error: reason(e) }; }
      dose.push(row); put({ kind: 'dose', phase: 'mass-dump2', ...row });
      console.log(`    gas ${Number(g) / 1e6}M -> ${row.outcome}${row.error ? ' :: ' + row.error : ''}`);
    }

    const snap = async () => ({
      openCount: await R('openCount'), plv: await R('plv'), ins: await R('insuranceEth'),
      unabs: await R('unabsorbedEth'), mark: await R('markSqrtPriceX96'), depth: await R('activeEthDepth'),
      minted: await pc.readContract({ address: A.collection, abi: art('CauldronCollection').abi, functionName: 'liquidatorMinted' }).catch(() => null),
      badges: await R('badgesOwed', [F]).catch(() => null),
    });
    const b4 = await snap(); put({ kind: 'snapshot', label: 'dump2/before', ...b4 });
    let rc = { ok: false };
    try {
      const sim = await pc.simulateContract({ address: A.router, abi: ROUTER, functionName: 'play', args: [0n, bal, 0n, 0n, 0n], account: acct, gas: DUMPGAS });
      const hash = await wc.writeContract({ ...sim.request, gas: DUMPGAS });
      const r = await pc.waitForTransactionReceipt({ hash, timeout: 240_000 });
      rc = { ok: r.status === 'success', tx: hash, gasUsed: String(r.gasUsed), block: String(r.blockNumber) };
    } catch (e) { rc = { ok: false, reason: reason(e) }; }
    put({ kind: 'action', phase: 'dump2', action: `ONE DUMP live bag @ ${Number(DUMPGAS) / 1e6}M`, ...rc });
    console.log(`  dump2: ok=${rc.ok} tx=${rc.tx} gas=${rc.gasUsed} ${rc.reason || ''}`);
    const af = await snap(); put({ kind: 'snapshot', label: 'dump2/after', ...af });

    const post = [];
    for (const r of pre) {
      const p = await R('positions', [BigInt(r.id)]).catch(() => null);
      post.push({ ...r, aliveAfter: !!(p && p[0] !== '0x0000000000000000000000000000000000000000') });
    }
    const died = post.filter(p => !p.aliveAfter).map(p => p.id);
    put({ kind: 'finding', topic: 'MASS-CASCADE-RESULT-2', tx: rc.tx, ok: rc.ok, reason: rc.reason,
      gasUsed: rc.gasUsed, killCount: died.length, died,
      projectedOnly: post.filter(p => !p.aliveAfter && p.isLiquidatable === false).map(p => p.id),
      gasPerKill: rc.gasUsed && died.length ? String(BigInt(rc.gasUsed) / BigInt(died.length)) : null,
      openCountBefore: b4.openCount, openCountAfter: af.openCount,
      insuranceBefore: b4.ins, insuranceAfter: af.ins,
      unabsorbedBefore: b4.unabs, unabsorbedAfter: af.unabs,
      unabsorbedMoved: String(b4.unabs) !== String(af.unabs),
      liquidatorMintedBefore: b4.minted, liquidatorMintedAfter: af.minted,
      plvBefore: b4.plv, plvAfter: af.plv, markBefore: b4.mark, markAfter: af.mark, table: post });
    console.log(`\n  KILLED ${died.length}/${pre.length}: ${died.join(',') || 'none'}`);
    console.log(`  UNABSORBED ${b4.unabs} → ${af.unabs}   openCount ${b4.openCount}→${af.openCount}  minted ${b4.minted}→${af.minted}`);
  }
})().catch(e => { console.error('FATAL', e); put({ kind: 'fatal', where: 'killscan', error: String(e?.shortMessage || e?.message || e).slice(0, 400) }); process.exit(1); });
