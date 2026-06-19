import { describe, expect, it } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import {
  handlePrivateEvidenceCloudSyncConsentRequest,
  type PrivateEvidenceCloudSyncConsentDependencies,
  type PrivateEvidenceCloudSyncConsentResponse
} from "../src/privateEvidenceConsent.js";

const now = new Date("2026-06-18T12:00:00.000Z");

function makeDependencies(existingConsentDocument: Record<string, unknown> | null = null) {
  const writes: Array<{
    userID: string;
    document: Record<string, unknown>;
  }> = [];
  const reads: string[] = [];
  const dependencies: PrivateEvidenceCloudSyncConsentDependencies = {
    async readConsentDocument(userID) {
      reads.push(userID);
      return existingConsentDocument;
    },
    async writeConsentDocument(userID, document) {
      writes.push({ userID, document });
    },
    now: () => now
  };

  return { dependencies, writes, reads };
}

function authed(
  data: unknown,
  dependencies: PrivateEvidenceCloudSyncConsentDependencies
): Promise<PrivateEvidenceCloudSyncConsentResponse> {
  return handlePrivateEvidenceCloudSyncConsentRequest({
    auth: { uid: "user_123" },
    data
  }, dependencies);
}

describe("handlePrivateEvidenceCloudSyncConsentRequest", () => {
  it("requires Firebase Auth before changing private evidence consent", async () => {
    const { dependencies, writes } = makeDependencies();

    const response = await handlePrivateEvidenceCloudSyncConsentRequest({
      auth: null,
      data: { schemaVersion: 1, enabled: true }
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
    expect(writes).toEqual([]);
  });

  it("records accepted consent as a server-owned document", async () => {
    const { dependencies, writes } = makeDependencies();

    const response = await authed({
      schemaVersion: 1,
      enabled: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      schemaVersion: 1,
      userID: "user_123",
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      firestoreDocumentPath: "users/user_123/consents/privateEvidenceCloudSync",
      updatedAt: "2026-06-18T12:00:00.000Z",
      externalActionTaken: false
    });
    expect(writes).toHaveLength(1);
    expect(writes[0]).toMatchObject({
      userID: "user_123",
      document: {
        schemaVersion: 1,
        ownerUserID: "user_123",
        status: "accepted",
        allowsPrivateEvidenceCloudSync: true,
        consentTextVersion: "private-evidence-cloud-sync-v1",
        collectionPath: "users/user_123/consents",
        documentPath: "users/user_123/consents/privateEvidenceCloudSync"
      }
    });
    expect(writes[0]?.document.acceptedAt).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document.updatedAt).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document).not.toHaveProperty("revokedAt");
  });

  it("records revoked consent without leaving an accepted rules shape", async () => {
    const { dependencies, writes } = makeDependencies();

    const response = await authed({
      schemaVersion: 1,
      enabled: false
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "revoked",
      allowsPrivateEvidenceCloudSync: false,
      firestoreDocumentPath: "users/user_123/consents/privateEvidenceCloudSync"
    });
    expect(writes).toHaveLength(1);
    expect(writes[0]?.document).toMatchObject({
      ownerUserID: "user_123",
      status: "revoked",
      allowsPrivateEvidenceCloudSync: false
    });
    expect(writes[0]?.document.revokedAt).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document).not.toHaveProperty("acceptedAt");
  });

  it("does not rewrite an already matching consent document", async () => {
    const { dependencies, writes, reads } = makeDependencies({
      schemaVersion: 1,
      ownerUserID: "user_123",
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    });

    const response = await authed({
      schemaVersion: 1,
      enabled: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    });
    expect(reads).toEqual(["user_123"]);
    expect(writes).toEqual([]);
  });

  it("rewrites matching-state consent when the stored owner does not match the signed-in user", async () => {
    const { dependencies, writes, reads } = makeDependencies({
      schemaVersion: 1,
      ownerUserID: "other_user",
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    });

    const response = await authed({
      schemaVersion: 1,
      enabled: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    });
    expect(reads).toEqual(["user_123"]);
    expect(writes).toHaveLength(1);
    expect(writes[0]?.document).toMatchObject({
      schemaVersion: 1,
      ownerUserID: "user_123",
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      consentTextVersion: "private-evidence-cloud-sync-v1"
    });
  });

  it("rejects malformed requests before writing consent", async () => {
    const cases: unknown[] = [
      null,
      [],
      { schemaVersion: 2, enabled: true },
      { schemaVersion: 1, enabled: "true" },
      { schemaVersion: 1, enabled: true, consentTextVersion: "" },
      { schemaVersion: 1, enabled: true, consentTextVersion: "private-evidence-cloud-sync-v2" }
    ];

    for (const data of cases) {
      const { dependencies, writes } = makeDependencies();

      const response = await authed(data, dependencies);

      expect(response).toMatchObject({
        ok: false,
        code: "invalid-argument"
      });
      expect(writes).toEqual([]);
    }
  });
});
