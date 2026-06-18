import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { readFileSync } from "node:fs";
import { deleteObject, getBytes, ref, uploadBytes, uploadString } from "firebase/storage";

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "openlarp-rules-test",
    storage: {
      rules: readFileSync(new URL("../../storage.rules", import.meta.url), "utf8")
    }
  });
});

beforeEach(async () => {
  await testEnv.clearStorage();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("Storage rules", () => {
  it("allows owner proof attachment uploads and reads for approved content types", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    const attachment = ref(alice, "users/alice/proofAttachments/proof1.png");

    await assertSucceeds(uploadString(
      attachment,
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "proof1.png", "image/png")
    ));
    await assertSucceeds(getBytes(attachment));
  });

  it("blocks overwriting existing proof attachment bytes", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    const attachment = ref(alice, "users/alice/proofAttachments/write-once.txt");

    await assertSucceeds(uploadString(
      attachment,
      "original-proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "write-once.txt", "text/plain")
    ));

    await assertFails(uploadString(
      attachment,
      "replacement-proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "write-once.txt", "text/plain")
    ));
  });

  it("blocks cross-user reads, unsupported content types, missing metadata, and deletes", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    const bob = testEnv.authenticatedContext("bob").storage();
    const aliceAttachment = ref(alice, "users/alice/proofAttachments/proof1.txt");

    await assertSucceeds(uploadString(
      aliceAttachment,
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "proof1.txt", "text/plain")
    ));
    await assertFails(getBytes(ref(bob, "users/alice/proofAttachments/proof1.txt")));
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/proof1.zip"),
      "zip-bytes",
      "raw",
      storageMetadata("alice", "proof1", "proof1.zip", "application/zip")
    ));
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/missing-metadata.txt"),
      "proof-bytes",
      "raw",
      { contentType: "text/plain" }
    ));
    await assertFails(deleteObject(aliceAttachment));
  });

  it("allows real proof attachment content types and enforces size", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();

    await assertSucceeds(uploadBytes(
      ref(alice, "users/alice/proofAttachments/proof1.pdf"),
      new Uint8Array(1024),
      storageMetadata("alice", "proof1", "proof1.pdf", "application/pdf")
    ));

    await assertSucceeds(uploadBytes(
      ref(alice, "users/alice/proofAttachments/proof1.jpg"),
      new Uint8Array(1024),
      storageMetadata("alice", "proof1", "proof1.jpg", "image/jpeg")
    ));

    await assertFails(uploadBytes(
      ref(alice, "users/alice/proofAttachments/too-large.pdf"),
      new Uint8Array(10 * 1024 * 1024),
      storageMetadata("alice", "proof1", "too-large.pdf", "application/pdf")
    ));
  });

  it("blocks unauthenticated and cross-owner proof attachment writes", async () => {
    const guest = testEnv.unauthenticatedContext().storage();
    const bob = testEnv.authenticatedContext("bob").storage();

    await assertFails(uploadString(
      ref(guest, "users/alice/proofAttachments/proof1.txt"),
      "proof",
      "raw",
      storageMetadata("alice", "proof1", "proof1.txt", "text/plain")
    ));

    await assertFails(uploadString(
      ref(bob, "users/alice/proofAttachments/proof1.txt"),
      "proof",
      "raw",
      storageMetadata("alice", "proof1", "proof1.txt", "text/plain")
    ));

    await assertFails(uploadString(
      ref(bob, "users/bob/proofAttachments/proof1.txt"),
      "proof",
      "raw",
      storageMetadata("alice", "proof1", "proof1.txt", "text/plain")
    ));
  });

  it("requires proof attachment upload metadata to match the storage path", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();

    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/proof1.txt"),
      "proof",
      "raw",
      storageMetadata("alice", "proof1", "different-attachment.txt", "text/plain")
    ));

    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/proof1.txt"),
      "proof",
      "raw",
      {
        contentType: "text/plain",
        customMetadata: {
          ownerUserID: "alice",
          proofID: "proof1",
          attachmentID: "proof1.txt",
          idempotencyKey: "wrong-key"
        }
      }
    ));
  });
});

function storageMetadata(ownerUserID, proofID, attachmentID, contentType) {
  return {
    contentType,
    customMetadata: {
      ownerUserID,
      proofID,
      attachmentID,
      idempotencyKey: `${ownerUserID}-${attachmentID}`
    }
  };
}
