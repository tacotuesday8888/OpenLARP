import { HttpsError } from "firebase-functions/v2/https";

export type OpenLARPFunctionErrorCode =
  | "unauthenticated"
  | "invalid-argument"
  | "permission-denied"
  | "failed-precondition"
  | "internal";

export type OpenLARPFunctionError = {
  ok: false;
  code: OpenLARPFunctionErrorCode;
  message: string;
  details?: unknown;
};

export function functionError(
  code: OpenLARPFunctionErrorCode,
  message: string,
  details?: unknown
): OpenLARPFunctionError {
  return details === undefined
    ? { ok: false, code, message }
    : { ok: false, code, message, details };
}

export function toHttpsError(error: OpenLARPFunctionError): HttpsError {
  return new HttpsError(error.code, error.message, error.details);
}
