import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import {
  configFromEnvironment,
  createVertexStructuredGenerator,
  executeWorkflow
} from "../../ai/src/index.js";
import {
  handleAIServiceRequest,
  MAX_AI_SERVICE_BODY_BYTES,
  type AIServiceDependencies
} from "./app.js";

const config = configFromEnvironment();
const generator = createVertexStructuredGenerator(config);
const dependencies: AIServiceDependencies = {
  execute: (request, signal) => executeWorkflow({
    envelope: request.envelope,
    policy: {
      ...request.policy,
      enabled: request.policy.enabled && config.enableLiveGeneration,
      maxOutputTokens: Math.min(request.policy.maxOutputTokens, config.maxOutputTokens)
    },
    generator,
    ...(signal ? { signal } : {})
  })
};

const server = createServer((request, response) => {
  void handleNodeRequest(request, response, dependencies);
});
const port = parsePort(process.env.PORT);
server.listen(port);

const shutdown = () => server.close(() => process.exit(0));
process.once("SIGTERM", shutdown);
process.once("SIGINT", shutdown);

async function handleNodeRequest(
  request: IncomingMessage,
  response: ServerResponse,
  serviceDependencies: AIServiceDependencies
) {
  const controller = new AbortController();
  request.once("aborted", () => controller.abort());
  let body = "";
  let exceeded = false;
  for await (const chunk of request) {
    if (exceeded) continue;
    body += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
    if (Buffer.byteLength(body, "utf8") > MAX_AI_SERVICE_BODY_BYTES) {
      exceeded = true;
      body = "x".repeat(MAX_AI_SERVICE_BODY_BYTES + 1);
    }
  }

  const serviceResponse = await handleAIServiceRequest({
    method: request.method ?? "",
    path: request.url?.split("?", 1)[0] ?? "",
    headers: {
      "content-type": Array.isArray(request.headers["content-type"])
        ? request.headers["content-type"][0]
        : request.headers["content-type"]
    },
    body,
    signal: controller.signal
  }, serviceDependencies);
  response.writeHead(serviceResponse.status, serviceResponse.headers);
  response.end(serviceResponse.body);
}

function parsePort(value: string | undefined): number {
  if (value === undefined || value.length === 0) return 8080;
  const port = Number.parseInt(value, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("PORT must be an integer between 1 and 65535.");
  }
  return port;
}
