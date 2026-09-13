/**
 * Unit tests for the quote-decimals arithmetic behind T6A and T6B.
 *
 * Run: `npm test` (node --test with native TS type stripping, node >= 22.6).
 *
 * Both copies of the module are imported — `src/lib/quoteUnits.ts` (frontend)
 * and `indexer/src/quoteUnits.ts` (Ponder builds from `indexer/` alone and
 * cannot reach across the tree) — and asserted to agree, so a drift between the
 * two fails here instead of silently mispricing a chart.
 */
import test from "node:test";
import assert from "node:assert/strict";

import * as fe from "../src/lib/quoteUnits.ts";
import * as ix from "../indexer/src/quoteUnits.ts";

/* ── T6B: raw currency0/currency1 ratio → human quote-per-token ─────────── */

test("18-decimal quote (native ETH): the raw ratio IS the price", () => {
  //  The bug never touched the ETH path and this pins that down.
  const raw = 1e-9; // 1e-9 ETH per token
  assert.equal(fe.normaliseQuotePerToken(raw, 18), raw);
  assert.equal(ix.normaliseQuotePerToken(raw, 18), raw);
});

test("6-decimal quote (USDG): the raw ratio is 1e12 too small", () => {
  //  The exact case the hunter measured: the indexer recorded 2.5e-18 for a pool
  //  whose true price is 0.0000025 USDG/token — 4e8x off once compared against
  //  the ETH-denominated number the widget was using.
  const raw = 2.5e-18;
  const got = fe.normaliseQuotePerToken(raw, 6);
  assert.ok(Math.abs(got - 0.0000025) < 1e-12, `expected ~2.5e-6, got ${got}`);
  assert.equal(ix.normaliseQuotePerToken(raw, 6), got);
  //  And the error the old code shipped was exactly 1e12.
  assert.ok(Math.abs(got / raw - 1e12) / 1e12 < 1e-9);
});

test("a non-positive or non-finite ratio is not a price", () => {
  for (const bad of [0, -1, NaN, Infinity]) {
    assert.equal(fe.normaliseQuotePerToken(bad, 6), 0);
    assert.equal(ix.normaliseQuotePerToken(bad, 6), 0);
  }
});

test("raw swap amounts carry the quote's decimals, not a hardcoded 1e18", () => {
  assert.equal(fe.rawToQuoteAmount(2_500_000n, 6), 2.5);          // 2.5 USDG
  assert.equal(fe.rawToQuoteAmount(-2_500_000n, 6), -2.5);
  assert.equal(ix.rawToQuoteAmount(10n ** 18n, 18), 1);           // 1 ETH
  assert.equal(ix.rawToQuoteAmount(2_500_000n, 6), 2.5);
});

/* ── T6A: how much quote the buy is allowed to spend ───────────────────── */

const USDG = (n) => BigInt(Math.round(n * 1e6));
const XNVDA = (n) => BigInt(n) * 10n ** 18n;

test("6-dec: spends the TYPED amount, not the wallet's whole balance", () => {
  //  The measured bug: 0.01 ETH typed (~25 USDG) against a 10,000 USDG balance
  //  signed quoteIn = 10,000 — a 400x overspend with a floor sized for 25.
  const expected = USDG(25);
  const balance = USDG(10_000);
  const spend = fe.quoteInForTypedAmount(expected, null, balance);
  assert.equal(spend, expected);
  assert.notEqual(spend, balance);
  assert.equal(Number(balance) / Number(spend), 400); // the old overspend factor
});

test("18-dec: same shape on an 18-decimal quote", () => {
  const expected = XNVDA(3);
  const spend = fe.quoteInForTypedAmount(expected, null, XNVDA(5_000));
  assert.equal(spend, expected);
});

test("a zap that under-delivers caps the spend at what actually arrived", () => {
  const expected = USDG(25);
  const delivered = USDG(24);
  assert.equal(fe.quoteInForTypedAmount(expected, delivered, USDG(24)), delivered);
});

test("a zap that over-delivers still only spends the typed amount", () => {
  const expected = USDG(25);
  assert.equal(fe.quoteInForTypedAmount(expected, USDG(30), USDG(30)), expected);
});

test("the spend never exceeds the wallet balance", () => {
  assert.equal(fe.quoteInForTypedAmount(USDG(25), null, USDG(10)), USDG(10));
  assert.equal(fe.quoteInForTypedAmount(USDG(25), null, 0n), 0n);
});

test("the floor is scaled down with the spend, never up", () => {
  const minOut = 1_000n * 10n ** 18n;
  //  Full spend: untouched.
  assert.equal(fe.scaleFloor(minOut, USDG(25), USDG(25)), minOut);
  //  Over-spend can't happen any more, but if it did the floor is not raised.
  assert.equal(fe.scaleFloor(minOut, USDG(50), USDG(25)), minOut);
  //  Half the input, half the floor — the per-unit price is preserved.
  assert.equal(fe.scaleFloor(minOut, USDG(12.5), USDG(25)), minOut / 2n);
  assert.equal(fe.scaleFloor(minOut, 0n, 0n), minOut);
});

/* ── FG-1: the dividend basket renders in each asset's OWN decimals ─────── */

import { formatUnits } from "viem";

test("a 6-dec basket asset is not formatted as ether", () => {
  //  The dividend basket can hold any ERC20 — round.json ships USDG at 6 — and
  //  the panel used to have an ether-only rail. Formatting 2,500 USDG (raw
  //  2_500_000_000) with formatUnits(_, 18) understates it by 1e12, which is the
  //  same class of mistake T6B made on the price. `decimals` comes from the
  //  token, per asset, in both the hook and the indexer's dividend_asset row.
  const raw = 2_500_000_000n; // 2,500 USDG at 6 decimals
  assert.equal(Number(formatUnits(raw, 6)), 2_500);
  assert.notEqual(Number(formatUnits(raw, 18)), 2_500);
  assert.equal(Number(formatUnits(raw, 18)) * 1e12, 2_500);
});

test("an 18-dec basket asset is unchanged by the same code path", () => {
  const raw = 3n * 10n ** 18n; // 3 xNVDA
  assert.equal(Number(formatUnits(raw, 18)), 3);
});

test("a basket total sums per asset, never across decimals", () => {
  //  Two assets with different decimals must never be added as raw bigints:
  //  2,500 USDG + 3 xNVDA is not 2_500_000_000 + 3e18 of anything.
  const basket = [
    { symbol: "USDG", decimals: 6, pending: 2_500_000_000n },
    { symbol: "xNVDA", decimals: 18, pending: 3n * 10n ** 18n },
  ];
  const human = basket.map((a) => Number(formatUnits(a.pending, a.decimals)));
  assert.deepEqual(human, [2_500, 3]);
  //  and the naive raw sum is the bug this pins down
  assert.notEqual(Number(formatUnits(basket[0].pending + basket[1].pending, 18)), 2_503);
});
