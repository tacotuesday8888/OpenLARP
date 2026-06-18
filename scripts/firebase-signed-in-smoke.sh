#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${OPENLARP_FIREBASE_PROJECT_ID:-openlarp-dev-langqi}"
IOS_APP_ID="${OPENLARP_FIREBASE_IOS_APP_ID:-1:795318771575:ios:5315b3cc5b1bff81e30b72}"
FUNCTION_REGION="${OPENLARP_FUNCTION_REGION:-us-central1}"
STORAGE_BUCKET="${OPENLARP_FIREBASE_STORAGE_BUCKET:-${PROJECT_ID}.firebasestorage.app}"
EXPECTED_STORAGE_BUCKET="${PROJECT_ID}.firebasestorage.app"
SMOKE_UID="${OPENLARP_FIREBASE_SMOKE_UID:-openlarp-smoke-$(date -u +%Y%m%d%H%M%S)-$RANDOM}"
SIGNING_SERVICE_ACCOUNT="${OPENLARP_FIREBASE_SIGNING_SERVICE_ACCOUNT:-}"
FIREBASE="npx -y firebase-tools@15.21.0"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_command node
require_command curl
require_command /usr/libexec/PlistBuddy

printf 'OpenLARP signed-in Firebase smoke for %s\n' "$PROJECT_ID"

if [[ "$PROJECT_ID" != "openlarp-dev-langqi" &&
  "${OPENLARP_FIREBASE_SMOKE_ALLOW_PROJECT:-}" != "$PROJECT_ID" ]]; then
  fail "Refusing signed-in smoke against non-dev project '$PROJECT_ID'. Set OPENLARP_FIREBASE_SMOKE_ALLOW_PROJECT=$PROJECT_ID to confirm."
fi

if [[ "$STORAGE_BUCKET" != "$EXPECTED_STORAGE_BUCKET" &&
  "${OPENLARP_FIREBASE_SMOKE_ALLOW_BUCKET:-}" != "$STORAGE_BUCKET" ]]; then
  fail "Refusing signed-in smoke against unexpected bucket '$STORAGE_BUCKET'. Set OPENLARP_FIREBASE_SMOKE_ALLOW_BUCKET=$STORAGE_BUCKET to confirm."
fi

if [[ ! "$SMOKE_UID" =~ ^openlarp-smoke-[A-Za-z0-9_-]+$ ]]; then
  fail "OPENLARP_FIREBASE_SMOKE_UID must start with reserved prefix 'openlarp-smoke-'."
fi

if [[ "${OPENLARP_FIREBASE_SMOKE_PREFLIGHT_ONLY:-}" == "1" ]]; then
  pass "Signed-in smoke preflight passed"
  exit 0
fi

api_key="${OPENLARP_FIREBASE_WEB_API_KEY:-}"
if [[ -z "$api_key" ]]; then
  sdk_config="$tmp_dir/GoogleService-Info.plist"
  $FIREBASE apps:sdkconfig IOS "$IOS_APP_ID" --project "$PROJECT_ID" > "$sdk_config"
  api_key="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' "$sdk_config")"
fi

if [[ -z "$api_key" ]]; then
  fail "Unable to resolve Firebase Web API key from environment or iOS SDK config."
fi

if [[ -z "$SIGNING_SERVICE_ACCOUNT" ]] && command -v gcloud >/dev/null 2>&1; then
  SIGNING_SERVICE_ACCOUNT="$(
    gcloud iam service-accounts list \
      --project "$PROJECT_ID" \
      --format='value(email)' 2>/dev/null |
      grep 'firebase-adminsdk' |
      head -n 1 || true
  )"
fi

export PROJECT_ID
export IOS_APP_ID
export FUNCTION_REGION
export STORAGE_BUCKET
export SMOKE_UID
export SIGNING_SERVICE_ACCOUNT
export OPENLARP_FIREBASE_WEB_API_KEY="$api_key"

node --input-type=module <<'NODE'
import { Buffer } from "node:buffer";
import { createHash, randomUUID } from "node:crypto";
import { applicationDefault, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { getAuth as getAdminAuth } from "firebase-admin/auth";
import { getFirestore as getAdminFirestore } from "firebase-admin/firestore";
import { getStorage as getAdminStorage } from "firebase-admin/storage";
import { initializeApp as initializeClientApp, deleteApp as deleteClientApp } from "firebase/app";
import { getAuth as getClientAuth, signInWithCustomToken } from "firebase/auth";
import { doc as clientDoc, getDoc as clientGetDoc, getFirestore as getClientFirestore } from "firebase/firestore";
import {
  getBytes as clientGetBytes,
  getMetadata as clientGetMetadata,
  getStorage as getClientStorage,
  ref as clientStorageRef,
  uploadBytes as clientUploadBytes
} from "firebase/storage";

const projectID = requiredEnv("PROJECT_ID");
const iosAppID = requiredEnv("IOS_APP_ID");
const region = requiredEnv("FUNCTION_REGION");
const storageBucket = requiredEnv("STORAGE_BUCKET");
const uid = requiredEnv("SMOKE_UID");
const webAPIKey = requiredEnv("OPENLARP_FIREBASE_WEB_API_KEY");
const callableBaseURL = `https://${region}-${projectID}.cloudfunctions.net`;
const now = new Date();
const startedAt = now;
const proofID = randomUUID();
const attachmentID = randomUUID();
const backendEventID = randomUUID();
const backendEventEntityID = randomUUID();
const storagePath = `users/${uid}/proofAttachments/${attachmentID}`;
const proofDocumentPath = `users/${uid}/proofRecords/${proofID}`;
const attachmentDocumentPath = storagePath;
const proofBytes = Buffer.from("OpenLARP signed-in Firebase smoke proof.\n", "utf8");
let createdSmokeUser = false;
let clientApp;
let clientAuth;
let clientFirestore;
let clientStorage;

const adminAppOptions = {
  credential: applicationDefault(),
  projectId: projectID,
  storageBucket
};
if (process.env.SIGNING_SERVICE_ACCOUNT) {
  adminAppOptions.serviceAccountId = process.env.SIGNING_SERVICE_ACCOUNT;
}
const adminApp = initializeAdminApp(adminAppOptions);
const auth = getAdminAuth(adminApp);
const firestore = getAdminFirestore(adminApp);
const bucket = getAdminStorage(adminApp).bucket(storageBucket);

try {
  await assertSmokeUserDoesNotExist();
  const customToken = await auth.createCustomToken(uid, {
    openlarpSmoke: true
  });
  createdSmokeUser = true;
  const idToken = await createSignedInClientSession(customToken);
  pass("Created temporary Firebase Auth smoke session");

  await smokeWorkflow(idToken);
  await smokeProofPromotionAndReconciliation(idToken);
  await smokeBackendEventAcknowledgement(idToken);
  pass("Signed-in callable, Storage, and Firestore smoke completed");
} catch (error) {
  throw new Error(smokeFailureMessage(error));
} finally {
  await cleanupSmokeState();
}

async function smokeWorkflow(idToken) {
  const requestID = randomUUID();
  const result = await callCallable("runOpenLARPWorkflow", idToken, {
    schemaVersion: 1,
    run: {
      schemaVersion: 1,
      kind: "cookedDiagnostic",
      providerRoute: "firebaseCallableGenkit",
      requestedAt: now.toISOString(),
      requestID,
      privacy: {
        memoryMode: "cloudReady",
        allowsLongTermMemoryWrite: true,
        requiresUserApprovalForExternalActions: true,
        shareWins: false
      }
    },
    safetyRules: {
      hardBannedClaims: [
        "Do not invent fake employers, fake schools, fake certificates, fake titles, fake dates, fake projects, or fake ownership."
      ],
      requiredBehaviors: [
        "Keep career recommendations tied to evidence and user-approved actions."
      ],
      privacyRequirements: [
        "external actions require user approval before the system can act."
      ]
    },
    payload: {
      goal: {
        currentStatus: "New graduate",
        targetRole: "AI product engineer",
        timeline: "12 weeks",
        background: "CS student with one shipped class project.",
        existingProof: "GitHub project and internship notes.",
        confidence: 3,
        biggestBlocker: "Not enough role-specific proof."
      },
      requestedAt: now.toISOString()
    }
  });

  assert(result.ok === true, "workflow did not return ok=true");
  assert(result.userID === uid, "workflow response userID did not match smoke UID");
  assert(result.requestID === requestID, "workflow response requestID did not match");
  assert(result.liveModelCallsEnabled === false, "workflow should keep live model calls disabled");
  assert(result.externalActionTaken === false, "workflow should not take external actions");
  pass("Signed-in workflow callable returned deterministic diagnostic");
}

async function smokeProofPromotionAndReconciliation(idToken) {
  const idempotencyKey = `${uid}-${attachmentID}`;
  const proofReference = clientStorageRef(clientStorage, storagePath);
  await withTransientRetry("signed-in Storage upload", () => (
    clientUploadBytes(
      proofReference,
      new Uint8Array(proofBytes),
      {
        contentType: "text/plain",
        customMetadata: {
          ownerUserID: uid,
          proofID,
          attachmentID,
          idempotencyKey
        }
      }
    )
  ));
  const metadata = await withTransientRetry("signed-in Storage metadata read", () => clientGetMetadata(proofReference));
  assert(metadata.customMetadata?.ownerUserID === uid, "signed-in Storage read did not return owner metadata");
  assert(metadata.customMetadata?.attachmentID === attachmentID, "signed-in Storage read did not return attachment metadata");
  const downloadedBytes = Buffer.from(await withTransientRetry(
    "signed-in Storage byte read",
    () => clientGetBytes(proofReference, proofBytes.byteLength + 1)
  ));
  assert(downloadedBytes.equals(proofBytes), "signed-in Storage read did not return uploaded proof bytes");
  pass("Signed-in client uploaded and read temporary proof object in Firebase Storage");

  const promotion = await callCallable("promoteProofUploadReceipt", idToken, {
    schemaVersion: 1,
    proofID,
    attachmentID,
    fileName: "openlarp-smoke-proof.txt",
    contentType: "text/plain",
    byteCount: proofBytes.byteLength,
    storagePath,
    proofDocumentPath,
    attachmentDocumentPath,
    idempotencyKey
  });

  assert(promotion.ok === true, "proof promotion did not return ok=true");
  assert(promotion.userID === uid, "proof promotion response userID did not match");
  assert(promotion.uploadReceipt?.status === "uploaded", "proof promotion did not return uploaded receipt");
  const attachmentSnapshot = await withTransientRetry(
    "signed-in Firestore attachment read",
    () => clientGetDoc(clientDoc(clientFirestore, attachmentDocumentPath))
  );
  assert(attachmentSnapshot.exists(), "signed-in Firestore read did not return promoted attachment receipt");
  pass("Signed-in proof promotion callable wrote a user-readable server receipt");

  const reconciliation = await callCallable("reconcileProofUploads", idToken, {
    mode: "reportOnly",
    attachmentIDs: [attachmentID],
    maxAttachments: 1
  });
  assert(reconciliation.ok === true, "proof reconciliation did not return ok=true");
  assert(reconciliation.scannedCount === 1, "proof reconciliation did not scan exactly one object");
  assert(reconciliation.candidates?.[0]?.status === "linked", "proof reconciliation did not report linked upload");
  pass("Signed-in proof reconciliation callable reported linked upload");
}

async function smokeBackendEventAcknowledgement(idToken) {
  const acknowledged = await callCallable("acknowledgeBackendEvents", idToken, {
    schemaVersion: 1,
    requestedAt: now.toISOString(),
    session: {
      ownerUserID: uid,
      isAuthenticated: true,
      authProvider: "firebaseAuth"
    },
    events: [{
      id: backendEventID,
      schemaVersion: 1,
      kind: "questStarted",
      syncStatus: "inFlight",
      ownerUserID: uid,
      entityID: backendEventEntityID,
      idempotencyKey: `${uid}-questStarted-${backendEventEntityID}`,
      occurredAt: now.toISOString(),
      retryCount: 0,
      summary: {
        questID: backendEventEntityID,
        questDay: 1,
        targetRoleTitle: "AI product engineer",
        xp: 20
      }
    }],
    integrationRoutes: []
  });

  assert(acknowledged.ok === true, "backend event acknowledgement did not return ok=true");
  assert(acknowledged.receipts?.[0]?.eventID === backendEventID, "backend event receipt did not match event ID");
  const eventSnapshot = await withTransientRetry(
    "signed-in Firestore backend event read",
    () => clientGetDoc(clientDoc(clientFirestore, `users/${uid}/backendEvents/${backendEventID}`))
  );
  assert(eventSnapshot.exists(), "signed-in Firestore read did not return backend event history");
  pass("Signed-in backend event acknowledgement wrote user-readable Firestore history");
}

async function callCallable(name, idToken, data) {
  const response = await withTransientRetry(name, () => fetch(`${callableBaseURL}/${name}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${idToken}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ data })
    })
  );
  const text = await response.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new Error(`${name} returned non-JSON HTTP ${response.status}`);
  }

  if (!response.ok || payload.error) {
    const status = payload.error?.status ?? response.status;
    const message = payload.error?.message ?? "callable request failed";
    throw new Error(`${name} failed with ${status}: ${message}`);
  }
  if (!payload.result || typeof payload.result !== "object") {
    throw new Error(`${name} did not return a callable result object`);
  }
  return payload.result;
}

async function createSignedInClientSession(customToken) {
  clientApp = initializeClientApp({
    apiKey: webAPIKey,
    appId: iosAppID,
    authDomain: `${projectID}.firebaseapp.com`,
    projectId: projectID,
    storageBucket
  }, `openlarp-smoke-${uid}`);
  clientAuth = getClientAuth(clientApp);
  clientFirestore = getClientFirestore(clientApp);
  clientStorage = getClientStorage(clientApp, `gs://${storageBucket}`);

  const credential = await withTransientRetry(
    "Firebase Auth custom token sign-in",
    () => signInWithCustomToken(clientAuth, customToken)
  );
  assert(credential.user.uid === uid, "signed-in client UID did not match smoke UID");
  return withTransientRetry("Firebase Auth ID token retrieval", () => credential.user.getIdToken());
}

async function cleanupSmokeState() {
  const cleanupTasks = [
    deleteClientAppIfNeeded(),
    deleteStoragePrefix(),
    deleteFirestoreUserTree(),
    deleteQuotaDays(),
    deleteSmokeUser()
  ];

  const settled = await Promise.allSettled(cleanupTasks);
  const rejected = settled.filter((result) => result.status === "rejected");
  if (rejected.length > 0) {
    const reasons = rejected.map((result) => result.reason?.message ?? String(result.reason));
    throw new Error([
      `Smoke cleanup failed for ${rejected.length} task(s): ${reasons.join("; ")}`,
      `Manual cleanup may be needed for smoke UID ${uid}, Storage prefix users/${uid}/proofAttachments/, Firestore tree users/${uid}, and quota documents for this UID.`
    ].join("\n"));
  }

  pass("Cleaned up temporary smoke Auth, Firestore, Storage, and quota data");
}

async function deleteClientAppIfNeeded() {
  if (!clientApp) {
    return;
  }
  await deleteClientApp(clientApp);
}

async function assertSmokeUserDoesNotExist() {
  try {
    await auth.getUser(uid);
    throw new Error(`Refusing to run because smoke UID already exists: ${uid}`);
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      return;
    }
    throw error;
  }
}

async function deleteSmokeUser() {
  if (!createdSmokeUser) {
    return;
  }
  if (!uid.startsWith("openlarp-smoke-")) {
    throw new Error(`Refusing to delete non-smoke UID ${uid}`);
  }
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") {
      throw error;
    }
  }
}

async function deleteQuotaDays() {
  const dayKeys = new Set([
    startedAt.toISOString().slice(0, 10),
    new Date().toISOString().slice(0, 10)
  ]);
  await Promise.all([...dayKeys].map((dayKey) => deleteQuotaDay(dayKey)));
}

async function deleteQuotaDay(dayKey) {
  const userBucketID = createHash("sha256").update(uid).digest("hex").slice(0, 40);
  const dayReference = firestore.doc(`_serverUsage/${userBucketID}/days/${dayKey}`);
  const charges = await dayReference.collection("charges").listDocuments();
  await Promise.all(charges.map((reference) => reference.delete()));
  await dayReference.delete();
}

async function deleteStoragePrefix() {
  const prefix = `users/${uid}/proofAttachments/`;
  const [files] = await bucket.getFiles({ prefix });
  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
  const [remainingFiles] = await bucket.getFiles({ prefix });
  if (remainingFiles.length > 0) {
    throw new Error(`Smoke Storage prefix cleanup left ${remainingFiles.length} object(s) under ${prefix}`);
  }
}

async function deleteFirestoreUserTree() {
  const userReference = firestore.doc(`users/${uid}`);
  await deleteFirestoreDocumentTree(userReference);
  await assertFirestoreUserTreeEmpty(userReference);
}

async function deleteFirestoreDocumentTree(documentReference) {
  const collections = await documentReference.listCollections();
  await Promise.all(collections.map((collection) => deleteFirestoreCollectionTree(collection)));
  await documentReference.delete();
}

async function deleteFirestoreCollectionTree(collectionReference) {
  const documents = await collectionReference.listDocuments();
  await Promise.all(documents.map((document) => deleteFirestoreDocumentTree(document)));
}

async function assertFirestoreUserTreeEmpty(userReference) {
  const snapshot = await userReference.get();
  if (snapshot.exists) {
    throw new Error(`Smoke Firestore cleanup left user document ${userReference.path}`);
  }

  const collections = await userReference.listCollections();
  const remaining = [];
  for (const collection of collections) {
    const documents = await collection.listDocuments();
    remaining.push(...documents.map((document) => document.path));
  }
  if (remaining.length > 0) {
    throw new Error(`Smoke Firestore cleanup left ${remaining.length} document(s): ${remaining.join(", ")}`);
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

function pass(message) {
  console.log(`PASS ${message}`);
}

async function withTransientRetry(label, operation, maxAttempts = 3) {
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt === maxAttempts || !isTransientSmokeError(error)) {
        throw error;
      }
      await delay(750 * attempt);
    }
  }
  throw lastError;
}

function isTransientSmokeError(error) {
  const code = typeof error?.code === "string" ? error.code : "";
  const message = error instanceof Error ? error.message : String(error);
  return [
    "network-request-failed",
    "fetch failed",
    "ECONNRESET",
    "ECONNREFUSED",
    "ETIMEDOUT",
    "ENOTFOUND",
    "socket hang up",
    "temporarily unavailable",
    "UNAVAILABLE"
  ].some((fragment) => code.includes(fragment) || message.includes(fragment));
}

function delay(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

function smokeFailureMessage(error) {
  const message = error instanceof Error ? error.message : String(error);
  if (
    message.includes("Could not load the default credentials") ||
    message.includes("Could not refresh access token") ||
    message.includes("iam.serviceAccounts.signBlob") ||
    message.includes("Permission iam.serviceAccounts.signBlob")
  ) {
    return [
      message,
      "Signed-in smoke requires local Google Application Default Credentials that can mint Firebase custom tokens.",
      "Run: gcloud auth application-default login",
      "If that still fails, grant the active gcloud account iam.serviceAccounts.signBlob on the Firebase Admin service account or set OPENLARP_FIREBASE_SIGNING_SERVICE_ACCOUNT.",
      "If using a service account, set GOOGLE_APPLICATION_CREDENTIALS to a local JSON key that is not committed."
    ].join("\n");
  }
  return message;
}
NODE
