import { describe, expect, it } from "vitest";
import {
  handlePrivateEvidenceRetentionRequest,
  isRevokedPrivateEvidenceCloudSyncConsentDocument,
  type PrivateEvidenceRetentionAttachmentSnapshot,
  type PrivateEvidenceRetentionAttachmentDeletePrecondition,
  type PrivateEvidenceRetentionDependencies,
  type PrivateEvidenceRetentionResponse,
  type PrivateEvidenceRetentionStorageObject
} from "../src/privateEvidenceRetention.js";
import { makeQuotaGuard } from "./quotaTestHelpers.js";

const now = new Date("2026-06-18T12:00:00.000Z");

function revokedConsent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schemaVersion: 1,
    ownerUserID: "user_123",
    status: "revoked",
    allowsPrivateEvidenceCloudSync: false,
    consentTextVersion: "private-evidence-cloud-sync-v1",
    ...overrides
  };
}

function proofAttachmentDocument(
  attachmentID = "attachment_123",
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  const storagePath = `users/user_123/proofAttachments/${attachmentID}`;
  return {
    metadata: {
      schemaVersion: 1,
      ownerUserID: "user_123",
      localID: attachmentID
    },
    proofID: "proof_123",
    fileName: "proof.png",
    originalFileName: "proof.png",
    contentType: "image/png",
    byteCount: 32_000,
    storagePath,
    uploadStatus: "uploaded",
    uploadReceipt: {
      schemaVersion: 1,
      proofID: "proof_123",
      attachmentID,
      storagePath,
      contentType: "image/png",
      byteCount: 32_000,
      status: "uploaded",
      storageGeneration: 101,
      idempotencyKey: `user_123-${attachmentID}`
    },
    collectionPath: "users/user_123/proofAttachments",
    documentPath: storagePath,
    ...overrides
  };
}

function storageObject(
  attachmentID = "attachment_123",
  overrides: Partial<PrivateEvidenceRetentionStorageObject> = {}
): PrivateEvidenceRetentionStorageObject {
  return {
    name: `users/user_123/proofAttachments/${attachmentID}`,
    contentType: "image/png",
    size: 32_000,
    generation: "101",
    metadata: {
      ownerUserID: "user_123",
      proofID: "proof_123",
      attachmentID,
      idempotencyKey: `user_123-${attachmentID}`
    },
    ...overrides
  };
}

function makeDependencies(options: {
  consent?: Record<string, unknown> | null;
  attachments?: Record<string, Record<string, unknown>>;
  storageObjects?: Record<string, PrivateEvidenceRetentionStorageObject | null>;
  quotaGuard?: PrivateEvidenceRetentionDependencies["quotaGuard"];
  storageDeleteResult?: boolean;
  firestoreDeleteResult?: boolean;
} = {}) {
  const attachments = options.attachments ?? {
    attachment_123: proofAttachmentDocument()
  };
  const storageObjects = options.storageObjects ?? {
    "users/user_123/proofAttachments/attachment_123": storageObject()
  };
  const consentReads: string[] = [];
  const listCalls: Array<{
    userID: string;
    attachmentIDs: string[] | undefined;
    maxAttachments: number;
  }> = [];
  const storageReads: string[] = [];
  const storageDeletes: Array<{ storagePath: string; generation: string | undefined }> = [];
  const firestoreDeletes: Array<{
    userID: string;
    attachmentID: string;
    precondition: PrivateEvidenceRetentionAttachmentDeletePrecondition;
  }> = [];

  const dependencies: PrivateEvidenceRetentionDependencies = {
    async readPrivateEvidenceCloudSyncConsent(userID) {
      consentReads.push(userID);
      return options.consent === undefined ? revokedConsent() : options.consent;
    },
    async listProofAttachments(userID, attachmentIDs, maxAttachments) {
      listCalls.push({ userID, attachmentIDs, maxAttachments });
      if (attachmentIDs) {
        return attachmentIDs.slice(0, maxAttachments).map((attachmentID) => {
          const data = attachments[attachmentID];
          return data
            ? { exists: true, attachmentID, data } satisfies PrivateEvidenceRetentionAttachmentSnapshot
            : { exists: false, attachmentID } satisfies PrivateEvidenceRetentionAttachmentSnapshot;
        });
      }

      return Object.entries(attachments).slice(0, maxAttachments).map(([attachmentID, data]) => ({
        exists: true,
        attachmentID,
        data
      })) satisfies PrivateEvidenceRetentionAttachmentSnapshot[];
    },
    async readStorageObject(storagePath) {
      storageReads.push(storagePath);
      return storageObjects[storagePath] ?? null;
    },
    async deleteStorageObjectGeneration(storagePath, generation) {
      storageDeletes.push({ storagePath, generation });
      return options.storageDeleteResult ?? true;
    },
    async deleteProofAttachmentDocument(userID, attachmentID, precondition) {
      firestoreDeletes.push({ userID, attachmentID, precondition });
      return options.firestoreDeleteResult ?? true;
    },
    ...(options.quotaGuard ? { quotaGuard: options.quotaGuard } : {}),
    now: () => now
  };

  return {
    dependencies,
    consentReads,
    listCalls,
    storageReads,
    storageDeletes,
    firestoreDeletes
  };
}

function authed(
  data: unknown,
  dependencies: PrivateEvidenceRetentionDependencies
): Promise<PrivateEvidenceRetentionResponse> {
  return handlePrivateEvidenceRetentionRequest({
    auth: { uid: "user_123" },
    data
  }, dependencies);
}

describe("handlePrivateEvidenceRetentionRequest", () => {
  it("recognizes only the current server-owned revoked consent shape", () => {
    expect(isRevokedPrivateEvidenceCloudSyncConsentDocument("user_123", revokedConsent())).toBe(true);
    expect(isRevokedPrivateEvidenceCloudSyncConsentDocument("user_123", revokedConsent({
      ownerUserID: "other_user"
    }))).toBe(false);
    expect(isRevokedPrivateEvidenceCloudSyncConsentDocument("user_123", revokedConsent({
      status: "accepted"
    }))).toBe(false);
    expect(isRevokedPrivateEvidenceCloudSyncConsentDocument("user_123", revokedConsent({
      allowsPrivateEvidenceCloudSync: true
    }))).toBe(false);
  });

  it("requires Firebase Auth before reporting or deleting private evidence backups", async () => {
    const { dependencies, listCalls, storageDeletes, firestoreDeletes } = makeDependencies();

    const response = await handlePrivateEvidenceRetentionRequest({
      auth: null,
      data: { mode: "reportOnly" }
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
    expect(listCalls).toEqual([]);
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
  });

  it("requires revoked consent before scanning private evidence backups", async () => {
    const { dependencies, consentReads, listCalls } = makeDependencies({
      consent: revokedConsent({
        status: "accepted",
        allowsPrivateEvidenceCloudSync: true
      })
    });

    const response = await authed({ mode: "reportOnly" }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "permission-denied"
    });
    expect(consentReads).toEqual(["user_123"]);
    expect(listCalls).toEqual([]);
  });

  it("reports eligible uploaded proof attachments by default without deleting", async () => {
    const { guard, charges } = makeQuotaGuard({ limitUnits: 30 });
    const { dependencies, listCalls, storageReads, storageDeletes, firestoreDeletes } = makeDependencies({
      quotaGuard: guard
    });

    const response = await authed(undefined, dependencies);

    expect(response).toMatchObject({
      ok: true,
      schemaVersion: 1,
      userID: "user_123",
      mode: "reportOnly",
      evaluatedAt: "2026-06-18T12:00:00.000Z",
      scannedCount: 1,
      eligibleCount: 1,
      deletedCount: 0,
      partialFailureCount: 0,
      externalActionTaken: false,
      candidates: [{
        attachmentID: "attachment_123",
        proofID: "proof_123",
        storagePath: "users/user_123/proofAttachments/attachment_123",
        storageGeneration: "101",
        status: "eligible",
        canDelete: true,
        deleted: false
      }]
    });
    expect(listCalls).toEqual([{
      userID: "user_123",
      attachmentIDs: undefined,
      maxAttachments: 25
    }]);
    expect(storageReads).toEqual(["users/user_123/proofAttachments/attachment_123"]);
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
    expect(charges).toEqual([{
      userID: "user_123",
      callable: "cleanupRevokedPrivateEvidenceUploads",
      category: "privateEvidenceRetention",
      units: 1,
      occurredAt: now,
      metadata: {
        mode: "reportOnly",
        maxAttachments: 25,
        hasAttachmentFilter: false
      }
    }]);
  });

  it("requires explicit confirmation and attachment IDs before deleting", async () => {
    const { dependencies, listCalls } = makeDependencies();

    const missingConfirmation = await authed({
      mode: "deleteSyncedEvidence",
      attachmentIDs: ["attachment_123"]
    }, dependencies);
    const missingIDs = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true
    }, dependencies);

    expect(missingConfirmation).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
    expect(missingIDs).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
    expect(listCalls).toEqual([]);
  });

  it("rejects unsupported schema versions and over-limit attachment lists before cleanup work", async () => {
    const { dependencies, listCalls, storageDeletes, firestoreDeletes } = makeDependencies();

    const badSchema = await authed({ schemaVersion: 2, mode: "reportOnly" }, dependencies);
    const tooManyIDs = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: Array.from({ length: 101 }, (_, index) => `attachment_${index}`)
    }, dependencies);

    expect(badSchema).toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
    expect(tooManyIDs).toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
    expect(listCalls).toEqual([]);
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
  });

  it("rejects destructive cleanup when maxAttachments would skip explicit IDs", async () => {
    const { dependencies, listCalls, storageDeletes, firestoreDeletes } = makeDependencies();

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_1", "attachment_2"],
      maxAttachments: 1
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
    expect(listCalls).toEqual([]);
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
  });

  it("deletes only explicitly confirmed matching Storage and Firestore proof attachment data", async () => {
    const { dependencies, listCalls, storageDeletes, firestoreDeletes } = makeDependencies();

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      mode: "deleteSyncedEvidence",
      scannedCount: 1,
      eligibleCount: 1,
      deletedCount: 1,
      partialFailureCount: 0,
      externalActionTaken: true,
      candidates: [{
        attachmentID: "attachment_123",
        status: "deleted",
        canDelete: false,
        deleted: true
      }]
    });
    expect(listCalls[0]).toMatchObject({
      userID: "user_123",
      attachmentIDs: ["attachment_123"]
    });
    expect(storageDeletes).toEqual([{
      storagePath: "users/user_123/proofAttachments/attachment_123",
      generation: "101"
    }]);
    expect(firestoreDeletes).toEqual([{
      userID: "user_123",
      attachmentID: "attachment_123",
      precondition: {
        proofID: "proof_123",
        storagePath: "users/user_123/proofAttachments/attachment_123",
        contentType: "image/png",
        byteCount: 32_000,
        idempotencyKey: "user_123-attachment_123",
        storageGeneration: "101"
      }
    }]);
  });

  it("skips deletion when Storage metadata no longer matches the Firestore receipt", async () => {
    const { dependencies, storageDeletes, firestoreDeletes } = makeDependencies({
      storageObjects: {
        "users/user_123/proofAttachments/attachment_123": storageObject("attachment_123", {
          metadata: {
            ownerUserID: "other_user",
            proofID: "proof_123",
            attachmentID: "attachment_123",
            idempotencyKey: "user_123-attachment_123"
          }
        })
      }
    });

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      deletedCount: 0,
      candidates: [{
        attachmentID: "attachment_123",
        status: "storageMetadataMismatch",
        canDelete: false,
        deleted: false
      }]
    });
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
  });

  it("skips deletion when the Storage generation changed after promotion", async () => {
    const { dependencies, storageDeletes, firestoreDeletes } = makeDependencies({
      storageObjects: {
        "users/user_123/proofAttachments/attachment_123": storageObject("attachment_123", {
          generation: "202"
        })
      }
    });

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      deletedCount: 0,
      candidates: [{
        attachmentID: "attachment_123",
        status: "storageMetadataMismatch",
        canDelete: false,
        deleted: false
      }]
    });
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
  });

  it("removes the Firestore proof attachment document when the Storage file is already missing", async () => {
    const { dependencies, storageDeletes, firestoreDeletes } = makeDependencies({
      storageObjects: {
        "users/user_123/proofAttachments/attachment_123": null
      }
    });

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      deletedCount: 1,
      candidates: [{
        attachmentID: "attachment_123",
        status: "deleted",
        deleted: true
      }]
    });
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([{
      userID: "user_123",
      attachmentID: "attachment_123",
      precondition: {
        proofID: "proof_123",
        storagePath: "users/user_123/proofAttachments/attachment_123",
        contentType: "image/png",
        byteCount: 32_000,
        idempotencyKey: "user_123-attachment_123",
        storageGeneration: "101"
      }
    }]);
  });

  it("reports partial failure when generation-matched Storage deletion fails", async () => {
    const { dependencies, storageDeletes, firestoreDeletes } = makeDependencies({
      storageDeleteResult: false
    });

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      deletedCount: 0,
      partialFailureCount: 1,
      externalActionTaken: true,
      candidates: [{
        attachmentID: "attachment_123",
        status: "storageDeleteFailed",
        canDelete: false,
        deleted: false
      }]
    });
    expect(storageDeletes).toHaveLength(1);
    expect(firestoreDeletes).toEqual([{
      userID: "user_123",
      attachmentID: "attachment_123",
      precondition: {
        proofID: "proof_123",
        storagePath: "users/user_123/proofAttachments/attachment_123",
        contentType: "image/png",
        byteCount: 32_000,
        idempotencyKey: "user_123-attachment_123",
        storageGeneration: "101"
      }
    }]);
  });

  it("leaves Storage untouched when Firestore precondition deletion fails", async () => {
    const { dependencies, storageDeletes, firestoreDeletes } = makeDependencies({
      firestoreDeleteResult: false
    });

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      eligibleCount: 1,
      deletedCount: 0,
      partialFailureCount: 1,
      externalActionTaken: false,
      candidates: [{
        attachmentID: "attachment_123",
        status: "firestoreDeleteFailed",
        canDelete: false,
        deleted: false
      }]
    });
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([{
      userID: "user_123",
      attachmentID: "attachment_123",
      precondition: {
        proofID: "proof_123",
        storagePath: "users/user_123/proofAttachments/attachment_123",
        contentType: "image/png",
        byteCount: 32_000,
        idempotencyKey: "user_123-attachment_123",
        storageGeneration: "101"
      }
    }]);
  });

  it("does not list or delete private evidence when retention quota is exhausted", async () => {
    const { guard, charges } = makeQuotaGuard({ exhausted: true, limitUnits: 30 });
    const { dependencies, listCalls, storageDeletes, firestoreDeletes } = makeDependencies({
      quotaGuard: guard
    });

    const response = await authed({
      mode: "deleteSyncedEvidence",
      confirmDeletion: true,
      attachmentIDs: ["attachment_123"]
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "resource-exhausted"
    });
    expect(charges).toHaveLength(1);
    expect(listCalls).toEqual([]);
    expect(storageDeletes).toEqual([]);
    expect(firestoreDeletes).toEqual([]);
  });
});
