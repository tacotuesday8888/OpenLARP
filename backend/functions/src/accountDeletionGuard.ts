import { getFirestore } from "firebase-admin/firestore";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type AccountDeletionRequestStatus = "deleting" | "deleted" | "partial";

export type AccountDeletionRequestDocument = {
  schemaVersion: 1;
  ownerUserID: string;
  status: AccountDeletionRequestStatus;
};

export type AccountDeletionStatusReader = {
  readAccountDeletionRequest: (userID: string) => Promise<Record<string, unknown> | null>;
};

export function accountDeletionRequestPath(userID: string): string {
  return `_accountDeletionRequests/${userID}`;
}

export async function rejectIfAccountDeletionRequested(
  userID: string,
  reader: AccountDeletionStatusReader = adminAccountDeletionStatusReader()
): Promise<OpenLARPFunctionError | null> {
  const document = await reader.readAccountDeletionRequest(userID);
  if (!isBlockingAccountDeletionRequest(userID, document)) {
    return null;
  }

  return functionError(
    "failed-precondition",
    accountDeletionBlockedMessage(),
    {
      status: document.status
    }
  );
}

export function accountDeletionBlockedError(status: AccountDeletionRequestStatus): OpenLARPFunctionError {
  return functionError(
    "failed-precondition",
    accountDeletionBlockedMessage(),
    {
      status
    }
  );
}

function accountDeletionBlockedMessage(): string {
  return "This OpenLARP account is already scheduled for deletion. Sign in again after deletion completes or contact support if it remains partial.";
}

export function isBlockingAccountDeletionRequest(
  userID: string,
  document: Record<string, unknown> | null | undefined
): document is AccountDeletionRequestDocument {
  return document?.schemaVersion === 1
    && document?.ownerUserID === userID
    && (
      document?.status === "deleting"
        || document?.status === "deleted"
        || document?.status === "partial"
    );
}

export function adminAccountDeletionStatusReader(): AccountDeletionStatusReader {
  return {
    async readAccountDeletionRequest(userID) {
      const snapshot = await getFirestore()
        .doc(accountDeletionRequestPath(userID))
        .get();
      return snapshot.exists ? snapshot.data() ?? null : null;
    }
  };
}
