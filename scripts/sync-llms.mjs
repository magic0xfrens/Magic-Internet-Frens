// Sync the single-source docs markdown to the public machine-readable paths.
// Source of truth: src/components/docs/magicfrens-llm.md (also bundled into the
// Docs page via ?raw). This copies it verbatim to the standard llms paths so
// assistants/crawlers fetch the full text directly. Runs on predev/prebuild.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const src = resolve(root, "src/components/docs/magicfrens-llm.md");
const doc = readFileSync(src, "utf8");

const targets = ["public/magicfrens-llm.md", "public/llms-full.txt"];
for (const t of targets) {
  writeFileSync(resolve(root, t), doc);
  console.log(`synced → ${t}`);
}
