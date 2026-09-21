import test from "node:test";
import assert from "node:assert/strict";

import {
  isIdleRotationAllowance,
  routeForRotationLeg,
} from "../src/lib/treasuryRotation.ts";

const ETH = "0x0000000000000000000000000000000000000000";
const USDG = "0x1111111111111111111111111111111111111111";
const ALT = "0x2222222222222222222222222222222222222222";

test("native destination with remaining allowance is active", () => {
  assert.equal(isIdleRotationAllowance([ETH, 2500]), false);
});

test("empty or expired allowance is idle regardless of zero quote", () => {
  // allowance() represents both absent and expired envelopes as (address(0), 0).
  assert.equal(isIdleRotationAllowance([ETH, 0]), true);
  assert.equal(isIdleRotationAllowance([USDG, 0]), true);
});

test("residual launch leg routes by its asset after generation requote", () => {
  // Generation denomination is now USDG, but leg 0 remains the launch ETH pair.
  // The helper intentionally has no generation-wide quote input to confuse them.
  const route = routeForRotationLeg(
    [{ index: 0, quote: ETH }, { index: 1, quote: USDG }],
    0,
    USDG,
    ETH,
  );
  assert.deepEqual(route, {
    currency0: ETH,
    currency1: USDG,
    fee: 3000,
    tickSpacing: 60,
    hooks: ETH,
  });
});

test("foreign secondary leg routes from the selected index", () => {
  const route = routeForRotationLeg(
    [{ index: 0, quote: ETH }, { index: 7, quote: ALT }],
    7,
    USDG,
    ETH,
  );
  assert.equal(route?.currency0, USDG);
  assert.equal(route?.currency1, ALT);
});

test("native destination is a valid route endpoint", () => {
  const route = routeForRotationLeg([{ index: 4, quote: USDG }], 4, ETH, ETH);
  assert.equal(route?.currency0, ETH);
  assert.equal(route?.currency1, USDG);
});

test("self-route and disappeared source leg fail closed", () => {
  const legs = [{ index: 3, quote: USDG }];
  assert.equal(routeForRotationLeg(legs, 3, USDG, ETH), null);
  assert.equal(routeForRotationLeg(legs, 99, ETH, ETH), null);
});
