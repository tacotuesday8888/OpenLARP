import { getApps, initializeApp } from "firebase-admin/app";
import { onCall } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import { adminBackendEventSyncDependencies, handleBackendEventSyncRequest } from "./backendEventSync.js";
import { adminCallableQuotaGuard } from "./callableQuotaGuard.js";
import { toHttpsError } from "./errors.js";
import {
  adminProofUploadPromotionDependencies,
  handleProofUploadPromotionRequest
} from "./proofUploadPromotion.js";
import {
  adminProofUploadReconciliationDependencies,
  handleProofUploadReconciliationRequest
} from "./proofUploadReconciliation.js";
import { handleOpenLARPWorkflowRequest } from "./workflowHandler.js";

if (getApps().length === 0) {
  initializeApp();
}

setGlobalOptions({
  region: "us-central1",
  maxInstances: 10
});

const callableQuotaGuard = adminCallableQuotaGuard();

export const runOpenLARPWorkflow = onCall(
  {
    cors: true,
    timeoutSeconds: 60,
    memory: "512MiB"
  },
  async (request) => {
    const response = await handleOpenLARPWorkflowRequest({
      auth: request.auth ? { uid: request.auth.uid, token: request.auth.token } : null,
      data: request.data
    }, {
      quotaGuard: callableQuotaGuard
    });

    if (!response.ok) {
      throw toHttpsError(response);
    }

    return response;
  }
);

export const reconcileProofUploads = onCall(
  {
    cors: true,
    timeoutSeconds: 60,
    memory: "512MiB"
  },
  async (request) => {
    const response = await handleProofUploadReconciliationRequest({
      auth: request.auth ? { uid: request.auth.uid } : null,
      data: request.data
    }, adminProofUploadReconciliationDependencies(callableQuotaGuard));

    if (!response.ok) {
      throw toHttpsError(response);
    }

    return response;
  }
);

export const promoteProofUploadReceipt = onCall(
  {
    cors: true,
    timeoutSeconds: 60,
    memory: "512MiB"
  },
  async (request) => {
    const response = await handleProofUploadPromotionRequest({
      auth: request.auth ? { uid: request.auth.uid } : null,
      data: request.data
    }, adminProofUploadPromotionDependencies(callableQuotaGuard));

    if (!response.ok) {
      throw toHttpsError(response);
    }

    return response;
  }
);

export const acknowledgeBackendEvents = onCall(
  {
    cors: true,
    timeoutSeconds: 60,
    memory: "512MiB"
  },
  async (request) => {
    const response = await handleBackendEventSyncRequest({
      auth: request.auth ? { uid: request.auth.uid } : null,
      data: request.data
    }, adminBackendEventSyncDependencies(callableQuotaGuard));

    if (!response.ok) {
      throw toHttpsError(response);
    }

    return response;
  }
);

export { handleBackendEventSyncRequest } from "./backendEventSync.js";
export {
  adminCallableQuotaGuard,
  callableQuotaDayPath,
  createFirestoreCallableQuotaGuard
} from "./callableQuotaGuard.js";
export { handleOpenLARPWorkflowRequest } from "./workflowHandler.js";
export { handleProofUploadPromotionRequest } from "./proofUploadPromotion.js";
export { handleProofUploadReconciliationRequest } from "./proofUploadReconciliation.js";
export type {
  BackendEventDocumentAcknowledgement,
  BackendEventSyncReceipt,
  BackendEventSyncResponse,
  BackendEventSyncSuccess,
  OpenLARPBackendEventSyncRequest
} from "./backendEventSync.js";
export type {
  OpenLARPProofUploadPromotionRequest,
  ProofUploadPromotionIntent,
  ProofUploadPromotionReceipt,
  ProofUploadPromotionResponse,
  ProofUploadPromotionStorageObject,
  ProofUploadPromotionSuccess
} from "./proofUploadPromotion.js";
export type {
  OpenLARPProofUploadReconciliationRequest,
  ProofUploadReconciliationCandidate,
  ProofUploadReconciliationResponse,
  ProofUploadReconciliationSuccess
} from "./proofUploadReconciliation.js";
export type {
  OpenLARPCallableAuth,
  OpenLARPWorkflowCallableRequest,
  OpenLARPWorkflowCallableResponse,
  OpenLARPWorkflowCallableSuccess
} from "./workflowHandler.js";
