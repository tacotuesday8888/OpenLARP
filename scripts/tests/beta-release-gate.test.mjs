import { describe, expect, it } from "vitest";
import { evaluateBetaReleaseGate } from "../beta-release-gate.mjs";

const projectFixture = [
  "packages:",
  "  FirebaseAppCheck:",
  "  GoogleSignIn:",
  "  RevenueCat:",
  "targets:",
  "  OpenLARP:",
  "    preBuildScripts:",
  "      - name: Local service configuration",
  "        script: |",
  "          GoogleService-Info.plist",
  "          RevenueCat-Info.plist",
  "    info:",
  "      properties:",
  "        OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)",
  "    settings:",
  "      base:",
  "        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.app",
  "      configs:",
  "        Debug:",
  "          OPENLARP_RELEASE_CHANNEL: internal-beta",
  "        Release:",
  "          OPENLARP_RELEASE_CHANNEL: app-store"
].join("\n");

const releaseConfigurationFixture = [
  "struct OpenLARPReleaseConfiguration {",
  "    static let appStoreMVP = OpenLARPReleaseConfiguration(",
  "        channel: .appStore,",
  "        accessMode: .free,",
  "        enabledCapabilities: []",
  "    )",
  "",
  "    static let internalBeta = OpenLARPReleaseConfiguration(",
  "        channel: .internalBeta,",
  "        accessMode: .subscription,",
  "        enabledCapabilities: [.subscriptions]",
  "    )",
  "",
  "    static func current(infoDictionary: [String: Any]) -> OpenLARPReleaseConfiguration {",
  "        guard let rawChannel = infoDictionary[infoDictionaryKey] as? String,",
  "              let channel = OpenLARPReleaseChannel(rawValue: rawChannel) else {",
  "            return .appStoreMVP",
  "        }",
  "",
  "        switch channel {",
  "        case .appStore:",
  "            return .appStoreMVP",
  "        case .internalBeta:",
  "            return .internalBeta",
  "        }",
  "    }",
  "}"
].join("\n");

function addingSafeProfileDecoy(source) {
  return [
    source,
    "",
    "let legacyFreePreview = OpenLARPReleaseConfiguration(",
    "    channel: .appStore,",
    "    accessMode: .free,",
    "    enabledCapabilities: []",
    ")"
  ].join("\n");
}

function replacingResolver(source, resolverLines) {
  const start = source.indexOf("    static func current");
  const end = source.lastIndexOf("\n}");
  return `${source.slice(0, start)}${resolverLines.join("\n")}${source.slice(end)}`;
}

function addingExternalChannelDecoy(configuration, value) {
  const expectedLine = `          OPENLARP_RELEASE_CHANNEL: ${value}`;
  return [
    projectFixture.replace(expectedLine, "          OPENLARP_RELEASE_CHANNEL: preview"),
    "  DecoyTarget:",
    "    settings:",
    "      configs:",
    `        ${configuration}:`,
    expectedLine
  ].join("\n");
}

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
  ["project.yml", projectFixture],
  ["OpenLARP/Models/OpenLARPReleaseConfiguration.swift", releaseConfigurationFixture],
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

function expectBlocker(files, message) {
  const gate = evaluatorFor(files);
  expect(gate.ok).toBe(false);
  expect(gate.results).toContainEqual({ level: "blocker", message });
}

const releaseConfigurationPath = "OpenLARP/Models/OpenLARPReleaseConfiguration.swift";
const releaseConfigurationBlocker = "App Store release configuration is missing or not fail-safe.";
const releaseChannelBlocker = "Debug or Release build channel configuration is missing.";

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

  it.each([
    ["paid App Store profile with a separate free-profile decoy", addingSafeProfileDecoy(
      releaseConfigurationFixture.replace("accessMode: .free", "accessMode: .subscription")
    )],
    ["non-empty App Store capabilities with an empty-profile decoy", addingSafeProfileDecoy(
      releaseConfigurationFixture.replace("enabledCapabilities: []", "enabledCapabilities: [.subscriptions]")
    )],
    ["internal App Store channel with an App Store-profile decoy", addingSafeProfileDecoy(
      releaseConfigurationFixture.replace("channel: .appStore", "channel: .internalBeta")
    )],
    ["internal-beta fallback with a later App Store switch case", releaseConfigurationFixture.replace(
      "            return .appStoreMVP",
      "            return .internalBeta"
    )],
    ["early internal return before an App Store fallback return", releaseConfigurationFixture.replace(
      "            return .appStoreMVP",
      [
        "            if infoDictionary[infoDictionaryKey] == nil { return .internalBeta }",
        "            return .appStoreMVP"
      ].join("\n")
    )],
    ["missing guard with matching comments and an unrelated else", replacingResolver(
      releaseConfigurationFixture,
      [
        "    static func current(infoDictionary: [String: Any]) -> OpenLARPReleaseConfiguration {",
        "        let rawChannel = infoDictionary[infoDictionaryKey] as? String ?? \"\"",
        "        if rawChannel.isEmpty { return .internalBeta }",
        "        // guard let rawChannel = infoDictionary[infoDictionaryKey] as? String,",
        "        // OpenLARPReleaseChannel(rawValue: rawChannel)",
        "        if rawChannel == \"internal-beta\" { return .internalBeta } else {",
        "            return .appStoreMVP",
        "        }",
        "    }"
      ]
    )],
    ["unvalidated unknown channel with guard-condition comment decoys", replacingResolver(
      releaseConfigurationFixture,
      [
        "    static func current(infoDictionary: [String: Any]) -> OpenLARPReleaseConfiguration {",
        "        guard !infoDictionary.isEmpty,",
        "              // infoDictionary[infoDictionaryKey] as? String",
        "              // OpenLARPReleaseChannel(rawValue: rawChannel)",
        "              true else { return .appStoreMVP }",
        "        let channel = OpenLARPReleaseChannel.internalBeta",
        "        switch channel {",
        "        case .appStore: return .appStoreMVP",
        "        case .internalBeta: return .internalBeta",
        "        }",
        "    }"
      ]
    )]
  ])("blocks %s", (_scenario, unsafeSource) => {
    const files = new Map(completeFiles);
    files.set(releaseConfigurationPath, unsafeSource);
    expectBlocker(files, releaseConfigurationBlocker);
  });

  it.each([
    ["Info key", "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)"],
    ["Debug channel", "OPENLARP_RELEASE_CHANNEL: internal-beta"],
    ["Release channel", "OPENLARP_RELEASE_CHANNEL: app-store"]
  ])("blocks a missing %s release channel marker", (_name, marker) => {
    const files = new Map(completeFiles);
    files.set("project.yml", files.get("project.yml").replace(marker, ""));
    expectBlocker(files, releaseChannelBlocker);
  });

  it.each([
    ["swapped Debug and Release values", projectFixture
      .replace("OPENLARP_RELEASE_CHANNEL: internal-beta", "OPENLARP_RELEASE_CHANNEL: swapped")
      .replace("OPENLARP_RELEASE_CHANNEL: app-store", "OPENLARP_RELEASE_CHANNEL: internal-beta")
      .replace("OPENLARP_RELEASE_CHANNEL: swapped", "OPENLARP_RELEASE_CHANNEL: app-store")],
    ["incorrect Debug value with a valid marker in another target",
      addingExternalChannelDecoy("Debug", "internal-beta")],
    ["incorrect Release value with a valid marker in another target",
      addingExternalChannelDecoy("Release", "app-store")],
    ["Info marker outside the OpenLARP target", [
      projectFixture.replace(
        "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)",
        "LegacyReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)"
      ),
      "  DecoyTarget:",
      "    info:",
      "      properties:",
      "        OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)"
    ].join("\n")],
    ["nested Debug marker decoy", projectFixture.replace(
      "          OPENLARP_RELEASE_CHANNEL: internal-beta",
      [
        "          OPENLARP_RELEASE_CHANNEL: preview",
        "          metadata:",
        "            OPENLARP_RELEASE_CHANNEL: internal-beta"
      ].join("\n")
    )],
    ["nested safe Debug header before the unsafe real configuration", projectFixture.replace(
      [
        "      configs:",
        "        Debug:",
        "          OPENLARP_RELEASE_CHANNEL: internal-beta"
      ].join("\n"),
      [
        "      configs:",
        "        metadata:",
        "          Debug:",
        "            OPENLARP_RELEASE_CHANNEL: internal-beta",
        "        Debug:",
        "          OPENLARP_RELEASE_CHANNEL: preview"
      ].join("\n")
    )]
  ])("blocks %s", (_scenario, unsafeProject) => {
    const files = new Map(completeFiles);
    files.set("project.yml", unsafeProject);
    expectBlocker(files, releaseChannelBlocker);
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
