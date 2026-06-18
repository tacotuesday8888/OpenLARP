import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { describe, expect, it } from "vitest";

const scriptURL = new URL("../firebase-signed-in-smoke.sh", import.meta.url);
const scriptPath = scriptURL.pathname;
const script = readFileSync(scriptURL, "utf8");

function runPreflight(env = {}) {
  return spawnSync("bash", [scriptPath], {
    encoding: "utf8",
    env: {
      ...process.env,
      OPENLARP_FIREBASE_SMOKE_PREFLIGHT_ONLY: "1",
      OPENLARP_FIREBASE_SMOKE_ALLOW_PROJECT: "",
      OPENLARP_FIREBASE_SMOKE_ALLOW_BUCKET: "",
      ...env
    }
  });
}

describe("firebase-signed-in-smoke guardrails", () => {
  it("passes preflight for the default dev project, default bucket, and smoke UID", () => {
    const result = runPreflight({
      OPENLARP_FIREBASE_PROJECT_ID: "openlarp-dev-langqi",
      OPENLARP_FIREBASE_STORAGE_BUCKET: "openlarp-dev-langqi.firebasestorage.app",
      OPENLARP_FIREBASE_SMOKE_UID: "openlarp-smoke-test"
    });

    expect(result.status).toBe(0);
    expect(result.stdout).toContain("PASS Signed-in smoke preflight passed");
    expect(result.stderr).toBe("");
  });

  it("refuses non-dev projects before any live Firebase command can run", () => {
    const result = runPreflight({
      OPENLARP_FIREBASE_PROJECT_ID: "openlarp-prod",
      OPENLARP_FIREBASE_STORAGE_BUCKET: "openlarp-prod.firebasestorage.app",
      OPENLARP_FIREBASE_SMOKE_UID: "openlarp-smoke-test"
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("Refusing signed-in smoke against non-dev project");
    expect(result.stdout).not.toContain("PASS Signed-in smoke preflight passed");
  });

  it("refuses unexpected bucket overrides before any live Firebase command can run", () => {
    const result = runPreflight({
      OPENLARP_FIREBASE_PROJECT_ID: "openlarp-dev-langqi",
      OPENLARP_FIREBASE_STORAGE_BUCKET: "prod-bucket.firebasestorage.app",
      OPENLARP_FIREBASE_SMOKE_UID: "openlarp-smoke-test"
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("Refusing signed-in smoke against unexpected bucket");
    expect(result.stdout).not.toContain("PASS Signed-in smoke preflight passed");
  });

  it("requires reserved smoke UIDs before any live Firebase command can run", () => {
    const result = runPreflight({
      OPENLARP_FIREBASE_PROJECT_ID: "openlarp-dev-langqi",
      OPENLARP_FIREBASE_STORAGE_BUCKET: "openlarp-dev-langqi.firebasestorage.app",
      OPENLARP_FIREBASE_SMOKE_UID: "real-user"
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("OPENLARP_FIREBASE_SMOKE_UID must start with reserved prefix");
    expect(result.stdout).not.toContain("PASS Signed-in smoke preflight passed");
  });

  it("deletes Auth users only when this run created a smoke-prefixed user", () => {
    expect(script).toContain("let createdSmokeUser = false");
    expect(script).toContain("createdSmokeUser = true");
    expect(script).toContain("if (!createdSmokeUser)");
    expect(script).toContain('uid.startsWith("openlarp-smoke-")');
    expect(script).toContain("Refusing to delete non-smoke UID");
  });

  it("fails on cleanup errors and clears quota for both start and cleanup UTC days", () => {
    expect(script).toContain("throw new Error([");
    expect(script).toContain("Smoke cleanup failed");
    expect(script).toContain("Manual cleanup may be needed");
    expect(script).toContain("startedAt.toISOString().slice(0, 10)");
    expect(script).toContain("new Date().toISOString().slice(0, 10)");
    expect(script).toContain("deleteStoragePrefix");
    expect(script).toContain("deleteFirestoreUserTree");
    expect(script).toContain("assertFirestoreUserTreeEmpty");
  });

  it("uses signed-in Firebase client SDK checks for user-facing Storage and Firestore access", () => {
    expect(script).toContain("signInWithCustomToken");
    expect(script).toContain("clientUploadBytes");
    expect(script).toContain("clientGetMetadata");
    expect(script).toContain("clientGetBytes");
    expect(script).toContain("clientGetDoc(clientDoc(clientFirestore");
    expect(script).not.toContain("exchangeCustomToken");
  });
});
