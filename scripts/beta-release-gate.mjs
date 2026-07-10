#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const REQUIRED_PRIVACY_DATA_TYPES = [
  "NSPrivacyCollectedDataTypeUserID",
  "NSPrivacyCollectedDataTypeEmailAddress",
  "NSPrivacyCollectedDataTypeOtherUserContent",
  "NSPrivacyCollectedDataTypePhotosorVideos",
  "NSPrivacyCollectedDataTypePurchaseHistory",
  "NSPrivacyCollectedDataTypeProductInteraction"
];

const REQUIRED_FILES = [
  "OpenLARP/PrivacyInfo.xcprivacy",
  "OpenLARP/OpenLARP.entitlements",
  "OpenLARP/Models/OpenLARPReleaseConfiguration.swift",
  "docs/APP_STORE_TESTFLIGHT_READINESS.md",
  "docs/BETA_TESTFLIGHT_PATH.md",
  "docs/FIREBASE_BACKEND_SETUP.md",
  "docs/REVENUECAT_SETUP.md",
  ".github/workflows/ios-ci.yml",
  "project.yml",
  "firestore.rules",
  "storage.rules"
];

function textIncludesAll(text, values) {
  return values.every((value) => text.includes(value));
}

function textHasLine(text, expectedLine) {
  return text.split(/\r?\n/).some((line) => line.trim() === expectedLine);
}

function textHasTopLevelLine(text, expectedLine) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim());
  const minimumIndentation = lines.reduce(
    (minimum, line) => Math.min(minimum, line.search(/\S/)),
    Number.POSITIVE_INFINITY
  );
  return lines.some(
    (line) => line.search(/\S/) === minimumIndentation && line.trim() === expectedLine
  );
}

function codeLineOffset(text, expectedPrefix) {
  let offset = 0;
  for (const line of text.split("\n")) {
    const trimmedLine = line.trimStart();
    if (trimmedLine.startsWith(expectedPrefix)) {
      return offset + line.indexOf(trimmedLine);
    }
    offset += line.length + 1;
  }
  return -1;
}

function extractBalancedBlockAfter(text, startIndex, openingCharacter, closingCharacter) {
  const openingIndex = text.indexOf(openingCharacter, startIndex);
  if (startIndex < 0 || openingIndex < 0) {
    return "";
  }

  let depth = 0;
  for (let index = openingIndex; index < text.length; index += 1) {
    if (text[index] === openingCharacter) {
      depth += 1;
    } else if (text[index] === closingCharacter) {
      depth -= 1;
      if (depth === 0) {
        return text.slice(openingIndex + 1, index);
      }
    }
  }

  return "";
}

function extractCodeBlock(text, expectedPrefix, openingCharacter, closingCharacter) {
  return extractBalancedBlockAfter(
    text,
    codeLineOffset(text, expectedPrefix),
    openingCharacter,
    closingCharacter
  );
}

function extractIndentedBlock(text, header) {
  const lines = text.split(/\r?\n/);
  const directChildIndentation = lines
    .filter((line) => line.trim())
    .reduce(
      (minimum, line) => Math.min(minimum, line.search(/\S/)),
      Number.POSITIVE_INFINITY
    );
  const headerIndex = lines.findIndex(
    (line) => line.search(/\S/) === directChildIndentation && line.trim() === header
  );
  if (headerIndex < 0) {
    return "";
  }

  const headerIndentation = lines[headerIndex].search(/\S/);
  const blockLines = [];
  for (let index = headerIndex + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (line.trim() && line.search(/\S/) <= headerIndentation) {
      break;
    }
    blockLines.push(line);
  }

  return blockLines.join("\n");
}

function readTrackedText(path) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return "";
  }
}

function addResult(results, level, message) {
  results.push({ level, message });
}

export function evaluateBetaReleaseGate(readText = readTrackedText, fileExists = existsSync) {
  const results = [];

  for (const path of REQUIRED_FILES) {
    if (fileExists(path)) {
      addResult(results, "pass", `Required file exists: ${path}`);
    } else {
      addResult(results, "blocker", `Missing required beta readiness file: ${path}`);
    }
  }

  const privacyManifest = readText("OpenLARP/PrivacyInfo.xcprivacy");
  if (privacyManifest) {
    if (privacyManifest.includes("<key>NSPrivacyTracking</key>") && privacyManifest.includes("<false/>")) {
      addResult(results, "pass", "Privacy manifest declares no tracking.");
    } else {
      addResult(results, "blocker", "Privacy manifest must explicitly declare tracking as false.");
    }

    if (textIncludesAll(privacyManifest, REQUIRED_PRIVACY_DATA_TYPES)) {
      addResult(results, "pass", "Privacy manifest covers current account, proof, payment, and analytics data categories.");
    } else {
      addResult(results, "blocker", "Privacy manifest is missing one or more required OpenLARP data categories.");
    }
  }

  const project = readText("project.yml");
  if (project) {
    if (project.includes("PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.app")) {
      addResult(results, "pass", "Bundle ID is set to com.openlarp.app.");
    } else {
      addResult(results, "blocker", "Bundle ID is not set to com.openlarp.app in project.yml.");
    }

    if (textIncludesAll(project, ["FirebaseAppCheck", "GoogleSignIn", "RevenueCat"])) {
      addResult(results, "pass", "Firebase App Check, Google Sign-In, and RevenueCat packages are declared.");
    } else {
      addResult(results, "blocker", "project.yml is missing Firebase App Check, Google Sign-In, or RevenueCat package wiring.");
    }

    if (project.includes("GoogleService-Info.plist") && project.includes("RevenueCat-Info.plist")) {
      addResult(results, "pass", "Local Firebase and RevenueCat plist copy hooks are present.");
    } else {
      addResult(results, "blocker", "Local Firebase and RevenueCat plist copy hooks are missing from project.yml.");
    }

    const targets = extractIndentedBlock(project, "targets:");
    const appTarget = extractIndentedBlock(targets, "OpenLARP:");
    const infoProperties = extractIndentedBlock(
      extractIndentedBlock(appTarget, "info:"),
      "properties:"
    );
    const configurations = extractIndentedBlock(
      extractIndentedBlock(appTarget, "settings:"),
      "configs:"
    );
    const debugConfiguration = extractIndentedBlock(configurations, "Debug:");
    const releaseConfiguration = extractIndentedBlock(configurations, "Release:");
    if (
      textHasTopLevelLine(infoProperties, "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)") &&
      textHasTopLevelLine(debugConfiguration, "OPENLARP_RELEASE_CHANNEL: internal-beta") &&
      textHasTopLevelLine(releaseConfiguration, "OPENLARP_RELEASE_CHANNEL: app-store")
    ) {
      addResult(results, "pass", "Debug and Release builds declare explicit release channels.");
    } else {
      addResult(results, "blocker", "Debug or Release build channel configuration is missing.");
    }
  }

  const releaseConfiguration = readText("OpenLARP/Models/OpenLARPReleaseConfiguration.swift");
  const appStoreProfile = extractCodeBlock(
    releaseConfiguration,
    "static let appStoreMVP = OpenLARPReleaseConfiguration",
    "(",
    ")"
  );
  const currentResolver = extractCodeBlock(
    releaseConfiguration,
    "static func current(",
    "{",
    "}"
  );
  const guardIndex = codeLineOffset(currentResolver, "guard ");
  const guardElseIndex = guardIndex < 0 ? -1 : currentResolver.indexOf("else {", guardIndex);
  const guardCondition = guardElseIndex < 0 ? "" : currentResolver.slice(guardIndex, guardElseIndex);
  const guardFallback = extractBalancedBlockAfter(currentResolver, guardElseIndex, "{", "}");
  if (
    textHasTopLevelLine(appStoreProfile, "channel: .appStore,") &&
    textHasTopLevelLine(appStoreProfile, "accessMode: .free,") &&
    textHasTopLevelLine(appStoreProfile, "enabledCapabilities: []") &&
    textHasLine(
      guardCondition,
      "guard let rawChannel = infoDictionary[infoDictionaryKey] as? String,"
    ) &&
    textHasLine(
      guardCondition,
      "let channel = OpenLARPReleaseChannel(rawValue: rawChannel)"
    ) &&
    guardFallback.trim() === "return .appStoreMVP"
  ) {
    addResult(results, "pass", "App Store release configuration is free and fail-safe.");
  } else {
    addResult(results, "blocker", "App Store release configuration is missing or not fail-safe.");
  }

  const rootView = readText("OpenLARP/AppRootView.swift");
  const todayView = readText("OpenLARP/Views/TodayView.swift");
  const profileView = readText("OpenLARP/Views/ProfileView.swift");
  if (
    rootView.includes("releaseConfiguration.isEnabled(.agent)") &&
    textIncludesAll(todayView, [
      "releaseConfiguration.isEnabled(.subscriptions)",
      "releaseConfiguration.isEnabled(.agent)"
    ]) &&
    textIncludesAll(profileView, [
      "releaseConfiguration.isEnabled(.account)",
      "releaseConfiguration.isEnabled(.cloudSync)",
      "releaseConfiguration.isEnabled(.subscriptions)",
      "releaseConfiguration.isEnabled(.developerTools)"
    ])
  ) {
    addResult(results, "pass", "Public SwiftUI surfaces gate unfinished capabilities.");
  } else {
    addResult(results, "blocker", "Public SwiftUI surfaces do not consistently gate unfinished capabilities.");
  }

  const entitlements = readText("OpenLARP/OpenLARP.entitlements");
  if (entitlements) {
    if (textIncludesAll(entitlements, [
      "com.apple.developer.applesignin",
      "com.apple.developer.devicecheck.appattest-environment",
      "production"
    ])) {
      addResult(results, "pass", "Sign in with Apple and production App Attest entitlements are declared.");
    } else {
      addResult(results, "blocker", "Apple sign-in or production App Attest entitlement is missing.");
    }
  }

  const workflow = readText(".github/workflows/ios-ci.yml");
  if (workflow) {
    if (textIncludesAll(workflow, [
      "npm run public:safety",
      "npm run beta:gate",
      "npm run test:backend",
      "npm run build:backend",
      "npm run test:rules:emulators",
      "xcodebuild",
      "test"
    ])) {
      addResult(results, "pass", "CI runs public safety, backend, rules, unsigned build, and simulator test checks.");
    } else {
      addResult(results, "blocker", "CI workflow is missing one or more beta gate checks.");
    }
  }

  const launchPacket = readText("docs/APP_STORE_TESTFLIGHT_READINESS.md");
  if (launchPacket) {
    if (textIncludesAll(launchPacket, [
      "TestFlight Beta Notes Draft",
      "Privacy Policy Checklist",
      "Support Page Checklist",
      "Pre-Submission Gates"
    ])) {
      addResult(results, "pass", "Launch packet includes TestFlight notes, privacy, support, and pre-submission gates.");
    } else {
      addResult(results, "blocker", "Launch packet is missing required TestFlight readiness sections.");
    }

    if (launchPacket.includes("or another owner-controlled page before submission")) {
      addResult(results, "warn", "Hosted privacy/support URLs still need final owner-controlled pages before TestFlight/App Store submission.");
    }
  }

  if (!fileExists("OpenLARP/GoogleService-Info.plist")) {
    addResult(results, "warn", "Local GoogleService-Info.plist is absent; live Google Sign-In and Firebase simulator smoke need ignored local config.");
  }

  if (!fileExists("OpenLARP/RevenueCat-Info.plist")) {
    addResult(results, "warn", "Local RevenueCat-Info.plist is absent; paid entitlement and purchase smoke remain setup-blocked.");
  }

  return {
    ok: !results.some((result) => result.level === "blocker"),
    results
  };
}

function main() {
  const gate = evaluateBetaReleaseGate();
  for (const result of gate.results) {
    const prefix = result.level === "pass" ? "PASS" : result.level === "warn" ? "WARN" : "BLOCKER";
    const stream = result.level === "blocker" ? process.stderr : process.stdout;
    stream.write(`${prefix} ${result.message}\n`);
  }

  if (!gate.ok) {
    process.exitCode = 1;
    return;
  }

  process.stdout.write("PASS beta release gate completed with no repo-controlled blockers\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
