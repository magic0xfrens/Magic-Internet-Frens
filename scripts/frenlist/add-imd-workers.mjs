#!/usr/bin/env node
/**
 * Add Identity.md workers who EARNED a frenlist spot.
 *
 * Earning = a submission ACCEPTED on one of the IMD jobs we posted. Each IMD
 * NFT that earned adds +1 to its current owner's allowance in frenlist.json
 * (owner read from Ethereum mainnet, not IMD's API). A wallet with three
 * earning IMD NFTs ends up with three.
 *
 * ONE PER IMD NFT, EVER: every grant is recorded in imd-grants.json by IMD
 * token id, and a token id already there is skipped — so passing an IMD NFT to
 * another wallet and working again never earns a second spot.
 *
 *   node scripts/frenlist/add-imd-workers.mjs <imd job id> [<imd job id> …]
 *   then: node scripts/frenlist/build.mjs
 *
 * Commit both JSON files: together they are the auditable record of who got
 * what and why (every grant points at a public job and submission on api.imd.fun).
 */
import { readFile, writeFile } from "node:fs/promises";
import { createPublicClient, getAddress, http } from "viem";
import { mainnet } from "viem/chains";

const IMD_API = "https://api.imd.fun";
const IMD_COLLECTION = "0x0000ec93127baa929e58e97dd0095a2bfb38ec1d"; // identity.md (IDMD), mainnet
const LIST = new URL("./frenlist.json", import.meta.url);
const GRANTS = new URL("./imd-grants.json", import.meta.url);
const DRY_RUN = process.argv.includes("--dry-run");

const jobIds = process.argv.slice(2).filter((a) => !a.startsWith("--"));
if (jobIds.length === 0) throw new Error("usage: add-imd-workers.mjs <imd job id> … [--dry-run]");

const list = JSON.parse(await readFile(LIST, "utf8"));
const grants = JSON.parse(await readFile(GRANTS, "utf8"));

// 1. IMD NFTs with an accepted submission on these jobs, not granted before.
const earned = new Map();
for (const jobId of jobIds) {
  const res = await fetch(`${IMD_API}/jobs/${jobId}/submissions`, { signal: AbortSignal.timeout(15_000) });
  if (!res.ok) throw new Error(`job ${jobId}: HTTP ${res.status}`);
  const { submissions = [] } = await res.json();
  for (const s of submissions) {
    const tokenId = s.seat?.tokenId;
    if (s.accepted !== true || tokenId === undefined) continue;
    if (grants[tokenId] || earned.has(tokenId)) continue;
    earned.set(tokenId, { jobId, submission: s.hash });
  }
}
if (earned.size === 0) {
  console.log("no newly earning IMD NFTs");
  process.exit(0);
}

// 2. Who holds each one now, on mainnet.
const client = createPublicClient({ chain: mainnet, transport: http(process.env.MAINNET_RPC ?? "https://ethereum-rpc.publicnode.com") });
const ids = [...earned.keys()];
const owners = await client.multicall({
  allowFailure: true,
  contracts: ids.map((id) => ({
    address: IMD_COLLECTION,
    abi: [{ type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] }],
    functionName: "ownerOf",
    args: [BigInt(id)],
  })),
});

// 3. +1 per IMD NFT, recorded so it can never count again.
const byLower = new Map(Object.keys(list).map((k) => [k.toLowerCase(), k]));
ids.forEach((id, i) => {
  if (owners[i].status !== "success") return console.warn(`IMD #${id}: ownerOf failed — skipped, retry later`);
  const wallet = getAddress(owners[i].result);
  const key = byLower.get(wallet.toLowerCase()) ?? wallet;
  byLower.set(wallet.toLowerCase(), key);
  list[key] = (list[key] ?? 0) + 1;
  grants[id] = { wallet, ...earned.get(id), grantedAt: new Date().toISOString() };
  console.log(`IMD #${id} -> ${wallet} (now ${list[key]})`);
});

if (DRY_RUN) {
  console.log("dry run — nothing written");
} else {
  await writeFile(LIST, `${JSON.stringify(list, null, 2)}\n`);
  await writeFile(GRANTS, `${JSON.stringify(grants, null, 2)}\n`);
  console.log("updated frenlist.json and imd-grants.json — now run build.mjs");
}
