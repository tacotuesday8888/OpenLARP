import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { readFileSync } from "node:fs";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "openlarp-rules-test",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8")
    }
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("Firestore rules", () => {
  it("allows users to write only their own safe profile tree", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const bob = testEnv.authenticatedContext("bob").firestore();

    await assertSucceeds(setDoc(doc(alice, "users/alice"), { ownerUserID: "alice", displayName: "Alice" }));
    await assertSucceeds(getDoc(doc(alice, "users/alice")));
    await assertFails(getDoc(doc(bob, "users/alice")));
    await assertFails(setDoc(doc(alice, "users/bob"), { ownerUserID: "alice" }));
  });

  it("rejects owner mismatch and external action claims", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();

    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/proof1"), {
      metadata: { ownerUserID: "mallory" },
      title: "Bad owner"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/agentActivities/activity1"), {
      ownerUserID: "alice",
      externalActionTaken: true
    }));

    await assertFails(setDoc(doc(alice, "users/alice/agentActivities/activity2"), {
      ownerUserID: "alice",
      title: "Arbitrary client-owned collection should not be writable"
    }));
  });

  it("rejects client-written sync status on regular user-tree documents", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();

    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/pending-sync"), {
      ownerUserID: "alice",
      syncStatus: "pending",
      title: "Unsafe status"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/acknowledged-sync"), {
      ownerUserID: "alice",
      syncStatus: "acknowledged",
      title: "Server-only status"
    }));
  });

  it("prevents clients from writing backend event acknowledgements", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const bob = testEnv.authenticatedContext("bob").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");
    const eventRef = doc(alice, "users/alice/backendEvents/event1");

    await assertFails(setDoc(eventRef, {
      ownerUserID: "alice",
      kind: "questStarted",
      syncStatus: "pending",
      entityID: "quest1",
      idempotencyKey: "alice-questStarted-quest1"
    }));

    await assertFails(setDoc(eventRef, safeBackendEvent("alice", "event1", timestamp)));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "users/alice/backendEvents/event1"),
        safeBackendEvent("alice", "event1", timestamp)
      );
    });

    await assertSucceeds(getDoc(eventRef));
    await assertFails(getDoc(doc(bob, "users/alice/backendEvents/event1")));
    await assertFails(updateDoc(eventRef, { syncStatus: "failed" }));
    await assertFails(updateDoc(eventRef, { acceptedAt: new Date("2026-06-18T01:00:00.000Z") }));
    await assertFails(deleteDoc(eventRef));
  });

  it("allows real career graph document contracts under the owner tree", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const bob = testEnv.authenticatedContext("bob").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");

    await assertSucceeds(setDoc(doc(alice, "users/alice/profiles/profile1"), {
      metadata: safeMetadata("alice", "profile1", timestamp),
      accountID: null,
      email: null,
      displayName: "Early-career candidate",
      segment: "newGrad",
      backgroundSummary: "",
      minutesPerDay: 25,
      networkingComfort: 3,
      privacy: {
        memoryMode: "cloudReady",
        shareWins: true,
        allowsPrivateEvidenceCloudSync: true,
        requireApprovalForExternalActions: true
      },
      collectionPath: "users/alice/profiles",
      documentPath: "users/alice/profiles/profile1"
    }));

    await seedPrivateEvidenceConsent("alice", timestamp);

    await assertSucceeds(setDoc(doc(alice, "users/alice/goals/current"), {
      schemaVersion: 1,
      ownerUserID: "alice",
      localID: "current",
      currentStatus: "newGrad",
      targetRole: "AI product engineer",
      timeline: "30 days",
      collectionPath: "users/alice/goals",
      documentPath: "users/alice/goals/current"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/targetRoles/role1"), {
      metadata: safeMetadata("alice", "role1", timestamp),
      title: "AI product engineer",
      seniority: "entry",
      roleFamily: "ai",
      timeline: "30 days",
      keywords: ["SwiftUI", "AI", "product"],
      preferredLocations: ["Remote"],
      status: "active",
      collectionPath: "users/alice/targetRoles",
      documentPath: "users/alice/targetRoles/role1"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/proofRecords/proof1"), {
      metadata: safeMetadata("alice", "proof1", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "Mapped real postings to shipped SwiftUI work.",
      link: "https://example.com/proof",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof1"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/proofAttachments/attachment1"), {
      metadata: safeMetadata("alice", "attachment1", timestamp),
      proofID: "proof1",
      fileName: "proof.png",
      originalFileName: "proof.png",
      contentType: "image/png",
      byteCount: 32000,
      createdAt: timestamp,
      storagePath: "users/alice/proofAttachments/attachment1",
      uploadStatus: "pendingUpload",
      collectionPath: "users/alice/proofAttachments",
      documentPath: "users/alice/proofAttachments/attachment1"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/outcomes/outcome1"), {
      metadata: safeMetadata("alice", "outcome1", timestamp),
      kind: "interview",
      title: "Technical screen",
      organizationName: "",
      note: "",
      occurredAt: timestamp,
      targetRoleTitle: "AI product engineer",
      isPrivate: false,
      collectionPath: "users/alice/outcomes",
      documentPath: "users/alice/outcomes/outcome1"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/readinessSnapshots/snapshot1"), {
      metadata: safeMetadata("alice", "snapshot1", timestamp),
      source: "proofClaim",
      reason: "Accepted proof",
      overall: 62,
      proofStrength: 68,
      confidence: 58,
      consistency: 55,
      skillProof: 70,
      networkStrength: 42,
      collectionPath: "users/alice/readinessSnapshots",
      documentPath: "users/alice/readinessSnapshots/snapshot1"
    }));

    await assertFails(getDoc(doc(bob, "users/alice/proofRecords/proof1")));
  });

  it("does not treat shareWins as private evidence sync consent", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");

    await assertSucceeds(setDoc(doc(alice, "users/alice/profiles/profile1"), {
      metadata: safeMetadata("alice", "profile1", timestamp),
      displayName: "Early-career candidate",
      segment: "newGrad",
      backgroundSummary: "",
      minutesPerDay: 25,
      networkingComfort: 3,
      privacy: {
        memoryMode: "cloudReady",
        shareWins: true,
        allowsPrivateEvidenceCloudSync: false,
        requireApprovalForExternalActions: true
      },
      collectionPath: "users/alice/profiles",
      documentPath: "users/alice/profiles/profile1"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/goals/public-goal"), {
      schemaVersion: 1,
      ownerUserID: "alice",
      localID: "public-goal",
      currentStatus: "newGrad",
      targetRole: "AI product engineer",
      timeline: "30 days",
      collectionPath: "users/alice/goals",
      documentPath: "users/alice/goals/public-goal"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/goals/private-goal-no-consent"), {
      schemaVersion: 1,
      ownerUserID: "alice",
      localID: "private-goal-no-consent",
      currentStatus: "newGrad",
      targetRole: "AI product engineer",
      timeline: "30 days",
      privateContext: {
        background: "Private background should not sync without consent.",
        existingProof: "Private proof inventory.",
        confidence: 3,
        biggestBlocker: "Private blocker."
      },
      collectionPath: "users/alice/goals",
      documentPath: "users/alice/goals/private-goal-no-consent"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/proof-no-consent"), {
      metadata: safeMetadata("alice", "proof-no-consent", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "This proof should not sync without private evidence consent.",
      link: "https://example.com/proof",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof-no-consent"
    }));

    await assertSucceeds(setDoc(doc(alice, "users/alice/outcomes/public-outcome"), {
      metadata: safeMetadata("alice", "public-outcome", timestamp),
      kind: "interview",
      title: "Public outcome",
      organizationName: "",
      note: "",
      occurredAt: timestamp,
      targetRoleTitle: "AI product engineer",
      isPrivate: false,
      collectionPath: "users/alice/outcomes",
      documentPath: "users/alice/outcomes/public-outcome"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/outcomes/private-outcome-no-consent"), {
      metadata: safeMetadata("alice", "private-outcome-no-consent", timestamp),
      kind: "interview",
      title: "Private outcome",
      organizationName: "Private organization",
      note: "Private outcome note should not sync without consent.",
      occurredAt: timestamp,
      targetRoleTitle: "AI product engineer",
      isPrivate: true,
      collectionPath: "users/alice/outcomes",
      documentPath: "users/alice/outcomes/private-outcome-no-consent"
    }));

    await seedPrivateEvidenceConsent("alice", timestamp, {
      status: "revoked",
      allowsPrivateEvidenceCloudSync: false,
      revokedAt: timestamp
    });
    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/proof-revoked-consent"), {
      metadata: safeMetadata("alice", "proof-revoked-consent", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "This proof should not sync after revoked private evidence consent.",
      link: "https://example.com/proof",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof-revoked-consent"
    }));
    await assertFails(setDoc(doc(alice, "users/alice/goals/private-goal-revoked-consent"), {
      schemaVersion: 1,
      ownerUserID: "alice",
      localID: "private-goal-revoked-consent",
      currentStatus: "newGrad",
      targetRole: "AI product engineer",
      timeline: "30 days",
      privateContext: {
        background: "Private background should not sync after revoked consent.",
        existingProof: "Private proof inventory.",
        confidence: 3,
        biggestBlocker: "Private blocker."
      },
      collectionPath: "users/alice/goals",
      documentPath: "users/alice/goals/private-goal-revoked-consent"
    }));
    await assertFails(setDoc(doc(alice, "users/alice/outcomes/private-outcome-revoked-consent"), {
      metadata: safeMetadata("alice", "private-outcome-revoked-consent", timestamp),
      kind: "interview",
      title: "Private outcome",
      organizationName: "Private organization",
      note: "Private outcome note should not sync after revoked consent.",
      occurredAt: timestamp,
      targetRoleTitle: "AI product engineer",
      isPrivate: true,
      collectionPath: "users/alice/outcomes",
      documentPath: "users/alice/outcomes/private-outcome-revoked-consent"
    }));

    await seedPrivateEvidenceConsent("alice", timestamp, {
      consentTextVersion: "private-evidence-cloud-sync-v0"
    });
    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/proof-stale-consent-version"), {
      metadata: safeMetadata("alice", "proof-stale-consent-version", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "This proof should not sync with stale consent text.",
      link: "https://example.com/proof",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof-stale-consent-version"
    }));

    await seedPrivateEvidenceConsent("alice", timestamp, {
      ownerUserID: "bob"
    });
    await assertFails(setDoc(doc(alice, "users/alice/goals/private-goal-wrong-consent-owner"), {
      schemaVersion: 1,
      ownerUserID: "alice",
      localID: "private-goal-wrong-consent-owner",
      currentStatus: "newGrad",
      targetRole: "AI product engineer",
      timeline: "30 days",
      privateContext: {
        background: "Private background should not sync with wrong consent owner.",
        existingProof: "Private proof inventory.",
        confidence: 3,
        biggestBlocker: "Private blocker."
      },
      collectionPath: "users/alice/goals",
      documentPath: "users/alice/goals/private-goal-wrong-consent-owner"
    }));

    await seedPrivateEvidenceConsent("alice", timestamp, {
      schemaVersion: 0
    });
    await assertFails(setDoc(doc(alice, "users/alice/outcomes/private-outcome-wrong-consent-schema"), {
      metadata: safeMetadata("alice", "private-outcome-wrong-consent-schema", timestamp),
      kind: "interview",
      title: "Private outcome",
      organizationName: "Private organization",
      note: "Private outcome note should not sync with wrong consent schema.",
      occurredAt: timestamp,
      targetRoleTitle: "AI product engineer",
      isPrivate: true,
      collectionPath: "users/alice/outcomes",
      documentPath: "users/alice/outcomes/private-outcome-wrong-consent-schema"
    }));

    await seedPrivateEvidenceConsent("alice", timestamp);
    await assertSucceeds(setDoc(doc(alice, "users/alice/goals/private-goal-with-consent"), {
      schemaVersion: 1,
      ownerUserID: "alice",
      localID: "private-goal-with-consent",
      currentStatus: "newGrad",
      targetRole: "AI product engineer",
      timeline: "30 days",
      privateContext: {
        background: "Private background can sync only after consent.",
        existingProof: "Private proof inventory.",
        confidence: 3,
        biggestBlocker: "Private blocker."
      },
      collectionPath: "users/alice/goals",
      documentPath: "users/alice/goals/private-goal-with-consent"
    }));
    await assertSucceeds(setDoc(doc(alice, "users/alice/proofRecords/proof-with-consent"), {
      metadata: safeMetadata("alice", "proof-with-consent", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "This proof can sync only after explicit private evidence consent.",
      link: "https://example.com/proof",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof-with-consent"
    }));
    await assertSucceeds(setDoc(doc(alice, "users/alice/outcomes/private-outcome-with-consent"), {
      metadata: safeMetadata("alice", "private-outcome-with-consent", timestamp),
      kind: "interview",
      title: "Private outcome",
      organizationName: "Private organization",
      note: "Private outcome can sync only after consent.",
      occurredAt: timestamp,
      targetRoleTitle: "AI product engineer",
      isPrivate: true,
      collectionPath: "users/alice/outcomes",
      documentPath: "users/alice/outcomes/private-outcome-with-consent"
    }));
  });

  it("denies client-authored private evidence consent documents", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");

    await assertFails(setDoc(
      doc(alice, "users/alice/consents/privateEvidenceCloudSync"),
      safePrivateEvidenceConsent("alice", timestamp)
    ));
  });

  it("blocks client user-tree writes after account deletion has been requested", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");
    await seedPrivateEvidenceConsent("alice", timestamp);
    await seedAccountDeletionRequest("alice", timestamp);

    await assertFails(setDoc(doc(alice, "users/alice"), {
      ownerUserID: "alice",
      displayName: "Alice"
    }));
    await assertFails(setDoc(doc(alice, "users/alice/profiles/profile1"), {
      metadata: safeMetadata("alice", "profile1", timestamp),
      displayName: "Early-career candidate",
      collectionPath: "users/alice/profiles",
      documentPath: "users/alice/profiles/profile1"
    }));
    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/proof1"), {
      metadata: safeMetadata("alice", "proof1", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "This should not sync after deletion starts.",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof1"
    }));
    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/attachment1"), {
      metadata: safeMetadata("alice", "attachment1", timestamp),
      proofID: "proof1",
      fileName: "proof.png",
      originalFileName: "proof.png",
      contentType: "image/png",
      byteCount: 32000,
      createdAt: timestamp,
      storagePath: "users/alice/proofAttachments/attachment1",
      uploadStatus: "pendingUpload",
      collectionPath: "users/alice/proofAttachments",
      documentPath: "users/alice/proofAttachments/attachment1"
    }));
    await assertFails(setDoc(
      doc(alice, "_accountDeletionRequests/alice"),
      safeAccountDeletionRequest("alice", timestamp)
    ));
  });

  it("rejects career graph update bypasses", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");
    const proofRef = doc(alice, "users/alice/proofRecords/proof1");

    await seedPrivateEvidenceConsent("alice", timestamp);

    await assertSucceeds(setDoc(proofRef, {
      metadata: safeMetadata("alice", "proof1", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "Mapped real postings to shipped SwiftUI work.",
      link: "https://example.com/proof",
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof1"
    }));

    await assertFails(updateDoc(proofRef, { "metadata.ownerUserID": "bob" }));
    await assertFails(updateDoc(proofRef, { externalActionTaken: true }));
    await assertFails(updateDoc(proofRef, { syncStatus: "pending" }));
    await assertFails(deleteDoc(proofRef));
  });

  it("rejects proof records that embed attachment documents or local file paths", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");

    await seedPrivateEvidenceConsent("alice", timestamp);

    await assertFails(setDoc(doc(alice, "users/alice/proofRecords/proof-with-nested-attachment"), {
      metadata: safeMetadata("alice", "proof-with-nested-attachment", timestamp),
      questID: "quest1",
      questTitle: "Map role requirements",
      kind: "proof",
      text: "Mapped real postings to shipped SwiftUI work.",
      link: "https://example.com/proof",
      attachments: [{
        metadata: safeMetadata("alice", "attachment1", timestamp),
        proofID: "proof-with-nested-attachment",
        fileName: "proof.png",
        originalFileName: "proof.png",
        contentType: "image/png",
        byteCount: 32000,
        createdAt: timestamp,
        storagePath: "users/alice/proofAttachments/attachment1",
        uploadStatus: "uploaded",
        uploadReceipt: safeUploadedReceipt("alice", "proof-with-nested-attachment", "attachment1", "image/png", 32000, timestamp),
        collectionPath: "users/alice/proofAttachments",
        documentPath: "users/alice/proofAttachments/attachment1",
        localRelativePath: "ProofAttachments/private.png"
      }],
      submittedAt: timestamp,
      collectionPath: "users/alice/proofRecords",
      documentPath: "users/alice/proofRecords/proof-with-nested-attachment"
    }));
  });

  it("allows only pending client proof attachment metadata before server receipt promotion", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");
    await seedPrivateEvidenceConsent("alice", timestamp);
    const pendingAttachment = {
      metadata: safeMetadata("alice", "attachment1", timestamp),
      proofID: "proof1",
      fileName: "proof.png",
      originalFileName: "proof.png",
      contentType: "image/png",
      byteCount: 32000,
      createdAt: timestamp,
      storagePath: "users/alice/proofAttachments/attachment1",
      uploadStatus: "pendingUpload",
      collectionPath: "users/alice/proofAttachments",
      documentPath: "users/alice/proofAttachments/attachment1"
    };

    await assertSucceeds(setDoc(doc(alice, "users/alice/proofAttachments/attachment1"), pendingAttachment));

    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/client-uploaded"), {
      ...pendingAttachment,
      metadata: safeMetadata("alice", "client-uploaded", timestamp),
      storagePath: "users/alice/proofAttachments/client-uploaded",
      uploadStatus: "uploaded",
      uploadReceipt: safeUploadedReceipt("alice", "proof1", "client-uploaded", "image/png", 32000, timestamp),
      documentPath: "users/alice/proofAttachments/client-uploaded"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/pending-with-receipt"), {
      ...pendingAttachment,
      metadata: safeMetadata("alice", "pending-with-receipt", timestamp),
      storagePath: "users/alice/proofAttachments/pending-with-receipt",
      uploadReceipt: safeUploadedReceipt("alice", "proof1", "pending-with-receipt", "image/png", 32000, timestamp),
      documentPath: "users/alice/proofAttachments/pending-with-receipt"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/attachment2"), {
      ...pendingAttachment,
      metadata: safeMetadata("alice", "attachment2", timestamp),
      storagePath: "users/alice/proofAttachments/attachment1",
      documentPath: "users/alice/proofAttachments/attachment2"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/attachment3"), {
      ...pendingAttachment,
      metadata: safeMetadata("alice", "attachment3", timestamp),
      storagePath: "users/bob/proofAttachments/attachment3",
      documentPath: "users/alice/proofAttachments/attachment3"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/attachment4"), {
      ...pendingAttachment,
      metadata: safeMetadata("bob", "attachment4", timestamp),
      storagePath: "users/alice/proofAttachments/attachment4",
      documentPath: "users/alice/proofAttachments/attachment4"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/proofAttachments/attachment5"), {
      ...pendingAttachment,
      metadata: safeMetadata("alice", "attachment5", timestamp),
      storagePath: "users/alice/proofAttachments/attachment5",
      documentPath: "users/alice/proofAttachments/attachment5",
      localRelativePath: "ProofAttachments/proof.png"
    }));
  });

  it("prevents clients from overwriting server-promoted proof attachment receipts", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");
    const attachmentRef = doc(alice, "users/alice/proofAttachments/server-promoted");
    const serverPromotedAttachment = {
      metadata: safeMetadata("alice", "server-promoted", timestamp),
      proofID: "proof1",
      fileName: "proof.png",
      originalFileName: "proof.png",
      contentType: "image/png",
      byteCount: 32000,
      createdAt: timestamp,
      storagePath: "users/alice/proofAttachments/server-promoted",
      uploadStatus: "uploaded",
      uploadReceipt: safeUploadedReceipt("alice", "proof1", "server-promoted", "image/png", 32000, timestamp),
      collectionPath: "users/alice/proofAttachments",
      documentPath: "users/alice/proofAttachments/server-promoted"
    };

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "users/alice/proofAttachments/server-promoted"),
        serverPromotedAttachment
      );
    });

    const downgradedAttachment = {
      ...serverPromotedAttachment,
      uploadStatus: "pendingUpload"
    };
    delete downgradedAttachment.uploadReceipt;
    await assertFails(setDoc(attachmentRef, downgradedAttachment));
    await assertFails(updateDoc(attachmentRef, {
      uploadStatus: "pendingUpload"
    }));
  });

  it("keeps backend event history server-owned even for valid acknowledged payloads", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const bob = testEnv.authenticatedContext("bob").firestore();
    const timestamp = new Date("2026-06-18T00:00:00.000Z");
    const eventRef = doc(alice, "users/alice/backendEvents/event1");

    await assertFails(setDoc(eventRef, safeBackendEvent("alice", "event1", timestamp)));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/bad-owner"), {
      ownerUserID: "bob",
      entityID: "event1",
      kind: "proofClaimed",
      syncStatus: "acknowledged",
      idempotencyKey: "bob-proofClaimed-event1"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/bad-kind"), {
      ownerUserID: "alice",
      entityID: "event1",
      kind: 123,
      syncStatus: "acknowledged",
      idempotencyKey: "alice-proofClaimed-event1"
    }));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/unknown-kind"), {
      schemaVersion: 1,
      eventID: "unknown-kind",
      ownerUserID: "alice",
      entityID: "unknown-kind",
      kind: "inventedEvent",
      syncStatus: "acknowledged",
      idempotencyKey: "alice-inventedEvent-unknown-kind",
      occurredAt: timestamp,
      retryCount: 0,
      summary: {},
      acceptedAt: timestamp
    }));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/bad-last-attempt"), {
      schemaVersion: 1,
      eventID: "bad-last-attempt",
      ownerUserID: "alice",
      entityID: "bad-last-attempt",
      kind: "proofClaimed",
      syncStatus: "acknowledged",
      idempotencyKey: "alice-proofClaimed-bad-last-attempt",
      occurredAt: timestamp,
      retryCount: 0,
      lastAttemptAt: "not-a-timestamp",
      summary: {},
      acceptedAt: timestamp
    }));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/bad-summary-key"), {
      schemaVersion: 1,
      eventID: "bad-summary-key",
      ownerUserID: "alice",
      entityID: "bad-summary-key",
      kind: "proofClaimed",
      syncStatus: "acknowledged",
      idempotencyKey: "alice-proofClaimed-bad-summary-key",
      occurredAt: timestamp,
      retryCount: 0,
      summary: { proofCount: 1, privateRawPayload: "nope" },
      acceptedAt: timestamp
    }));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/bad-summary-type"), {
      schemaVersion: 1,
      eventID: "bad-summary-type",
      ownerUserID: "alice",
      entityID: "bad-summary-type",
      kind: "proofClaimed",
      syncStatus: "acknowledged",
      idempotencyKey: "alice-proofClaimed-bad-summary-type",
      occurredAt: timestamp,
      retryCount: 0,
      summary: { proofCount: "one" },
      acceptedAt: timestamp
    }));

    await assertFails(setDoc(doc(alice, "users/alice/backendEvents/missing-key"), {
      ownerUserID: "alice",
      entityID: "event1",
      kind: "proofClaimed",
      syncStatus: "acknowledged"
    }));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "users/alice/backendEvents/event1"),
        safeBackendEvent("alice", "event1", timestamp)
      );
    });

    await assertSucceeds(getDoc(eventRef));
    await assertFails(getDoc(doc(bob, "users/alice/backendEvents/event1")));
    await assertFails(setDoc(eventRef, safeBackendEvent("alice", "event1", timestamp)));
  });
});

function safeMetadata(ownerUserID, localID, timestamp) {
  return {
    schemaVersion: 1,
    ownerUserID,
    localID,
    createdAt: timestamp,
    updatedAt: timestamp
  };
}

function safeUploadedReceipt(ownerUserID, proofID, attachmentID, contentType, byteCount, timestamp) {
  return {
    schemaVersion: 1,
    proofID,
    attachmentID,
    storagePath: `users/${ownerUserID}/proofAttachments/${attachmentID}`,
    contentType,
    byteCount,
    status: "uploaded",
    uploadedAt: timestamp,
    storageBucket: "openlarp-test.appspot.com",
    storageGeneration: 101,
    metadataGeneration: 2,
    md5Hash: "mock-md5",
    idempotencyKey: `${ownerUserID}-${attachmentID}`
  };
}

async function seedPrivateEvidenceConsent(ownerUserID, timestamp, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `users/${ownerUserID}/consents/privateEvidenceCloudSync`),
      safePrivateEvidenceConsent(ownerUserID, timestamp, overrides)
    );
  });
}

async function seedAccountDeletionRequest(ownerUserID, timestamp, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `_accountDeletionRequests/${ownerUserID}`),
      safeAccountDeletionRequest(ownerUserID, timestamp, overrides)
    );
  });
}

function safeAccountDeletionRequest(ownerUserID, timestamp, overrides = {}) {
  return {
    schemaVersion: 1,
    ownerUserID,
    status: "deleting",
    requestedAt: timestamp,
    updatedAt: timestamp,
    collectionPath: "_accountDeletionRequests",
    documentPath: `_accountDeletionRequests/${ownerUserID}`,
    ...overrides
  };
}

function safePrivateEvidenceConsent(ownerUserID, timestamp, overrides = {}) {
  const document = {
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
    delete document.acceptedAt;
  }
  return {
    ...document,
    ...overrides
  };
}

function safeBackendEvent(ownerUserID, eventID, timestamp) {
  return {
    schemaVersion: 1,
    eventID,
    ownerUserID,
    entityID: eventID,
    kind: "proofClaimed",
    syncStatus: "acknowledged",
    idempotencyKey: `${ownerUserID}-proofClaimed-${eventID}`,
    occurredAt: timestamp,
    retryCount: 0,
    lastAttemptAt: timestamp,
    summary: { proofCount: 1, qualityAccepted: true },
    acceptedAt: timestamp
  };
}
