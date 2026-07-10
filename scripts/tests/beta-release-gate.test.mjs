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
    "RevenueCat-Info.plist",
    "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)",
    "OPENLARP_RELEASE_CHANNEL: internal-beta",
    "OPENLARP_RELEASE_CHANNEL: app-store"
  ].join("\n")],
  ["OpenLARP/Models/OpenLARPReleaseConfiguration.swift", [
    "static let appStoreMVP",
    "accessMode: .free",
    "enabledCapabilities: []",
    "return .appStoreMVP"
  ].join("\n")],
  ["OpenLARP/AppRootView.swift", "releaseConfiguration.isEnabled(.agent)"],
  ["OpenLARP/Views/TodayView.swift", [
    "releaseConfiguration.isEnabled(.subscriptions)",
    "releaseConfiguration.isEnabled(.agent)"
  ].join("\n")],
  ["OpenLARP/Views/ProfileView.swift", [
    "releaseConfiguration.isEnabled(.account)",
    "releaseConfiguration.isEnabled(.cloudSync)",
    "releaseConfiguration.isEnabled(.subscriptions)",
    "releaseConfiguration.isEnabled(.developerTools)"
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

  it("blocks a missing fail-safe App Store release profile", () => {
    const files = new Map(completeFiles);
    files.delete("OpenLARP/Models/OpenLARPReleaseConfiguration.swift");

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "App Store release configuration is missing or not fail-safe."
    });
  });

  it("blocks a paid App Store release profile", () => {
    const files = new Map(completeFiles);
    files.set(
      "OpenLARP/Models/OpenLARPReleaseConfiguration.swift",
      files.get("OpenLARP/Models/OpenLARPReleaseConfiguration.swift")
        .replace("accessMode: .free", "accessMode: .subscriptionRequired")
    );

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "App Store release configuration is missing or not fail-safe."
    });
  });

  it("blocks an App Store release profile with enabled capabilities", () => {
    const files = new Map(completeFiles);
    files.set(
      "OpenLARP/Models/OpenLARPReleaseConfiguration.swift",
      files.get("OpenLARP/Models/OpenLARPReleaseConfiguration.swift")
        .replace("enabledCapabilities: []", "enabledCapabilities: [.subscriptions]")
    );

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "App Store release configuration is missing or not fail-safe."
    });
  });

  it.each([
    ["Info key", "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)"],
    ["Debug channel", "OPENLARP_RELEASE_CHANNEL: internal-beta"],
    ["Release channel", "OPENLARP_RELEASE_CHANNEL: app-store"]
  ])("blocks a missing %s release channel marker", (_name, marker) => {
    const files = new Map(completeFiles);
    files.set("project.yml", files.get("project.yml").replace(marker, ""));

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "Debug or Release build channel configuration is missing."
    });
  });

  it("blocks public views that do not consume release capabilities", () => {
    const files = new Map(completeFiles);
    files.set("OpenLARP/Views/TodayView.swift", "Today without release gates");

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "Public SwiftUI surfaces do not consistently gate unfinished capabilities."
    });
  });

  it.each([
    ["OpenLARP/AppRootView.swift", "releaseConfiguration.isEnabled(.agent)"],
    ["OpenLARP/Views/TodayView.swift", "releaseConfiguration.isEnabled(.subscriptions)"],
    ["OpenLARP/Views/TodayView.swift", "releaseConfiguration.isEnabled(.agent)"],
    ["OpenLARP/Views/ProfileView.swift", "releaseConfiguration.isEnabled(.account)"],
    ["OpenLARP/Views/ProfileView.swift", "releaseConfiguration.isEnabled(.cloudSync)"],
    ["OpenLARP/Views/ProfileView.swift", "releaseConfiguration.isEnabled(.subscriptions)"],
    ["OpenLARP/Views/ProfileView.swift", "releaseConfiguration.isEnabled(.developerTools)"]
  ])("blocks %s when it is missing %s", (path, marker) => {
    const files = new Map(completeFiles);
    files.set(path, files.get(path).replace(marker, ""));

    const gate = evaluatorFor(files);

    expect(gate.ok).toBe(false);
    expect(gate.results).toContainEqual({
      level: "blocker",
      message: "Public SwiftUI surfaces do not consistently gate unfinished capabilities."
    });
  });
});
