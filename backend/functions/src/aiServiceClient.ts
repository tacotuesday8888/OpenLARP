import { GoogleAuth } from "google-auth-library";
import {
  internalWorkflowSuccessSchema,
  type InternalWorkflowRequest,
  type InternalWorkflowSuccess
} from "../../ai/src/internalServiceContracts.js";

type IdTokenRequestClient = {
  request: (options: {
    url: string;
    method: "POST";
    data: InternalWorkflowRequest;
    timeout: number;
    responseType: "json";
    maxContentLength: number;
    maxRedirects: number;
    validateStatus: (status: number) => boolean;
  }) => Promise<{ data: unknown }>;
};

export type AIServiceClient = {
  run: (request: Omit<InternalWorkflowRequest, "schemaVersion">) => Promise<InternalWorkflowSuccess>;
};

export class AIServiceClientError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AIServiceClientError";
  }
}

export function createAIServiceClient(input: {
  serviceURL: string;
  allowLoopbackHTTP?: boolean;
  getIdTokenClient?: (audience: string) => Promise<IdTokenRequestClient>;
}): AIServiceClient {
  const serviceURL = parseAIServiceURL(input.serviceURL, input.allowLoopbackHTTP);
  const getIdTokenClient = input.getIdTokenClient ?? (async (audience: string) => {
    const client = await new GoogleAuth().getIdTokenClient(audience);
    return client as IdTokenRequestClient;
  });

  return {
    async run(request) {
      try {
        const client = await getIdTokenClient(serviceURL.origin);
        const response = await client.request({
          url: `${serviceURL.origin}/v1/workflows:run`,
          method: "POST",
          data: { schemaVersion: 1, ...request },
          timeout: Math.min(request.policy.timeoutMs + 2_000, 50_000),
          responseType: "json",
          maxContentLength: 256 * 1024,
          maxRedirects: 0,
          validateStatus: (status) => status >= 200 && status < 300
        });
        const parsed = internalWorkflowSuccessSchema.safeParse(response.data);
        if (
          !parsed.success ||
          parsed.data.requestID !== request.envelope.run.requestID ||
          parsed.data.kind !== request.envelope.run.kind ||
          parsed.data.execution.policyRevision !== request.policy.policyRevision
        ) {
          throw new AIServiceClientError("AI service response failed validation.");
        }
        return parsed.data;
      } catch (error) {
        if (error instanceof AIServiceClientError) throw error;
        throw new AIServiceClientError("AI service request failed.");
      }
    }
  };
}

export function parseAIServiceURL(value: string, allowLoopbackHTTP = false): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("OPENLARP_AI_SERVICE_URL must be a valid URL.");
  }
  const loopback = url.hostname === "localhost" || url.hostname === "127.0.0.1" || url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(allowLoopbackHTTP && loopback && url.protocol === "http:")) {
    throw new Error("OPENLARP_AI_SERVICE_URL must use HTTPS.");
  }
  if (url.username || url.password || url.search || url.hash || (url.pathname !== "/" && url.pathname !== "")) {
    throw new Error("OPENLARP_AI_SERVICE_URL must be a credential-free service origin.");
  }
  return url;
}

export function aiServiceClientFromEnvironment(env: NodeJS.ProcessEnv = process.env): AIServiceClient | null {
  const serviceURL = env.OPENLARP_AI_SERVICE_URL;
  if (!serviceURL) return null;
  try {
    return createAIServiceClient({ serviceURL });
  } catch {
    return null;
  }
}
