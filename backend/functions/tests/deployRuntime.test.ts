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
    expect(entrypoint).toContain("export const promoteProofUploadReceipt = onCall");
    expect(entrypoint).toContain("export const cleanupRevokedPrivateEvidenceUploads = onCall");
    expect(entrypoint).toContain("export const setPrivateEvidenceCloudSyncConsent = onCall");
    expect(entrypoint).toContain("export const acknowledgeBackendEvents = onCall");
    expect(entrypoint).toContain("export const deleteOpenLARPAccount = onCall");
    expect(entrypoint).toContain("export const syncOpenLARPCareerState = onCall");
  });

  it("wires deployed callable exports through the Admin callable quota guard", () => {
    const entrypoint = readText("src/index.ts");
    const quotaGuard = readText("src/callableQuotaGuard.ts");

    expect(entrypoint).toContain("const callableQuotaGuard = adminCallableQuotaGuard()");
    expect(entrypoint).toContain("const accountDeletionStatusReader = adminAccountDeletionStatusReader()");
    expect(entrypoint).toContain("rejectIfAccountDeletionRequested(userID, accountDeletionStatusReader)");
    expect(entrypoint).toContain("quotaGuard: callableQuotaGuard");
    expect(entrypoint).toContain("adminProofUploadReconciliationDependencies(callableQuotaGuard)");
    expect(entrypoint).toContain("adminProofUploadPromotionDependencies(callableQuotaGuard)");
    expect(entrypoint).toContain("adminPrivateEvidenceRetentionDependencies(callableQuotaGuard)");
    expect(entrypoint).toContain("adminBackendEventSyncDependencies(callableQuotaGuard)");
    expect(entrypoint).not.toContain("adminAccountDeletionDependencies(callableQuotaGuard)");
    expect(quotaGuard).toContain("CALLABLE_DAILY_QUOTA_LIMITS");
    expect(quotaGuard).toContain("resource-exhausted");
  });

  it("wires live workflow policy, private dispatch, and provider budget dependencies only on the server", () => {
    const entrypoint = readText("src/index.ts");

    expect(entrypoint).toContain("const aiRuntimePolicyReader = adminAIRuntimePolicyReader()");
    expect(entrypoint).toContain("const aiServiceClient = aiServiceClientFromEnvironment()");
    expect(entrypoint).toContain("const providerBudgetGuard = adminProviderBudgetGuard()");
    expect(entrypoint).toContain("runtimePolicyReader: aiRuntimePolicyReader");
    expect(entrypoint).toContain("aiServiceClient");
    expect(entrypoint).toContain("providerBudgetGuard");
  });

  it("keeps the model provider SDK out of the deployable Functions package", () => {
    const packageJson = JSON.parse(readText("package.json")) as {
      dependencies?: Record<string, string>;
      scripts?: Record<string, string>;
    };

    expect(packageJson.dependencies).not.toHaveProperty("genkit");
    expect(packageJson.dependencies).not.toHaveProperty("@google/genai");
    expect(packageJson.dependencies).toHaveProperty("google-auth-library", "11.3.4");
    expect(packageJson.dependencies).toHaveProperty("zod", "4.6.7");
    expect(packageJson.scripts?.build).not.toContain("external:@google/genai");
  });

  it("keeps shared request contracts on direct Zod", () => {
    const sharedContracts = readFileSync(resolve(functionsRoot, "../ai/src/contracts.ts"), "utf8");

    expect(sharedContracts).toContain('from "zod"');
    expect(sharedContracts).not.toContain('from "@google/genai"');
  });

  it("keeps provider code and AI barrel imports out of the bundled callable graph", async () => {
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
      || input.includes("node_modules/@google/genai/")
      || input.endsWith("backend/ai/src/liveGeneration.ts")
      || input.endsWith("backend/ai/src/index.ts")
    );

    expect(forbiddenInputs).toEqual([]);
  });
});
