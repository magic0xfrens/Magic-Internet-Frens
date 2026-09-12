import { createConfig, factory } from "ponder";
import { parseAbiItem } from "viem";
import { PoolManagerAbi } from "./abis/PoolManagerAbi";
import { RegistryAbi } from "./abis/RegistryAbi";
import { CollectionAbi } from "./abis/CollectionAbi";
import { HookGachaAbi, RegistryCollAbi, GovernorAbi } from "./abis/GachaGovAbi";
import { DividendAbi } from "./abis/DividendAbi";
import { PerpEngineAbi } from "./abis/PerpEngineAbi";
import { RegistryFloorAbi, HookFloorAbi } from "./abis/FloorAbi";
import { SeederAbi } from "./abis/SeederAbi";
import { TreasuryGovAbi, RotationExecAbi, Erc721TransferAbi } from "./abis/TreasuryGovAbi";

// ── SINGLE SOURCE OF TRUTH ──────────────────────────────────────────────────
// All addresses/blocks/poolIds come from ./deployments/round.json — the SAME
// manifest the frontend reads. NOT from env: stale Railway env vars from a prior
// round silently overrode these and pinned the indexer to a dead deploy (r29
// served as r31). To ship a round: edit round.json, run scripts/deploy-round.mjs.
import round from "./deployments/round.json";

// Deployment identity comes from the manifest ONLY. A CHAIN_ID env var here
// could point this indexer at a different network than the manifest it is
// serving addresses for, which reads as missing data rather than an error.
const chainId = Number(round.chainId);
const startBlock = round.blocks.indexer; // gen-1 pool summon (before the genesis mints)

const REGISTRY = round.contracts.registry as `0x${string}`;
const POSITION_MANAGER = round.contracts.positionManager as `0x${string}`;
const POOL_MANAGER = round.contracts.poolManager as `0x${string}`;
const PRESALE = round.contracts.presale as `0x${string}`;
const HOOK = round.contracts.hook as `0x${string}`;
const GOVERNOR = round.contracts.governor as `0x${string}`;
const DIVIDEND = round.contracts.dividend as `0x${string}`;
const PERP_ENGINE = round.contracts.perpEngine as `0x${string}`;
const PERP_START = round.blocks.indexer;
// Only index Swaps on OUR pool(s) — the PoolManager is shared across every
// Sepolia V4 pool, so without this filter we'd index the whole chain's swaps
// (huge load → timeouts/crashes). The Swap event's `id` is the poolId (indexed),
// so we filter getLogs to just our generation pool(s). Append per gen at relaunch.
const POOL_IDS = round.poolIds as `0x${string}`[];
// The progressive seeder. Absent on an atomic (SEED_WINDOW=0) deployment and on
// any manifest written before the launch feed existed, so it degrades to the zero
// address — registered either way so its event types resolve, yielding no logs.
//  A PLACEHOLDER IS NOT AN ADDRESS, AND `??` DOES NOT CATCH IT.
//  `apply-deployment.mjs` writes `__ASK_CHAIN_COLLECTION__` until the summon
//  creates the collection, and a nullish-coalesce only fires on null/undefined —
//  so the placeholder sailed through and Ponder refused the whole build
//  ("Invalid prefix for address"), taking the indexer down for the entire window
//  between deploying a round and igniting it. That window is exactly when the
//  frontend is being checked.
//
//  Anything that is not a 0x address degrades to the zero address: the
//  subscription registers, yields no logs, and starts working the moment the
//  manifest is refreshed after the summon.
const rawCollection = (round.contracts as Record<string, string>).collection ?? "";
const LIVE_COLLECTION = (/^0x[0-9a-fA-F]{40}$/.test(rawCollection)
  ? rawCollection
  : "0x0000000000000000000000000000000000000000") as `0x${string}`;
const SEEDER = ((round.contracts as Record<string, string>).seeder ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;
// The TREASURY governor — what the LP is denominated in. Distinct from GOVERNOR
// above, which picks the next BREW. Defaults to the zero address on a manifest
// written before rotation existed, so it registers (types resolve) and yields
// no logs rather than failing the whole config.
const TREASURY_GOV = ((round.contracts as Record<string, string>).treasuryGovernor ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export default createConfig({
  database: process.env.DATABASE_URL
    ? { kind: "postgres", connectionString: process.env.DATABASE_URL }
    : undefined,

  chains: {
    cauldron: {
      id: chainId,
      // PONDER_RPC_URL may be a COMMA-SEPARATED list; Ponder load-balances across
      // them. DEFAULT = publicnode. ⚠️ DO NOT use Alchemy FREE keys here: the free
      // tier caps eth_getLogs at a 10-BLOCK range, but Ponder syncs in bigger
      // chunks → RpcRequestError → Ponder shuts down (crash-loop). publicnode has
      // no block-range cap and (with the OUR-pool filter below) syncs to realtime
      // in seconds. Paid Alchemy tiers are fine.
      rpc: (() => {
        // Full public nodes → Ponder fails over on any DNS/network/rate blip
        // instead of crashing (v0.11 treats an RPC error as fatal). ⚠️ NOT Alchemy
        // free keys here — their 10-block eth_getLogs cap breaks Ponder's sync.
        // CHAIN-AWARE default: pick the fallback set from the manifest's chainId so
        // an unset PONDER_RPC_URL can NEVER silently point Sepolia nodes at a
        // Robinhood (4663) manifest — that mismatch = wrong/empty data or a crash.
        const SEPOLIA = [
          "https://ethereum-sepolia-rpc.publicnode.com",
          "https://1rpc.io/sepolia",
          "https://rpc.ankr.com/eth_sepolia",
          "https://sepolia.drpc.org",
          "https://eth-sepolia.public.blastapi.io",
        ];
        const ROBINHOOD = ["https://rpc.chain.robinhood.com"];
        const DEFAULTS = chainId === 4663 ? ROBINHOOD : SEPOLIA;
        const env = (process.env.PONDER_RPC_URL ?? "").split(",").map((s) => s.trim()).filter(Boolean);
        const list = env.length > 0 ? env : DEFAULTS;
        return list.length > 1 ? list : list[0];
      })(),
      // Block polling, matched to the chain's actual block time.
      //
      // Sepolia produces a block roughly every 12s, so polling at 1.5s spends
      // about eight requests to learn nothing seven times. 4s still surfaces a
      // new block within a few seconds of it landing, at a third of the request
      // volume. The Orbit L2 target has sub-second blocks, where fast polling is
      // genuinely useful — so pick from the manifest's chainId rather than
      // running the L2 cadence against an L1 testnet.
      pollingInterval: Number(
        process.env.POLLING_INTERVAL_MS ?? (chainId === 4663 ? 1000 : 4000),
      ),
      // Per-endpoint request cap. With N rotated keys the effective throughput is
      // N × this. Default scales with the number of endpoints provided.
      maxRequestsPerSecond: Number(
        process.env.PONDER_MAX_RPS ??
          12 * Math.max(1, (process.env.PONDER_RPC_URL ?? "").split(",").filter(Boolean).length || 1),
      ),
    },
  },

  contracts: {
    CauldronRegistry: { chain: "cauldron", abi: RegistryAbi, address: REGISTRY, startBlock },
    RegistryColl: { chain: "cauldron", abi: RegistryCollAbi, address: REGISTRY, startBlock },
    // r31: redemption-floor + legacy-collection-floor events on the registry, and
    // the proposer-flywheel payout on the hook.
    RegistryFloor: { chain: "cauldron", abi: RegistryFloorAbi, address: REGISTRY, startBlock },
    HookFloor: { chain: "cauldron", abi: HookFloorAbi, address: HOOK, startBlock },
    PoolManager: (() => {
      //  ── WHY THIS IS NOT PINNED TO A POOL ID ──────────────────────────────
      //  The filter used to be `{ event: "Swap", args: { id: POOL_IDS } }`,
      //  reading the pool ids out of the manifest. That CANNOT work for this
      //  protocol: a pool id is derived from the generation's TOKEN address,
      //  the token is deployed fresh at every summon and every relaunch, and
      //  the manifest is baked into the container at build time. So the id was
      //  always one deploy stale - the indexer would filter Swaps to the
      //  PREVIOUS generation's dead pool and index nothing at all, until
      //  somebody hand-edited round.json and redeployed. That is a manual step
      //  on the protocol's core loop (eternal relaunch), i.e. it would break on
      //  every single rebirth, forever.
      //
      //  Measured before removing it: 88 Swap logs in 2000 Sepolia blocks
      //  across EVERY v4 pool on the chain - 0.04 logs/block, ~13/hour. The
      //  "huge load" the filter was protecting against is not real here. Swaps
      //  that are not ours are discarded by `ensurePool`, which asks the
      //  registry whether the pool id is actually the live generation's before
      //  registering anything (and negative-caches the answer).
      //
      //  STRICT_POOL_FILTER restores the old behaviour for a chain where v4
      //  volume genuinely is heavy; it then pins to the manifest's ids and the
      //  hand-edit-per-relaunch returns with it.
      const strict = process.env.STRICT_POOL_FILTER === "true" && POOL_IDS.length > 0;
      return {
        chain: "cauldron" as const, abi: PoolManagerAbi, address: POOL_MANAGER, startBlock,
        ...(strict ? { filter: { event: "Swap" as const, args: { id: POOL_IDS } } } : {}),
      };
    })(),
    Governor: { chain: "cauldron", abi: GovernorAbi, address: GOVERNOR, startBlock },
    // Treasury rotation: the vote, and the slices it authorises. The vote lives
    // on the treasury governor; the EXECUTION is emitted by RedemptionExt
    // through the registry's own address, so the two need separate entries.
    TreasuryGov: { chain: "cauldron", abi: TreasuryGovAbi, address: TREASURY_GOV, startBlock },
    RotationExec: { chain: "cauldron", abi: RotationExecAbi, address: REGISTRY, startBlock },
    //  POSITION OWNERSHIP. The PositionManager is shared across every Sepolia v4
    //  pool, so this is filtered to transfers involving OUR registry — without
    //  the filter it would index the whole chain's LP NFTs. Two entries because
    //  a position arriving and a position leaving are different filters.
    PosmIn: {
      chain: "cauldron", abi: Erc721TransferAbi, address: POSITION_MANAGER, startBlock,
      filter: { event: "Transfer", args: { to: REGISTRY } },
    },
    PosmOut: {
      chain: "cauldron", abi: Erc721TransferAbi, address: POSITION_MANAGER, startBlock,
      filter: { event: "Transfer", args: { from: REGISTRY } },
    },
    // Launch seeding feed: stream progress + prime-buy tranches, so the frontend
    // reads them from Ponder instead of polling the seeder over public RPC.
    Seeder: { chain: "cauldron", abi: SeederAbi, address: SEEDER, startBlock },
    Hook: { chain: "cauldron", abi: HookGachaAbi, address: HOOK, startBlock },
    Dividend: { chain: "cauldron", abi: DividendAbi, address: DIVIDEND, startBlock },
    // Perp engine — always registered so its event types resolve; the 0x0 default
    // yields no logs until PERP_ENGINE is set to the deployed address.
    PerpEngine: { chain: "cauldron", abi: PerpEngineAbi, address: PERP_ENGINE, startBlock: PERP_START },
    // Genesis / iter-#2 MiFrens collection (fixed address).
    Presale: { chain: "cauldron", abi: CollectionAbi, address: PRESALE, startBlock },
    // Every per-iteration collection, discovered from the registry's
    // CollectionDeployed event (Ponder factory pattern) → one handler set covers
    // Gnomeland, Frog Nation, and every future brew automatically.
    //  THE LIVE COLLECTION, BY ADDRESS. The factory entry below discovers every
    //  per-iteration collection from the registry's CollectionDeployed event, and it
    //  is what covers PAST generations — but it did not index the current one: the
    //  presale (a fixed address) indexed all 1111 frens while the freshly-summoned
    //  collection had zero rows, so "0 sealed" was shown to a wallet holding four
    //  crystals on chain. A fixed-address subscription for the live collection is
    //  belt-and-braces: whatever the factory does or does not discover, the
    //  generation people are actually looking at is always indexed.
    LiveCollection: {
      chain: "cauldron",
      abi: CollectionAbi,
      address: LIVE_COLLECTION,
      startBlock,
    },
    Collection: {
      chain: "cauldron",
      abi: CollectionAbi,
      address: factory({
        address: REGISTRY,
        event: parseAbiItem("event CollectionDeployed(uint256 indexed generation, address collection, uint8 mode)"),
        parameter: "collection",
      }),
      startBlock,
    },
  },
});
