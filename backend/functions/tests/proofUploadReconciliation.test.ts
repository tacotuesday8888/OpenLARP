import { describe, expect, it } from "vitest";
import {
  handleProofUploadReconciliationRequest,
  type ProofUploadReconciliationDependencies,
  type ProofUploadReconciliationResponse,
  type ProofUploadStorageObject
} from "../src/proofUploadReconciliation.js";
import { makeQuotaGuard } from "./quotaTestHelpers.js";

const now = new Date("2026-06-18T12:00:00.000Z");

function storageObject(
  attachmentID: string,
  overrides: Partial<ProofUploadStorageObject> = {}
): ProofUploadStorageObject {
  return {
    name: `users/user_123/proofAttachments/${attachmentID}`,
    contentType: "image/png",
    size: 32_000,
    updatedAt: "2026-06-18T11:00:00.000Z",
    bucket: "openlarp-test.appspot.com",
    generation: "101",
    metageneration: "2",
    md5Hash: "mock-md5",
    metadata: {
      ownerUserID: "user_123",
      proofID: "proof_123",
      attachmentID,
      idempotencyKey: `user_123-${attachmentID}`
    },
    ...overrides
  };
}

function firestoreAttachment(attachmentID: string) {
  return {
    uploadStatus: "uploaded",
    proofID: "proof_123",
    storagePath: `users/user_123/proofAttachments/${attachmentID}`,
    uploadReceipt: {
      status: "uploaded",
      proofID: "proof_123",
      attachmentID,
      storagePath: `users/user_123/proofAttachments/${attachmentID}`,
      contentType: "image/png",
      byteCount: 32_000,
      idempotencyKey: `user_123-${attachmentID}`
    }
  };
}

function makeDependencies(options: {
  objects: ProofUploadStorageObject[];
  firestoreAttachments?: Record<string, Record<string, unknown>>;
  quotaGuard?: ProofUploadReconciliationDependencies["quotaGuard"];
}) {
  const deletedPaths: string[] = [];
  const deleteGenerations: Array<string | undefined> = [];
  const requestedAttachmentIDs: Array<string[] | undefined> = [];
  const dependencies: ProofUploadReconciliationDependencies = {
    async listStorageObjects(_userID, attachmentIDs) {
      requestedAttachmentIDs.push(attachmentIDs);
      if (!attachmentIDs) {
        return options.objects;
      }

      return options.objects.filter((object) =>
        attachmentIDs.some((attachmentID) => object.name.endsWith(`/${attachmentID}`))
      );
    },
    async readFirestoreAttachment(_userID, attachmentID) {
      const data = options.firestoreAttachments?.[attachmentID];
      return data ? { exists: true, data } : { exists: false };
    },
    async deleteStorageObjectGeneration(storagePath, generation) {
      deletedPaths.push(storagePath);
      deleteGenerations.push(generation);
      return true;
    },
    ...(options.quotaGuard ? { quotaGuard: options.quotaGuard } : {}),
    now: () => now
  };

  return { dependencies, deletedPaths, deleteGenerations, requestedAttachmentIDs };
}

function authed(
  data: unknown,
  dependencies: ProofUploadReconciliationDependencies
): Promise<ProofUploadReconciliationResponse> {
  return handleProofUploadReconciliationRequest({
    auth: { uid: "user_123" },
    data
  }, dependencies);
}

describe("handleProofUploadReconciliationRequest", () => {
  it("requires Firebase Auth before scanning proof uploads", async () => {
    const { dependencies } = makeDependencies({ objects: [] });

    const response = await handleProofUploadReconciliationRequest({
      auth: null,
      data: { mode: "reportOnly" }
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
  });

  it("reports linked uploads without taking external action", async () => {
    const object = storageObject("attachment_123");
    const { dependencies, deletedPaths } = makeDependencies({
      objects: [object],
      firestoreAttachments: {
        attachment_123: firestoreAttachment("attachment_123")
      }
    });

    const response = await authed({ attachmentIDs: ["attachment_123"] }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      mode: "reportOnly",
      scannedCount: 1,
      orphanedCount: 0,
      deletedCount: 0,
      externalActionTaken: false,
      candidates: [
        {
          attachmentID: "attachment_123",
          status: "linked",
          canDelete: false,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual([]);
  });

  it("records quota before scanning Storage objects", async () => {
    const { guard, charges } = makeQuotaGuard({ limitUnits: 30 });
    const object = storageObject("attachment_123");
    const { dependencies, requestedAttachmentIDs } = makeDependencies({
      objects: [object],
      firestoreAttachments: {
        attachment_123: firestoreAttachment("attachment_123")
      },
      quotaGuard: guard
    });

    const response = await authed({
      attachmentIDs: ["attachment_123"],
      maxAttachments: 10
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      scannedCount: 1
    });
    expect(requestedAttachmentIDs).toEqual([["attachment_123"]]);
    expect(charges).toEqual([{
      userID: "user_123",
      callable: "reconcileProofUploads",
      category: "proofUploadRepair",
      units: 1,
      occurredAt: now,
      metadata: {
        mode: "reportOnly",
        maxAttachments: 10,
        hasAttachmentFilter: true
      }
    }]);
  });

  it("does not list or delete Storage objects when reconciliation quota is exhausted", async () => {
    const { guard, charges } = makeQuotaGuard({ exhausted: true, limitUnits: 30 });
    const { dependencies, requestedAttachmentIDs, deletedPaths } = makeDependencies({
      objects: [storageObject("orphan_123")],
      quotaGuard: guard
    });

    const response = await authed({
      mode: "deleteOrphans",
      confirmDeletion: true,
      maxAttachments: 10
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "resource-exhausted"
    });
    expect(charges).toHaveLength(1);
    expect(requestedAttachmentIDs).toEqual([]);
    expect(deletedPaths).toEqual([]);
  });

  it("defaults omitted callable payloads to report-only scans", async () => {
    const { dependencies } = makeDependencies({ objects: [] });

    const response = await authed(undefined, dependencies);

    expect(response).toMatchObject({
      ok: true,
      mode: "reportOnly",
      scannedCount: 0,
      orphanedCount: 0,
      deletedCount: 0,
      externalActionTaken: false
    });
  });

  it("reports orphaned Storage uploads without deleting by default", async () => {
    const object = storageObject("orphan_123");
    const { dependencies, deletedPaths } = makeDependencies({ objects: [object] });

    const response = await authed({ mode: "reportOnly" }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      mode: "reportOnly",
      scannedCount: 1,
      orphanedCount: 1,
      deletedCount: 0,
      externalActionTaken: false,
      candidates: [
        {
          attachmentID: "orphan_123",
          status: "orphanedStorageObject",
          canDelete: true,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual([]);
  });

  it("requires explicit confirmation before deleting orphaned uploads", async () => {
    const object = storageObject("orphan_123");
    const { dependencies } = makeDependencies({ objects: [object] });

    const response = await authed({ mode: "deleteOrphans" }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
  });

  it("deletes only safe confirmed orphaned uploads", async () => {
    const object = storageObject("orphan_123");
    const { dependencies, deletedPaths, deleteGenerations } = makeDependencies({ objects: [object] });

    const response = await authed({
      mode: "deleteOrphans",
      confirmDeletion: true
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      mode: "deleteOrphans",
      scannedCount: 1,
      orphanedCount: 1,
      deletedCount: 1,
      externalActionTaken: true,
      candidates: [
        {
          attachmentID: "orphan_123",
          status: "deleted",
          canDelete: true,
          deleted: true
        }
      ]
    });
    expect(deletedPaths).toEqual(["users/user_123/proofAttachments/orphan_123"]);
    expect(deleteGenerations).toEqual(["101"]);
  });

  it("does not delete recent orphaned uploads that may still be retrying metadata writes", async () => {
    const object = storageObject("fresh_orphan_123", {
      updatedAt: "2026-06-18T11:55:00.000Z"
    });
    const { dependencies, deletedPaths } = makeDependencies({ objects: [object] });

    const response = await authed({
      mode: "deleteOrphans",
      confirmDeletion: true
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      scannedCount: 1,
      orphanedCount: 1,
      deletedCount: 0,
      externalActionTaken: false,
      candidates: [
        {
          attachmentID: "fresh_orphan_123",
          status: "orphanedStorageObject",
          canDelete: false,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual([]);
  });

  it("rechecks Firestore before deleting an orphan candidate", async () => {
    const object = storageObject("race_123");
    const deletedPaths: string[] = [];
    let readCount = 0;
    const dependencies: ProofUploadReconciliationDependencies = {
      async listStorageObjects() {
        return [object];
      },
      async readFirestoreAttachment() {
        readCount += 1;
        if (readCount === 1) {
          return { exists: false };
        }
        return { exists: true, data: firestoreAttachment("race_123") };
      },
      async deleteStorageObjectGeneration(storagePath) {
        deletedPaths.push(storagePath);
        return true;
      },
      now: () => now
    };

    const response = await authed({
      mode: "deleteOrphans",
      confirmDeletion: true
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      scannedCount: 1,
      orphanedCount: 0,
      deletedCount: 0,
      externalActionTaken: false,
      candidates: [
        {
          attachmentID: "race_123",
          status: "linked",
          canDelete: false,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual([]);
    expect(readCount).toBe(2);
  });

  it("skips deletion when the inspected Storage generation changed", async () => {
    const object = storageObject("changed_generation_123");
    const deletedPaths: string[] = [];
    const dependencies: ProofUploadReconciliationDependencies = {
      async listStorageObjects() {
        return [object];
      },
      async readFirestoreAttachment() {
        return { exists: false };
      },
      async deleteStorageObjectGeneration(storagePath) {
        deletedPaths.push(storagePath);
        return false;
      },
      now: () => now
    };

    const response = await authed({
      mode: "deleteOrphans",
      confirmDeletion: true
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      scannedCount: 1,
      orphanedCount: 1,
      deletedCount: 0,
      externalActionTaken: false,
      candidates: [
        {
          attachmentID: "changed_generation_123",
          status: "orphanedStorageObject",
          canDelete: false,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual(["users/user_123/proofAttachments/changed_generation_123"]);
  });

  it("does not delete Storage objects with mismatched owner metadata", async () => {
    const object = storageObject("unsafe_123", {
      metadata: {
        ownerUserID: "someone_else",
        proofID: "proof_123",
        attachmentID: "unsafe_123",
        idempotencyKey: "someone_else-unsafe_123"
      }
    });
    const { dependencies, deletedPaths } = makeDependencies({ objects: [object] });

    const response = await authed({
      mode: "deleteOrphans",
      confirmDeletion: true
    }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      scannedCount: 1,
      orphanedCount: 0,
      deletedCount: 0,
      externalActionTaken: false,
      candidates: [
        {
          attachmentID: "unsafe_123",
          status: "metadataMismatch",
          canDelete: false,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual([]);
  });

  it("flags existing Firestore attachments with mismatched receipts", async () => {
    const object = storageObject("mismatch_123");
    const { dependencies, deletedPaths } = makeDependencies({
      objects: [object],
      firestoreAttachments: {
        mismatch_123: {
          ...firestoreAttachment("mismatch_123"),
          uploadReceipt: {
            ...firestoreAttachment("mismatch_123").uploadReceipt,
            byteCount: 12
          }
        }
      }
    });

    const response = await authed({ mode: "reportOnly" }, dependencies);

    expect(response).toMatchObject({
      ok: true,
      scannedCount: 1,
      orphanedCount: 0,
      deletedCount: 0,
      candidates: [
        {
          attachmentID: "mismatch_123",
          status: "firestoreReceiptMismatch",
          canDelete: false,
          deleted: false
        }
      ]
    });
    expect(deletedPaths).toEqual([]);
  });

  it("validates request shape and attachment filters", async () => {
    const { dependencies, requestedAttachmentIDs } = makeDependencies({
      objects: [storageObject("attachment_123")]
    });

    await expect(authed({
      attachmentIDs: ["attachment_123", "attachment_123"],
      maxAttachments: 5
    }, dependencies)).resolves.toMatchObject({
      ok: true,
      scannedCount: 1
    });
    expect(requestedAttachmentIDs).toEqual([["attachment_123"]]);

    await expect(authed({
      mode: "deleteEverything"
    }, dependencies)).resolves.toMatchObject({
      ok: false,
      code: "invalid-argument"
    });

    await expect(authed({
      maxAttachments: 0
    }, dependencies)).resolves.toMatchObject({
      ok: false,
      code: "invalid-argument"
    });

    await expect(authed({
      attachmentIDs: []
    }, dependencies)).resolves.toMatchObject({
      ok: false,
      code: "invalid-argument"
    });

    await expect(authed({
      attachmentIDs: ["nested/path"]
    }, dependencies)).resolves.toMatchObject({
      ok: false,
      code: "invalid-argument"
    });

    await expect(authed({
      minimumAgeMinutes: 0
    }, dependencies)).resolves.toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
  });
});
