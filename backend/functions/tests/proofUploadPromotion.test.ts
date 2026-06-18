import { describe, expect, it } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import {
  handleProofUploadPromotionRequest,
  type ProofUploadPromotionDependencies,
  type ProofUploadPromotionIntent,
  type ProofUploadPromotionResponse,
  type ProofUploadPromotionStorageObject
} from "../src/proofUploadPromotion.js";

const now = new Date("2026-06-18T12:00:00.000Z");

function promotionIntent(
  overrides: Partial<ProofUploadPromotionIntent> = {}
): ProofUploadPromotionIntent {
  return {
    schemaVersion: 1,
    proofID: "proof_123",
    attachmentID: "attachment_123",
    fileName: "proof.png",
    contentType: "image/png",
    byteCount: 32_000,
    storagePath: "users/user_123/proofAttachments/attachment_123",
    proofDocumentPath: "users/user_123/proofRecords/proof_123",
    attachmentDocumentPath: "users/user_123/proofAttachments/attachment_123",
    idempotencyKey: "user_123-attachment_123",
    ...overrides
  };
}

function storageObject(
  overrides: Partial<ProofUploadPromotionStorageObject> = {}
): ProofUploadPromotionStorageObject {
  return {
    name: "users/user_123/proofAttachments/attachment_123",
    contentType: "image/png",
    size: 32_000,
    updatedAt: "2026-06-18T11:45:00.000Z",
    bucket: "openlarp-test.appspot.com",
    generation: "101",
    metageneration: "2",
    md5Hash: "mock-md5",
    metadata: {
      ownerUserID: "user_123",
      proofID: "proof_123",
      attachmentID: "attachment_123",
      idempotencyKey: "user_123-attachment_123"
    },
    ...overrides
  };
}

function makeDependencies(object: ProofUploadPromotionStorageObject | null) {
  const writes: Array<{
    userID: string;
    attachmentID: string;
    document: Record<string, unknown>;
  }> = [];
  const readPaths: string[] = [];
  const dependencies: ProofUploadPromotionDependencies = {
    async readStorageObject(storagePath) {
      readPaths.push(storagePath);
      return object;
    },
    async writeProofAttachmentDocument(userID, attachmentID, document) {
      writes.push({ userID, attachmentID, document });
    },
    now: () => now
  };

  return { dependencies, writes, readPaths };
}

function authed(
  data: unknown,
  dependencies: ProofUploadPromotionDependencies
): Promise<ProofUploadPromotionResponse> {
  return handleProofUploadPromotionRequest({
    auth: { uid: "user_123" },
    data
  }, dependencies);
}

describe("handleProofUploadPromotionRequest", () => {
  it("requires Firebase Auth before promoting uploaded proof receipts", async () => {
    const { dependencies } = makeDependencies(storageObject());

    const response = await handleProofUploadPromotionRequest({
      auth: null,
      data: promotionIntent()
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
  });

  it("promotes a matching Storage object into a server-written proof attachment document", async () => {
    const { dependencies, writes, readPaths } = makeDependencies(storageObject());

    const response = await authed(promotionIntent(), dependencies);

    expect(readPaths).toEqual(["users/user_123/proofAttachments/attachment_123"]);
    expect(response).toMatchObject({
      ok: true,
      schemaVersion: 1,
      userID: "user_123",
      promotedAt: "2026-06-18T12:00:00.000Z",
      firestoreDocumentPath: "users/user_123/proofAttachments/attachment_123",
      externalActionTaken: false,
      uploadReceipt: {
        schemaVersion: 1,
        proofID: "proof_123",
        attachmentID: "attachment_123",
        storagePath: "users/user_123/proofAttachments/attachment_123",
        contentType: "image/png",
        byteCount: 32_000,
        status: "uploaded",
        uploadedAt: "2026-06-18T11:45:00.000Z",
        storageBucket: "openlarp-test.appspot.com",
        storageGeneration: 101,
        metadataGeneration: 2,
        md5Hash: "mock-md5",
        idempotencyKey: "user_123-attachment_123"
      }
    });
    expect(writes).toHaveLength(1);
    expect(writes[0]).toMatchObject({
      userID: "user_123",
      attachmentID: "attachment_123",
      document: {
        metadata: {
          schemaVersion: 1,
          ownerUserID: "user_123",
          localID: "attachment_123"
        },
        proofID: "proof_123",
        fileName: "proof.png",
        originalFileName: "proof.png",
        contentType: "image/png",
        byteCount: 32_000,
        storagePath: "users/user_123/proofAttachments/attachment_123",
        uploadStatus: "uploaded",
        collectionPath: "users/user_123/proofAttachments",
        documentPath: "users/user_123/proofAttachments/attachment_123"
      }
    });
    const document = writes[0]?.document;
    expect((document?.metadata as Record<string, unknown>).createdAt).toBeInstanceOf(Timestamp);
    expect((document?.metadata as Record<string, unknown>).updatedAt).toBeInstanceOf(Timestamp);
    expect(document?.createdAt).toBeInstanceOf(Timestamp);
    expect(((document?.uploadReceipt as Record<string, unknown>).uploadedAt)).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document).not.toHaveProperty("localRelativePath");
    expect(writes[0]?.document).toHaveProperty("uploadReceipt");
  });

  it("rejects cross-user paths and idempotency keys before reading Storage", async () => {
    const { dependencies, writes, readPaths } = makeDependencies(storageObject());

    const response = await authed(
      promotionIntent({
        storagePath: "users/other_user/proofAttachments/attachment_123",
        idempotencyKey: "other_user-attachment_123"
      }),
      dependencies
    );

    expect(response).toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
    expect(readPaths).toEqual([]);
    expect(writes).toEqual([]);
  });

  it("rejects unsupported content types before reading Storage", async () => {
    const { dependencies, writes, readPaths } = makeDependencies(storageObject());

    const response = await authed(
      promotionIntent({ contentType: "application/zip" }),
      dependencies
    );

    expect(response).toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
    expect(readPaths).toEqual([]);
    expect(writes).toEqual([]);
  });

  it("rejects missing Storage objects without writing Firestore", async () => {
    const { dependencies, writes } = makeDependencies(null);

    const response = await authed(promotionIntent(), dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "not-found"
    });
    expect(writes).toEqual([]);
  });

  it("rejects Storage metadata mismatches without writing Firestore", async () => {
    const cases: Array<[string, Partial<ProofUploadPromotionStorageObject>]> = [
      ["path", { name: "users/user_123/proofAttachments/other_attachment" }],
      ["content type", { contentType: "application/pdf" }],
      ["byte count", { size: 12 }],
      ["owner metadata", { metadata: { ...storageObject().metadata, ownerUserID: "other_user" } }],
      ["extra metadata", { metadata: { ...storageObject().metadata, localRelativePath: "ProofAttachments/private.png" } }]
    ];

    for (const [label, overrides] of cases) {
      const { dependencies, writes } = makeDependencies(storageObject(overrides));

      const response = await authed(promotionIntent(), dependencies);

      expect(response, label).toMatchObject({
        ok: false,
        code: "invalid-argument"
      });
      expect(writes, label).toEqual([]);
    }
  });
});
