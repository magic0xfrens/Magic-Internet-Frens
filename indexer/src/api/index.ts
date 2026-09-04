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
const POSITION_MGR = (process.env.POSITION_MANAGER ?? "0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4") as `0x${string}`;
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
    if (sqrtP === 0n || posId === 0n) return 0;
    const L = await perpClient.readContract({ address: POSITION_MGR, abi: POSLIQ, functionName: "getPositionLiquidity", args: [posId] }) as bigint;
    if (L === 0n) return 0;
    const amount0 = (L * Q96 * (SQRT_MAX - sqrtP)) / (sqrtP * SQRT_MAX);
    return Number(formatEther(amount0));
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

// GENESIS REDEMPTION FLOOR (v2, ratcheting) — the RISING stat. floorPerFren is
// DYNAMIC (reserve / genesisShares) and only goes up as buybacks + re-enchant fees
// grow the reserve. We surface the token floor, its ETH value, the % of the live
// token's FDV each fren now backs, and the enchant fee. Reads live (cached 4s).
let floorCache: { at: number; v: unknown } = { at: 0, v: null };
app.get("/floor", async (c) => {
  if (Date.now() - floorCache.at < 4000 && floorCache.v) return c.json(floorCache.v);
  const ps = await presaleState();
  const mark = await markPriceEth(); // ETH per token at the TWAP mark
  const rd = async (fn: string) =>
    (await perpClient.readContract({ address: REGISTRY, abi: REG_GENESIS, functionName: fn as never }).catch(() => 0n)) as bigint;
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
const HOOK_LEGACY = [
  { type: "function", name: "legacyBuffer", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "legacyThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "legacyBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
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
    const rd = async (a: `0x${string}`, abi: readonly unknown[], fn: string, args: unknown[] = []) =>
      (await perpClient.readContract({ address: a, abi: abi as never, functionName: fn as never, args: args as never }).catch(() => 0n)) as bigint;
    const curGen = Number(await rd(REGISTRY, REG_CURGEN, "currentGeneration"));
    // live token symbol (for "N $GNOME" labels) — read server-side so the browser
    // stays RPC-free (the reason the panel's own reads were flaky → 0% shown).
    const curToken = curGen > 0
      ? await perpClient.readContract({ address: REGISTRY, abi: REG_CURGEN, functionName: "currentToken" }).catch(() => ZERO) as `0x${string}`
      : ZERO as `0x${string}`;
    const ticker = curToken && curToken !== ZERO
      ? await perpClient.readContract({ address: curToken, abi: SYMBOL_ABI, functionName: "symbol" }).catch(() => "") as string
      : "";
    const [buffer, threshold, bps, liveEntitled] = await Promise.all([
      rd(HOOK, HOOK_LEGACY, "legacyBuffer"), rd(HOOK, HOOK_LEGACY, "legacyThreshold"),
      rd(HOOK, HOOK_LEGACY, "legacyBps"),
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
      thresholdEth: Number(threshold) / 1e18,
      bufferPct: threshold > 0n ? Math.min(100, (Number(buffer) / Number(threshold)) * 100) : 0,
      legacyBps: Number(bps),
      past,
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
  return c.json({ swaps: rows.map((r) => ({ price: r.price, amountEth: r.amountEth, isBuy: r.isBuy, t: Number(r.timestamp), o: Number(r.orderKey), tx: r.txHash })) });
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
      ethSharePrice: eSh > 0n ? n(aEth) / n(eSh) : 1, tokSharePrice: tSh > 0n ? n(aTok) / n(tSh) : 1,
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
app.get("/collection-floors", async (c) => {
  const rows = await db.select().from(schema.collectionFloor)
    .orderBy(desc(schema.collectionFloor.id)).limit(200);
  const recent = await db.select().from(schema.collectionFloorEvent)
    .orderBy(desc(schema.collectionFloorEvent.ts)).limit(100);
  return c.json({
    floors: rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, s(v)]))),
    events: recent.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, s(v)]))),
  });
});

// Proposer flywheel leaderboard (fee earned per iteration proposer).
app.get("/proposers", async (c) => {
  const rows = await db.select().from(schema.proposerEarning)
    .orderBy(desc(schema.proposerEarning.totalEarned)).limit(100);
  return c.json({ proposers: rows.map((r) => ({
    proposer: r.id, totalEarned: s(r.totalEarned), payoutCount: r.payoutCount,
  })) });
});

export default app;
