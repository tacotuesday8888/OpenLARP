import {
  internalWorkflowRequestSchema,
  internalWorkflowSuccessSchema,
  type InternalWorkflowRequest,
  type WorkflowExecutionResult
} from "../../ai/src/index.js";

export const MAX_AI_SERVICE_BODY_BYTES = 256 * 1024;

export type AIServiceRequest = {
  method: string;
  path: string;
  headers: Record<string, string | undefined>;
  body: string;
  signal?: AbortSignal;
};

export type AIServiceResponse = {
  status: number;
  headers: Record<string, string>;
  body: string;
};

export type AIServiceDependencies = {
  execute: (request: InternalWorkflowRequest, signal?: AbortSignal) => Promise<WorkflowExecutionResult>;
};

const RESPONSE_HEADERS = {
  "cache-control": "no-store",
  "content-type": "application/json; charset=utf-8",
  "x-content-type-options": "nosniff"
};

export async function handleAIServiceRequest(
  request: AIServiceRequest,
  dependencies: AIServiceDependencies
): Promise<AIServiceResponse> {
  if (request.path === "/healthz") {
    if (request.method !== "GET") {
      return errorResponse(405, "method-not-allowed", "Method not allowed.");
    }
    return jsonResponse(200, { ok: true, schemaVersion: 1, service: "openlarp-ai" });
  }
  if (request.path !== "/v1/workflows:run") {
    return errorResponse(404, "not-found", "Route not found.");
  }
  if (request.method !== "POST") {
    return errorResponse(405, "method-not-allowed", "Method not allowed.");
  }
  if (mediaType(request.headers["content-type"]) !== "application/json") {
    return errorResponse(415, "unsupported-media-type", "Content-Type must be application/json.");
  }
  if (Buffer.byteLength(request.body, "utf8") > MAX_AI_SERVICE_BODY_BYTES) {
    return errorResponse(413, "payload-too-large", "Request body exceeded the service limit.");
  }

  let body: unknown;
  try {
    body = JSON.parse(request.body);
  } catch {
    return errorResponse(400, "invalid-request", "Request body was not valid JSON.");
  }
  const parsed = internalWorkflowRequestSchema.safeParse(body);
  if (!parsed.success) {
    return errorResponse(400, "invalid-request", "Request did not match the internal workflow contract.");
  }

  try {
    const result = await dependencies.execute(
      parsed.data,
      ...(request.signal ? [request.signal] : [])
    );
    const response = internalWorkflowSuccessSchema.parse({
      ok: true,
      schemaVersion: 1,
      requestID: parsed.data.envelope.run.requestID,
      kind: parsed.data.envelope.run.kind,
      externalActionTaken: false,
      result: result.result,
      execution: result.execution
    });
    return jsonResponse(200, response);
  } catch {
    return errorResponse(
      503,
      "service-unavailable",
      "OpenLARP AI service could not complete the workflow."
    );
  }
}

function mediaType(value: string | undefined): string {
  return value?.split(";", 1)[0]?.trim().toLowerCase() ?? "";
}

function jsonResponse(status: number, body: unknown): AIServiceResponse {
  return {
    status,
    headers: RESPONSE_HEADERS,
    body: JSON.stringify(body)
  };
}

function errorResponse(status: number, code: string, message: string): AIServiceResponse {
  return jsonResponse(status, {
    ok: false,
    schemaVersion: 1,
    code,
    message
  });
}
