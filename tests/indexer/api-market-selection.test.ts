import { beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { apiRows } from "./mocks/api";

const ZERO = "0x0000000000000000000000000000000000000000";
const USDG = "0x2000000000000000000000000000000000000000";
const TOKEN1 = "0xf000000000000000000000000000000000000001";
const TOKEN2 = "0xf000000000000000000000000000000000000002";
const quoteByGeneration = new Map<bigint, string>();
const readCalls: any[] = [];
let failQuoteGeneration: bigint | null = null;

vi.mock("ponder", () => ({
  eq: (column: unknown, value: unknown) => ({ op: "eq", column, value }),
  gte: (column: unknown, value: unknown) => ({ op: "gte", column, value }),
  ne: (column: unknown, value: unknown) => ({ op: "ne", column, value }),
  and: (...args: unknown[]) => ({ op: "and", args }),
  desc: (column: unknown) => ({ direction: "desc", column }),
  graphql: () => async (_c: unknown, next: () => Promise<void>) => next(),
}));

vi.mock("viem", async (importOriginal) => {
  const actual = await importOriginal<typeof import("viem")>();
  return {
    ...actual,
    http: () => ({}), fallback: () => ({}),
    createPublicClient: () => ({
      async readContract(args: any) {
        readCalls.push(args);
        if (args.functionName === "generationQuote") {
          const gen = args.args[0] as bigint;
          if (failQuoteGeneration === gen) throw new Error("transient quote RPC");
          return quoteByGeneration.get(gen);
        }
        if (args.functionName === "isDead") return false;
        throw new Error(`unexpected read ${args.functionName}`);
      },
    }),
  };
});

let selectGenerationMarket: any;
const poolRow = (id: string, generation: number, token: string, quote: string, isPrimary: boolean, volumeEth: number) => ({
  id, generation, token, quote, quoteDecimals: quote === ZERO ? 18 : 6, isPrimary,
  name: `Gen ${generation}`, symbol: `G${generation}`, dead: false, lastPrice: generation,
  volumeEth, swapCount: generation, createdAt: 1n, createdBlock: 1n, updatedAt: 1n,
});

beforeAll(async () => { selectGenerationMarket = (await import("../../indexer/src/api/index.ts")).selectGenerationMarket; });
beforeEach(() => {
  apiRows.clear(); quoteByGeneration.clear(); readCalls.length = 0; failQuoteGeneration = null;
  apiRows.set("collection", []); apiRows.set("candle", []); apiRows.set("swap", []);
});

describe("API generation market selection", () => {
  test("selects authoritative quote while retaining the distinct launch primary", async () => {
    const launch = poolRow(`0x${"11".repeat(32)}`, 1, TOKEN1, ZERO, true, 20);
    const rotated = poolRow(`0x${"12".repeat(32)}`, 1, TOKEN1, USDG, false, 3);
    const selected = await selectGenerationMarket([launch, rotated], 1, async () => USDG);
    expect(selected).toMatchObject({ market: rotated, launch, quote: USDG });
  });

  test("follows native to ERC20 to native while historical generations stay independent", async () => {
    const g1 = poolRow(`0x${"21".repeat(32)}`, 1, TOKEN1, ZERO, true, 1);
    const g2Launch = poolRow(`0x${"22".repeat(32)}`, 2, TOKEN2, ZERO, true, 2);
    const g2Usd = poolRow(`0x${"23".repeat(32)}`, 2, TOKEN2, USDG, false, 3);
    const reversed = [g2Launch, g1, g2Usd];
    expect((await selectGenerationMarket(reversed.filter((p) => p.generation === 1), 1, async () => ZERO)).market.id).toBe(g1.id);
    expect((await selectGenerationMarket(reversed.filter((p) => p.generation === 2), 2, async () => ZERO)).market).toMatchObject({ id: g2Launch.id, quoteDecimals: 18 });
    expect((await selectGenerationMarket(reversed.filter((p) => p.generation === 2), 2, async () => USDG)).market).toMatchObject({ id: g2Usd.id, quoteDecimals: 6 });
    expect((await selectGenerationMarket(reversed.filter((p) => p.generation === 2), 2, async () => ZERO)).market).toMatchObject({ id: g2Launch.id, quoteDecimals: 18 });
  });

  test("explicitly reports missing quote market and quote RPC failure", async () => {
    const launch = poolRow(`0x${"31".repeat(32)}`, 1, TOKEN1, ZERO, true, 1);
    expect(await selectGenerationMarket([launch], 1, async () => USDG))
      .toMatchObject({ unavailable: true, reason: "missing-market", quote: USDG });
    expect(await selectGenerationMarket([launch], 1, async () => { throw new Error("transient quote RPC"); }))
      .toMatchObject({ unavailable: true, reason: "quote-rpc", quote: null });
  });
});
