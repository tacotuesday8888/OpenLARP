import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { readFileSync } from "node:fs";
import { deleteDoc, doc, getDoc, setDoc } from "firebase/firestore";

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
  });

  it("requires acknowledged backend event shape and denies deletes", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    const eventRef = doc(alice, "users/alice/backendEvents/event1");

    await assertFails(setDoc(eventRef, {
      ownerUserID: "alice",
      kind: "questStarted",
      syncStatus: "pending",
      idempotencyKey: "alice-questStarted-event1"
    }));

    await assertSucceeds(setDoc(eventRef, {
      ownerUserID: "alice",
      kind: "questStarted",
      syncStatus: "acknowledged",
      idempotencyKey: "alice-questStarted-event1"
    }));

    await assertFails(deleteDoc(eventRef));
  });
});
