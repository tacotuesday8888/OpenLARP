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

curl_read_flags=(-sS --http1.1 --retry 3 --retry-delay 1 --retry-all-errors)

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

check_app_check_enforcement() {
  if [[ "${OPENLARP_FIREBASE_SMOKE_SKIP_APP_CHECK_STATUS:-}" == "1" ]]; then
    return
  fi
  if ! command -v gcloud >/dev/null 2>&1; then
    printf 'WARN gcloud unavailable; skipped Firebase App Check enforcement preflight.\n'
    return
  fi

  local project_number
  project_number="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || true)"
  if [[ -z "$project_number" ]]; then
    printf 'WARN Unable to resolve Firebase project number; skipped App Check enforcement preflight.\n'
    return
  fi

  local app_check_access_token
  app_check_access_token="$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token 2>/dev/null || true)"
  if [[ -z "$app_check_access_token" ]]; then
    printf 'WARN gcloud credentials unavailable; skipped App Check enforcement preflight.\n'
    return
  fi

  local enforced_services=()
  local service service_json service_status service_mode
  for service in firestore.googleapis.com firebasestorage.googleapis.com; do
    service_json="$tmp_dir/app-check-${service}.json"
    service_status="$(
      curl "${curl_read_flags[@]}" -o "$service_json" -w '%{http_code}' \
        -H "Authorization: Bearer ${app_check_access_token}" \
        -H "X-Goog-User-Project: ${PROJECT_ID}" \
        "https://firebaseappcheck.googleapis.com/v1/projects/${project_number}/services/${service}"
    )"
    if [[ "$service_status" != "200" ]]; then
      printf 'WARN Unable to read App Check status for %s before signed-in smoke: HTTP %s\n' "$service" "$service_status"
      continue
    fi

    service_mode="$(node --input-type=module - "$service_json" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
console.log(payload.enforcementMode ?? "OFF");
NODE
)"
    if [[ "$service_mode" == "ENFORCED" ]]; then
      enforced_services+=("$service")
    fi
  done

  if (( ${#enforced_services[@]} > 0 )); then
    fail "Firebase App Check is enforced for ${enforced_services[*]}, but this CLI smoke does not yet mint or attach registered App Check debug/device tokens. Register private App Check tokens and update the smoke token path before running signed-in cloud smoke against enforced services."
  fi
  pass "Firebase App Check is not enforced for Firestore or Storage before signed-in smoke"
}

check_app_check_enforcement

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
  await smokeAccountDeletion(idToken);
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
        shareWins: false,
        allowsPrivateEvidenceCloudSync: false
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
  const consent = await callCallable("setPrivateEvidenceCloudSyncConsent", idToken, {
    schemaVersion: 1,
    enabled: true,
    consentTextVersion: "private-evidence-cloud-sync-v1"
  });
  assert(consent.ok === true, "private evidence consent did not return ok=true");
  assert(consent.userID === uid, "private evidence consent response userID did not match");
  assert(consent.status === "accepted", "private evidence consent was not accepted");
  assert(consent.allowsPrivateEvidenceCloudSync === true, "private evidence consent did not enable proof sync");
  pass("Signed-in private evidence cloud sync consent callable accepted proof sync");

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

  const revokedConsent = await callCallable("setPrivateEvidenceCloudSyncConsent", idToken, {
    schemaVersion: 1,
    enabled: false,
    consentTextVersion: "private-evidence-cloud-sync-v1"
  });
  assert(revokedConsent.ok === true, "private evidence consent revoke did not return ok=true");
  assert(revokedConsent.status === "revoked", "private evidence consent revoke did not return revoked status");
  assert(revokedConsent.allowsPrivateEvidenceCloudSync === false, "private evidence consent revoke did not disable proof sync");
  pass("Signed-in private evidence cloud sync consent callable revoked future proof sync");

  const retentionReport = await callCallable("cleanupRevokedPrivateEvidenceUploads", idToken, {
    mode: "reportOnly",
    attachmentIDs: [attachmentID],
    maxAttachments: 1
  });
  assert(retentionReport.ok === true, "private evidence backup cleanup report did not return ok=true");
  assert(retentionReport.scannedCount === 1, "private evidence backup cleanup did not scan exactly one attachment");
  assert(retentionReport.deletedCount === 0, "private evidence backup cleanup report should not delete");
  assert(retentionReport.externalActionTaken === false, "private evidence backup cleanup report should not take external action");
  assert(retentionReport.candidates?.[0]?.status === "eligible", "private evidence backup cleanup did not report eligible upload");
  pass("Signed-in private evidence backup cleanup callable reported retained upload after revocation");

  const retentionDelete = await callCallable("cleanupRevokedPrivateEvidenceUploads", idToken, {
    mode: "deleteSyncedEvidence",
    confirmDeletion: true,
    attachmentIDs: [attachmentID],
    maxAttachments: 1
  });
  assert(retentionDelete.ok === true, "private evidence backup cleanup delete did not return ok=true");
  assert(retentionDelete.scannedCount === 1, "private evidence backup cleanup delete did not scan exactly one attachment");
  assert(retentionDelete.deletedCount === 1, "private evidence backup cleanup delete did not delete the smoke attachment");
  assert(retentionDelete.externalActionTaken === true, "private evidence backup cleanup delete did not report an external action");
  assert(retentionDelete.candidates?.[0]?.status === "deleted", "private evidence backup cleanup did not report deleted upload");
  await assertStorageObjectMissing(proofReference);
  const deletedAttachmentSnapshot = await withTransientRetry(
    "signed-in Firestore deleted attachment read",
    () => clientGetDoc(clientDoc(clientFirestore, attachmentDocumentPath))
  );
  assert(!deletedAttachmentSnapshot.exists(), "private evidence backup cleanup left the attachment document readable");
  const consentSnapshot = await withTransientRetry(
    "signed-in Firestore retained consent read",
    () => clientGetDoc(clientDoc(clientFirestore, `users/${uid}/consents/privateEvidenceCloudSync`))
  );
  assert(consentSnapshot.exists(), "private evidence backup cleanup removed the consent document");
  assert(consentSnapshot.data()?.status === "revoked", "private evidence backup cleanup changed the revoked consent status");
  pass("Signed-in private evidence backup cleanup callable deleted only the temporary proof backup");
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

async function smokeAccountDeletion(idToken) {
  const deletion = await callCallable("deleteOpenLARPAccount", idToken, {
    schemaVersion: 1,
    confirmDeletion: true,
    confirmationText: "DELETE MY OPENLARP ACCOUNT"
  });

  assert(deletion.ok === true, "account deletion did not return ok=true");
  assert(deletion.userID === uid, "account deletion response userID did not match smoke UID");
  assert(deletion.status === "deleted", "account deletion did not report deleted status");
  assert(deletion.storageUserPrefix?.status === "completed", "account deletion did not complete Storage cleanup");
  assert(deletion.firestoreUserTree?.status === "completed", "account deletion did not complete Firestore cleanup");
  assert(deletion.quotaUsageTree?.status === "completed", "account deletion did not complete quota cleanup");
  assert(deletion.deletionRequestMarker?.status === "completed", "account deletion did not finalize the deletion marker");
  assert(
    deletion.firebaseAuthUser?.status === "deleted" || deletion.firebaseAuthUser?.status === "alreadyMissing",
    "account deletion did not delete Firebase Auth user"
  );
  assert(deletion.externalActionTaken === true, "account deletion did not report external action");
  await assertSmokeUserDeleted();
  await assertStorageUserPrefixEmpty();
  await assertFirestoreUserTreeEmpty(firestore.doc(`users/${uid}`));
  await assertQuotaUsageTreeEmpty();
  await assertAccountDeletionMarker("deleted");
  pass("Signed-in account deletion callable removed temporary Auth, Firestore, Storage, and quota data");
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
    deleteAccountDeletionMarker(),
    deleteSmokeUser()
  ];

  const settled = await Promise.allSettled(cleanupTasks);
  const rejected = settled.filter((result) => result.status === "rejected");
  if (rejected.length > 0) {
    const reasons = rejected.map((result) => result.reason?.message ?? String(result.reason));
    throw new Error([
      `Smoke cleanup failed for ${rejected.length} task(s): ${reasons.join("; ")}`,
      `Manual cleanup may be needed for smoke UID ${uid}, Storage prefix users/${uid}/proofAttachments/, Firestore tree users/${uid}, quota documents for this UID, and _accountDeletionRequests/${uid}.`
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

async function assertQuotaUsageTreeEmpty() {
  const userBucketID = createHash("sha256").update(uid).digest("hex").slice(0, 40);
  const quotaReference = firestore.doc(`_serverUsage/${userBucketID}`);
  const snapshot = await quotaReference.get();
  if (snapshot.exists) {
    throw new Error(`Account deletion left quota document ${quotaReference.path}`);
  }

  const collections = await quotaReference.listCollections();
  const remaining = [];
  for (const collection of collections) {
    const documents = await collection.listDocuments();
    remaining.push(...documents.map((document) => document.path));
  }
  if (remaining.length > 0) {
    throw new Error(`Account deletion left ${remaining.length} quota document(s): ${remaining.join(", ")}`);
  }
}

async function deleteAccountDeletionMarker() {
  if (!uid.startsWith("openlarp-smoke-")) {
    throw new Error(`Refusing to delete account deletion marker for non-smoke UID ${uid}`);
  }
  await firestore.doc(`_accountDeletionRequests/${uid}`).delete();
}

async function assertAccountDeletionMarker(expectedStatus) {
  const snapshot = await firestore.doc(`_accountDeletionRequests/${uid}`).get();
  if (!snapshot.exists) {
    throw new Error(`Account deletion did not write _accountDeletionRequests/${uid}`);
  }
  const data = snapshot.data();
  if (data?.ownerUserID !== uid || data?.status !== expectedStatus) {
    throw new Error(`Account deletion marker had unexpected shape: ${JSON.stringify(data)}`);
  }
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

async function assertStorageUserPrefixEmpty() {
  const prefix = `users/${uid}/`;
  const [remainingFiles] = await bucket.getFiles({ prefix });
  if (remainingFiles.length > 0) {
    throw new Error(`Account deletion left ${remainingFiles.length} Storage object(s) under ${prefix}`);
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

async function assertSmokeUserDeleted() {
  try {
    await auth.getUser(uid);
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      return;
    }
    throw error;
  }
  throw new Error(`Account deletion left Firebase Auth user ${uid}`);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function assertStorageObjectMissing(reference) {
  try {
    await withTransientRetry("signed-in deleted Storage metadata read", () => clientGetMetadata(reference));
  } catch (error) {
    const code = typeof error?.code === "string" ? error.code : "";
    if (code.includes("object-not-found")) {
      return;
    }
    throw error;
  }
  throw new Error("private evidence backup cleanup left the Storage proof object readable");
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
