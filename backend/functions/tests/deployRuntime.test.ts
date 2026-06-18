import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { describe, expect, it } from "vitest";

const functionsRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(functionsRoot, "../..");

function readText(path: string) {
  return readFileSync(resolve(functionsRoot, path), "utf8");
}

describe("Firebase Functions deploy runtime", () => {
  it("keeps Firebase deployment config pointed at the deterministic callable package", () => {
    const firebaseJson = JSON.parse(readFileSync(resolve(repoRoot, "firebase.json"), "utf8")) as {
      functions?: {
        source?: string;
        runtime?: string;
        codebase?: string;
      };
    };
    const entrypoint = readText("src/index.ts");

    expect(firebaseJson.functions).toMatchObject({
      source: "backend/functions",
      runtime: "nodejs22",
      codebase: "openlarp-ai"
    });
    expect(entrypoint).toContain("export const runOpenLARPWorkflow = onCall");
    expect(entrypoint).toContain("export const reconcileProofUploads = onCall");
  });

  it("keeps the deployable Functions package free of Genkit runtime dependencies", () => {
    const packageJson = JSON.parse(readText("package.json")) as {
      dependencies?: Record<string, string>;
      scripts?: Record<string, string>;
    };

    expect(packageJson.dependencies).not.toHaveProperty("genkit");
    expect(packageJson.dependencies).toHaveProperty("zod", "3.25.76");
    expect(packageJson.scripts?.build).not.toContain("external:genkit");
  });

  it("keeps shared request contracts on direct Zod instead of importing Genkit", () => {
    const sharedContracts = readFileSync(resolve(functionsRoot, "../ai/src/contracts.ts"), "utf8");

    expect(sharedContracts).toContain('from "zod"');
    expect(sharedContracts).not.toContain('from "genkit"');
  });

  it("keeps the bundled callable graph away from Genkit and AI barrel imports", async () => {
    const result = await build({
      entryPoints: [resolve(functionsRoot, "src/index.ts")],
      bundle: true,
      platform: "node",
      format: "esm",
      target: "node22",
      write: false,
      metafile: true,
      external: ["firebase-admin", "firebase-functions"]
    });

    const inputs = Object.keys(result.metafile.inputs);
    const forbiddenInputs = inputs.filter((input) =>
      input.includes("node_modules/genkit")
      || input.includes("node_modules/@genkit-ai")
      || input.endsWith("backend/ai/src/genkitFlows.ts")
      || input.endsWith("backend/ai/src/index.ts")
    );

    expect(forbiddenInputs).toEqual([]);
  });
});
