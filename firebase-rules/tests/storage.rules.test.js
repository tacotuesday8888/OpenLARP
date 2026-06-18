import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { readFileSync } from "node:fs";
import { deleteObject, getBytes, ref, uploadString } from "firebase/storage";

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

    await assertSucceeds(uploadString(attachment, "proof-bytes", "raw", { contentType: "image/png" }));
    await assertSucceeds(getBytes(attachment));
  });

  it("blocks cross-user reads, unsupported content types, and deletes", async () => {
    const alice = testEnv.authenticatedContext("alice").storage();
    const bob = testEnv.authenticatedContext("bob").storage();
    const aliceAttachment = ref(alice, "users/alice/proofAttachments/proof1.txt");

    await assertSucceeds(uploadString(aliceAttachment, "proof-bytes", "raw", { contentType: "text/plain" }));
    await assertFails(getBytes(ref(bob, "users/alice/proofAttachments/proof1.txt")));
    await assertFails(uploadString(
      ref(alice, "users/alice/proofAttachments/proof1.zip"),
      "zip-bytes",
      "raw",
      { contentType: "application/zip" }
    ));
    await assertFails(deleteObject(aliceAttachment));
  });
});
