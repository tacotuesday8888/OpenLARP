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
