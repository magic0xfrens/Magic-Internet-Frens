import { defineConfig } from "vitest/config";

// API regressions execute locally with mocked transports, never provider RPCs.
export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/api/**/*.test.ts"],
    pool: "forks",
    minWorkers: 1,
    maxWorkers: 1,
  },
});
