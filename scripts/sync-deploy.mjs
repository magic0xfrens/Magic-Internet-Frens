#!/usr/bin/env node
/**
 * sync-deploy.mjs — propagate deployments/sepolia.json (the SINGLE SOURCE OF
 * TRUTH) to every place that hardcodes addresses, so a new deploy is one edit
 * + one command.
 *
 *   1. edit  deployments/sepolia.json   (paste the new addresses / round)
 *   2. run   node scripts/sync-deploy.mjs
 *
 * It patches, using anchored replacements:
 *   - src/config/cauldron.ts    (CAULDRON.* addresses + deployBlock + supply)
 *   - src/config/perp.ts        (engine + vault + startBlock defaults)
 *   - indexer/ponder.config.ts  (address consts + startBlock + POOL_IDS default)
 *   - scripts/marketmaker.sh    (GACHA/TOKEN/PERP/POOL_ID defaults)
 *   - scripts/keeper.sh         (PERP default)
 *   - .env.local                (VITE_CAULDRON_INDEXER)
 *   - indexer/railway.json      (--schema)
 * and PRINTS the Railway env command to push (so the hosted indexer matches).
 *
 * Idempotent: safe to run repeatedly. Uses regex on stable patterns; if a file
 * drifts it warns instead of silently missing.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const d = JSON.parse(readFileSync(join(ROOT, "deployments/sepolia.json"), "utf8"));

let changed = 0;
const warns = [];

/** Replace with an anchored regex; warn if nothing matched. */
function patch(file, edits) {
  const path = join(ROOT, file);
  if (!existsSync(path)) { warns.push(`skip (missing): ${file}`); return; }
  let src = readFileSync(path, "utf8");
  let hit = 0;
  for (const [re, repl, label] of edits) {
    if (!re.test(src)) { warns.push(`no match in ${file}: ${label}`); continue; }
    const next = src.replace(re, repl);
    if (next !== src) { src = next; hit++; } // else: already at target (no-op, no warn)
  }
  if (hit) { writeFileSync(path, src); changed++; console.log(`✓ ${file} (${hit} edit${hit > 1 ? "s" : ""})`); }
}

const A = (addr) => `"${addr}" as Address`;

// ── src/config/cauldron.ts ──
patch("src/config/cauldron.ts", [
  [/registry: "0x[0-9a-fA-F]{40}" as Address,/, `registry: ${A(d.registry)},`, "registry"],
  [/hook: "0x[0-9a-fA-F]{40}" as Address,/, `hook: ${A(d.hook)},`, "hook"],
  [/gachaRouter: "0x[0-9a-fA-F]{40}" as Address,/, `gachaRouter: ${A(d.gachaRouter)},`, "gachaRouter"],
  [/dividend: "0x[0-9a-fA-F]{40}" as Address,/, `dividend: ${A(d.dividend)},`, "dividend"],
  [/governor: "0x[0-9a-fA-F]{40}" as Address,/, `governor: ${A(d.governor)},`, "governor"],
  [/mifrens: "0x[0-9a-fA-F]{40}" as Address,/, `mifrens: ${A(d.mifrens)},`, "mifrens"],
  [/genesisSupply: \d+,/, `genesisSupply: ${d.genesisSupply},`, "genesisSupply"],
  [/deployBlock: \d+n,/, `deployBlock: ${d.startBlock}n,`, "deployBlock"],
]);

// ── src/config/perp.ts ──
patch("src/config/perp.ts", [
  [/(VITE_PERP_ENGINE as string\) \|\|\s*\n\s*)"0x[0-9a-fA-F]{40}"/, `$1"${d.perpEngine}"`, "engine default"],
  [/(VITE_PERP_START_BLOCK as string\) \|\| ")\d+(")/, `$1${d.startBlock}$2`, "startBlock default"],
  [/(VITE_PERP_VAULT as string\) \|\|\s*\n\s*)"0x[0-9a-fA-F]{40}"/, `$1"${d.perpVault}"`, "vault default"],
]);

// ── indexer/ponder.config.ts ──
patch("indexer/ponder.config.ts", [
  [/const startBlock = \d+;/, `const startBlock = ${d.startBlock};`, "startBlock"],
  [/const REGISTRY = "0x[0-9a-fA-F]{40}" as/, `const REGISTRY = "${d.registry}" as`, "REGISTRY"],
  [/const PRESALE = "0x[0-9a-fA-F]{40}" as/, `const PRESALE = "${d.mifrens}" as`, "PRESALE"],
  [/const HOOK = "0x[0-9a-fA-F]{40}" as/, `const HOOK = "${d.hook}" as`, "HOOK"],
  [/const GOVERNOR = "0x[0-9a-fA-F]{40}" as/, `const GOVERNOR = "${d.governor}" as`, "GOVERNOR"],
  [/const DIVIDEND = "0x[0-9a-fA-F]{40}" as/, `const DIVIDEND = "${d.dividend}" as`, "DIVIDEND"],
  [/(PERP_ENGINE \?\?\s*\n\s*)"0x[0-9a-fA-F]{40}"/, `$1"${d.perpEngine}"`, "PERP_ENGINE default"],
  [/(PERP_START_BLOCK \?\? )\d+/, `$1${d.startBlock}`, "PERP_START default"],
  [/(POOL_IDS \?\?\s*\n\s*)"0x[0-9a-fA-F]{64}"/, `$1"${d.gen1PoolId}"`, "POOL_IDS default"],
]);

// ── src/config/presale.ts (the mint UI's genesis address) ──
patch("src/config/presale.ts", [
  [/address: "0x[0-9a-fA-F]{40}" as Address,/, `address: ${A(d.mifrens)},`, "presale address"],
  [/maxSupply: \d+,/, `maxSupply: ${d.genesisSupply},`, "presale maxSupply"],
]);

// ── indexer/src/index.ts (handler-side PRESALE/REGISTRY defaults) ──
patch("indexer/src/index.ts", [
  [/(PRESALE_ADDRESS \?\? ")0x[0-9a-fA-F]{40}(")/, `$1${d.mifrens}$2`, "PRESALE default"],
  [/(REGISTRY_ADDRESS \?\? ")0x[0-9a-fA-F]{40}(")/, `$1${d.registry}$2`, "REGISTRY default"],
]);

// ── scripts/marketmaker.sh ──
patch("scripts/marketmaker.sh", [
  [/GACHA="\$\{GACHA:-0x[0-9a-fA-F]{40}\}"/, `GACHA="\${GACHA:-${d.gachaRouter}}"`, "GACHA"],
  [/TOKEN="\$\{TOKEN:-0x[0-9a-fA-F]{40}\}"/, `TOKEN="\${TOKEN:-${d.gen1Token}}"`, "TOKEN"],
  [/PERP="\$\{PERP_ENGINE:-0x[0-9a-fA-F]{40}\}"/, `PERP="\${PERP_ENGINE:-${d.perpEngine}}"`, "PERP"],
  [/POOL_ID="\$\{POOL_ID:-0x[0-9a-fA-F]{64}\}"/, `POOL_ID="\${POOL_ID:-${d.gen1PoolId}}"`, "POOL_ID"],
]);

// ── scripts/keeper.sh ──
patch("scripts/keeper.sh", [
  [/PERP="\$\{PERP_ENGINE:-0x[0-9a-fA-F]{40}\}"/, `PERP="\${PERP_ENGINE:-${d.perpEngine}}"`, "PERP"],
]);

// ── .env.local (VITE_CAULDRON_INDEXER) ──
{
  const path = join(ROOT, ".env.local");
  if (existsSync(path)) {
    let src = readFileSync(path, "utf8");
    if (/^VITE_CAULDRON_INDEXER=/m.test(src)) {
      src = src.replace(/^VITE_CAULDRON_INDEXER=.*$/m, `VITE_CAULDRON_INDEXER=${d.indexerUrl}`);
    } else {
      src += `\nVITE_CAULDRON_INDEXER=${d.indexerUrl}\n`;
    }
    writeFileSync(path, src);
    console.log("✓ .env.local (VITE_CAULDRON_INDEXER)");
    changed++;
  } else warns.push("skip (missing): .env.local");
}

// ── indexer/railway.json (--schema) ──
patch("indexer/railway.json", [
  [/--schema cauldron_prod\d+/, `--schema ${d.databaseSchema}`, "railway schema"],
]);

console.log(`\n${changed} file(s) updated for round ${d.round}.`);
if (warns.length) { console.log("\n⚠ warnings:"); warns.forEach((w) => console.log("  - " + w)); }

console.log(`\n── Push the SAME values to the Railway indexer, then it redeploys:\n`);
console.log(`  cd indexer && railway variables \\`);
console.log(`    --set "DATABASE_SCHEMA=${d.databaseSchema}" \\`);
console.log(`    --set "PERP_ENGINE=${d.perpEngine}" \\`);
console.log(`    --set "PERP_START_BLOCK=${d.startBlock}" \\`);
console.log(`    --set "POOL_IDS=${d.gen1PoolId}" \\`);
console.log(`    --set "PRESALE_ADDRESS=${d.mifrens}" \\`);
console.log(`    --set "REGISTRY_ADDRESS=${d.registry}" \\`);
console.log(`    --set "HOOK_ADDRESS=${d.hook}" && railway up --detach\n`);
console.log(`(also set VITE_CAULDRON_INDEXER on Vercel to ${d.indexerUrl} for the hosted frontend)`);
