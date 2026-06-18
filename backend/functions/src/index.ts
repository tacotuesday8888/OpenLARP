import { getApps, initializeApp } from "firebase-admin/app";
import { onCall } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import { toHttpsError } from "./errors.js";
import { handleOpenLARPWorkflowRequest } from "./workflowHandler.js";

if (getApps().length === 0) {
  initializeApp();
}

setGlobalOptions({
  region: "us-central1",
  maxInstances: 10
});

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
    });

    if (!response.ok) {
      throw toHttpsError(response);
    }

    return response;
  }
);

export { handleOpenLARPWorkflowRequest } from "./workflowHandler.js";
export type {
  OpenLARPCallableAuth,
  OpenLARPWorkflowCallableRequest,
  OpenLARPWorkflowCallableResponse,
  OpenLARPWorkflowCallableSuccess
} from "./workflowHandler.js";
