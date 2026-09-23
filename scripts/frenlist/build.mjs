#!/usr/bin/env node
/**
 * Build the frenlist root and proofs from scripts/frenlist/frenlist.json.
 *
 *   frenlist.json   { "0xWallet": allowance, … }   — the one list the setter edits.
 *                   Allowances are CUMULATIVE totals: to give a wallet one more,
 *                   raise its number; never reset it to "what's left".
 *
 *   node scripts/frenlist/build.mjs
 *
 * Writes public/frenlist/<root>.json and prints the setDiscountRoot call.
 * The file is named after its root because the app reads the root from the
 * chain and fetches exactly that file — so deploy the site with the new file
 * BEFORE publishing the root, or wallets will not see their allowance.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { getAddress, isAddress } from "viem";
import { buildTree, verifyProof } from "./merkle.mjs";

const LIST = new URL("./frenlist.json", import.meta.url);
const OUT = "public/frenlist";

const raw = JSON.parse(await readFile(LIST, "utf8"));
const entries = Object.entries(raw).map(([wallet, allowance]) => {
  if (!isAddress(wallet)) throw new Error(`not an address (or bad checksum): ${wallet}`);
  if (!Number.isInteger(allowance) || allowance <= 0) throw new Error(`bad allowance for ${wallet}: ${allowance}`);
  return { wallet: getAddress(wallet), allowance: BigInt(allowance) };
});
const seen = new Set();
for (const e of entries) {
  if (seen.has(e.wallet)) throw new Error(`listed twice (different case?): ${e.wallet}`);
  seen.add(e.wallet);
}

const { root, items } = buildTree(entries);
const allowances = {};
for (const it of items) {
  if (!verifyProof(it.proof, root, it.leaf)) throw new Error(`proof self-check failed: ${it.wallet}`);
  allowances[it.wallet.toLowerCase()] = { allowance: Number(it.allowance), proof: it.proof };
}

await mkdir(OUT, { recursive: true });
const file = `${OUT}/${root}.json`;
await writeFile(file, `${JSON.stringify({ root, builtAt: new Date().toISOString(), allowances }, null, 2)}\n`);
console.log(`${items.length} wallets, ${items.reduce((n, i) => n + Number(i.allowance), 0)} frenlist mints`);
console.log(`wrote ${file}`);
console.log(`1. deploy the site with that file`);
console.log(`2. cast send <MiFrensGenesis> "setDiscountRoot(bytes32)" ${root}`);
