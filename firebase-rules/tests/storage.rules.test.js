import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { readFileSync } from "node:fs";
import { doc, setDoc } from "firebase/firestore";
import { deleteObject, getBytes, ref, uploadBytes, uploadString } from "firebase/storage";

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "openlarp-rules-test",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8")
    },
    storage: {
      rules: readFileSync(new URL("../../storage.rules", import.meta.url), "utf8")
    }
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("Storage rules", () => {
  it("allows owner proof attachment uploads and reads for approved content types", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    const attachment = ref(alice, "users/alice/proofAttachments/proof1.png");
    await seedPrivateEvidenceConsent("alice");

    await assertSucceeds(uploadString(
      attachment,
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "proof1.png", "image/png")
    ));
    await assertSucceeds(getBytes(attachment));
  });

  it("rejects proof attachment uploads without private evidence sync consent", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();

    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/no-consent.txt"),
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "no-consent.txt", "text/plain")
    ));

    await seedPrivateEvidenceConsent("alice", {
      status: "revoked",
      allowsPrivateEvidenceCloudSync: false,
      revokedAt: new Date("2026-06-18T00:01:00.000Z")
    });
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/revoked-consent.txt"),
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "revoked-consent.txt", "text/plain")
    ));

    await seedPrivateEvidenceConsent("alice", {
      consentTextVersion: "private-evidence-cloud-sync-v0"
    });
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/stale-consent-version.txt"),
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "stale-consent-version.txt", "text/plain")
    ));

    await seedPrivateEvidenceConsent("alice", {
      ownerUserID: "bob"
    });
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/wrong-consent-owner.txt"),
      "proof-bytes",
      "raw",
      storageMetadata("alice", "proof1", "wrong-consent-owner.txt", "text/plain")
    ));
  });

  it("blocks overwriting existing proof attachment bytes", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    const attachment = ref(alice, "users/alice/proofAttachments/write-once.txt");
    await seedPrivateEvidenceConsent("alice");

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
    await seedPrivateEvidenceConsent("alice");

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
      ref(alice, "users/alice/proofAttachments/proof1.svg"),
      "<svg></svg>",
      "raw",
      storageMetadata("alice", "proof1", "proof1.svg", "image/svg+xml")
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
    await seedPrivateEvidenceConsent("alice");

    await assertSucceeds(uploadString(
      ref(alice, "users/alice/proofAttachments/proof1.jpg"),
      "jpeg-proof-bytes",
      "raw",
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
    await seedPrivateEvidenceConsent("alice");
    await seedPrivateEvidenceConsent("bob");

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
    await seedPrivateEvidenceConsent("alice");

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

  it("blocks extra or oversized proof attachment upload metadata", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    await seedPrivateEvidenceConsent("alice");
    const withExtraMetadata = storageMetadata("alice", "proof1", "extra-metadata.txt", "text/plain");
    withExtraMetadata.customMetadata.localRelativePath = "ProofAttachments/private-local-path.txt";

    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/extra-metadata.txt"),
      "proof",
      "raw",
      withExtraMetadata
    ));

    const oversizedProofID = storageMetadata(
      "alice",
      "p".repeat(129),
      "oversized-metadata.txt",
      "text/plain"
    );
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/oversized-metadata.txt"),
      "proof",
      "raw",
      oversizedProofID
    ));
  });
});

async function seedPrivateEvidenceConsent(ownerUserID, overrides = {}) {
  const timestamp = new Date("2026-06-18T00:00:00.000Z");
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const documentData = {
      schemaVersion: 1,
      ownerUserID,
      status: "accepted",
      allowsPrivateEvidenceCloudSync: true,
      acceptedAt: timestamp,
      consentTextVersion: "private-evidence-cloud-sync-v1",
      collectionPath: `users/${ownerUserID}/consents`,
      documentPath: `users/${ownerUserID}/consents/privateEvidenceCloudSync`
    };
    if (overrides.status === "revoked") {
      delete documentData.acceptedAt;
    }
    await setDoc(
      doc(context.firestore(), `users/${ownerUserID}/consents/privateEvidenceCloudSync`),
      {
        ...documentData,
        ...overrides
      }
    );
  });
}

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
