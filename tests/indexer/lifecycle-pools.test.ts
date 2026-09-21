import { beforeAll, beforeEach, describe, expect, test } from "vitest";
import { handlers } from "./mocks/registry";
import * as schema from "./mocks/schema";

type Table = { name: string };
type Row = Record<string, any>;

const ETH = "0x0000000000000000000000000000000000000000";
const TOKEN1 = "0xf000000000000000000000000000000000000001";
const TOKEN2 = "0xf000000000000000000000000000000000000002";
const USDG = "0x2000000000000000000000000000000000000000";
const HOOK = "0x3000000000000000000000000000000000000000";
const PRIMARY1 = `0x${"11".repeat(32)}`;
const PRIMARY2 = `0x${"22".repeat(32)}`;
const FOREIGN = `0x${"ff".repeat(32)}`;

const stores = new Map<string, Map<any, Row>>();
const store = (t: Table) => {
  if (!stores.has(t.name)) stores.set(t.name, new Map());
  return stores.get(t.name)!;
};

const db = {
  async find(t: Table, key: { id: any }) { return store(t).get(key.id) ?? null; },
  insert(t: Table) {
    return { values(value: Row) {
      const operation = {
        async onConflictDoNothing() {
          if (!store(t).has(value.id)) store(t).set(value.id, { ...value });
        },
        async onConflictDoUpdate(update: ((row: Row) => Row) | (() => Row)) {
          const current = store(t).get(value.id);
          store(t).set(value.id, current ? { ...current, ...update(current) } : { ...value });
        },
        then(resolve: (value?: unknown) => unknown, reject: (reason?: unknown) => unknown) {
          if (!store(t).has(value.id)) store(t).set(value.id, { ...value });
          return Promise.resolve().then(resolve, reject);
        },
      };
      return operation;
    }};
  },
  update(t: Table, key: { id: any }) {
    return { async set(update: Row | ((row: Row) => Row)) {
      const current = store(t).get(key.id);
      if (!current) throw new Error(`missing ${t.name}:${key.id}`);
      store(t).set(key.id, { ...current, ...(typeof update === "function" ? update(current) : update) });
    }};
  },
};

let currentGeneration = 1n;
let currentToken = TOKEN1;
let currentPrimary = PRIMARY1;
let failCurrentGeneration = false;
let failDecimals = false;
const positions = new Map<bigint, readonly [Row, bigint]>();
const primaryKeys = new Map<bigint, readonly [string, string, number, number, string]>();
const generationTokens = new Map<bigint, string>();

const client = {
  async readContract(args: Row): Promise<any> {
    if (args.functionName === "currentGeneration") {
      if (failCurrentGeneration) { failCurrentGeneration = false; throw new Error("transient RPC"); }
      return currentGeneration;
    }
    if (args.functionName === "currentToken") return currentToken;
    if (args.functionName === "generationToken") return generationTokens.get(args.args[0])!;
    if (args.functionName === "generationPoolId") return currentPrimary;
    if (args.functionName === "generationPoolKey") return primaryKeys.get(args.args[0])!;
    if (args.functionName === "getCreatureForGeneration") return [`Fren ${args.args[0]}`, `F${args.args[0]}`];
    if (args.functionName === "getPoolAndPositionInfo") return positions.get(args.args[0])!;
    if (args.functionName === "decimals") {
      if (failDecimals) { failDecimals = false; throw new Error("metadata unavailable"); }
      return 6;
    }
    throw new Error(`unexpected read ${args.functionName}`);
  },
};

const context = { db, client };
const meta = (block: bigint, logIndex = 0) => ({
  block: { number: block, timestamp: block * 12n },
  transaction: { hash: `0x${block.toString(16).padStart(64, "0")}` },
  log: { logIndex },
});
const call = async (name: string, event: Row) => {
  const handler = handlers.get(name);
  if (!handler) throw new Error(`missing registered handler ${name}`);
  await handler({ event, context });
};
const swapEvent = (id: string, block: bigint) => ({
  ...meta(block),
  args: { id, sender: TOKEN2, sqrtPriceX96: 2n ** 96n, amount0: -1_000_000n },
});

beforeAll(async () => { await import("../../indexer/src/index.ts"); });
beforeEach(() => {
  stores.clear(); positions.clear(); primaryKeys.clear(); generationTokens.clear();
  currentGeneration = 1n; currentToken = TOKEN1; currentPrimary = PRIMARY1;
  failCurrentGeneration = false;
  failDecimals = false;
  primaryKeys.set(1n, [ETH, TOKEN1, 0, 200, HOOK]);
  generationTokens.set(1n, TOKEN1);
});

describe("lifecycle pool discovery", () => {
  test("indexes an authenticated rotation leg and its swaps, preserving relaunch history", async () => {
    await call("CauldronRegistry:CauldronSummoned", {
      ...meta(10n), args: { generation: 1n, token: TOKEN1, poolId: PRIMARY1, name: "First", symbol: "ONE" },
    });
    const legKey = { currency0: USDG, currency1: TOKEN1, fee: 0, tickSpacing: 200, hooks: HOOK };
    positions.set(77n, [legKey, 0n]);
    await call("RotationExec:LegOpened", { ...meta(11n), args: { gen: 1n, quote: USDG, positionId: 77n } });

    const legs = [...store(schema.pool).values()].filter((row) => !row.isPrimary);
    expect(legs).toHaveLength(1);
    expect(legs[0]).toMatchObject({ generation: 1, token: TOKEN1.toLowerCase(), quote: USDG.toLowerCase(), quoteDecimals: 6 });
    await call("PoolManager:Swap", swapEvent(legs[0].id, 12n));
    expect(store(schema.swap).size).toBe(1);
    expect(store(schema.candle).size).toBe(1);

    currentGeneration = 2n; currentToken = TOKEN2; currentPrimary = PRIMARY2;
    primaryKeys.set(2n, [ETH, TOKEN2, 0, 200, HOOK]);
    generationTokens.set(2n, TOKEN2);
    await call("CauldronRegistry:CauldronReborn", {
      ...meta(20n), args: { generation: 2n, token: TOKEN2, poolId: PRIMARY2, name: "Second", symbol: "TWO" },
    });
    expect(store(schema.pool).get(PRIMARY1)?.quote).toBe(ETH);
    expect(store(schema.pool).get(legs[0].id)?.quote).toBe(USDG.toLowerCase());
    expect(store(schema.pool).get(PRIMARY2)).toMatchObject({ generation: 2, isPrimary: true, quote: ETH });
  });

  test("rejects unrelated pools without permanently caching transient RPC failure", async () => {
    failCurrentGeneration = true;
    await expect(call("PoolManager:Swap", swapEvent(PRIMARY1, 30n))).rejects.toThrow("transient RPC");
    expect(store(schema.swap).size).toBe(0);
    await call("PoolManager:Swap", swapEvent(PRIMARY1, 31n));
    expect(store(schema.swap).size).toBe(1);
    await call("PoolManager:Swap", swapEvent(FOREIGN, 32n));
    expect(store(schema.swap).size).toBe(1);
    expect(store(schema.pool).has(FOREIGN)).toBe(false);
  });

  test("does not persist an ERC20 rotation pool with guessed native metadata", async () => {
    const legKey = { currency0: USDG, currency1: TOKEN1, fee: 0, tickSpacing: 200, hooks: HOOK };
    positions.set(88n, [legKey, 0n]);
    const event = { ...meta(40n), args: { gen: 1n, quote: USDG, positionId: 88n } };
    failDecimals = true;
    await expect(call("RotationExec:LegOpened", event)).rejects.toThrow("metadata unavailable");
    expect([...store(schema.pool).values()].some((row) => row.quote === USDG.toLowerCase())).toBe(false);
    await call("RotationExec:LegOpened", event);
    expect([...store(schema.pool).values()].find((row) => row.quote === USDG.toLowerCase()))
      .toMatchObject({ quoteDecimals: 6, isPrimary: false });
  });

  test("derives repeated same-block legs after the earlier position is burned", async () => {
    // Ponder's event-pinned call observes end-of-block state. The first NFT was
    // burned/replaced later in this block, so PositionManager has cleared it.
    positions.set(70n, [{ currency0: ETH, currency1: ETH, fee: 0, tickSpacing: 0, hooks: ETH }, 0n]);
    positions.set(71n, [{ currency0: USDG, currency1: TOKEN1, fee: 0, tickSpacing: 200, hooks: HOOK }, 0n]);
    const first = { ...meta(50n, 1), args: { gen: 1n, quote: USDG, positionId: 70n } };
    const replacement = { ...meta(50n, 3), args: { gen: 1n, quote: USDG, positionId: 71n } };

    await call("RotationExec:LegOpened", first);
    const leg = [...store(schema.pool).values()].find((row) => !row.isPrimary)!;
    expect(leg).toMatchObject({ generation: 1, token: TOKEN1.toLowerCase(), quote: USDG.toLowerCase() });
    await call("PoolManager:Swap", swapEvent(leg.id, 50n));
    await call("RotationExec:LegOpened", replacement);

    expect([...store(schema.pool).values()].filter((row) => !row.isPrimary)).toHaveLength(1);
    expect(store(schema.pool).get(leg.id)?.swapCount).toBe(1);
    expect(store(schema.swap).size).toBe(1);

    currentGeneration = 2n; currentToken = TOKEN2; currentPrimary = PRIMARY2;
    primaryKeys.set(2n, [ETH, TOKEN2, 0, 200, HOOK]);
    generationTokens.set(2n, TOKEN2);
    await call("CauldronRegistry:CauldronReborn", {
      ...meta(51n), args: { generation: 2n, token: TOKEN2, poolId: PRIMARY2, name: "Second", symbol: "TWO" },
    });
    expect(store(schema.pool).get(leg.id)).toMatchObject({ generation: 1, swapCount: 1, quote: USDG.toLowerCase() });
    expect(store(schema.pool).get(PRIMARY2)).toMatchObject({ generation: 2, token: TOKEN2.toLowerCase(), isPrimary: true });
  });
});
