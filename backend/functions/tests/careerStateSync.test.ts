import { describe, expect, it } from "vitest";
import {
  handleCareerStateSyncRequest,
  hashCareerStatePayload,
  type CareerStateSnapshot,
  type CareerStateSyncDependencies
} from "../src/careerStateSync.js";

const now = new Date("2026-08-11T08:00:00.000Z");

function payload(label: string, includesPrivateEvidence = false): CareerStateSnapshot["payload"] {
  return {
    schemaVersion: 1,
    includesPrivateEvidence,
    state: {
      schemaVersion: 16,
      marker: label,
      userProfile: null,
      questReminders: { isEnabled: false, hour: 19, minute: 0, cadence: "everyDay" },
      progress: { recentProof: [] },
      outcomeLog: [],
      betaEvents: [],
      aiWorkflowRuns: [],
      backendEvents: []
    }
  };
}

function requestData(overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    action: "reconcile",
    requestedAt: "2026-08-11T07:59:00.000Z",
    hasMeaningfulLocalData: true,
    payload: payload("local"),
    ...overrides
  };
}

function dependencies(existing: CareerStateSnapshot | null = null, consent = false) {
  let stored = existing;
  const writes: CareerStateSnapshot[] = [];
  const value: CareerStateSyncDependencies = {
    now: () => now,
    async reconcileSnapshot(userID, input) {
      expect(userID).toBe("user_123");
      const result = input.decide(stored, consent);
      if (result.snapshotToWrite) {
        stored = result.snapshotToWrite;
        writes.push(result.snapshotToWrite);
      }
      return result.response;
    }
  };
  return { value, writes, stored: () => stored };
}

function cloudSnapshot(revision: number, marker: string, hash = "a".repeat(64)): CareerStateSnapshot {
  return {
    schemaVersion: 1,
    ownerUserID: "user_123",
    revision,
    payloadHash: hash,
    payload: payload(marker),
    createdAt: new Date("2026-08-10T08:00:00.000Z"),
    updatedAt: new Date("2026-08-11T07:00:00.000Z")
  };
}

async function call(data: unknown, dependency: CareerStateSyncDependencies) {
  return handleCareerStateSyncRequest({
    auth: { uid: "user_123" },
    data
  }, dependency);
}

describe("handleCareerStateSyncRequest", () => {
  it("requires authentication and rejects owner identity supplied by the client", async () => {
    const { value } = dependencies();
    const unauthenticated = await handleCareerStateSyncRequest({ auth: null, data: requestData() }, value);
    const injectedOwner = await call(requestData({ ownerUserID: "other_user" }), value);

    expect(unauthenticated).toMatchObject({ ok: false, code: "unauthenticated" });
    expect(injectedOwner).toMatchObject({ ok: false, code: "invalid-argument" });
  });

  it("creates revision one when meaningful local state has no cloud snapshot", async () => {
    const state = dependencies();

    const response = await call(requestData(), state.value);

    expect(response).toMatchObject({
      ok: true,
      status: "uploaded",
      revision: 1,
      userID: "user_123",
      didWrite: true
    });
    expect(state.writes).toHaveLength(1);
    expect(state.writes[0]).toMatchObject({
      ownerUserID: "user_123",
      revision: 1,
      payload: payload("local")
    });
  });

  it("returns noData without creating an empty cloud snapshot", async () => {
    const state = dependencies();

    const response = await call(requestData({
      hasMeaningfulLocalData: false,
      payload: payload("empty")
    }), state.value);

    expect(response).toMatchObject({ ok: true, status: "noData", revision: 0, didWrite: false });
    expect(state.writes).toHaveLength(0);
  });

  it("restores cloud state onto an empty device", async () => {
    const state = dependencies(cloudSnapshot(3, "cloud"));

    const response = await call(requestData({
      hasMeaningfulLocalData: false,
      payload: payload("empty")
    }), state.value);

    expect(response).toMatchObject({
      ok: true,
      status: "restored",
      revision: 3,
      cloudPayload: payload("cloud"),
      didWrite: false
    });
  });

  it("returns a conflict when first-use local and cloud state differ", async () => {
    const state = dependencies(cloudSnapshot(2, "cloud"));

    const response = await call(requestData(), state.value);

    expect(response).toMatchObject({
      ok: true,
      status: "conflict",
      revision: 2,
      cloudPayload: payload("cloud"),
      didWrite: false
    });
    expect(state.writes).toHaveLength(0);
  });

  it("restores a newer cloud revision when local state still matches its base hash", async () => {
    const baseHash = hashCareerStatePayload(payload("local"));
    const state = dependencies(cloudSnapshot(4, "new cloud", "c".repeat(64)));

    const response = await call(requestData({
      expectedRevision: 2,
      basePayloadHash: baseHash
    }), state.value);

    expect(response).toMatchObject({ status: "restored", revision: 4, cloudPayload: payload("new cloud") });
  });

  it("advances a known revision when only the local payload changed", async () => {
    const baseHash = hashCareerStatePayload(payload("base"));
    const state = dependencies(cloudSnapshot(5, "base", baseHash));

    const response = await call(requestData({
      expectedRevision: 5,
      basePayloadHash: baseHash
    }), state.value);

    expect(response).toMatchObject({ status: "uploaded", revision: 6, didWrite: true });
    expect(state.writes[0]).toMatchObject({ revision: 6, payload: payload("local") });
  });

  it("does not silently overwrite when local and cloud both changed", async () => {
    const state = dependencies(cloudSnapshot(7, "remote edit", "e".repeat(64)));

    const response = await call(requestData({
      expectedRevision: 5,
      basePayloadHash: "d".repeat(64)
    }), state.value);

    expect(response).toMatchObject({ status: "conflict", revision: 7, didWrite: false });
    expect(state.writes).toHaveLength(0);
  });

  it("requires the observed revision before explicitly keeping local state", async () => {
    const state = dependencies(cloudSnapshot(7, "remote edit"));

    const stale = await call(requestData({ action: "keepLocal", expectedRevision: 6 }), state.value);
    const current = await call(requestData({ action: "keepLocal", expectedRevision: 7 }), state.value);

    expect(stale).toMatchObject({ status: "conflict", revision: 7, didWrite: false });
    expect(current).toMatchObject({ status: "uploaded", revision: 8, didWrite: true });
  });

  it("returns the latest cloud state when the user explicitly chooses cloud", async () => {
    const state = dependencies(cloudSnapshot(9, "cloud chosen"));

    const response = await call(requestData({ action: "useCloud" }), state.value);

    expect(response).toMatchObject({
      status: "restored",
      revision: 9,
      cloudPayload: payload("cloud chosen"),
      didWrite: false
    });
  });

  it("requires accepted consent before storing private evidence", async () => {
    const denied = dependencies(null, false);
    const allowed = dependencies(null, true);
    const privateRequest = requestData({ payload: payload("private", true) });

    const deniedResponse = await call(privateRequest, denied.value);
    const allowedResponse = await call(privateRequest, allowed.value);

    expect(deniedResponse).toMatchObject({ ok: false, code: "failed-precondition" });
    expect(denied.writes).toHaveLength(0);
    expect(allowedResponse).toMatchObject({ ok: true, status: "uploaded" });
  });

  it("rejects private evidence hidden behind a false consent flag and all local attachment paths", async () => {
    const state = dependencies(null, false);
    const hiddenProof = payload("hidden proof");
    hiddenProof.state.progress = {
      recentProof: [{ text: "private", attachments: [] }]
    };
    const localPath = payload("local path", true);
    localPath.state.progress = {
      recentProof: [{ text: "private", attachments: [{ localRelativePath: "ProofAttachments/private.png" }] }]
    };

    const hiddenResponse = await call(requestData({ payload: hiddenProof }), state.value);
    const pathResponse = await call(requestData({ payload: localPath }), dependencies(null, true).value);

    expect(hiddenResponse).toMatchObject({ ok: false, code: "invalid-argument" });
    expect(pathResponse).toMatchObject({ ok: false, code: "invalid-argument" });
  });

  it("does not return a private cloud snapshot after consent is revoked", async () => {
    const state = dependencies({
      ...cloudSnapshot(3, "private cloud"),
      payload: payload("private cloud", true)
    }, false);

    const response = await call(requestData({ action: "useCloud" }), state.value);

    expect(response).toMatchObject({ ok: false, code: "failed-precondition" });
    expect(response).not.toHaveProperty("cloudPayload");
  });

  it("lets the current revision replace a private snapshot with a redacted copy after revocation", async () => {
    const privateCloud = {
      ...cloudSnapshot(3, "private cloud"),
      payload: payload("private cloud", true)
    };
    const state = dependencies(privateCloud, false);

    const response = await call(requestData({ expectedRevision: 3 }), state.value);

    expect(response).toMatchObject({ ok: true, status: "uploaded", revision: 4, didWrite: true });
    expect(state.writes[0]?.payload.includesPrivateEvidence).toBe(false);
  });

  it("rejects malformed, oversized, and client-hash-spoofed payloads", async () => {
    const state = dependencies();
    const malformed = await call(requestData({ payload: { schemaVersion: 2, state: {} } }), state.value);
    const oversized = await call(requestData({
      payload: payload("x".repeat(750_000))
    }), state.value);
    const spoofedHash = await call(requestData({ payloadHash: "f".repeat(64) }), state.value);

    expect(malformed).toMatchObject({ ok: false, code: "invalid-argument" });
    expect(oversized).toMatchObject({ ok: false, code: "invalid-argument" });
    expect(spoofedHash).toMatchObject({ ok: false, code: "invalid-argument" });
  });
});
