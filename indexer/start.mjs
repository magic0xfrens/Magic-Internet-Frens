// Production entrypoint: derive the Postgres schema from the SAME manifest the
// rest of the stack reads (deployments/round.json), then exec Ponder. This keeps
// the schema in ONE place — no hardcoded `--schema` in railway.json (which
// silently overrode both the config and DATABASE_SCHEMA env in past rounds and
// pinned the indexer to a dead schema). Bump `schema` in round.json → next deploy
// reindexes cleanly; keep it the same → Ponder resumes (crash recovery, no wipe).
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";

const manifest = JSON.parse(
  readFileSync(new URL("./deployments/round.json", import.meta.url), "utf8"),
);
const schema = manifest.schema;
if (!schema || !/^[a-z0-9_]+$/.test(schema)) {
  console.error(`[start] invalid schema in round.json: ${JSON.stringify(schema)}`);
  process.exit(1);
}
console.log(`[start] round ${manifest.round} → ponder start --schema ${schema}`);

const child = spawn("npx", ["ponder", "start", "--schema", schema], {
  stdio: "inherit",
  env: process.env,
});
child.on("exit", (code) => process.exit(code ?? 1));
process.on("SIGTERM", () => child.kill("SIGTERM"));
process.on("SIGINT", () => child.kill("SIGINT"));
