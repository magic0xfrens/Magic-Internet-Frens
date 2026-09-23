/**
 * The frenlist tree, checked against the contract's encoding.
 *
 * Run: `node --test scripts/frenlist/test-merkle.mjs`
 *
 * The pinned root and proofs are also hardcoded in
 * contracts/solidity/test/GenesisDiscountMint.t.sol, where they are spent
 * through the real `mintDiscounted`. If the leaf encoding or pair hashing
 * drifts on either side, one of the two tests fails.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { getAddress } from "viem";

import { buildTree, leafHash, verifyProof } from "./merkle.mjs";

const beef = getAddress("0x000000000000000000000000000000000000beef");
const cafe = getAddress("0x000000000000000000000000000000000000cafe");
const dead = getAddress("0x000000000000000000000000000000000000dead");
const FIXTURE = [
  { wallet: beef, allowance: 2n },
  { wallet: cafe, allowance: 3n },
  { wallet: dead, allowance: 1n },
];
const PINNED_ROOT = "0xbbd259d9a434955807656444a51c8fccf081a20f8f8382e431b24fb515db4e3c";

test("the fixture builds the root the Solidity test spends against", () => {
  assert.equal(buildTree(FIXTURE).root, PINNED_ROOT);
});

test("input order does not change the root", () => {
  assert.equal(buildTree([...FIXTURE].reverse()).root, PINNED_ROOT);
});

test("every proof verifies, and only for its own wallet and allowance", () => {
  const { root, items } = buildTree(FIXTURE);
  for (const it of items) assert.ok(verifyProof(it.proof, root, it.leaf));
  const beefItem = items.find((i) => i.wallet === beef);
  assert.ok(!verifyProof(beefItem.proof, root, leafHash(beef, 5n)), "an inflated allowance fails");
  assert.ok(!verifyProof(beefItem.proof, root, leafHash(dead, 2n)), "another wallet fails");
});

test("raising one allowance changes the root", () => {
  assert.notEqual(buildTree([{ wallet: beef, allowance: 3n }, ...FIXTURE.slice(1)]).root, PINNED_ROOT);
});

test("a single-wallet list is its own root with an empty proof", () => {
  const { root, items } = buildTree([FIXTURE[0]]);
  assert.equal(root, leafHash(beef, 2n));
  assert.deepEqual(items[0].proof, []);
});
