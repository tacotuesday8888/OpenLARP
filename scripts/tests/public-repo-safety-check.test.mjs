import { describe, expect, it } from "vitest";
import {
  blockedTrackedPaths,
  secretTextFindings
} from "../public-repo-safety-check.mjs";

describe("public repo safety check", () => {
  const syntheticFirebaseKey = `AIza${"A".repeat(32)}`;
  const syntheticRevenueCatKey = `appl_${"1".repeat(16)}`;

  it("blocks tracked local config, macOS metadata, env, and signing files", () => {
    expect(blockedTrackedPaths([
      "OpenLARP/GoogleService-Info.plist",
      "OpenLARP/RevenueCat-Info.plist",
      "docs/.DS_Store",
      ".env.local",
      "AuthKey_ABC123.p8",
      "distribution.mobileprovision",
      "OpenLARP/Models/OpenLARPStore.swift"
    ])).toEqual([
      "OpenLARP/GoogleService-Info.plist",
      "OpenLARP/RevenueCat-Info.plist",
      "docs/.DS_Store",
      ".env.local",
      "AuthKey_ABC123.p8",
      "distribution.mobileprovision"
    ]);
  });

  it("finds real-looking keys outside test and docs fixtures", () => {
    const findings = secretTextFindings([
      {
        path: "OpenLARP/Config.swift",
        text: `let apiKey = "${syntheticFirebaseKey}"`
      },
      {
        path: "backend/functions/src/config.ts",
        text: `const key = '${syntheticRevenueCatKey}'`
      }
    ]);

    expect(findings).toEqual([
      {
        path: "OpenLARP/Config.swift",
        patternName: "Firebase API key"
      },
      {
        path: "backend/functions/src/config.ts",
        patternName: "RevenueCat iOS SDK key"
      }
    ]);
  });

  it("allows placeholder names and short redaction fixtures that are not key-shaped", () => {
    expect(secretTextFindings([
      {
        path: "OpenLARPTests/BetaMeasurementTests.swift",
        text: "sk-test-secret should stay as a redaction fixture"
      },
      {
        path: "docs/REVENUECAT_SETUP.md",
        text: "Use REVENUECAT_IOS_API_KEY locally, not in source control."
      },
      {
        path: "scripts/tests/public-repo-safety-check.test.mjs",
        text: "appl_public_test_key"
      }
    ])).toEqual([]);
  });
});
