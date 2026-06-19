import { describe, expect, it } from "vitest";
import { evaluateBetaReleaseGate } from "../beta-release-gate.mjs";

const completeFiles = new Map([
  ["OpenLARP/PrivacyInfo.xcprivacy", [
    "<key>NSPrivacyTracking</key>",
    "<false/>",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeOtherUserContent",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypePurchaseHistory",
    "NSPrivacyCollectedDataTypeProductInteraction"
  ].join("\n")],
  ["OpenLARP/OpenLARP.entitlements", [
    "com.apple.developer.applesignin",
    "com.apple.developer.devicecheck.appattest-environment",
    "production"
  ].join("\n")],
  ["docs/APP_STORE_TESTFLIGHT_READINESS.md", [
    "TestFlight Beta Notes Draft",
    "Privacy Policy Checklist",
    "Support Page Checklist",
    "Pre-Submission Gates",
    "or another owner-controlled page before submission"
  ].join("\n")],
  ["docs/BETA_TESTFLIGHT_PATH.md", "Beta path"],
  ["docs/FIREBASE_BACKEND_SETUP.md", "Firebase setup"],
  ["docs/REVENUECAT_SETUP.md", "RevenueCat setup"],
  [".github/workflows/ios-ci.yml", [
    "npm run public:safety",
    "npm run beta:gate",
    "npm run test:backend",
    "npm run build:backend",
    "npm run test:rules:emulators",
    "xcodebuild",
    "test"
  ].join("\n")],
  ["project.yml", [
    "PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.app",
    "FirebaseAppCheck",
    "GoogleSignIn",
    "RevenueCat",
    "GoogleService-Info.plist",
    "RevenueCat-Info.plist"
  ].join("\n")],
  ["firestore.rules", "rules_version = '2';"],
  ["storage.rules", "rules_version = '2';"]
]);

function evaluatorFor(files) {
  return evaluateBetaReleaseGate(
    (path) => files.get(path) ?? "",
    (path) => files.has(path)
  );
}

describe("beta release gate", () => {
  it("passes repo-controlled beta gates while warning about external setup", () => {
    const gate = evaluatorFor(completeFiles);

    expect(gate.ok).toBe(true);
    expect(gate.results.some((result) => result.level === "blocker")).toBe(false);
    expect(gate.results).toContainEqual({
      level: "warn",
      message: "Hosted privacy/support URLs still need final owner-controlled pages before TestFlight/App Store submission."
    });
    expect(gate.results).toContainEqual({
      level: "warn",
      message: "Local GoogleService-Info.plist is absent; live Google Sign-In and Firebase simulator smoke need ignored local config."
    });
    expect(gate.results).toContainEqual({
      level: "warn",
      message: "Local RevenueCat-Info.plist is absent; paid entitlement and purchase smoke remain setup-blocked."
    });
  });

  it("blocks missing privacy data categories", () => {
    const files = new Map(completeFiles);
    files.set("OpenLARP/PrivacyInfo.xcprivacy", "<key>NSPrivacyTracking</key>\n<false/>");

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "Privacy manifest is missing one or more required OpenLARP data categories."
    });
  });

  it("blocks missing CI beta checks", () => {
    const files = new Map(completeFiles);
    files.set(".github/workflows/ios-ci.yml", "xcodebuild");

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "CI workflow is missing one or more beta gate checks."
    });
  });
});
