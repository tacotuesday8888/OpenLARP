import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const read = (path) => readFileSync(resolve(repoRoot, path), "utf8");

describe("private AI service container contract", () => {
  it("uses a CommonJS bundle that can start Genkit's Node dependencies", () => {
    const packageJSON = JSON.parse(read("backend/ai-service/package.json"));
    const dockerfile = read("backend/ai-service/Dockerfile");

    expect(packageJSON.scripts.build).toContain("--format=cjs");
    expect(packageJSON.scripts.build).toContain("--outfile=dist/index.cjs");
    expect(packageJSON.scripts.start).toBe("node dist/index.cjs");
    expect(dockerfile).toContain("/dist/index.cjs ./index.cjs");
    expect(dockerfile).toContain('CMD ["node", "index.cjs"]');
  });

  it("sends only required service build inputs into the Docker context", () => {
    const dockerIgnore = read("backend/ai-service/Dockerfile.dockerignore");
    expect(dockerIgnore.split(/\r?\n/, 1)[0]).toBe("**");
    for (const required of [
      "!package.json",
      "!package-lock.json",
      "!backend/ai/package.json",
      "!backend/ai/src/**",
      "!backend/ai-service/package.json",
      "!backend/ai-service/tsconfig.json",
      "!backend/ai-service/src/**",
      "!backend/functions/package.json",
      "!firebase-rules/package.json"
    ]) {
      expect(dockerIgnore).toContain(`${required}\n`);
    }
    expect(dockerIgnore).not.toMatch(/!.*(?:\.env|GoogleService-Info|RevenueCat-Info|\.p8|\.p12)/);
  });

  it("uploads only required service build inputs to Cloud Build", () => {
    const cloudIgnore = read(".gcloudignore");
    expect(cloudIgnore.split(/\r?\n/, 1)[0]).toBe("**");
    for (const required of [
      "!backend/ai-service/Dockerfile.dockerignore",
      "!backend/ai-service/Dockerfile",
      "!backend/ai-service/cloudbuild.yaml",
      "!backend/ai-service/src/**",
      "!backend/ai/src/**"
    ]) {
      expect(cloudIgnore).toContain(`${required}\n`);
    }
    expect(cloudIgnore).not.toMatch(/!.*(?:\.env|GoogleService-Info|RevenueCat-Info|\.p8|\.p12)/);
  });
});
