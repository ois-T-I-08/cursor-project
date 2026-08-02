import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    // PostgreSQL suites share the intentionally singleton automation control
    // row. File-level serialization prevents a stop-race fixture from leaking
    // into an unrelated database suite.
    fileParallelism: false,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "server-only": path.resolve(
        __dirname,
        "./src/lib/__tests__/server-only-stub.ts",
      ),
    },
  },
});
