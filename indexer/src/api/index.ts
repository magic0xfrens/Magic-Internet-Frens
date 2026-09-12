import { db } from "ponder:api";
import schema from "ponder:schema";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { graphql, eq, desc, and, gte, ne } from "ponder";
import { createPublicClient, fallback, http, formatEther, keccak256, encodeAbiParameters } from "viem";
// SINGLE SOURCE OF TRUTH — same manifest as ponder.config.ts + the frontend.
import round from "../../deployments/round.json";

const app = new Hono();
app.use("*", cors({ origin: process.env.CORS_ORIGIN ?? "*" }));

// Short-lived shared caching on every read.
//
// The frontend polls several of these endpoints from every open tab, and the
// data behind them only changes as fast as the chain does. Without a
// Cache-Control header each poll is a full round-trip to Postgres plus, on some
// routes, live chain reads — so N viewers cost N times as much for identical
// bytes. A few seconds of shared caching collapses that to roughly one
// computation per interval regardless of audience size, while staying well
// inside the polling period so nothing looks stale.
//
// stale-while-revalidate lets a proxy serve the previous body during a refresh,
// so a slow query never becomes a slow page.
const READ_CACHE = "public, max-age=5, s-maxage=5, stale-while-revalidate=30";
app.use("*", async (c, next) => {
  await next();
  if (c.req.method === "GET" && !c.res.headers.has("Cache-Control")) {
    c.res.headers.set("Cache-Control", READ_CACHE);
  }
});
/**
 * GraphQL is public, and this indexer is the frontend's ENTIRE read layer — if
 * it stops answering, the UI has nothing to fall back to on most routes. An
 * unbounded query language in front of that is a cheap way to take the whole
 * site down: GraphQL lets one small request ask for arbitrarily deep nesting,
 * and the cost is paid by Postgres, not the caller. The in-process watchdog
 * would then restart the container into the same load, turning a slow query into
 * a restart loop.
 *
 * A byte cap is the bluntest useful bound and the one that cannot be reasoned
 * around: depth, breadth and alias-multiplication all have to be spelled out in
 * the document to be requested. Real queries from the app are a few hundred
 * bytes; this leaves two orders of magnitude of headroom.
 *
 * A missing `Content-Length` is rejected rather than waved through. Every real
 * GraphQL client sets it; omitting it means chunked transfer-encoding, which is
 * exactly how you would sidestep a header-based cap. The alternative — reading
 * the body here to measure it — risks consuming the stream before Ponder's
 * middleware parses it, and this is the frontend's whole read layer to break.
 */
const MAX_GRAPHQL_BYTES = Number(process.env.MAX_GRAPHQL_BYTES ?? 8_000);

/**
 * The cap must guard EVERY mount that serves GraphQL (audit Q-05).
 *
 * Ponder mounts the same resolver at `/graphql` AND at `/`. The cap was
 * registered only on `/graphql`, so `POST /` reached the identical unbounded
 * resolver with no limit at all — the bound existed and could be walked around
 * by dropping six characters from the path.
 *
 * The header is still only a header: a client that lies about `content-length`
 * is not stopped by this, which is why the 411 on a missing one matters (chunked
 * encoding is the other way around it). Measuring the body here was rejected
 * upstream because consuming the stream before Ponder parses it risks breaking
 * the frontend's whole read layer — so this is a bound on the honest majority
 * and a speed bump on the rest, applied consistently rather than on one path.
 */
const graphqlBodyCap = async (c: any, next: any) => {
  if (c.req.method === "POST") {
    const raw = c.req.header("content-length");
    if (raw === undefined) {
      return c.json({ errors: [{ message: "content-length required" }] }, 411);
    }
    if (Number(raw) > MAX_GRAPHQL_BYTES) {
      return c.json({ errors: [{ message: "query too large" }] }, 413);
    }
    //  ...AND VERIFY IT (audit Q-05). The header above is set by the client, so
    //  on its own it bounds only honest callers: `Content-Length: 100` with a
    //  multi-megabyte body sailed straight through. Measure the real thing.
    //
    //  Read a CLONE, never `c.req`. Cloning a Fetch Request tees the stream, so
    //  the original is left untouched for Ponder's parser — which is the concern
    //  that stopped this being measured before, and it is solved by the clone
    //  rather than by not measuring.
    //
    //  Counted incrementally with an early exit, so an attacker streaming a huge
    //  body cannot make the CHECK the memory exhaustion: we abort at the cap
    //  instead of buffering the whole thing to find out how big it was.
    try {
      const body = c.req.raw.clone().body;
      if (body) {
        const reader = body.getReader();
        let seen = 0;
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          seen += value?.byteLength ?? 0;
          if (seen > MAX_GRAPHQL_BYTES) {
            await reader.cancel();
            return c.json({ errors: [{ message: "query too large" }] }, 413);
          }
        }
      }
    } catch {
      //  A body we cannot measure is not a body we should forward blind, but
      //  neither is a clone failure the caller's fault — fall through to the
      //  header bound, which already rejected anything declaring itself oversized.
    }
  }
  await next();
};
app.use("/graphql", graphqlBodyCap);
app.use("/", graphqlBodyCap);
app.use("/graphql", graphql({ db, schema }));
app.use("/", graphql({ db, schema }));

/* ── live engine stats, read SERVER-SIDE (rotated keys) so the browser never
      touches RPC. Cached briefly to bound load under many viewers. ────────── */
const PERP_ENGINE = round.contracts.perpEngine as `0x${string}`;
// DEDICATED read pool for the API's server-side eth_calls (perp stats, vault,
// presale). Kept SEPARATE from Ponder's sync RPC — the sync polls constantly and
// was starving/rate-limiting these calls on a shared endpoint (perp stats + vault
// read 0 despite the contracts being funded). Use API_RPC_URL if set, else a
// multi-node public fallback distinct from the sync's single node.
const API_RPCS = (process.env.API_RPC_URL ?? [
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://sepolia.drpc.org",
  "https://1rpc.io/sepolia",
  "https://rpc.ankr.com/eth_sepolia",
  "https://eth-sepolia.public.blastapi.io",
].join(","))
  .split(",").map((s) => s.trim()).filter(Boolean);
const perpClient = createPublicClient({ transport: fallback(API_RPCS.map((u) => http(u, { retryCount: 2, retryDelay: 200 }))) });
const STATS_ABI = [{
  type: "function", name: "stats", stateMutability: "view", inputs: [],
  outputs: [
    { type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" },
    { type: "uint256" }, { type: "uint8" }, { type: "uint160" }, { type: "int256" }, { type: "bool" },
  ],
}] as const;
// Individual cheap getters — a fallback for when the bundled stats() view (which
// does heavy pool math: activeEthDepth/maxLeverage/markSqrtPriceX96) fails on a
// public RPC's eth_call. plv/plvToken/longOiEth/shortOiToken are plain SLOADs and
// always succeed → the liquidity guard + panel still get real numbers.
const ENGINE_READ = [
  { type: "function", name: "plv", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "plvToken", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "longOiEth", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "activeEthDepth", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "maxLeverage", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "markSqrtPriceX96", stateMutability: "view", inputs: [], outputs: [{ type: "uint160" }] },
  { type: "function", name: "fundingIndex", stateMutability: "view", inputs: [], outputs: [{ type: "int256" }] },
] as const;
// ── Community PLV vault (staking) — server-side reads so the browser is RPC-free.
const PERP_VAULT = round.contracts.perpVault as `0x${string}`;
const VAULT_ABI = [
  { type: "function", name: "assetsEth", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "assetsTok", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "ethShares", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tokShares", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "ethPosition", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "tokenPosition", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "ethShareOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tokShareOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pendingTokYield", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

let statsCache: { at: number; v: { depthEth: number; plvEth: number; plvToken: number; maxLev: number; longOiEth: number; shortOiEth: number; fundingIdx: number; dead: boolean; markSqrt: bigint } | null } = { at: 0, v: null };
async function liveStats() {
  if (PERP_ENGINE === "0x0000000000000000000000000000000000000000") return null;
  if (Date.now() - statsCache.at < 5000 && statsCache.v) return statsCache.v;
  const n = (v: bigint) => Number(formatEther(v));
  // Try the bundled stats() first (one call). If it fails on the RPC, fall back
  // to individual cheap getters so plvEth/plvToken/depth still populate.
  try {
    const s = await perpClient.readContract({ address: PERP_ENGINE, abi: STATS_ABI, functionName: "stats" }) as
      readonly [bigint, bigint, bigint, bigint, bigint, number, bigint, bigint, boolean];
    const v = { longOiEth: n(s[0]), shortOiEth: n(s[1]), plvEth: n(s[2]), plvToken: n(s[3]), depthEth: n(s[4]), maxLev: Number(s[5]), markSqrt: s[6], fundingIdx: Number(s[7]) / 1e18, dead: s[8] };
    statsCache = { at: Date.now(), v };
    return v;
  } catch { /* fall back to per-getter reads below */ }
  try {
    const rd = (fn: "plv" | "plvToken" | "longOiEth" | "activeEthDepth" | "maxLeverage" | "markSqrtPriceX96" | "fundingIndex") =>
      perpClient.readContract({ address: PERP_ENGINE, abi: ENGINE_READ, functionName: fn });
    const [plv, plvTok, longOi] = await Promise.all([rd("plv"), rd("plvToken"), rd("longOiEth")]) as [bigint, bigint, bigint];
    // heavy pool-math getters — each optional (keep the last good / sane default)
    const [depth, maxLev, mark, fidx] = await Promise.all([
      rd("activeEthDepth").catch(() => statsCache.v ? BigInt(Math.round(statsCache.v.depthEth * 1e18)) : 0n),
      rd("maxLeverage").catch(() => statsCache.v?.maxLev ?? 2),
      rd("markSqrtPriceX96").catch(() => statsCache.v?.markSqrt ?? 0n),
      rd("fundingIndex").catch(() => 0n),
    ]) as [bigint, number, bigint, bigint];
    const v = { longOiEth: n(longOi), shortOiEth: statsCache.v?.shortOiEth ?? 0, plvEth: n(plv), plvToken: n(plvTok), depthEth: n(depth), maxLev: Number(maxLev), markSqrt: mark, fundingIdx: Number(fidx) / 1e18, dead: false };
    statsCache = { at: Date.now(), v };
    return v;
  } catch { return statsCache.v; }
}

/* ── full BREW state, read SERVER-SIDE (cached) so the browser fetches the whole
      cauldron in ONE call — no browser RPC. The identity/price come from indexed
      tables; the handful of chain-only values (death floor, art cap, vault +
      reserve ETH, relaunch timer) are read via a cached multicall. ─────────── */
const REGISTRY = round.contracts.registry as `0x${string}`;
const HOOK = round.contracts.hook as `0x${string}`;
// MiFrensGenesis presale — server-side reads so the homepage hero shows the
// mint count + summon state WITHOUT the browser touching a flaky public RPC.
const PRESALE = round.contracts.presale as `0x${string}`;
const PRESALE_READ = [
  { type: "function", name: "minted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "soldOut", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "finalized", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "GENESIS_SUPPLY", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const REG_GENESIS = [
  { type: "function", name: "genesisSharePerFren", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisBonusBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisShares", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "TOTAL_SUPPLY", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "getCreatureForGeneration", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "string" }, { type: "string" }] },
  // v2 recycle-ratchet floor: DYNAMIC floor + the reserve backing it.
  { type: "function", name: "floorPerFren", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisReserveOutstanding", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "enchantFee", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
let presaleCache: { at: number; v: { minted: number; soldOut: boolean; finalized: boolean; supply: number; airdropPerFren: number; airdropTicker: string } | null } = { at: 0, v: null };
async function presaleState() {
  if (Date.now() - presaleCache.at < 4000 && presaleCache.v) return presaleCache.v;
  try {
    const [minted, soldOut, finalized, supply, sharePost, bonusBps, gShares, totalSupply, creature] = await Promise.all([
      perpClient.readContract({ address: PRESALE, abi: PRESALE_READ, functionName: "minted" }) as Promise<bigint>,
      perpClient.readContract({ address: PRESALE, abi: PRESALE_READ, functionName: "soldOut" }) as Promise<boolean>,
      perpClient.readContract({ address: PRESALE, abi: PRESALE_READ, functionName: "finalized" }) as Promise<boolean>,
      perpClient.readContract({ address: PRESALE, abi: PRESALE_READ, functionName: "GENESIS_SUPPLY" }) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: "genesisSharePerFren" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: "genesisBonusBps" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: "genesisShares" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: "TOTAL_SUPPLY" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: "getCreatureForGeneration", args: [1n] }).catch(() => ["", ""]) as Promise<[string, string]>,
    ]);
    // genesisSharePerFren is only set AT summon; pre-summon compute it from config:
    // pool = TOTAL_SUPPLY * bonusBps/1e4, per-fren = pool / genesisShares (1e18-scaled → whole tokens).
    let per = Number(sharePost) / 1e18;
    if (per === 0 && gShares > 0n) per = Number((totalSupply * bonusBps) / 10_000n / gShares) / 1e18;
    const v = { minted: Number(minted), soldOut, finalized, supply: Number(supply), airdropPerFren: Math.round(per), airdropTicker: creature?.[1] || "" };
    presaleCache = { at: Date.now(), v };
    return v;
  } catch { return presaleCache.v; }
}
const POOL_MGR = round.contracts.poolManager as `0x${string}`;
const POSITION_MGR = round.contracts.positionManager as `0x${string}`;
const REG_READ = [
  { type: "function", name: "generationVault", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "generationPositionId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "lastSummonAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "minLifetime", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const HOOK_READ = [
  { type: "function", name: "deathThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "relaunchETH", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const COL_READ = [
  { type: "function", name: "maxSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const EXTSLOAD = [{ type: "function", name: "extsload", stateMutability: "view", inputs: [{ type: "bytes32" }], outputs: [{ type: "bytes32" }] }] as const;
const POSLIQ = [{ type: "function", name: "getPositionLiquidity", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint128" }] }] as const;
// Progressive-seed reads. A streamed generation holds ledger-A liquidity in the
// seeder's own core positions, so it has no PositionManager position id.
const SEEDER_READ = [
  { type: "function", name: "ethTotal", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "seeding", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "primeBudget", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "primeSpent", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const REG_SEEDER = [
  { type: "function", name: "seeder", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;
// ETH held in the active LP position (currency0=ETH) — the amount recovered + re
// -seeded on relaunch, i.e. the real "available for next launch".
async function lpEthOf(poolId: `0x${string}`, gen: bigint): Promise<number> {
  try {
    const Q96 = 1n << 96n, SQRT_MAX = 1461446703485210103287273052203988822378723970342n;
    const slot = keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "uint256" }], [poolId, 6n]));
    const [raw, posId] = await Promise.all([
      perpClient.readContract({ address: POOL_MGR, abi: EXTSLOAD, functionName: "extsload", args: [slot] }) as Promise<`0x${string}`>,
      perpClient.readContract({ address: REGISTRY, abi: REG_READ, functionName: "generationPositionId", args: [gen] }) as Promise<bigint>,
    ]);
    const sqrtP = BigInt(raw) & ((1n << 160n) - 1n);
    if (sqrtP === 0n) return 0;

    //  ── THE TWO SOURCES ARE ADDITIVE, NOT ALTERNATIVES ──────────────────
    //  This used to `return` from the position branch, on the reasoning that a
    //  position id meant an ATOMIC launch and no seeder. The hybrid seed broke
    //  that: the registry now lays the BASE tranche as a PositionManager
    //  position AND hands the remainder to the seeder, so both exist at once.
    //  Returning early therefore reported only the base — about 15% of ledger A
    //  — and "available for next launch" read 0.09 against a pool holding 0.55.
    let quoteWei = 0n;

    // 1. The registry's own position (full range: the base, or ledger A whole on
    //    an atomic launch). amount0 is the QUOTE side by construction — the
    //    token is mined to sort above it — so the brew's own token is excluded,
    //    which is the only honest way to state liquidity.
    if (posId !== 0n) {
      const L = await perpClient.readContract({ address: POSITION_MGR, abi: POSLIQ, functionName: "getPositionLiquidity", args: [posId] }) as bigint;
      if (L > 0n) quoteWei += (L * Q96 * (SQRT_MAX - sqrtP)) / (sqrtP * SQRT_MAX);
    }

    // 2. The seeder's streamed bands. It holds these as CORE positions, which
    //    carry no PositionManager id, so they are invisible to the read above.
    const seeder = await perpClient.readContract({ address: REGISTRY, abi: REG_SEEDER, functionName: "seeder" }) as `0x${string}`;
    if (!seeder || seeder === "0x0000000000000000000000000000000000000000") {
      return Number(formatEther(quoteWei));
    }
    // ethTotal is the exact ETH the seeder was funded with at start — the
    // contract enforces `msg.value == cfg.ethTotal` — and the seeder holds no
    // ETH of its own once streaming has run, so this is the ETH now sitting in
    // its pool positions. Teardown's withdrawAll recovers those positions, so it
    // is also what the next launch has to work with.
    //
    // Conservative by construction: net buy inflow since launch also sits in the
    // pool and is recovered, so the real figure is this or higher. Streaming
    // progress does not change it — unplaced budget is still held by the seeder
    // and recovered the same way.
    //  Only counts while a campaign is live: `withdrawAll` clears `seeding` and
    //  returns everything to the registry, and `ethTotal` keeps its last value —
    //  so counting it unconditionally would double-report a dead generation's
    //  liquidity against the new one.
    const seeding = await perpClient.readContract({
      address: seeder, abi: SEEDER_READ, functionName: "seeding",
    }).catch(() => false) as boolean;
    if (seeding) {
      const ethTotalWei = await perpClient.readContract({
        address: seeder, abi: SEEDER_READ, functionName: "ethTotal",
      }) as bigint;
      quoteWei += ethTotalWei;
    }
    return Number(formatEther(quoteWei));
  } catch (e) { console.error("lpEthOf failed:", String(e).slice(0,200)); return 0; }
}
type BrewChain = { deathThresholdEth: number; relaunchEth: number; nftMax: number; vaultEth: number; relaunchAt: number };
let brewCache: { at: number; gen: number; v: BrewChain | null } = { at: 0, gen: -1, v: null };
async function brewChain(gen: number, collectionAddr: `0x${string}`, poolId: `0x${string}`): Promise<BrewChain | null> {
  if (Date.now() - brewCache.at < 10_000 && brewCache.v && brewCache.gen === gen) return brewCache.v;
  try {
    const g = BigInt(gen);
    const [vault, lastSummonAt, minLifetime, deathThr, relaunchWei, maxSupply, lpEth] = await Promise.all([
      perpClient.readContract({ address: REGISTRY, abi: REG_READ, functionName: "generationVault", args: [g] }) as Promise<`0x${string}`>,
      perpClient.readContract({ address: REGISTRY, abi: REG_READ, functionName: "lastSummonAt" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_READ, functionName: "minLifetime" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: HOOK, abi: HOOK_READ, functionName: "deathThreshold" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: HOOK, abi: HOOK_READ, functionName: "relaunchETH" }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: collectionAddr, abi: COL_READ, functionName: "maxSupply" }).catch(() => 0n) as Promise<bigint>,
      lpEthOf(poolId, g), // ETH in the active LP → the real "available for next launch"
    ]);
    const vaultBal = vault && vault !== "0x0000000000000000000000000000000000000000"
      ? await perpClient.getBalance({ address: vault }).catch(() => 0n) : 0n;
    const v: BrewChain = {
      deathThresholdEth: Number(formatEther(deathThr)),
      // available for next launch = LP ETH (recovered on relaunch) + hook reserve.
      relaunchEth: lpEth + Number(formatEther(relaunchWei)),
      nftMax: Number(maxSupply),
      vaultEth: Number(formatEther(vaultBal)),
      relaunchAt: Number(lastSummonAt + minLifetime),
    };
    brewCache = { at: Date.now(), gen, v };
    return v;
  } catch { return brewCache.v; }
}

// The whole live brew state in ONE call → the browser never touches RPC.
// Genesis presale state (minted / soldOut / finalized) — read SERVER-SIDE so the
// homepage hero never depends on the browser's flaky public Sepolia RPC.
app.get("/presale", async (c) => c.json((await presaleState()) ?? { minted: 0, soldOut: false, finalized: false, supply: 0 }));

/* ── TREASURY COMPOSITION — what the LP is denominated in, and what the guild
      actually holds across every allowed quote.

      SERVER-SIDE, like everything else here. The first cut of this read the
      balances from the BROWSER, one `balanceOf` per quote per holder plus an
      oracle call each, polling every 30s per open tab. That is the pattern this
      file exists to avoid: it multiplies by viewers, it hits the same public
      nodes the Ponder sync is already using, and it earns a 429 exactly when the
      app is busiest. One cached server-side read serves every viewer instead.
      ───────────────────────────────────────────────────────────────────────── */
const ROTATOR = (round.contracts as Record<string, string>).quoteRotator as `0x${string}` | undefined;
const QUOTES = (round.quoteAssets ?? []) as { address: string; symbol: string; decimals: number }[];
/** The treasury governor — what the LP is denominated in. Distinct from the
 *  BREW governor at `round.contracts.governor`. */
const TREASURY_GOV = ((round.contracts as Record<string, string>).treasuryGovernor ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;
const TGOV_READ = [
  { type: "function", name: "VOTING_PERIOD", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "EXECUTION_WINDOW", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "COOLDOWN", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "ENVELOPE_LIFETIME", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  //  THE CONTRACT'S OWN ANSWER for which proposal `execute` would accept. It
  //  applies `_passed` (for > against AND a 10%-of-past-supply quorum) and the
  //  execution window, then `execute` additionally demands `id == winner()`.
  //  Re-deriving that off-chain would drift; asking costs one call.
  { type: "function", name: "winner", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
/**
 * Decimals for a quote address, defaulting to 18.
 *
 * 18 is right for native ETH and for every ERC20 that does not say otherwise,
 * and wrong by a factor of 10^12 for USDG — which is precisely why an UNKNOWN
 * address must not silently take it. An address missing from the manifest is a
 * deployment/manifest mismatch, so it is logged rather than quietly rendered as
 * a number a trillion times too small.
 */
function decimalsOf(addr: string): number {
  const a = addr.toLowerCase();
  const hit = QUOTES.find((q) => q.address.toLowerCase() === a);
  if (!hit) {
    console.error(`decimalsOf: ${addr} is not in round.json quoteAssets — assuming 18`);
    return 18;
  }
  return hit.decimals;
}
const ERC20_BAL = [{
  type: "function", name: "balanceOf", stateMutability: "view",
  inputs: [{ type: "address" }], outputs: [{ type: "uint256" }],
}] as const;
const ORACLE_READ = [{
  type: "function", name: "usdPerRawUnit", stateMutability: "view",
  inputs: [{ type: "address" }], outputs: [{ type: "uint256" }],
}] as const;
const ROTATOR_READ = [{
  type: "function", name: "quoteOracle", stateMutability: "view",
  inputs: [], outputs: [{ type: "address" }],
}] as const;
const REG_QUOTE = [{
  type: "function", name: "generationQuote", stateMutability: "view",
  inputs: [{ type: "uint256" }], outputs: [{ type: "address" }],
}] as const;
const REG_LP = [
  { type: "function", name: "generationPositionId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "generationPoolKey", stateMutability: "view", inputs: [{ type: "uint256" }],
    outputs: [{ type: "address" }, { type: "address" }, { type: "uint24" }, { type: "int24" }, { type: "address" }] },
  //  THE ROTATION LEGS. `generationPositionId` is the PRIMARY position only, so
  //  everything a rotation opens is invisible to it — and a rotation is exactly
  //  when this panel matters. Confirmed live on Sepolia: after one 25% slice,
  //  legCount(1) = 1 and a USDG position (39263) held 182.24 USDG that the
  //  treasury view could not see, so the panel still read "100% ETH".
  { type: "function", name: "legCount", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "legAt", stateMutability: "view",
    inputs: [{ type: "uint256" }, { type: "uint256" }],
    outputs: [{ type: "address" }, { type: "uint256" },
      { type: "tuple", components: [
        { name: "currency0", type: "address" }, { name: "currency1", type: "address" },
        { name: "fee", type: "uint24" }, { name: "tickSpacing", type: "int24" },
        { name: "hooks", type: "address" },
      ] }] },
] as const;
const POSM = round.contracts.positionManager as `0x${string}`;
const POSM_READ = [{
  type: "function", name: "getPositionLiquidity", stateMutability: "view",
  inputs: [{ type: "uint256" }], outputs: [{ type: "uint128" }],
}] as const;
const NATIVE = "0x0000000000000000000000000000000000000000";
//  Deploy-time config the hook does not expose publicly (both fields are
//  `internal`). Sourced from the manifest so it travels with the deployment
//  rather than being guessed, and defaulted to the contract's own initialiser.
const LEGACY_THRESHOLD_ETH = Number((round as Record<string, unknown>).legacyThresholdEth ?? 0.02);
const LEGACY_BPS = Number((round as Record<string, unknown>).legacyBps ?? 4000);

let treasuryCache: { at: number; v: unknown } = { at: 0, v: null };
app.get("/treasury", async (c) => {
  // 30s: balances move with trading, and nothing downstream is second-sensitive.
  if (Date.now() - treasuryCache.at < 30_000 && treasuryCache.v) return c.json(treasuryCache.v);

  // The live generation, from the indexed table rather than a chain read.
  const genRows = await db.select().from(schema.pool).orderBy(desc(schema.pool.generation)).limit(1);
  const gen = genRows[0]?.generation ?? 0;

  const basis = gen
    ? await perpClient.readContract({
        address: REGISTRY, abi: REG_QUOTE, functionName: "generationQuote", args: [BigInt(gen)],
      }).catch(() => NATIVE) as string
    : NATIVE;

  // The oracle handle is public on the rotator; `CauldronHook.quoteOracle` is
  // internal and the hook has no bytecode budget for a getter.
  const oracle = ROTATOR
    ? await perpClient.readContract({ address: ROTATOR, abi: ROTATOR_READ, functionName: "quoteOracle" })
        .catch(() => null) as string | null
    : null;

  //  ── MEASURE THE LP POSITIONS, NOT IDLE BALANCES ─────────────────────────
  //  The first cut of this measured `balanceOf(registry)` per quote, which is
  //  the wrong question. `RedemptionExt.rotateSlice` removes a slice, swaps it
  //  and REDEPLOYS it as liquidity in ONE transaction (:243-266) — so a working
  //  treasury holds essentially nothing idle, and a balance-based panel would
  //  read ~0 forever while the guild's actual position sat in the pools.
  //
  //  What a generation is worth is therefore its LIVE POSITIONS. A generation
  //  can run several pairs at once: rotation is sliced (MAX_SLICE_BPS = 5% per
  //  call), so mid-rotation the LP is genuinely split between the old quote and
  //  the new one, and `linkVolume` ties the siblings together. That split IS the
  //  composition this panel exists to show.
  //
  //  Idle balances are still reported, separately and additively, because value
  //  DOES rest there between a rebirth's recovery and its reseed.
  //  EVERY POOL THE GENERATION HOLDS, not just the one it was born with.
  //  `generationPositionId` is the PRIMARY position; a rotation opens a new
  //  position against the destination quote and records it as a LEG. Reading
  //  only the primary meant the panel reported "100% ETH" immediately after a
  //  rotation had moved part of the treasury into USDG — it showed the asset the
  //  guild was leaving and omitted the one it was moving to, which is precisely
  //  backwards for a screen whose subject is the split.
  const valuePosition = async (
    g: number, posId: bigint, key: readonly [string, string, number, number, string], isPrimary: boolean,
  ) => {
    if (!posId) return null;
    const liq = await perpClient.readContract({
      address: POSM, abi: POSM_READ, functionName: "getPositionLiquidity", args: [posId],
    }).catch(() => 0n) as bigint;

    //  ── VALUE THE POSITION, DO NOT JUST COUNT ITS L UNITS ────────────────
    //  Everything above this line was already right, and then the USD below was
    //  computed from the IDLE balance alone — so a treasury whose entire point
    //  is that it holds nothing idle reported its own worth as the dust left
    //  over. Measured live: raw = 321 wei against a position of 2.787e21 L, and
    //  the panel printed "<$0.01 in pool".
    //
    //  L is not a value. Converting it needs the pool's current price and the
    //  position's range; these positions are FULL RANGE (PoolOps._seedActive
    //  spans MIN_TICK..MAX_TICK), which collapses the general formula to
    //      amount0 = L * 2^96 * (sqrtMax - sqrtP) / (sqrtP * sqrtMax)
    //  and amount0 IS the quote side, because the iteration token is mined to
    //  sort above the quote. So this counts what BACKS the pool and excludes the
    //  brew's own token, which is the only honest way to state it — the token
    //  side is a claim on this same liquidity, not additional backing.
    //
    //  Raw units, not ether: the quote may be 6-decimal USDG. `lpEthOf` does the
    //  same arithmetic but formatEther's it, which is correct for its native-only
    //  caller and would be off by 10^12 here.
    //  A MALFORMED KEY MUST NOT 500 THE WHOLE PANEL. `encodeAbiParameters`
    //  throws on a bad address, and this route serves several positions — one
    //  unreadable leg should cost that leg, not the entire treasury view.
    let poolId: `0x${string}`;
    try {
      poolId = keccak256(encodeAbiParameters(
        [{ type: "address" }, { type: "address" }, { type: "uint24" }, { type: "int24" }, { type: "address" }],
        [key[0] as `0x${string}`, key[1] as `0x${string}`, key[2], key[3], key[4] as `0x${string}`],
      ));
    } catch (e) {
      console.error(`treasury: bad pool key for gen ${g} pos ${posId}: ${String(e).slice(0, 120)}`);
      return null;
    }
    let lpRaw = 0n;
    if (liq > 0n) {
      const slot = keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "uint256" }], [poolId, 6n]));
      const rawSlot = await perpClient.readContract({
        address: POOL_MGR, abi: EXTSLOAD, functionName: "extsload", args: [slot],
      }).catch(() => null) as `0x${string}` | null;
      const sqrtP = rawSlot ? BigInt(rawSlot) & ((1n << 160n) - 1n) : 0n;
      //  sqrtP == 0 means the pool did not answer. Leave the LP side at 0 and
      //  let `partial` surface it, rather than valuing a position at a price we
      //  do not have.
      if (sqrtP > 0n) {
        const Q96 = 1n << 96n;
        const SQRT_MAX = 1461446703485210103287273052203988822378723970342n;
        lpRaw = (liq * Q96 * (SQRT_MAX - sqrtP)) / (sqrtP * SQRT_MAX);
      }
    }
    // currency0 is the quote in every Cauldron pair the registry opens; the
    // token is currency1 (PoolOps mines the token to sort ABOVE the quote).
    return {
      generation: g, positionId: posId.toString(), quote: key[0],
      liquidity: liq.toString(), lpRaw: lpRaw.toString(), isPrimary,
    };
  };

  const positions = (await Promise.all(genRows.map(async (row) => {
    const g = row.generation;
    const [posId, key] = await Promise.all([
      perpClient.readContract({ address: REGISTRY, abi: REG_LP, functionName: "generationPositionId", args: [BigInt(g)] }).catch(() => 0n) as Promise<bigint>,
      perpClient.readContract({ address: REGISTRY, abi: REG_LP, functionName: "generationPoolKey", args: [BigInt(g)] }).catch(() => null) as Promise<readonly [string, string, number, number, string] | null>,
    ]);
    const out = key ? [await valuePosition(g, posId, key, true)] : [];

    //  A deployment predating leg tracking simply reverts `legCount`, which is
    //  caught here and reported as "primary only" — the truth for such a
    //  deployment, and not something to fabricate legs for.
    const n = await perpClient.readContract({
      address: REGISTRY, abi: REG_LP, functionName: "legCount", args: [BigInt(g)],
    }).catch(() => 0n) as bigint;
    for (let i = 0n; i < n; i++) {
      const leg = await perpClient.readContract({
        address: REGISTRY, abi: REG_LP, functionName: "legAt", args: [BigInt(g), i],
      }).catch(() => null) as readonly [string, bigint, unknown] | null;
      if (!leg) continue;
      const [, legPosId, rawKey] = leg;
      //  NORMALISE THE POOL KEY. `legAt`'s third output is a NAMED tuple, so
      //  viem decodes it to an OBJECT — while `generationPoolKey` declares five
      //  flat outputs and decodes to an ARRAY. Indexing the object positionally
      //  yielded `undefined` for every field, which surfaced as
      //  `InvalidAddressError: Address "undefined"` and took the WHOLE /treasury
      //  route down with a 500, not just the legs. The panel then reported "no
      //  live positions" for a treasury holding two.
      const k = rawKey as Record<string, unknown> & ArrayLike<unknown>;
      const legKey = (Array.isArray(rawKey)
        ? rawKey
        : [k.currency0, k.currency1, k.fee, k.tickSpacing, k.hooks]
      ) as readonly [string, string, number, number, string];
      if (!legKey[0] || !legKey[1]) continue;
      out.push(await valuePosition(g, legPosId, legKey, false));
    }
    return out;
  }))).flat();

  // Idle balances on the REGISTRY — what a rebirth recovered but has not yet
  // reseeded, plus anything a rotation left behind.
  const holdings = await Promise.all(QUOTES.map(async (q) => {
    const raw = q.address === NATIVE
      ? await perpClient.getBalance({ address: REGISTRY }).catch(() => 0n)
      : await perpClient.readContract({
          address: q.address as `0x${string}`, abi: ERC20_BAL,
          functionName: "balanceOf", args: [REGISTRY],
        }).catch(() => 0n) as bigint;

    // Liquidity this quote currently backs, summed across the generation's live
    // positions, with the quote-side amount those L units represent.
    const mine = positions.filter((p) => p && p.quote.toLowerCase() === q.address.toLowerCase());
    const liq = mine.reduce((a, p) => a + BigInt(p!.liquidity), 0n);
    const lpRaw = mine.reduce((a, p) => a + BigInt(p!.lpRaw), 0n);

    //  THE ASSET'S VALUE IS IDLE + DEPLOYED. Pricing `raw` alone answered "what
    //  has this treasury failed to put to work", which is ~0 for a healthy one
    //  by design — and then presented that as the treasury's size.
    const totalRaw = raw + lpRaw;

    // 0 from the oracle means CANNOT JUDGE, never "worthless" — it stays null so
    // the UI omits the asset from the split instead of drawing it at zero.
    let usd: number | null = null;
    if (oracle && oracle !== NATIVE) {
      const f = await perpClient.readContract({
        address: oracle as `0x${string}`, abi: ORACLE_READ,
        functionName: "usdPerRawUnit", args: [q.address as `0x${string}`],
      }).catch(() => 0n) as bigint;
      if (f > 0n) usd = (Number(totalRaw) * Number(f)) / 1e18 / 1e18;
    }

    return {
      address: q.address,
      raw: raw.toString(),                     // string: JSON has no bigint
      amount: Number(raw) / 10 ** q.decimals,  // IDLE only, as the name says
      //  The deployed side, reported separately so the UI can distinguish "in
      //  the pool" from "sitting in the registry" — they mean different things
      //  about the treasury's health, and summing them silently would hide a
      //  failed reseed.
      lpRaw: lpRaw.toString(),
      lpAmount: Number(lpRaw) / 10 ** q.decimals,
      totalAmount: Number(totalRaw) / 10 ** q.decimals,
      usd,
      liquidity: liq.toString(),
      isBasis: q.address.toLowerCase() === (basis ?? NATIVE).toLowerCase(),
    };
  }));

  const totalUsd = holdings.reduce((a, h) => a + (h.usd ?? 0), 0);
  const v = {
    generation: gen,
    basis: basis ?? NATIVE,
    oracle,
    positions: positions.filter(Boolean),
    holdings: holdings.map((h) => ({
      ...h,
      share: h.usd !== null && totalUsd > 0 ? h.usd / totalUsd : null,
    })),
    totalUsd,
    //  An asset is "held" if it is idle OR deployed — the LP side was missing
    //  here too, so an unpriceable quote that lived entirely in a pool was
    //  omitted from the split WITHOUT the warning that says so.
    partial: holdings.some((h) => h.usd === null && (h.raw !== "0" || h.lpRaw !== "0")),
  };
  treasuryCache = { at: Date.now(), v };
  return c.json(v);
});

// GENESIS REDEMPTION FLOOR (v2, ratcheting) — the RISING stat. floorPerFren is
// DYNAMIC (reserve / genesisShares) and only goes up as buybacks + re-enchant fees
// grow the reserve. We surface the token floor, its ETH value, the % of the live
// token's FDV each fren now backs, and the enchant fee. Reads live (cached 4s).
let floorCache: { at: number; v: unknown } = { at: 0, v: null };
app.get("/floor", async (c) => {
  if (Date.now() - floorCache.at < 4000 && floorCache.v) return c.json(floorCache.v);
  const ps = await presaleState();
  const mark = await markPriceEth(); // ETH per token at the TWAP mark
  //  A READ THAT FAILED AND A READ THAT RETURNED ZERO ARE DIFFERENT FACTS.
  //  The browser now treats this route as its PRIMARY source for the redemption
  //  floor, so a swallowed revert here would render as a confident "0 tokens per
  //  fren" in the genesis panel. Failures are still soft (the route keeps
  //  answering) but they are NAMED in `failedReads`, and the client refuses to
  //  believe a floor whose read is listed there.
  const failedReads: string[] = [];
  const rd = async (fn: string) =>
    (await perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: fn as never })
      .catch(() => { failedReads.push(fn); return 0n; })) as bigint;
  const [floorWei, reserveWei, feeWei, totalSupplyWei] = await Promise.all([
    rd("floorPerFren"), rd("genesisReserveOutstanding"), rd("enchantFee"), rd("TOTAL_SUPPLY"),
  ]);
  const floorPerFren = Number(floorWei) / 1e18;          // tokens redeemable per fren NOW
  const totalSupply = Number(totalSupplyWei) / 1e18;
  const redeemFloorEth = mark != null ? floorPerFren * mark : null;
  // What % of the token's FULL marketcap each fren now backs (floor / totalSupply).
  const floorPctOfMcap = totalSupply > 0 ? (floorPerFren / totalSupply) * 100 : 0;
  const v = {
    floorPerFren,                                        // tokens per fren (DYNAMIC, ratchets up)
    sharePerFren: floorPerFren,                          // back-compat alias
    reserveTokens: Number(reserveWei) / 1e18,            // the reserve backing the floor
    enchantFeeTokens: Number(feeWei) / 1e18,             // cost to re-enchant a moved fren
    markPriceEth: mark,                                  // ETH per token (live mark)
    redeemFloorEth,                                      // floor × mark = fren's live ETH value
    floorPctOfMcap,                                      // % of FDV each fren backs (rises)
    ticker: ps?.airdropTicker ?? "",
    //  WEI, AS A STRING. `floorPerFren` above is a float in whole tokens, which
    //  loses the low digits of a 1e18 value — fine for a chart label, wrong for
    //  the "recycle N frens for X $TOKEN" figure, which is share × count. The
    //  browser multiplies the exact integer instead of a rounded float.
    floorPerFrenWei: floorWei.toString(),
    reserveWei: reserveWei.toString(),
    enchantFeeWei: feeWei.toString(),
    //  Empty unless a chain read actually failed (see `rd` above). A client that
    //  sees a name here knows the matching number is not live data.
    failedReads,
  };
  floorCache = { at: Date.now(), v };
  return c.json(v);
});

// COLLECTION LEGACY FLOORS (r28) — the live collection's building floor (buyback
// pending + buffer progress) + each past (dead) collection's redeemable per-NFT
// floor, read server-side from the CollectionLedger. Cached 5s.
// Manifest-only (NO env fallback): a stale Railway COLLECTION_LEDGER once pinned
// this to a dead ledger → the legacy floor read 0 $GNOME even after a real buyback.
const LEDGER_ADDR = round.contracts.collectionLedger as `0x${string}`;
// Unified CollectionLedger ABI (live+dead): floorPerNFT/outstanding take the live
// mint count (ignored once crystallized). entitledTokens = the collection's banked
// pot. No `pending` (live buyback credits entitledTokens directly).
const LEDGER_READ = [
  { type: "function", name: "floorPerNFT", stateMutability: "view", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "outstanding", stateMutability: "view", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "entitledTokens", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "crystallized", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "totalEntitled", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const COL_MINTED = [{ type: "function", name: "totalMinted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] }] as const;
//  ONLY `legacyBuffer()` EXISTS. Verified against contracts/solidity/out:
//  CauldronHook implements legacyBuffer() (0xb5b67321) but NOT legacyThreshold()
//  or legacyBps() — the threshold and the split are internal, written once by
//  `setLegacyBuyback(address,uint256,uint256)`. Declaring getters for them meant
//  two reads that always reverted, and the blanket `.catch(() => 0n)` below
//  turned each revert into a confident `0`: the panel showed a 0 ETH threshold
//  and 0% progress while ETH was visibly piling up in the buffer.
const HOOK_LEGACY = [
  { type: "function", name: "legacyBuffer", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;
const REG_CURGEN = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "currentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "generationCollection", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
] as const;
const SYMBOL_ABI = [{ type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] }] as const;
let colFloorCache: { at: number; v: unknown } = { at: 0, v: null };
app.get("/collection-floors", async (c) => {
  if (Date.now() - colFloorCache.at < 5000 && colFloorCache.v) return c.json(colFloorCache.v);
  try {
    //  A read that FAILED and a read that returned zero are different facts.
    //  Collapsing them with `.catch(() => 0n)` is what hid the two dead legacy
    //  getters for a whole release, so a failure is still soft (the route keeps
    //  answering) but it is now NAMED, and the response says so.
    const failedReads: string[] = [];
    const rd = async (a: `0x${string}`, abi: readonly unknown[], fn: string, args: unknown[] = []) =>
      (await perpClient
        .readContract({ address: a, abi: abi as never, functionName: fn as never, args: args as never })
        .catch(() => { failedReads.push(fn); return 0n; })) as bigint;
    const curGen = Number(await rd(REGISTRY, REG_CURGEN, "currentGeneration"));
    // live token symbol (for "N $GNOME" labels) — read server-side so the browser
    // stays RPC-free (the reason the panel's own reads were flaky → 0% shown).
    const curToken = curGen > 0
      ? await perpClient.readContract({ address: REGISTRY, abi: REG_CURGEN, functionName: "currentToken" }).catch(() => ZERO) as `0x${string}`
      : ZERO as `0x${string}`;
    const ticker = curToken && curToken !== ZERO
      ? await perpClient.readContract({ address: curToken, abi: SYMBOL_ABI, functionName: "symbol" }).catch(() => "") as string
      : "";
    const [buffer, liveEntitled] = await Promise.all([
      rd(HOOK, HOOK_LEGACY, "legacyBuffer"),
      curGen > 0 ? rd(LEDGER_ADDR, LEDGER_READ, "entitledTokens", [BigInt(curGen)]) : Promise.resolve(0n),
    ]);
    // LIVE collection is now redeemable (post-unify): read its per-NFT floor at the
    // live mint count so the panel can show "redeem a creature for N $TOKEN now".
    let liveFloorPerNFT = 0, liveOutstanding = 0;
    if (curGen > 0) {
      const col = await perpClient.readContract({ address: REGISTRY, abi: REG_CURGEN, functionName: "generationCollection", args: [BigInt(curGen)] }).catch(() => ZERO) as `0x${string}`;
      if (col && col !== ZERO) {
        const minted = await rd(col, COL_MINTED, "totalMinted");
        const [flr, out] = await Promise.all([
          rd(LEDGER_ADDR, LEDGER_READ, "floorPerNFT", [BigInt(curGen), minted]),
          rd(LEDGER_ADDR, LEDGER_READ, "outstanding", [BigInt(curGen), minted]),
        ]);
        liveFloorPerNFT = Number(flr) / 1e18;
        liveOutstanding = Number(out);
      }
    }
    const past: Array<{ gen: number; floorPerNFT: number; outstanding: number }> = [];
    for (let g = 1; g < curGen; g++) {
      const cry = await perpClient.readContract({ address: LEDGER_ADDR, abi: LEDGER_READ, functionName: "crystallized", args: [BigInt(g)] }).catch(() => false) as boolean;
      if (!cry) continue;
      // crystallized → mintedNow ignored (uses frozen supply); pass 0.
      const [flr, out] = await Promise.all([
        rd(LEDGER_ADDR, LEDGER_READ, "floorPerNFT", [BigInt(g), 0n]),
        rd(LEDGER_ADDR, LEDGER_READ, "outstanding", [BigInt(g), 0n]),
      ]);
      past.push({ gen: g, floorPerNFT: Number(flr) / 1e18, outstanding: Number(out) });
    }
    const v = {
      currentGen: curGen,
      ticker,
      // total banked for the live collection (was `livePending` pre-unify; now the
      // live entitledTokens). Key kept for frontend compatibility.
      livePending: Number(liveEntitled) / 1e18,
      liveFloorPerNFT,   // token redeemable per LIVE creature NFT right now
      liveOutstanding,   // entitled (redeemable) live NFTs
      bufferEth: Number(buffer) / 1e18,
      //  DEPLOY-TIME CONFIGURATION, FROM THE MANIFEST — not from the chain.
      //  The hook exposes no getter for either (see HOOK_LEGACY above), so there
      //  is nothing to prefer a chain read to; pretending otherwise is what
      //  produced a confident 0. `thresholdSource` says where the number came
      //  from so a consumer never has to guess whether it is live.
      thresholdEth: LEGACY_THRESHOLD_ETH,
      legacyBps: LEGACY_BPS,
      thresholdSource: "manifest" as const,
      bufferPct: LEGACY_THRESHOLD_ETH > 0
        ? Math.min(100, (Number(buffer) / 1e18 / LEGACY_THRESHOLD_ETH) * 100)
        : 0,
      past,
      //  Empty unless a chain read actually failed. A caller that sees a 0 here
      //  knows it is a real 0; a caller that sees a name knows it is not.
      failedReads,
    };
    colFloorCache = { at: Date.now(), v };
    return c.json(v);
  } catch { return c.json(colFloorCache.v ?? { currentGen: 0, past: [] }); }
});

app.get("/cauldron", async (c) => {
  // Latest generation from the indexed pools (the live brew).
  const pools = await db.select().from(schema.pool).orderBy(desc(schema.pool.generation)).limit(1);
  const p = pools[0];
  if (!p) {
    const ps = await presaleState();
    // presaleMinted at the TOP level too (useCauldronMachine reads it there) +
    // nested `presale` for the richer hero. Both from the server-side read.
    return c.json({ summoned: false, gen: 0, presale: ps, presaleMinted: ps?.minted ?? 0, presaleSoldOut: ps?.soldOut ?? false, presaleFinalized: ps?.finalized ?? false });
  }
  const gen = p.generation;

  // NFT collection for this gen (volume-mint art).
  const cols = await db.select().from(schema.collection).where(eq(schema.collection.generation, gen)).limit(1);
  const col = cols[0];

  // 24h volume from indexed swaps.
  const since = BigInt(Math.floor(Date.now() / 1000) - 86400);
  const recent = await db.select().from(schema.swap)
    .where(and(eq(schema.swap.generation, gen), gte(schema.swap.timestamp, since)));
  const vol24hEth = recent.reduce((s, r) => s + r.amountEth, 0);

  const chain = col ? await brewChain(gen, col.id as `0x${string}`, p.id as `0x${string}`) : null;
  const deathEth = chain?.deathThresholdEth ?? 0;
  const phase = p.dead ? "dead" : (deathEth > 0 && vol24hEth < deathEth ? "dying" : "live");

  return c.json({
    summoned: true,
    gen,
    token: p.token,
    collection: col?.id ?? null,
    poolId: p.id,
    name: p.name,
    ticker: p.symbol,
    dead: p.dead,
    phase,
    spotPrice: p.lastPrice,
    volumeEth: p.volumeEth,
    vol24hEth,
    nftMinted: col?.totalMinted ?? 0,
    nftMax: chain?.nftMax ?? 0,
    deathThresholdEth: deathEth,
    vaultEth: chain?.vaultEth ?? 0,
    relaunchEth: chain?.relaunchEth ?? 0,
    relaunchAt: chain?.relaunchAt ?? 0,
  });
});

/* ── charting ──────────────────────────────────────────────────────────── */
app.get("/candles/:generation", async (c) => {
  const gen = Number(c.req.param("generation"));
  const limit = Math.min(Number(c.req.query("limit") ?? 120), 500);
  const pools = await db.select().from(schema.pool).where(eq(schema.pool.generation, gen)).limit(1);
  const p = pools[0];
  if (!p) return c.json({ pool: null, candles: [], last: 0 });
  const rows = await db.select().from(schema.candle).where(eq(schema.candle.poolId, p.id)).orderBy(desc(schema.candle.bucketStart)).limit(limit);
  const candles = rows.reverse().map((r) => ({ t: r.bucketStart, o: r.open, h: r.high, l: r.low, c: r.close, v: r.volumeEth }));
  return c.json({ pool: { id: p.id, generation: p.generation, token: p.token, name: p.name, symbol: p.symbol, dead: p.dead }, candles, last: p.lastPrice, volumeEth: p.volumeEth, swapCount: p.swapCount });
});
app.get("/recent/:generation", async (c) => {
  const gen = Number(c.req.param("generation"));
  const limit = Math.min(Number(c.req.query("limit") ?? 150), 5000);
  const pools = await db.select().from(schema.pool).where(eq(schema.pool.generation, gen)).limit(1);
  const p = pools[0];
  if (!p) return c.json({ swaps: [] });
  // Order by strict EXECUTION order (block*1e6+logIndex), NOT timestamp — many
  // swaps share a block (liquidation buy-backs), and timestamp ties scramble the
  // tick chart's close. Newest first for the tape; the frontend reverses.
  const rows = await db.select().from(schema.swap).where(eq(schema.swap.poolId, p.id)).orderBy(desc(schema.swap.orderKey)).limit(limit);
  // `o` = execution order key. The client MUST sort by this (not timestamp) —
  // same-block swaps share `t`, so a t-sort scrambles the liquidation buy-backs.
  //  `s` (the swap's sender) is what lets the feed tell a CRYSTAL SPIN from an
  //  organic trade: a spin is routed through CauldronGachaRouter, so the router
  //  is the sender on-chain. Without it every roll rendered as its own
  //  "Bought $TOKEN" line and buried real trades under them.
  return c.json({
    gachaRouter: (round.contracts as Record<string, string>).gachaRouter ?? null,
    legacyBps: LEGACY_BPS,
    swaps: rows.map((r) => ({
      price: r.price, amountEth: r.amountEth, isBuy: r.isBuy,
      t: Number(r.timestamp), o: Number(r.orderKey), tx: r.txHash, s: r.sender,
    })),
  });
});

/* ── perps: liquidation heatmap + a trader's positions ─────────────────── */
// The POST-OPEN spot = the open's own swap price (looked up by openTx), so PnL
// counts only moves AFTER your impact (no self-impact paper profit). Falls back
// to the stored avg-execution entry if the swap isn't found.
const PERP_M = Number(process.env.PERP_MAINTENANCE_BPS ?? 1500) / 1e4;
async function postOpenEntry(openTx: string | null, storedEntry: number): Promise<number> {
  if (!openTx) return storedEntry;
  try {
    const rows = await db.select().from(schema.swap).where(eq(schema.swap.txHash, openTx as `0x${string}`)).limit(1);
    const px = rows[0]?.price;
    return px && px > 0 ? px : storedEntry;
  } catch { return storedEntry; }
}
function liqFrom(entry: number, lev: number, isLong: boolean): number {
  if (lev <= 0) return entry;
  return isLong ? (entry * (lev - 1) * (1 + PERP_M)) / lev : (entry * (lev + 1) * (1 - PERP_M)) / lev;
}

// EXACT liquidation price (ETH per token) — mirrors the contract's _underwater()
// using the position's REAL fields (collateral/principal/size) + live maintenance,
// so the heatmap wall sits precisely where the position actually liquidates (the
// simplified entry-based liqFrom drifts a few % on thin pools). Derivation:
//   markValue = size × P  (P = eth per token; _quoteMark is linear in P)
//   SHORT liq: markValue > backing×(1−m)  → P > backing×(1−m)/size
//   LONG  liq: markValue < principal×(1+m) → P < principal×(1+m)/size
const POS_READ = [
  { type: "function", name: "positions", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [
    { name: "trader", type: "address" }, { name: "isLong", type: "bool" }, { name: "collateral", type: "uint128" },
    { name: "size", type: "uint256" }, { name: "principal", type: "uint256" }, { name: "openedAt", type: "uint64" },
    { name: "leverage", type: "uint8" }, { name: "entryFunding", type: "int256" },
  ] },
  { type: "function", name: "maintenanceBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
let maintCache = { at: 0, bps: 1500 };
async function maintenanceM(): Promise<number> {
  if (Date.now() - maintCache.at < 30_000) return maintCache.bps / 1e4;
  try {
    const b = await perpClient.readContract({ address: PERP_ENGINE, abi: POS_READ, functionName: "maintenanceBps" }) as bigint;
    maintCache = { at: Date.now(), bps: Number(b) };
  } catch { /* keep last */ }
  return maintCache.bps / 1e4;
}
const liqCache = new Map<string, { at: number; v: number }>();
async function exactLiqPrice(id: bigint, entryFallback: number, lev: number, isLong: boolean): Promise<number> {
  const key = `${id}`;
  const c = liqCache.get(key);
  if (c && Date.now() - c.at < 8_000) return c.v;
  try {
    const [p, m] = await Promise.all([
      perpClient.readContract({ address: PERP_ENGINE, abi: POS_READ, functionName: "positions", args: [id] }) as Promise<readonly [string, boolean, bigint, bigint, bigint, bigint, number, bigint]>,
      maintenanceM(),
    ]);
    const collateral = Number(formatEther(p[2])), size = Number(formatEther(p[3])), principal = Number(formatEther(p[4]));
    if (size <= 0) return c?.v ?? liqFrom(entryFallback, lev, isLong);
    const price = isLong
      ? (principal * (1 + m)) / size          // LONG liquidates below this
      : ((collateral + principal) * (1 - m)) / size; // SHORT liquidates above this
    liqCache.set(key, { at: Date.now(), v: price });
    return price;
  } catch { return c?.v ?? liqFrom(entryFallback, lev, isLong); }
}

// mark price (gwei→eth per token) from the engine's live TWAP mark, for the UI's
// liquidation-hint targeting. sqrtP → price = (Q96/sqrt)^2 (token per eth is
// (sqrt/Q96)^2, so eth per token is the inverse).
async function markPriceEth(): Promise<number | null> {
  const live = await liveStats();
  if (!live || !live.markSqrt || live.markSqrt <= 0n) return null;
  const Q = 2 ** 96;
  const s = Number(live.markSqrt) / Q;
  return s > 0 ? 1 / (s * s) : null;
}

app.get("/perp-heatmap/:generation", async (c) => {
  const gen = Number(c.req.param("generation"));
  const open = await db.select().from(schema.perpPosition)
    .where(and(eq(schema.perpPosition.generation, gen), eq(schema.perpPosition.status, "open")))
    .orderBy(desc(schema.perpPosition.notionalEth)).limit(500);
  // Recently CLOSED / LIQUIDATED positions → drawn as HISTORY (open→close
  // segments) so a wall leaves a trace instead of vanishing. Cap to the last 200.
  const closed = await db.select().from(schema.perpPosition)
    .where(and(eq(schema.perpPosition.generation, gen), ne(schema.perpPosition.status, "open")))
    .orderBy(desc(schema.perpPosition.closedAt)).limit(200);
  const st = await db.select().from(schema.perpStat).where(eq(schema.perpStat.id, gen)).limit(1);
  const s = st[0];
  const live = await liveStats(); // depth/vault/maxLev — server-side RPC (rotated keys)
  const markPrice = await markPriceEth();

  const openPositions = await Promise.all(open.map(async (p) => {
    const entry = await postOpenEntry(p.openTx, p.entryPrice);
    // EXACT on-chain liq level for OPEN positions (still liquidatable) so the wall
    // lines up with the real trigger; falls back to the entry formula if the read
    // fails or the position already left the contract.
    const liqPrice = await exactLiqPrice(p.positionId, entry, p.leverage, p.isLong);
    return { id: p.positionId.toString(), isLong: p.isLong, leverage: p.leverage,
      entryPrice: entry, liqPrice, notionalEth: p.notionalEth,
      openedAt: Number(p.openedAt), closedAt: null as number | null, status: "open" };
  }));
  const history = await Promise.all(closed.map(async (p) => {
    const entry = await postOpenEntry(p.openTx, p.entryPrice);
    // Closed positions no longer exist on-chain → use the stored liqPrice if the
    // indexer captured it, else the entry formula (history walls are cosmetic).
    return { id: p.positionId.toString(), isLong: p.isLong, leverage: p.leverage,
      entryPrice: entry, liqPrice: p.liqPrice > 0 ? p.liqPrice : liqFrom(entry, p.leverage, p.isLong), notionalEth: p.notionalEth,
      openedAt: Number(p.openedAt), closedAt: Number(p.closedAt ?? 0), status: p.status };
  }));

  return c.json({
    live: true,
    positions: openPositions, // live walls (open → now)
    history,                  // finished walls (open → close/liquidation)
    markPrice,                // eth per token at the TWAP mark (for hint targeting)
    // OI from the live engine when available (authoritative), else the index.
    longOiEth: live?.longOiEth ?? s?.longOiEth ?? 0,
    shortOiEth: live?.shortOiEth ?? s?.shortOiEth ?? 0,
    plvEth: live?.plvEth ?? 0,
    plvToken: live?.plvToken ?? 0,
    depthEth: live?.depthEth ?? 0,
    maxLev: live?.maxLev ?? 3,
    fundingIdx: live?.fundingIdx ?? 0,
    dead: live?.dead ?? false,
    openFeeBps: 690, ogDiscountBps: 5000,
    // per-position notional cap (mirrors PerpEngine.maxNotionalBps) so the UI can
    // block a doomed open BEFORE it hits _checkNotional's BadLeverage() revert.
    maxNotionalBps: 500, maxOiBps: 3000,
    openCount: s?.openPositions ?? open.length,
    // Freshness beacon for the UI: if the indexer has diverged from the chain
    // (stale build / stalled realtime), the frontend must NOT render "no positions"
    // as truth — it shows a "data delayed" warning instead. Cheap: reuses the
    // cached /health evaluation.
    stale: !(await evaluateHealth()).ok,
  });
});
app.get("/perp-positions/:trader", async (c) => {
  const trader = c.req.param("trader").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.perpPosition)
    .where(and(eq(schema.perpPosition.trader, trader), eq(schema.perpPosition.status, "open")))
    .orderBy(desc(schema.perpPosition.openedAt)).limit(200);
  const positions = await Promise.all(rows.map(async (p) => {
    const entry = await postOpenEntry(p.openTx, p.entryPrice); // post-open spot
    return { id: p.positionId.toString(), isLong: p.isLong, leverage: p.leverage,
      collateralEth: p.collateralEth, notionalEth: p.notionalEth,
      entryPrice: entry, liqPrice: liqFrom(entry, p.leverage, p.isLong), openedAt: Number(p.openedAt) };
  }));
  return c.json({ positions });
});
// A trader's recently LIQUIDATED positions → the frontend pops a RIP PnL card.
app.get("/perp-rekt/:trader", async (c) => {
  const trader = c.req.param("trader").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.perpPosition)
    .where(and(eq(schema.perpPosition.trader, trader), eq(schema.perpPosition.status, "liquidated")))
    .orderBy(desc(schema.perpPosition.closedAt)).limit(20);
  return c.json({ rekt: rows.map((p) => ({
    id: p.positionId.toString(), isLong: p.isLong, leverage: p.leverage,
    collateralEth: p.collateralEth, pnlEth: p.pnlEth ?? -p.collateralEth,
    closedAt: Number(p.closedAt ?? 0), liquidatedBy: p.liquidatedBy ?? null,
  })) });
});
/* ── /health — the anti-footgun. A plain process-ping (the old /candles/1) returns
      200 even when the indexer is running a STALE BUILD pinned to a PREVIOUS round's
      pool + engine (exactly the bug that once hid live positions + a liquidation).
      This CROSS-CHECKS live chain state against the indexed DB so that failure mode
      trips the healthcheck:
        • poolMismatch  — the registry's current pool isn't in our indexed pools
                          (we're watching the wrong/old contracts entirely)
        • missedLaunch  — chain generation is ahead of the newest indexed pool
        • missedOpens   — the engine has more open positions than the DB recorded
      A grace timer means normal startup/backfill + the few-second lag after a tx
      never trips it — only a divergence that PERSISTS. In-memory state resets on
      restart (fine: a restart is exactly what a persistent failure should cause). ── */
const REG_POOLID = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "generationPoolId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bytes32" }] },
] as const;
const ENGINE_OPENCOUNT = [{ type: "function", name: "openCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] }] as const;
const HEALTH_GRACE_MS = 180_000;   // a real desync must persist 3 min before we fail
const ZERO_POOL = "0x0000000000000000000000000000000000000000000000000000000000000000";
let divergingSince = 0;            // ms; 0 = last check was healthy
let everHealthy = false;           // gate the watchdog: only self-restart if we WERE fine
let healthCache: { at: number; body: Record<string, unknown>; ok: boolean } = { at: 0, body: {}, ok: true };

async function evaluateHealth() {
  if (Date.now() - healthCache.at < 4000) return healthCache;
  try {
    const rd = async <T,>(p: Promise<T>, d: T): Promise<T> => { try { return await p; } catch { return d; } };
    const [chainGenBn, chainOpenBn, pools, openRows] = await Promise.all([
      rd(perpClient.readContract({ address: REGISTRY, abi: REG_POOLID, functionName: "currentGeneration" }) as Promise<bigint>, 0n),
      rd(perpClient.readContract({ address: PERP_ENGINE, abi: ENGINE_OPENCOUNT, functionName: "openCount" }) as Promise<bigint>, 0n),
      db.select().from(schema.pool),
      db.select().from(schema.perpPosition).where(eq(schema.perpPosition.status, "open")),
    ]);
    const chainGen = Number(chainGenBn);
    const curPoolId = chainGen > 0
      ? await rd(perpClient.readContract({ address: REGISTRY, abi: REG_POOLID, functionName: "generationPoolId", args: [BigInt(chainGen)] }) as Promise<`0x${string}`>, ZERO_POOL as `0x${string}`)
      : ZERO_POOL as `0x${string}`;
    const indexedIds = new Set(pools.map((p) => p.id.toLowerCase()));
    const indexedGen = pools.reduce((m, p) => Math.max(m, p.generation), 0);
    const chainOpen = Number(chainOpenBn);
    const dbOpen = openRows.length;

    // A chain read that returned the fallback 0/zero → RPC blip, not a real divergence.
    const chainReadable = chainGen > 0 && curPoolId !== ZERO_POOL;
    const poolMismatch = chainReadable && !indexedIds.has(curPoolId.toLowerCase());
    const missedLaunch = chainReadable && indexedGen > 0 && chainGen > indexedGen;
    const missedOpens = chainOpen > dbOpen;                 // chain has opens the DB lacks
    const diverged = poolMismatch || missedLaunch || missedOpens;

    const now = Date.now();
    if (diverged) { if (!divergingSince) divergingSince = now; }
    else { divergingSince = 0; everHealthy = true; }
    const persistedMs = divergingSince ? now - divergingSince : 0;
    // NOT-ok only once we've been healthy at least once (a fresh backfill has
    // dbOpen<chainOpen for its whole duration — that's expected, not a fault) AND
    // the divergence has persisted past the grace. `everHealthy` gates out the
    // startup window so this can never deadlock a deploy.
    const ok = !diverged || !everHealthy || persistedMs <= HEALTH_GRACE_MS;

    const body = {
      ok, chainGen, indexedGen, curPoolId, indexedPools: [...indexedIds],
      chainOpenPositions: chainOpen, dbOpenPositions: dbOpen,
      reasons: { poolMismatch, missedLaunch, missedOpens },
      divergingForMs: persistedMs, warmingUp: !everHealthy,
    };
    healthCache = { at: now, body, ok };
    return healthCache;
  } catch (e) {
    // Startup / transient (tables not created yet, RPC blip): report OK so the
    // freshness beacon never 500s and the deploy is never blocked. Divergence
    // self-heal is the watchdog's job, not this read's.
    const body = { ok: true, warmingUp: true, error: e instanceof Error ? e.message : String(e) };
    healthCache = { at: Date.now(), body, ok: true };
    return healthCache;
  }
}

// NOTE: intentionally NOT mounted at "/health" — that path is Ponder's built-in
// LIVENESS endpoint (always 200 once the server is up), which Railway's
// healthcheck uses to promote a deploy. Overriding it with this divergence check
// (which can 503 during a fresh backfill) DEADLOCKED promotion. This is the
// deeper FRESHNESS beacon for external monitoring + the frontend `stale` flag.
app.get("/freshness", async (c) => {
  const { body, ok } = await evaluateHealth();
  return c.json(body, ok ? 200 : 503);
});

// In-process WATCHDOG: if the indexer diverges from the chain and STAYS diverged
// well past the /health grace, exit non-zero so Railway's ON_FAILURE policy
// restarts the container (a fresh worker re-syncs). Only armed once we've been
// healthy at least once, so a genuinely misconfigured deploy fails the healthcheck
// (blocking promotion + alerting) instead of crash-looping pointlessly. Opt out
// with HEALTH_WATCHDOG=0.
if (process.env.HEALTH_WATCHDOG !== "0") {
  const WATCHDOG_KILL_MS = HEALTH_GRACE_MS * 3; // ~9 min of sustained divergence
  setInterval(async () => {
    try {
      const { ok } = await evaluateHealth();
      if (!ok && everHealthy && divergingSince && Date.now() - divergingSince > WATCHDOG_KILL_MS) {
        console.error(`[watchdog] indexer diverged from chain for ${Math.round((Date.now() - divergingSince) / 1000)}s — exiting for a clean restart`);
        process.exit(1);
      }
    } catch { /* never let the watchdog itself crash the process */ }
  }, 30_000);
}

/** PerpVault's virtual-shares offset (`OFFSET`, PerpVault.sol:64). Shares are
 *  minted at this multiple of assets, so any assets-per-share figure has to be
 *  scaled by it before it means anything to a human. */
const SHARE_OFFSET = 1e6;

// Community PLV vault (staking) state + a user's position — server-side reads.
let vaultCache: { at: number; v: { assetsEth: number; assetsTok: number; ethShares: number; tokShares: number; ethSharePrice: number; tokSharePrice: number } | null } = { at: 0, v: null };
async function vaultState() {
  if (Date.now() - vaultCache.at < 5000 && vaultCache.v) return vaultCache.v;
  try {
    const n = (v: bigint) => Number(formatEther(v));
    const [aEth, aTok, eSh, tSh] = await Promise.all([
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "assetsEth" }) as Promise<bigint>,
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "assetsTok" }) as Promise<bigint>,
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "ethShares" }) as Promise<bigint>,
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "tokShares" }) as Promise<bigint>,
    ]);
    const v = {
      assetsEth: n(aEth), assetsTok: n(aTok), ethShares: n(eSh), tokShares: n(tSh),
      //  NORMALISED BY THE VAULT'S VIRTUAL-SHARE OFFSET. PerpVault mints at
      //  OFFSET x assets (`shares = amount * (ethShares + 1e6) / (assetsEth + 1)`,
      //  PerpVault.sol:225) as ERC-4626-style inflation protection, so raw
      //  assets/shares is ~1e-6 at par, not ~1. Unnormalised, the frontend
      //  rendered "Share price 0.0000" (toFixed(4) of 1e-6) and, worse, computed
      //  vault yield as `(sharePrice - 1) * 100` = -99.9999% — a healthy vault
      //  reporting that it had lost everything. Measured live: assetsEth 5e17
      //  against ethShares 5e23, exactly the offset.
      //  1.0 means par, which is the convention the client already defaults to.
      ethSharePrice: eSh > 0n ? (n(aEth) / n(eSh)) * SHARE_OFFSET : 1,
      tokSharePrice: tSh > 0n ? (n(aTok) / n(tSh)) * SHARE_OFFSET : 1,
    };
    vaultCache = { at: Date.now(), v };
    return v;
  } catch { return vaultCache.v; }
}
app.get("/perp-vault", async (c) => c.json({ vault: await vaultState() }));
app.get("/perp-vault/:user", async (c) => {
  const user = c.req.param("user").toLowerCase() as `0x${string}`;
  const n = (v: bigint) => Number(formatEther(v));
  let ethPos = { redeemable: 0, instant: 0, pending: 0, shares: "0" };
  let tokPos = { redeemable: 0, instant: 0, pending: 0, shares: "0", ethReward: 0 };
  try {
    const [e, t, eSh, tSh] = await Promise.all([
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "ethPosition", args: [user] }) as Promise<[bigint, bigint, bigint]>,
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "tokenPosition", args: [user] }) as Promise<[bigint, bigint, bigint]>,
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "ethShareOf", args: [user] }) as Promise<bigint>,
      perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "tokShareOf", args: [user] }) as Promise<bigint>,
    ]);
    ethPos = { redeemable: n(e[0]), instant: n(e[1]), pending: n(e[2]), shares: eSh.toString() };
    tokPos = { redeemable: n(t[0]), instant: n(t[1]), pending: n(t[2]), shares: tSh.toString(), ethReward: 0 };
  } catch { /* zeros */ }
  // token-side ETH reward (short-attributed yield) — separate try so an older
  // vault that lacks the fn still returns positions.
  try {
    const r = await perpClient.readContract({ address: PERP_VAULT, abi: VAULT_ABI, functionName: "pendingTokYield", args: [user] }) as bigint;
    tokPos.ethReward = n(r);
  } catch { /* not on this vault build */ }
  return c.json({ vault: await vaultState(), eth: ethPos, token: tokPos });
});

// Liquidatoor leaderboard — who's rekt the most frens (gamification).
app.get("/perp-liquidators", async (c) => {
  const limit = Math.min(Number(c.req.query("limit") ?? 50), 200);
  const rows = await db.select().from(schema.liquidator).orderBy(desc(schema.liquidator.kills)).limit(limit);
  return c.json({ liquidators: rows.map((r) => ({
    address: r.id, kills: r.kills, badges: r.badges, lastAt: Number(r.lastAt ?? 0),
  })) });
});

// A wallet's KILLS — the positions it liquidated, with the REAL side + stats so a
// Liquidatoor badge shows its true story (short vs long, entry, liq, victim) rather
// than a fabricated roll. Keyed by badgeId so the frontend can match owned badges.
app.get("/perp-kills/:wallet", async (c) => {
  const w = (c.req.param("wallet") || "").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.perpPosition)
    .where(and(eq(schema.perpPosition.liquidatedBy, w), eq(schema.perpPosition.status, "liquidated")))
    .orderBy(desc(schema.perpPosition.closedAt)).limit(200);
  return c.json({ kills: rows.map((r) => ({
    badgeId: r.badgeId ? r.badgeId.toString() : null,
    positionId: r.positionId.toString(),
    isLong: r.isLong, leverage: r.leverage,
    entryPrice: r.entryPrice, liqPrice: r.liqPrice, notionalEth: r.notionalEth,
    victim: r.trader, block: Number(r.closedAt ?? 0),
  })) });
});

/* ── collections + NFTs + holders ──────────────────────────────────────── */
app.get("/collections", async (c) => {
  const rows = await db.select().from(schema.collection);
  return c.json({ collections: rows.map((r) => ({
    address: r.id, generation: r.generation, name: r.name, symbol: r.symbol,
    totalMinted: r.totalMinted, isPresale: r.isPresale,
    createdAt: r.createdAt ? Number(r.createdAt) : null,
  })) });
});
// NFTs owned by a wallet (across all collections) — the "my frens" view.
app.get("/nfts/:owner", async (c) => {
  const owner = c.req.param("owner").toLowerCase() as `0x${string}`;
  const limit = Math.min(Number(c.req.query("limit") ?? 500), 2000);
  const rows = await db.select().from(schema.nft).where(eq(schema.nft.owner, owner)).limit(limit);
  return c.json({ nfts: rows.map((r) => ({ collection: r.collection, tokenId: r.tokenId, rarity: r.rarity, revealed: r.revealed, isLiquidatoor: r.isLiquidatoor })) });
});
// NFTs in a collection.
app.get("/collection/:address/nfts", async (c) => {
  const addr = c.req.param("address").toLowerCase() as `0x${string}`;
  const limit = Math.min(Number(c.req.query("limit") ?? 200), 2000);
  const rows = await db.select().from(schema.nft).where(eq(schema.nft.collection, addr)).orderBy(desc(schema.nft.tokenId)).limit(limit);
  return c.json({ nfts: rows.map((r) => ({ tokenId: r.tokenId, owner: r.owner, rarity: r.rarity, revealed: r.revealed })) });
});

/* ── gacha player stats ────────────────────────────────────────────────── */
app.get("/gacha/:player", async (c) => {
  const p = c.req.param("player").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.gachaPlayer).where(eq(schema.gachaPlayer.id, p)).limit(1);
  const g = rows[0];
  return c.json(g ? { wins: g.wins, misses: g.misses, committed: g.committed } : { wins: 0, misses: 0, committed: 0 });
});

/* ── dividend + "cast the spell" enchant ───────────────────────────────── */
/* ── REAL LIQUIDITY COMPOSITION ─────────────────────────────────────────────
 * What actually backs the brew, split by the asset it is denominated in.
 *
 * ONLY THE QUOTE SIDE COUNTS. A pool holds two assets, and one of them is the
 * brew's own token — counting that is how a project claims a "$2M pool" that is
 * half its own paper. Every Cauldron pair is opened with the quote as currency0
 * (PoolOps mines the token to sort ABOVE it), so `amount0` IS the real side and
 * the token is excluded by construction rather than by a subtraction someone has
 * to remember to make.
 *
 * The split exists because rotation is SLICED: a generation part-way through a
 * move from ETH to USDG genuinely holds both, and that is the composition worth
 * drawing. Today's single-quote generation reports one slice at 100%, which is
 * the same shape rather than a special case.
 *
 * Reserves are reported SEPARATELY and never folded into the pool figure: the
 * hook's fee reserve and the floor vault are real value that seeds the next
 * launch, but they are not liquidity anyone can trade against right now. */
let realLiqCache: { at: number; v: unknown } = { at: 0, v: null };
app.get("/liquidity", async (c) => {
  if (realLiqCache.v && Date.now() - realLiqCache.at < 8000) return c.json(realLiqCache.v);
  try {
    const gen = await perpClient.readContract({
      address: REGISTRY, abi: REG_POOLID, functionName: "currentGeneration",
    }) as bigint;
    if (gen === 0n) return c.json({ generation: 0, assets: [], totalUsd: null, pool: 0 });

    const key = await perpClient.readContract({
      address: REGISTRY, abi: REG_LP, functionName: "generationPoolKey", args: [gen],
    }).catch(() => null) as readonly [string, string, number, number, string] | null;
    const poolId = await perpClient.readContract({
      address: REGISTRY, abi: REG_POOLID, functionName: "generationPoolId", args: [gen],
    }).catch(() => null) as `0x${string}` | null;

    const quoteAddr = (key?.[0] ?? NATIVE).toLowerCase();
    const meta = QUOTES.find((q) => q.address.toLowerCase() === quoteAddr)
      ?? { address: quoteAddr, symbol: quoteAddr === NATIVE ? "ETH" : "?", decimals: 18 };

    // The pool's real depth, in the quote asset. Same measurement the relaunch
    // recovers, so the number on screen is the number the next launch gets.
    const poolAmount = poolId ? await lpEthOf(poolId, gen) : 0;

    //  ── THE FLOORS ARE TOKEN-DENOMINATED, SO THEY ARE NOT REPORTED HERE ──
    //  An earlier cut of this reported `generationVault`'s ether balance as a
    //  "floor vault", which is a measurement of something designed to be
    //  permanently zero. The registry says so at the point it deploys the vault:
    //
    //      // UNIFIED FLOOR: no ETH vault - route the fee floor-share into the
    //      // token buyback buffer (setVault(0)); the vault stays deployed only
    //      // as a supply counter for crystallize.
    //      hook.setVault(address(0));
    //
    //  Both floors this protocol has are backed in TOKEN, not ether: the genesis
    //  redemption floor is the out-of-range reserve (claimed 1:1 by burn, see
    //  /floor), and each collection's floor is a token entitlement in
    //  CollectionLedger. Reporting an ether figure for either would invite the
    //  reader to add it to the pool, which is exactly the wrong sum.
    //
    //  The hook's fee reserve IS ether and IS additive to the next launch, so it
    //  stays.
    const relaunchWei = await perpClient.readContract({
      address: HOOK, abi: HOOK_READ, functionName: "relaunchETH",
    }).catch(() => 0n) as bigint;

    // USD, when an oracle can price it. 0 from the oracle means CANNOT JUDGE,
    // never "worthless" — it stays null and the UI omits the figure rather than
    // drawing a confident zero.
    let usd: number | null = null;
    const oracle = ROTATOR
      ? await perpClient.readContract({ address: ROTATOR, abi: ROTATOR_READ, functionName: "quoteOracle" }).catch(() => null) as string | null
      : null;
    if (oracle && oracle !== NATIVE) {
      const f = await perpClient.readContract({
        address: oracle as `0x${string}`, abi: ORACLE_READ,
        functionName: "usdPerRawUnit", args: [meta.address as `0x${string}`],
      }).catch(() => 0n) as bigint;
      if (f > 0n) usd = poolAmount * (Number(f) / 1e18);
    }

    const assets = [{
      address: meta.address,
      symbol: meta.symbol,
      amount: poolAmount,
      usd,
      share: 1,          // one quote today; the shape is already the split
      isBasis: true,
    }];

    const v = {
      generation: Number(gen),
      pool: poolAmount,                       // real, quote-side, token excluded
      assets,
      totalUsd: usd,
      reserves: {
        hookReserve: Number(formatEther(relaunchWei)),
      },
      nextLaunch: poolAmount + Number(formatEther(relaunchWei)),
    };
    realLiqCache = { at: Date.now(), v };
    return c.json(v);
  } catch (e) {
    return c.json({ generation: 0, assets: [], pool: 0, totalUsd: null, error: String(e).slice(0, 120) });
  }
});

/* ── LAUNCH SEEDING FEED ────────────────────────────────────────────────────
 * Live progress of the progressive stream + the tranched prime buy, plus the
 * recent tape so the page can announce each step as it lands.
 *
 * `target` is computed HERE rather than stored, because it is a pure function of
 * wall-clock time (SeedLib.deployedTargetWad) and would otherwise need a write
 * every second. The gap between `target` and `placed` is exactly what a poke
 * would deploy, so the UI can show "catching up" honestly. */
app.get("/seeding", async (c) => {
  const rows = await db.select().from(schema.seedState).where(eq(schema.seedState.id, "live")).limit(1);
  const s = rows[0];
  const feed = await db
    .select().from(schema.seedEvent)
    .orderBy(desc(schema.seedEvent.block))
    .limit(Number(c.req.query("limit") ?? 25));

  const WAD = 10n ** 18n;
  const now = BigInt(Math.floor(Date.now() / 1000));
  const start = s?.startTs ?? 0n;
  const win = s?.window ?? 0n;
  let target = 0n;
  if (s) {
    if (win === 0n || now >= start + win) target = WAD;
    else if (now <= start) target = 0n;
    else target = ((WAD) * (now - start)) / win;
  }
  const placed = s?.placedWad ?? 0n;
  const remaining = s && win > 0n && now < start + win ? Number(start + win - now) : 0;

  return c.json({
    active: !!s && !s.complete && start > 0n,
    complete: s?.complete ?? false,
    generation: s?.generation ?? 0,
    placedWad: placed.toString(),
    targetWad: target.toString(),
    placed: Number(placed) / 1e18,
    target: Number(target) / 1e18,
    basePlaced: s?.basePlaced ?? false,
    pokes: s?.pokes ?? 0,
    startTs: Number(start),
    window: Number(win),
    remaining,
    ethTotal: (s?.ethTotal ?? 0n).toString(),
    tokenTotal: (s?.tokenTotal ?? 0n).toString(),
    prime: {
      budget: (s?.primeBudget ?? 0n).toString(),
      spent: (s?.primeSpent ?? 0n).toString(),
      tokenOut: (s?.primeTokenOut ?? 0n).toString(),
      budgetEth: Number(s?.primeBudget ?? 0n) / 1e18,
      spentEth: Number(s?.primeSpent ?? 0n) / 1e18,
    },
    feed: feed.map((e) => ({
      id: e.id, kind: e.kind, generation: e.generation,
      fromWad: e.fromWad.toString(), toWad: e.toWad.toString(),
      from: Number(e.fromWad) / 1e18, to: Number(e.toWad) / 1e18,
      ethIn: e.ethIn.toString(), ethInEth: Number(e.ethIn) / 1e18,
      tokenOut: e.tokenOut.toString(),
      tick: e.tick, ts: Number(e.ts), block: Number(e.block), txHash: e.txHash,
    })),
  });
});

app.get("/dividend", async (c) => {
  const rows = await db.select().from(schema.dividendStat).where(eq(schema.dividendStat.id, "dividend")).limit(1);
  const s = rows[0];
  const active = await db.select().from(schema.enchant).where(eq(schema.enchant.active, true));
  return c.json({
    totalDeposited: (s?.totalDeposited ?? 0n).toString(),
    totalClaimed: (s?.totalClaimed ?? 0n).toString(),
    treasuryFunded: (s?.treasuryFunded ?? 0n).toString(),
    activeShares: active.length,
  });
});
// Which of a wallet's genesis frens are currently enchanted (spell cast).
app.get("/enchants/:owner", async (c) => {
  const owner = c.req.param("owner").toLowerCase() as `0x${string}`;
  const rows = await db.select().from(schema.enchant).where(and(eq(schema.enchant.fren, owner), eq(schema.enchant.active, true)));
  return c.json({ tokenIds: rows.map((r) => r.id) });
});

/* ── per-iteration migration + burn (deflation) ────────────────────────── */
app.get("/iterations", async (c) => {
  const rows = await db.select().from(schema.iteration).orderBy(desc(schema.iteration.id));
  let totalBurned = 0n;
  for (const r of rows) totalBurned += r.burned;
  return c.json({
    iterations: rows.map((r) => ({
      generation: r.id, token: r.token, symbol: r.symbol,
      migratedOut: r.migratedOut.toString(), burned: r.burned.toString(),
      //  `burned` is NOT indexed — no contract emits `UnclaimedBurned`, so it is
      //  structurally 0. Flagged so a consumer cannot mistake it for live data.
      burnedIndexed: false,
    })),
    totalBurned: totalBurned.toString(),
    supplyPerGen: "777000000000000000000000000", // fixed 777M * 1e18 per iteration
  });
});

/* ── governance ────────────────────────────────────────────────────────── */
// The Proposed event only carries name/symbol/proposer — the rich launch spec
// (nftSupply, volumePerNFT, website, socials, art mode) lives in the contract's
// _proposals mapping. Read it on-chain via getProposal so the UI shows real
// numbers instead of 0s. Cached 10s.
const GOVERNOR = round.contracts.governor as `0x${string}`; // from the shared manifest
const GOV_READ = [{
  type: "function", name: "getProposal", stateMutability: "view", inputs: [{ type: "uint256" }],
  outputs: [{ type: "tuple", components: [
    { name: "name", type: "string" }, { name: "symbol", type: "string" }, { name: "mode", type: "uint8" },
    { name: "baseURI", type: "string" }, { name: "renderer", type: "address" }, { name: "website", type: "string" },
    { name: "socials", type: "string" }, { name: "nftSupply", type: "uint256" }, { name: "volumePerNFT", type: "uint256" },
    { name: "proposer", type: "address" }, { name: "votes", type: "uint256" }, { name: "snapshot", type: "uint256" },
    { name: "consumed", type: "bool" }, { name: "exists", type: "bool" },
  ] }],
}] as const;
const propCache = new Map<number, { at: number; v: Record<string, unknown> }>();
async function fullProposal(id: number) {
  const c = propCache.get(id);
  if (c && Date.now() - c.at < 10_000) return c.v;
  try {
    const p = await perpClient.readContract({ address: GOVERNOR, abi: GOV_READ, functionName: "getProposal", args: [BigInt(id)] }) as {
      name: string; symbol: string; mode: number; baseURI: string; renderer: string; website: string; socials: string;
      nftSupply: bigint; volumePerNFT: bigint; proposer: string; votes: bigint; consumed: boolean;
    };
    const nftSupply = Number(p.nftSupply);
    const volPerNft = Number(formatEther(p.volumePerNFT));
    const v = {
      website: p.website || null, socials: p.socials || null,
      metaMode: p.mode === 1 ? "renderer" : "uri", metaValue: p.mode === 1 ? p.renderer : p.baseURI,
      nftSupply, mintOutEth: volPerNft * nftSupply,
    };
    propCache.set(id, { at: Date.now(), v });
    return v;
  } catch { return c?.v ?? null; }
}
app.get("/proposals", async (c) => {
  const rows = await db.select().from(schema.proposal).orderBy(desc(schema.proposal.votes));
  // Dedupe by symbol — a proposer can re-file the same brew (e.g. to change the
  // art mode); keep only the NEWEST (highest id) per ticker so the list stays
  // clean. Unvoted duplicates from a re-propose don't clutter governance.
  const seen = new Set<string>();
  const deduped = [...rows].sort((a, b) => b.id - a.id).filter((r) => {
    const k = (r.symbol || "").toUpperCase();
    if (!k) return true;
    if (seen.has(k)) return false;
    seen.add(k); return true;
  }).sort((a, b) => Number(b.votes - a.votes));
  const proposals = await Promise.all(deduped.map(async (r) => ({
    id: r.id, name: r.name, symbol: r.symbol, proposer: r.proposer, votes: r.votes.toString(), consumed: r.consumed,
    ...(await fullProposal(r.id) ?? {}),
  })));
  return c.json({ proposals });
});

/* ── r30: floor history + legacy collection floors + proposer flywheel ───── */
const s = (v: unknown) => (typeof v === "bigint" ? v.toString() : v);

// Append-only genesis-floor action log (redeem / buy-2x / grow) + live state.
app.get("/floor/history", async (c) => {
  const gen = Number(c.req.query("gen") ?? 0);
  const limit = Math.min(Number(c.req.query("limit") ?? 100), 500);
  const where = gen > 0 ? eq(schema.floorEvent.generation, gen) : undefined;
  const rows = await db.select().from(schema.floorEvent)
    .where(where as never).orderBy(desc(schema.floorEvent.ts)).limit(limit);
  const state = await db.select().from(schema.genesisFloor)
    .orderBy(desc(schema.genesisFloor.id)).limit(1);
  return c.json({
    state: state[0] ? Object.fromEntries(Object.entries(state[0]).map(([k, v]) => [k, s(v)])) : null,
    events: rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, s(v)]))),
  });
});

// Per-generation LEGACY collection floors (recycle / buy-2x rollup) + recent log.
//  `/collection-floors` WAS REGISTERED TWICE. Hono serves the first match, so
//  this second handler — raw `collectionFloor` / `collectionFloorEvent` rows,
//  a completely different response shape — was unreachable from the moment it
//  was added. The live one is the chain-reading, cached handler above, which is
//  what the panel consumes; two registrations of one path is a coin-flip about
//  which response a client gets, so the dead one is gone rather than renamed.

// Proposer flywheel leaderboard (fee earned per iteration proposer).
app.get("/proposers", async (c) => {
  const rows = await db.select().from(schema.proposerEarning)
    .orderBy(desc(schema.proposerEarning.totalEarned)).limit(100);
  return c.json({ proposers: rows.map((r) => ({
    proposer: r.id, totalEarned: s(r.totalEarned), payoutCount: r.payoutCount,
  })) });
});

export default app;

/**
 * TREASURY ROTATION GOVERNANCE — live proposals, tallies, and executed slices.
 *
 * Proposals are CONCURRENT here, not serialised: `TreasuryGovernor.propose`
 * refuses only while an envelope is live or inside its cooldown, because
 * one-open-proposal-at-a-time let anyone holding the 5-MiFren threshold file
 * junk forever and veto treasury governance for the price of gas. So this
 * returns a LIST and marks the current leader, rather than a single "the"
 * proposal.
 *
 * `open` is derived from the chain's clock, not from a stored flag: a proposal
 * whose voting window has simply elapsed emits nothing, so a flag would never
 * be corrected and the UI would keep offering a vote that reverts.
 */
app.get("/rotation/governance", async (c) => {
  const nowSec = BigInt(Math.floor(Date.now() / 1000));

  const [props, slices, timing, winnerId] = await Promise.all([
    db.select().from(schema.rotationProposal).orderBy(desc(schema.rotationProposal.createdTs)).limit(25),
    db.select().from(schema.rotationSlice).orderBy(desc(schema.rotationSlice.ts)).limit(25),
    (async () => {
      if (!TREASURY_GOV || TREASURY_GOV === NATIVE) return null;
      const read = (fn: "VOTING_PERIOD" | "EXECUTION_WINDOW" | "COOLDOWN" | "ENVELOPE_LIFETIME") => perpClient.readContract({
        address: TREASURY_GOV as `0x${string}`, abi: TGOV_READ, functionName: fn,
      }).then((v) => Number(v as bigint)).catch(() => null);
      const [votingPeriod, executionWindow, cooldown, envelopeLifetime] =
        await Promise.all([read("VOTING_PERIOD"), read("EXECUTION_WINDOW"), read("COOLDOWN"), read("ENVELOPE_LIFETIME")]);
      return { votingPeriod, executionWindow, cooldown, envelopeLifetime };
    })(),
    (TREASURY_GOV && TREASURY_GOV !== NATIVE
      ? perpClient.readContract({ address: TREASURY_GOV as `0x${string}`, abi: TGOV_READ, functionName: "winner" })
          .then((v) => (v as bigint).toString()).catch(() => null)
      : Promise.resolve(null)) as Promise<string | null>,
  ]);

  const vp = timing?.votingPeriod ?? null;
  const ew = timing?.executionWindow ?? null;

  const rows = props.map((p) => {
    //  The vote closes VOTING_PERIOD after creation, and stays executable for
    //  EXECUTION_WINDOW after that. Both come from the governor's immutables;
    //  when they cannot be read the state is reported as "unknown" rather than
    //  guessed, because a testnet runs these in minutes and mainnet in days.
    const endsAt = vp === null ? null : Number(p.createdTs) + vp;
    const execUntil = endsAt === null || ew === null ? null : endsAt + ew;
    const now = Number(nowSec);
    const open = endsAt === null ? null : now < endsAt;
    return {
      id: p.id,
      proposer: p.proposer,
      quote: p.quote,
      maxTotalBps: p.maxTotalBps,
      forVotes: p.forVotes.toString(),
      againstVotes: p.againstVotes.toString(),
      voters: p.voters,
      executed: p.executed,
      cancelled: p.cancelled,
      expiry: Number(p.expiry),
      createdTs: Number(p.createdTs),
      endsAt, execUntil, open,
      //  DID IT WIN, not merely "has voting closed".
      //  This previously offered "Execute" on a proposal beaten 0-1111 — a
      //  primary button whose only outcome is a DidNotPass revert. `execute`
      //  demands `_passed` AND `id == winner()`, so the governor's own
      //  `winner()` is the single honest source; `passed` is reported separately
      //  so a rejected proposal can be LABELLED rather than silently dropped.
      passed: p.forVotes > p.againstVotes,
      executable: winnerId !== null && winnerId === p.id && !p.executed && !p.cancelled,
      txHash: p.txHash,
    };
  });

  //  THE LEADER IS AMONG OPEN PROPOSALS ONLY, and ties do not count as leading.
  //  `execute` picks the winner on chain; this is presentation, so it must not
  //  imply a winner the contract would not agree with.
  const live = rows.filter((r) => r.open && !r.cancelled);
  let leader: string | null = null;
  if (live.length > 0) {
    const sorted = [...live].sort((a, b) => (BigInt(b.forVotes) > BigInt(a.forVotes) ? 1 : -1));
    const top = sorted[0]!;
    const tied = sorted.filter((r) => r.forVotes === top.forVotes).length > 1;
    if (!tied && BigInt(top.forVotes) > BigInt(top.againstVotes)) leader = top.id;
  }

  return c.json({
    timing,
    leader,
    proposals: rows,
    slices: slices.map((s) => ({
      id: s.id,
      generation: s.generation,
      fromQuote: s.fromQuote,
      toQuote: s.toQuote,
      // Raw, plus each side converted by ITS OWN asset's decimals — ETH is 18
      // and USDG is 6, so a shared divisor would misreport one of them by 10^12.
      quoteIn: s.quoteIn.toString(),
      quoteOut: s.quoteOut.toString(),
      amountIn: Number(s.quoteIn) / 10 ** (decimalsOf(s.fromQuote)),
      amountOut: Number(s.quoteOut) / 10 ** (decimalsOf(s.toQuote)),
      sliceBps: s.sliceBps,
      ts: Number(s.ts),
      txHash: s.txHash,
    })),
  });
});
