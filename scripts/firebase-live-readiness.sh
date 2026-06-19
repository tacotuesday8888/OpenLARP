#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${OPENLARP_FIREBASE_PROJECT_ID:-openlarp-dev-langqi}"
IOS_APP_ID="${OPENLARP_FIREBASE_IOS_APP_ID:-1:795318771575:ios:5315b3cc5b1bff81e30b72}"
FUNCTION_REGION="${OPENLARP_FUNCTION_REGION:-us-central1}"
FUNCTIONS_REPOSITORY="${OPENLARP_FUNCTIONS_REPOSITORY:-gcf-artifacts}"
FIREBASE="npx -y firebase-tools@15.21.0"
export PROJECT_ID

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pass() {
  printf 'PASS %s\n' "$1"
}

warn() {
  printf 'WARN %s\n' "$1"
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

printf 'OpenLARP Firebase live readiness for %s\n' "$PROJECT_ID"

firebase_version="$($FIREBASE --version)"
if [[ "$firebase_version" == "15.21.0" ]]; then
  pass "Firebase CLI 15.21.0 available"
else
  warn "Firebase CLI version is $firebase_version, expected 15.21.0"
fi

db_json="$tmp_dir/firestore-db.json"
$FIREBASE firestore:databases:get '(default)' --project "$PROJECT_ID" --json > "$db_json"
node --input-type=module - "$db_json" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const db = payload.result;
if (!db || db.name !== `projects/${process.env.PROJECT_ID ?? "openlarp-dev-langqi"}/databases/(default)`) {
  throw new Error("Default Firestore database was not returned.");
}
if (db.type !== "FIRESTORE_NATIVE" || db.databaseEdition !== "STANDARD") {
  throw new Error(`Unexpected Firestore shape: ${db.type ?? "missing type"} ${db.databaseEdition ?? "missing edition"}`);
}
NODE
pass "Default Firestore database is native Standard edition"

functions_json="$tmp_dir/functions.json"
$FIREBASE functions:list --project "$PROJECT_ID" --json > "$functions_json"
node --input-type=module - "$functions_json" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const functions = payload.result ?? [];
const required = new Map([
  ["runOpenLARPWorkflow", "nodejs22"],
  ["reconcileProofUploads", "nodejs22"],
  ["promoteProofUploadReceipt", "nodejs22"],
  ["cleanupRevokedPrivateEvidenceUploads", "nodejs22"],
  ["setPrivateEvidenceCloudSyncConsent", "nodejs22"],
  ["acknowledgeBackendEvents", "nodejs22"],
  ["deleteOpenLARPAccount", "nodejs22"]
]);
for (const [id, runtime] of required) {
  const entry = functions.find((item) => item.id === id);
  if (!entry) {
    throw new Error(`Missing deployed function ${id}`);
  }
  if (entry.state !== "ACTIVE") {
    throw new Error(`${id} state is ${entry.state}`);
  }
  if (entry.runtime !== runtime) {
    throw new Error(`${id} runtime is ${entry.runtime}`);
  }
}
NODE
pass "Required callable Functions are deployed and ACTIVE"

if grep -q "adminCallableQuotaGuard" backend/functions/src/index.ts &&
  grep -q "CALLABLE_DAILY_QUOTA_LIMITS" backend/functions/src/callableQuotaGuard.ts; then
  pass "Local Functions deploy source includes callable quota guard"
else
  fail "Local Functions deploy source is missing the callable quota guard"
fi

callable_response="$tmp_dir/callable-response.txt"
http_status="$(
  curl -sS -o "$callable_response" -w '%{http_code}' \
    -X POST "https://${FUNCTION_REGION}-${PROJECT_ID}.cloudfunctions.net/runOpenLARPWorkflow" \
    -H 'Content-Type: application/json' \
    -d '{"data":{"schemaVersion":1,"run":{"schemaVersion":1,"kind":"cookedDiagnostic","providerRoute":"firebaseCallableGenkit","requestedAt":"2026-06-18T10:00:00.000Z","requestID":"11111111-1111-4111-8111-111111111111","privacy":{"memoryMode":"cloudReady","allowsLongTermMemoryWrite":true,"requiresUserApprovalForExternalActions":true,"shareWins":false,"allowsPrivateEvidenceCloudSync":false}},"safetyRules":{"hardBannedClaims":["Do not invent fake employers, fake schools, fake certificates, fake titles, fake dates, fake projects, or fake ownership."],"requiredBehaviors":["Keep career recommendations tied to evidence and user-approved actions."],"privacyRequirements":["external actions require user approval before the system can act."]},"payload":{"goal":{"currentStatus":"New graduate","targetRole":"AI product engineer","timeline":"12 weeks","background":"CS student with one shipped class project.","existingProof":"GitHub project and internship notes.","confidence":3,"biggestBlocker":"Not enough role-specific proof."},"requestedAt":"2026-06-18T10:00:00.000Z"}}}'
)"
if [[ "$http_status" != "401" ]]; then
  fail "Unauthenticated callable returned HTTP $http_status instead of 401"
fi
node --input-type=module - "$callable_response" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.error?.status !== "UNAUTHENTICATED") {
  throw new Error(`Unexpected callable error: ${JSON.stringify(payload)}`);
}
NODE
pass "Callable endpoint rejects unauthenticated workflow requests"

promotion_response="$tmp_dir/promotion-response.txt"
promotion_http_status="$(
  curl -sS -o "$promotion_response" -w '%{http_code}' \
    -X POST "https://${FUNCTION_REGION}-${PROJECT_ID}.cloudfunctions.net/promoteProofUploadReceipt" \
    -H 'Content-Type: application/json' \
    -d '{"data":{"schemaVersion":1,"proofID":"proof_123","attachmentID":"attachment_123","fileName":"proof.png","contentType":"image/png","byteCount":32000,"storagePath":"users/user_123/proofAttachments/attachment_123","proofDocumentPath":"users/user_123/proofRecords/proof_123","attachmentDocumentPath":"users/user_123/proofAttachments/attachment_123","idempotencyKey":"user_123-attachment_123"}}'
)"
if [[ "$promotion_http_status" != "401" ]]; then
  fail "Unauthenticated proof upload promotion callable returned HTTP $promotion_http_status instead of 401"
fi
node --input-type=module - "$promotion_response" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.error?.status !== "UNAUTHENTICATED") {
  throw new Error(`Unexpected proof promotion callable error: ${JSON.stringify(payload)}`);
}
NODE
pass "Proof upload promotion callable rejects unauthenticated requests"

consent_response="$tmp_dir/consent-response.txt"
consent_http_status="$(
  curl -sS -o "$consent_response" -w '%{http_code}' \
    -X POST "https://${FUNCTION_REGION}-${PROJECT_ID}.cloudfunctions.net/setPrivateEvidenceCloudSyncConsent" \
    -H 'Content-Type: application/json' \
    -d '{"data":{"schemaVersion":1,"enabled":true,"consentTextVersion":"private-evidence-cloud-sync-v1"}}'
)"
if [[ "$consent_http_status" != "401" ]]; then
  fail "Unauthenticated private evidence consent callable returned HTTP $consent_http_status instead of 401"
fi
node --input-type=module - "$consent_response" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.error?.status !== "UNAUTHENTICATED") {
  throw new Error(`Unexpected private evidence consent callable error: ${JSON.stringify(payload)}`);
}
NODE
pass "Private evidence consent callable rejects unauthenticated requests"

retention_response="$tmp_dir/retention-response.txt"
retention_http_status="$(
  curl -sS -o "$retention_response" -w '%{http_code}' \
    -X POST "https://${FUNCTION_REGION}-${PROJECT_ID}.cloudfunctions.net/cleanupRevokedPrivateEvidenceUploads" \
    -H 'Content-Type: application/json' \
    -d '{"data":{"schemaVersion":1,"mode":"reportOnly","attachmentIDs":["attachment_123"],"maxAttachments":1}}'
)"
if [[ "$retention_http_status" != "401" ]]; then
  fail "Unauthenticated private evidence backup cleanup callable returned HTTP $retention_http_status instead of 401"
fi
node --input-type=module - "$retention_response" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.error?.status !== "UNAUTHENTICATED") {
  throw new Error(`Unexpected private evidence backup cleanup callable error: ${JSON.stringify(payload)}`);
}
NODE
pass "Private evidence backup cleanup callable rejects unauthenticated requests"

event_ack_response="$tmp_dir/event-ack-response.txt"
event_ack_http_status="$(
  curl -sS -o "$event_ack_response" -w '%{http_code}' \
    -X POST "https://${FUNCTION_REGION}-${PROJECT_ID}.cloudfunctions.net/acknowledgeBackendEvents" \
    -H 'Content-Type: application/json' \
    -d '{"data":{"schemaVersion":1,"requestedAt":"2026-06-18T10:00:00.000Z","session":{"ownerUserID":"user_123","isAuthenticated":true,"authProvider":"firebaseAuth"},"events":[{"id":"11111111-1111-4111-8111-111111111111","schemaVersion":1,"kind":"proofClaimed","syncStatus":"inFlight","ownerUserID":"user_123","entityID":"33333333-3333-4333-8333-333333333333","idempotencyKey":"user_123-proofClaimed-33333333-3333-4333-8333-333333333333","occurredAt":"2026-06-18T09:59:00.000Z","retryCount":0,"summary":{"proofID":"33333333-3333-4333-8333-333333333333","proofCount":1}}],"integrationRoutes":[]}}'
)"
if [[ "$event_ack_http_status" != "401" ]]; then
  fail "Unauthenticated backend event acknowledgement callable returned HTTP $event_ack_http_status instead of 401"
fi
node --input-type=module - "$event_ack_response" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.error?.status !== "UNAUTHENTICATED") {
  throw new Error(`Unexpected backend event acknowledgement callable error: ${JSON.stringify(payload)}`);
}
NODE
pass "Backend event acknowledgement callable rejects unauthenticated requests"

account_deletion_response="$tmp_dir/account-deletion-response.txt"
account_deletion_http_status="$(
  curl -sS -o "$account_deletion_response" -w '%{http_code}' \
    -X POST "https://${FUNCTION_REGION}-${PROJECT_ID}.cloudfunctions.net/deleteOpenLARPAccount" \
    -H 'Content-Type: application/json' \
    -d '{"data":{"schemaVersion":1,"confirmDeletion":true,"confirmationText":"DELETE MY OPENLARP ACCOUNT"}}'
)"
if [[ "$account_deletion_http_status" != "401" ]]; then
  fail "Unauthenticated account deletion callable returned HTTP $account_deletion_http_status instead of 401"
fi
node --input-type=module - "$account_deletion_response" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.error?.status !== "UNAUTHENTICATED") {
  throw new Error(`Unexpected account deletion callable error: ${JSON.stringify(payload)}`);
}
NODE
pass "Account deletion callable rejects unauthenticated requests"

sdk_config="$tmp_dir/GoogleService-Info.plist"
$FIREBASE apps:sdkconfig IOS "$IOS_APP_ID" --project "$PROJECT_ID" > "$sdk_config"
if /usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$sdk_config" >/dev/null 2>&1; then
  pass "iOS Firebase app config can be retrieved by CLI"
else
  fail "iOS Firebase app config did not include GOOGLE_APP_ID"
fi

if /usr/libexec/PlistBuddy -c 'Print :CLIENT_ID' "$sdk_config" >/dev/null 2>&1 &&
  /usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$sdk_config" >/dev/null 2>&1; then
  pass "iOS config includes Google OAuth client IDs"
else
  warn "iOS config is missing CLIENT_ID/REVERSED_CLIENT_ID; enable/configure Google provider before live Google Sign-In"
fi

if command -v gcloud >/dev/null 2>&1; then
  bucket_name="${PROJECT_ID}.firebasestorage.app"
  if gcloud storage buckets describe "gs://${bucket_name}" --project "$PROJECT_ID" >/dev/null 2>&1; then
    pass "Firebase Storage default bucket exists"
  else
    warn "Firebase Storage default bucket is not initialized; finish Storage setup in Firebase Console before rules deploy"
  fi

  project_number="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
  storage_service_agent="service-${project_number}@gcp-sa-firebasestorage.iam.gserviceaccount.com"
  iam_policy_json="$tmp_dir/iam-policy.json"
  gcloud projects get-iam-policy "$PROJECT_ID" --format=json > "$iam_policy_json"
  node --input-type=module - "$iam_policy_json" "$storage_service_agent" <<'NODE'
import fs from "node:fs";

const policy = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const storageServiceAgent = `serviceAccount:${process.argv[3]}`;
const allowedRoles = new Set([
  "roles/datastore.viewer",
  "roles/datastore.user",
  "roles/datastore.owner",
  "roles/editor",
  "roles/owner"
]);
const hasFirestoreReadRole = (policy.bindings ?? []).some((binding) => (
  allowedRoles.has(binding.role) && (binding.members ?? []).includes(storageServiceAgent)
));
if (!hasFirestoreReadRole) {
  throw new Error(
    `Missing Firestore read IAM role for Cloud Storage for Firebase service agent ${storageServiceAgent}. ` +
    "Grant roles/datastore.viewer so Storage rules can read private evidence consent documents."
  );
}
NODE
  pass "Cloud Storage for Firebase service agent can read Firestore consent documents"

  cleanup_json="$tmp_dir/cleanup-policies.json"
  gcloud artifacts repositories list-cleanup-policies "$FUNCTIONS_REPOSITORY" \
    --project "$PROJECT_ID" \
    --location "$FUNCTION_REGION" \
    --format=json > "$cleanup_json"
  node --input-type=module - "$cleanup_json" <<'NODE'
import fs from "node:fs";

const policies = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const names = new Set(policies.map((policy) => policy.name));
if (!names.has("delete-older-than-7-days") || !names.has("keep-most-recent-5")) {
  throw new Error("Expected Artifact Registry cleanup policies were not found.");
}
NODE
  pass "Functions Artifact Registry cleanup policies are installed"
else
  warn "gcloud unavailable; skipped Storage bucket and cleanup-policy checks"
fi

printf 'Firebase live readiness check complete.\n'
