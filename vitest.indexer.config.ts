import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "ponder:registry": fileURLToPath(new URL("./tests/indexer/mocks/registry.ts", import.meta.url)),
      "ponder:schema": fileURLToPath(new URL("./tests/indexer/mocks/schema.ts", import.meta.url)),
      "ponder:api": fileURLToPath(new URL("./tests/indexer/mocks/api.ts", import.meta.url)),
    },
  },
  test: {
    environment: "node",
    include: ["tests/indexer/**/*.test.ts"],
    pool: "forks",
    minWorkers: 1,
    maxWorkers: 1,
  },
});
