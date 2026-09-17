#!/usr/bin/env node
/**
 * EXTERNAL FRESHNESS PROBE — the alarm the read layer did not have.
 *
 *  ── WHY THIS EXISTS ───────────────────────────────────────────────────────
 *  Before this file there was no alerting anywhere in the repo: no pager, no
 *  webhook, no external check. `/freshness` is a good beacon, but the only
 *  thing that polled it was a BROWSER (`src/hooks/useIndexerHealth.ts`), so it
 *  only reported a problem to someone who was already looking at the site. And
 *  Railway's `/health` probe is Ponder's LIVENESS path: it returns 200 as soon
 *  as the HTTP server is up, so it cannot signal a stalled or diverged sync
 *  (`indexer/railway.json:6`, `indexer/src/api/index.ts:1544-1548`).
 *
 *  Railway also stops restarting after ten consecutive failures
 *  (`indexer/railway.json:8`, `restartPolicyMaxRetries: 10`). That cap is a
 *  DELIBERATE decision — the in-process watchdog relies on it to bound a
 *  restart loop — so it is not something to raise. It does mean the service can
 *  end up permanently down with nothing saying so. Catching that is this
 *  probe's job.
 *
 *  ── WHAT IT READS, AND WHY BOTH ───────────────────────────────────────────
 *  `/status` — Ponder's own sync status. `{ <chainName>: { id, block: {
 *  number, timestamp } } }`. VERIFIED live 2026-09-16. This is the TRUE indexer
 *  height and it is the primary staleness signal.
 *
 *  `/freshness` — the divergence + reorg beacon. It carries `reorgToleranceOk`,
 *  the divergence `reasons`, and 503s when either trips.
 *
 *  Both are needed, and neither substitutes for the other:
 *
 *    • `/freshness`'s own `lagSeconds` is NOT a lag measurement. It is
 *      `latestBlock.timestamp - newestIndexedSwap.timestamp`
 *      (`indexer/src/api/index.ts:1514-1520`) — the age of the last SWAP, not
 *      the age of the last indexed BLOCK. On a quiet market it grows without
 *      bound while the indexer is perfectly healthy, and if the round has no
 *      swaps at all it is `null`. Paging on it alone pages on a quiet night.
 *      `/status` has no such coupling to trade volume.
 *
 *    • `/status` says nothing about divergence or reorg tolerance. A container
 *      indexing the WRONG pool at the chain head reports a perfectly fresh
 *      `/status`. Only `/freshness` catches that.
 *
 *  ── THE 200 IS NOT PROOF OF HEALTH ────────────────────────────────────────
 *  `evaluateHealth`'s catch-all returns `{ ok: true, warmingUp: true, error }`
 *  on ANY exception (`indexer/src/api/index.ts:1534-1541`), so a DB failure
 *  surfaces as a 200. That is the right call for the endpoint (it must never
 *  block a Railway promotion) and the wrong thing for a monitor to trust. This
 *  probe therefore treats a persistent `error` field, and a body that is
 *  MISSING the height fields altogether, as faults in their own right.
 *
 *  No secret is ever printed. The webhook URL is read from the environment and
 *  is never logged, echoed, or included in output.
 */
import { readFileSync } from "node:fs";

/* ── Chain profiles. Block times are MEASURED, not assumed. ─────────────────
 *
 *  4663, measured 2026-09-16 against https://rpc.mainnet.chain.robinhood.com:
 *    latest    64,645,113 @ ts 1,789,575,427
 *    finalized 64,636,839 @ ts 1,789,574,597
 *    → finality distance 8,274 blocks over 830 s
 *    → 830 / 8,274 = 0.1003 s per block. Hence blockMs 100.
 *
 *  `finalityBlocks` mirrors indexer/scripts/patch-ponder-finality.mjs, which is
 *  what Ponder actually runs with. Sepolia is NOT in that table, so it runs on
 *  Ponder's own built-in 65 (node_modules/ponder/dist/esm/utils/finality.js).
 */
const CHAINS = {
  4663: { name: "Robinhood mainnet", blockMs: 100, finalityBlocks: 12_000 },
  46630: { name: "Robinhood testnet", blockMs: 100, finalityBlocks: 12_000 },
  5042002: { name: "Arc testnet", blockMs: 1_000, finalityBlocks: 1_200 },
  11155111: { name: "Sepolia", blockMs: 12_000, finalityBlocks: 65 },
};

/* ── Thresholds. Every one is derived below; none is a round number picked
 *     because it looked sensible. Override with env vars for a drill. ────── */

//  STALE_CRIT_S — how many seconds behind the chain head the indexer may fall
//  before this is a page.
//
//  Floor (what normal looks like): Ponder polls 4663 every 1,000 ms
//  (`indexer/ponder.config.ts:166`) and blocks are ~100 ms, so steady-state lag
//  is ~1-2 s. Nothing near the threshold.
//
//  Ceiling (what it must not exceed): staleness must be caught BEFORE it
//  approaches the chain's finality distance, because past that point the blocks
//  the indexer still has to catch up on are ones it will treat as final on
//  arrival. Measured finality distance on 4663 is 8,274 blocks = 830 s.
//
//  Restart allowance (what must NOT page): Railway's healthcheckTimeout is 300 s
//  (`indexer/railway.json:7`), so one crash-and-resync can legitimately take up
//  to ~300 s.
//
//  300 s (one legitimate restart) < 600 s < 830 s (finality distance).
//  600 s sits above the largest benign event and 230 s below the dangerous one.
const STALE_CRIT_S = num(process.env.STALE_CRIT_S, 600);
//  Warn at one restart-allowance, so a restart LOOP is visible before the page.
const STALE_WARN_S = num(process.env.STALE_WARN_S, 120);

//  FINALITY_WARN_FRACTION — early warning before `reorgToleranceOk` flips.
//
//  The endpoint only tells you once finalityLagBlocks EXCEEDS the patched
//  tolerance, and by then Ponder is already pruning journals for blocks the
//  chain can still rewrite. The margin is thinner than it looks: 12,000 patched
//  against 8,274 measured is only 3,726 blocks of headroom = 374 s.
//
//  Two independent measurements of 4663's finality distance exist: 8,274 (this
//  run, measured) and ~9,650 (audit/RH_MAINNET_2026-09-16/CHAIN_PROFILE.md).
//  A warn threshold has to sit above BOTH or it fires on normal variation.
//    0.85 x 12,000 = 10,200 blocks.
//    8,274 = 69% of tolerance. 9,650 = 80%. 10,200 = 85%.
//  So the warn fires only on genuine drift past every figure ever measured,
//  and still leaves 1,800 blocks (~180 s) before the endpoint 503s.
const FINALITY_WARN_FRACTION = num(process.env.FINALITY_WARN_FRACTION, 0.85);

//  /freshness does up to two `eth_getBlock` calls plus two contract reads plus
//  DB queries, behind a 4 s cache (`indexer/src/api/index.ts:1437`). 20 s is
//  generous for that and still far below any sane cron interval.
const TIMEOUT_MS = num(process.env.PROBE_TIMEOUT_MS, 20_000);

function num(v, d) {
  const n = Number(v);
  return Number.isFinite(n) && v !== undefined && v !== "" ? n : d;
}

const manifest = JSON.parse(
  readFileSync(new URL("../deployments/round.json", import.meta.url), "utf8"),
);
//  Both the URL and the expected chain id come from the manifest, so the
//  Robinhood cutover (which REPLACES round.json) re-points this probe with no
//  separate edit. A monitor pinned to its own copy of the chain id is a monitor
//  that keeps watching the old chain.
const BASE = (process.env.INDEXER_URL || manifest.indexerUrl || "").replace(/\/+$/, "");
const EXPECT_CHAIN = Number(process.env.EXPECT_CHAIN_ID || manifest.chainId);
const profile = CHAINS[EXPECT_CHAIN] ?? { name: `chain ${EXPECT_CHAIN}`, blockMs: null, finalityBlocks: null };

const crits = [];
const warns = [];
const notes = [];
const crit = (m) => crits.push(m);
const warn = (m) => warns.push(m);

async function get(path) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${BASE}${path}`, {
      signal: ctl.signal,
      headers: { accept: "application/json" },
    });
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* not json — keep the status */ }
    return { status: res.status, json, text };
  } catch (e) {
    return { status: 0, json: null, text: String(e?.message ?? e) };
  } finally {
    clearTimeout(t);
  }
}

async function main() {
  if (!BASE) {
    crit("no indexer URL: neither INDEXER_URL nor round.json `indexerUrl` is set");
    return report();
  }
  notes.push(`target ${BASE} — expecting chain ${EXPECT_CHAIN} (${profile.name})`);

  /* ── 1. Ponder sync status: the true indexer height ───────────────────── */
  const st = await get("/status");
  if (st.status === 0) {
    crit(`/status unreachable: ${st.text}`);
  } else if (st.status !== 200 || !st.json) {
    crit(`/status returned HTTP ${st.status} (expected 200 + JSON)`);
  } else {
    //  Keyed by Ponder's chain NAME, which is a config detail we should not
    //  hardcode. Match on the chain ID instead, which is the thing that matters.
    const entries = Object.entries(st.json).filter(([, v]) => v && typeof v === "object" && "block" in v);
    if (!entries.length) {
      crit(`/status has no chain entries: ${st.text.slice(0, 200)}`);
    } else {
      const hit = entries.find(([, v]) => Number(v.id) === EXPECT_CHAIN);
      if (!hit) {
        //  Indexing a chain nobody asked for. This is the failure that once
        //  rendered a sold-out presale as "0 / 1111".
        crit(
          `/status reports chain ${entries.map(([k, v]) => `${k}=${v.id}`).join(", ")} ` +
            `but the manifest says ${EXPECT_CHAIN} — the indexer is on the WRONG CHAIN`,
        );
      } else {
        const [chainName, v] = hit;
        const ts = Number(v.block?.timestamp ?? 0);
        const nowS = Math.floor(Date.now() / 1000);
        const stale = nowS - ts;
        notes.push(`/status ${chainName} block ${v.block?.number} @ ${ts} → ${stale}s behind wall clock`);
        //  Negative means the chain's clock is ahead of ours; that is a clock
        //  problem on this runner, not an indexer fault. Do not page on it.
        if (stale < -120) {
          warn(`indexed block timestamp is ${-stale}s in the FUTURE — check this runner's clock, not the indexer`);
        } else if (stale > STALE_CRIT_S) {
          crit(`indexer is ${stale}s behind the chain (page above ${STALE_CRIT_S}s)`);
        } else if (stale > STALE_WARN_S) {
          warn(`indexer is ${stale}s behind the chain (warn above ${STALE_WARN_S}s)`);
        }
      }
    }
  }

  /* ── 2. /freshness: divergence + reorg tolerance ──────────────────────── */
  const fr = await get("/freshness");
  if (fr.status === 0) {
    crit(`/freshness unreachable: ${fr.text}`);
    return report();
  }
  const b = fr.json;
  if (!b) {
    crit(`/freshness returned HTTP ${fr.status} with non-JSON body: ${fr.text.slice(0, 200)}`);
    return report();
  }

  //  A 503 is the endpoint deliberately raising its hand: sustained divergence,
  //  or the live finality lag exceeding the patched tolerance.
  if (fr.status === 503) {
    const why = Object.entries(b.reasons ?? {}).filter(([, v]) => v === true).map(([k]) => k);
    crit(`/freshness 503 — ${why.length ? why.join(", ") : "ok:false with no reason flag set"}`);
  } else if (fr.status !== 200) {
    crit(`/freshness returned HTTP ${fr.status} (expected 200 or 503)`);
  }

  //  THE MONITOR MUST KNOW WHETHER IT CAN SEE. The reorg fields arrived in
  //  commit 286056b. A deployment that predates it answers 200 with none of
  //  them, and every reorg check below would silently evaluate to "undefined is
  //  not greater than anything" — a monitor reporting all-clear because it is
  //  blind. Measured 2026-09-16: the LIVE service is exactly in this state.
  if (b.chainHeight === undefined && b.warmingUp !== true) {
    crit(
      "/freshness body has no `chainHeight`/`reorgToleranceOk` — the DEPLOYED build " +
        "predates commit 286056b, so the reorg-tolerance alarm is not running at all. " +
        "Redeploy the indexer; until then this probe cannot see a reorg fault.",
    );
  }

  if (b.ok === false) crit("/freshness reports ok:false");
  if (b.error) warn(`/freshness caught an internal error (reported as healthy): ${String(b.error).slice(0, 200)}`);
  if (b.warmingUp === true) notes.push("warmingUp:true — backfill in progress, not a fault by itself");

  if (Number(b.chainId) && Number(b.chainId) !== EXPECT_CHAIN) {
    crit(`/freshness says chainId ${b.chainId}, manifest says ${EXPECT_CHAIN}`);
  }

  //  Divergence: indexed the WRONG thing. Waiting never fixes it.
  if (b.reasons?.poolMismatch) crit("poolMismatch — indexing a pool that is not the live one");
  if (b.reasons?.missedLaunch) crit("missedLaunch — the chain launched a generation the indexer never saw");

  //  Reorg tolerance, with an early warning the endpoint itself does not give.
  const lag = b.finalityLagBlocks;
  const tol = b.finalityBlockCount;
  if (b.reorgToleranceOk === false) {
    crit(
      `reorg tolerance EXCEEDED: chain finality lag ${lag} blocks > Ponder tolerance ${tol}. ` +
        "Ponder is calling final blocks the chain can still rewrite, and it prunes the journals for them.",
    );
  } else if (b.reorgToleranceOk === null) {
    warn("reorgToleranceOk is null — the RPC did not serve a `finalized` tag, so tolerance is UNPROVEN");
  } else if (typeof lag === "number" && typeof tol === "number" && tol > 0) {
    const frac = lag / tol;
    const secs = profile.blockMs ? Math.round((lag * profile.blockMs) / 1000) : null;
    notes.push(
      `finality lag ${lag}/${tol} blocks (${(frac * 100).toFixed(1)}% of tolerance` +
        (secs !== null ? `, ~${secs}s` : "") + ")",
    );
    if (frac > FINALITY_WARN_FRACTION) {
      warn(
        `finality lag is ${(frac * 100).toFixed(1)}% of the patched tolerance ` +
          `(warn above ${(FINALITY_WARN_FRACTION * 100).toFixed(0)}%). Re-derive ` +
          "indexer/scripts/patch-ponder-finality.mjs before it 503s.",
      );
    }
    //  Cross-check the staleness threshold against the chain the probe is
    //  ACTUALLY watching, so these constants cannot quietly drift apart the way
    //  Ponder's 30-block default drifted from a 100 ms chain.
    if (secs !== null && secs > 0 && STALE_CRIT_S >= secs) {
      warn(
        `STALE_CRIT_S (${STALE_CRIT_S}s) is no longer below this chain's finality ` +
          `distance (~${secs}s). Re-derive it — the page would fire too late to matter.`,
      );
    }
  }

  //  Reported for context only. See the header: this is swap age, not lag.
  if (b.lagSeconds !== undefined && b.lagSeconds !== null) {
    notes.push(`(context) /freshness lagSeconds=${b.lagSeconds} — age of last indexed SWAP, not indexer lag`);
  }

  return report();
}

async function report() {
  const level = crits.length ? "CRIT" : warns.length ? "WARN" : "OK";
  const lines = [
    ...crits.map((m) => `  [CRIT] ${m}`),
    ...warns.map((m) => `  [WARN] ${m}`),
    ...notes.map((m) => `  [note] ${m}`),
  ];
  const summary = `indexer monitor: ${level}\n${lines.join("\n")}`;
  console.log(summary);

  if (process.env.GITHUB_STEP_SUMMARY) {
    const { appendFileSync } = await import("node:fs");
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `### indexer monitor: ${level}\n\n\`\`\`\n${lines.join("\n")}\n\`\`\`\n`);
  }

  //  Only CRIT pages. A WARN is for the run log — a monitor that pages on
  //  everything is a monitor the operator learns to ignore, and the whole point
  //  of the derivations above is that the page means something.
  if (crits.length) await notifyWebhook(summary);
  process.exitCode = crits.length ? 1 : 0;
}

/** Post to a Slack- or Discord-compatible incoming webhook, if one is set.
 *  The URL itself is a secret and is NEVER logged — only whether a post
 *  succeeded, and the HTTP status if it did not. */
async function notifyWebhook(text) {
  const url = process.env.ALERT_WEBHOOK_URL;
  if (!url) {
    console.log("  [note] ALERT_WEBHOOK_URL is not set — nothing was paged. See indexer/monitor/README.md");
    return;
  }
  //  Slack wants `text`, Discord wants `content`. Choose by host so neither
  //  gets a field it rejects.
  let host = "";
  try { host = new URL(url).host; } catch { crits.push("ALERT_WEBHOOK_URL is not a valid URL"); return; }
  const body = host.endsWith("discord.com") || host.endsWith("discordapp.com")
    ? { content: text.slice(0, 1900) }
    : { text };
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    //  Deliberately reports the HOST only, never the path — the path is the secret.
    console.log(`  [note] alert POSTed to ${host} → HTTP ${res.status}`);
  } catch (e) {
    console.log(`  [note] alert POST failed: ${String(e?.message ?? e)}`);
  }
}

await main();
