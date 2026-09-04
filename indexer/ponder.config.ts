import { createConfig, factory } from "ponder";
import { parseAbiItem } from "viem";
import { PoolManagerAbi } from "./abis/PoolManagerAbi";
import { RegistryAbi } from "./abis/RegistryAbi";
import { CollectionAbi } from "./abis/CollectionAbi";
import { HookGachaAbi, RegistryCollAbi, GovernorAbi } from "./abis/GachaGovAbi";
import { DividendAbi } from "./abis/DividendAbi";

// round-14 (fixed GnomeRenderer, art cap 2222). Addresses are HARDCODED (not env)
// on purpose: stale Railway env vars from a previous round were silently
// overriding the defaults and pinning the indexer to a dead deploy. Bump these +
// DATABASE_SCHEMA (railway.json) each round to force a clean reindex.
const chainId = Number(process.env.CHAIN_ID ?? 11155111);
const startBlock = 11581000; // launchpad deploy block

const REGISTRY = "0x65Dd9Ba0eB1dA5C7CBcDA01d3d9218e804C7a54c" as `0x${string}`;
const POOL_MANAGER = "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543" as `0x${string}`;
const PRESALE = "0x4D180c050978F0037d030BaC455c3cfA70aAA8e1" as `0x${string}`;
const HOOK = "0x82FC4A9da3B9953b6BCF67Fb29F644C59d4bd0CC" as `0x${string}`;
const GOVERNOR = "0xf9730985C55D3deB26f070b45A65CD96F0E36D0E" as `0x${string}`;
const DIVIDEND = "0x96Bd816C9A5089b453BF7C56fBA716D4a6Cc32A2" as `0x${string}`;

export default createConfig({
  database: process.env.DATABASE_URL
    ? { kind: "postgres", connectionString: process.env.DATABASE_URL }
    : undefined,

  chains: {
    cauldron: {
      id: chainId,
      rpc: process.env.PONDER_RPC_URL ?? "https://ethereum-sepolia-rpc.publicnode.com",
      pollingInterval: Number(process.env.POLLING_INTERVAL_MS ?? 4000),
    },
  },

  contracts: {
    CauldronRegistry: { chain: "cauldron", abi: RegistryAbi, address: REGISTRY, startBlock },
    RegistryColl: { chain: "cauldron", abi: RegistryCollAbi, address: REGISTRY, startBlock },
    PoolManager: { chain: "cauldron", abi: PoolManagerAbi, address: POOL_MANAGER, startBlock },
    Governor: { chain: "cauldron", abi: GovernorAbi, address: GOVERNOR, startBlock },
    Hook: { chain: "cauldron", abi: HookGachaAbi, address: HOOK, startBlock },
    Dividend: { chain: "cauldron", abi: DividendAbi, address: DIVIDEND, startBlock },
    // Genesis / iter-#2 MiFrens collection (fixed address).
    Presale: { chain: "cauldron", abi: CollectionAbi, address: PRESALE, startBlock },
    // Every per-iteration collection, discovered from the registry's
    // CollectionDeployed event (Ponder factory pattern) → one handler set covers
    // Gnomeland, Frog Nation, and every future brew automatically.
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
