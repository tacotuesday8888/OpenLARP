import { describe, expect, it } from "vitest";
import { evaluateBetaReleaseGate } from "../beta-release-gate.mjs";

const projectFixture = `
name: OpenLARP
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
  GoogleSignIn:
    url: https://github.com/google/GoogleSignIn-iOS
  RevenueCat:
    url: https://github.com/RevenueCat/purchases-ios
targets:
  OpenLARP:
    type: application
    dependencies:
      - package: Firebase
        product: FirebaseAppCheck
      - package: GoogleSignIn
        product: GoogleSignIn
      - package: RevenueCat
        product: RevenueCat
    postBuildScripts:
      - name: Copy Local Firebase Configuration
        script: |
          CONFIG_FILE="\${SRCROOT}/OpenLARP/GoogleService-Info.plist"
          TARGET_FILE="\${BUILT_PRODUCTS_DIR}/\${PRODUCT_NAME}.app/GoogleService-Info.plist"
          if [ "\${OPENLARP_RELEASE_CHANNEL}" != "internal-beta" ]; then
            rm -f "$TARGET_FILE"
            exit 0
          fi
          if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$TARGET_FILE"
          else
            rm -f "$TARGET_FILE"
          fi
      - name: Copy Local RevenueCat Configuration
        script: |
          CONFIG_FILE="\${SRCROOT}/OpenLARP/RevenueCat-Info.plist"
          TARGET_FILE="\${BUILT_PRODUCTS_DIR}/\${PRODUCT_NAME}.app/RevenueCat-Info.plist"
          if [ "\${OPENLARP_RELEASE_CHANNEL}" != "internal-beta" ]; then
            rm -f "$TARGET_FILE"
            exit 0
          fi
          if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$TARGET_FILE"
          else
            rm -f "$TARGET_FILE"
          fi
    scheme:
      testTargets:
        - OpenLARPTests
    info:
      properties:
        OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.app
      configs:
        Debug:
          OPENLARP_RELEASE_CHANNEL: internal-beta
        Release:
          OPENLARP_RELEASE_CHANNEL: app-store
  OpenLARPTests:
    type: bundle.unit-test
    dependencies:
      - target: OpenLARP
  OpenLARPReleaseContractTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - OpenLARPReleaseContractTests
    dependencies:
      - target: OpenLARP
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.release-contract-tests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  OpenLARPReleaseContract:
    management:
      shared: true
    build:
      buildImplicitDependencies: false
      targets:
        OpenLARP:
          - test
        OpenLARPReleaseContractTests:
          - test
    test:
      config: Release
      targets:
        - OpenLARPReleaseContractTests
`.trim();

const workflowFixture = `
name: iOS CI
jobs:
  build-and-test:
    steps:
      - name: Check public repo safety
        run: npm run public:safety
      - name: Check beta release gate
        run: npm run beta:gate
      - name: Test Genkit backend
        run: npm run test:backend
      - name: Build Firebase Functions backend
        run: npm run build:backend
      - name: Test Firebase security rules
        run: npm run test:rules:emulators
      - name: Generate Xcode project
        run: xcodegen generate
      - name: Select available iPhone simulator
        id: simulator
        run: |
          DEVICE_ID="$(python3 - <<'PY'
          import subprocess
          import sys
          try:
              result = subprocess.run(["xcrun", "simctl", "list", "devices", "available"], timeout=120)
          except subprocess.TimeoutExpired:
              print("::error::Timed out while listing iOS simulators.", file=sys.stderr)
              sys.exit(1)
          if result.returncode != 0:
              sys.exit(result.returncode or 1)
          print("00000000-0000-0000-0000-000000000000")
          PY
          )"
          if [ -z "$DEVICE_ID" ]; then
            echo "::error::No available iPhone simulator found."
            exit 1
          fi
          echo "device_id=$DEVICE_ID" >> "$GITHUB_OUTPUT"
      - name: Build unsigned iOS app
        run: |
          xcodebuild -project OpenLARP.xcodeproj -scheme OpenLARP -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build
      - name: Run Debug simulator tests
        run: |
          set -euo pipefail
          DEBUG_RESULT_BUNDLE="\${RUNNER_TEMP}/OpenLARPDebug-\${GITHUB_RUN_ID}-\${GITHUB_RUN_ATTEMPT}.xcresult"
          xcodebuild -project OpenLARP.xcodeproj -scheme OpenLARP -configuration Debug -destination "id=\${{ steps.simulator.outputs.device_id }}" -derivedDataPath /tmp/OpenLARPDerivedDataTests -resultBundlePath "$DEBUG_RESULT_BUNDLE" test
          export DEBUG_SUMMARY_JSON="$(xcrun xcresulttool get test-results summary --path "$DEBUG_RESULT_BUNDLE" --compact)"
          python3 - <<'PY'
          import json
          import os
          import sys
          summary = json.loads(os.environ["DEBUG_SUMMARY_JSON"])
          total = summary.get("totalTestCount")
          passed = summary.get("passedTests")
          failed = summary.get("failedTests")
          skipped = summary.get("skippedTests")
          if not isinstance(total, int) or total <= 0 or passed != total or failed != 0 or skipped != 0:
              print("::error::Debug test count mismatch.", file=sys.stderr)
              sys.exit(1)
          PY
      - name: Run optimized App Store Release contract
        run: |
          set -euo pipefail
          ENABLE_TESTABILITY="$(xcodebuild -project OpenLARP.xcodeproj -target OpenLARP -configuration Release -showBuildSettings | awk -F ' = ' '/^[[:space:]]*ENABLE_TESTABILITY = / { print $2 }')"
          if [ "$ENABLE_TESTABILITY" != "NO" ]; then
            echo "::error::Release ENABLE_TESTABILITY must be NO."
            exit 1
          fi
          RESULT_BUNDLE="\${RUNNER_TEMP}/OpenLARPReleaseContract-\${GITHUB_RUN_ID}-\${GITHUB_RUN_ATTEMPT}.xcresult"
          xcodebuild -project OpenLARP.xcodeproj -scheme OpenLARPReleaseContract -configuration Release -destination "id=\${{ steps.simulator.outputs.device_id }}" -derivedDataPath /tmp/OpenLARPReleaseContractTests -resultBundlePath "$RESULT_BUNDLE" -only-testing:OpenLARPReleaseContractTests/OpenLARPReleaseContractTests/testAppStoreReleaseContract test
          export SUMMARY_JSON="$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --compact)"
          python3 - <<'PY'
          import json
          import os
          import sys
          summary = json.loads(os.environ["SUMMARY_JSON"])
          expected = {
              "totalTestCount": 1,
              "passedTests": 1,
              "failedTests": 0,
              "skippedTests": 0,
          }
          actual = {key: summary.get(key) for key in expected}
          if actual != expected:
              print(f"::error::Release contract test count mismatch: {actual}", file=sys.stderr)
              sys.exit(1)
          PY
`.trim();

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
  ["OpenLARP/Models/OpenLARPReleaseConfiguration.swift", "release configuration"],
  ["OpenLARP/Models/OpenLARPReleasePresentationPolicy.swift", "presentation policy"],
  ["OpenLARP/Models/OpenLARPReleaseContractSnapshot.swift", "release snapshot"],
  ["OpenLARPReleaseContractTests/OpenLARPReleaseContractTests.swift", "ordinary import contract"],
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
  [".github/workflows/ios-ci.yml", workflowFixture],
  ["project.yml", projectFixture],
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

function replacing(path, from, to) {
  const files = new Map(completeFiles);
  files.set(path, files.get(path).replace(from, to));
  return files;
}

const projectContractBlocker = "project.yml must define the isolated Release contract target and scheme.";
const releaseChannelBlocker = "Debug or Release build channel configuration is missing.";
const serviceCopyBlocker = "Local service configuration copy hooks must be restricted to internal-beta builds.";
const workflowBlocker = "CI workflow must fail closed and execute Debug tests plus the verified Release contract.";

describe("beta release gate", () => {
  it("passes repository-controlled checks while warning about external setup", () => {
    const gate = evaluatorFor(completeFiles);

    expect(gate.results.filter((result) => result.level === "blocker")).toEqual([]);
    expect(gate.ok).toBe(true);
    expect(gate.results.some((result) => result.level === "blocker")).toBe(false);
    expect(gate.results).toContainEqual({
      level: "warn",
      message: "Hosted privacy/support URLs still need final owner-controlled pages before TestFlight/App Store submission."
    });
  });

  it("blocks missing privacy data categories", () => {
    expectBlocker(
      replacing("OpenLARP/PrivacyInfo.xcprivacy", "NSPrivacyCollectedDataTypeUserID", ""),
      "Privacy manifest is missing one or more required OpenLARP data categories."
    );
  });

  it.each([
    ["contract target", "  OpenLARPReleaseContractTests:\n", "  RenamedContractTests:\n"],
    ["contract target type", "    type: bundle.unit-test\n    platform: iOS", "    type: application\n    platform: iOS"],
    ["contract target platform", "  OpenLARPReleaseContractTests:\n    type: bundle.unit-test\n    platform: iOS", "  OpenLARPReleaseContractTests:\n    type: bundle.unit-test\n    platform: macOS"],
    ["contract target source", "    sources:\n      - OpenLARPReleaseContractTests", "    sources:\n      - OpenLARPTests"],
    ["contract target app dependency", "    dependencies:\n      - target: OpenLARP\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.release-contract-tests", "    dependencies:\n      - target: OpenLARPTests\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.release-contract-tests"],
    ["contract target sole dependency", "    dependencies:\n      - target: OpenLARP\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.release-contract-tests", "    dependencies:\n      - target: OpenLARP\n      - target: OpenLARPTests\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.release-contract-tests"],
    ["contract target unique bundle ID", "PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.release-contract-tests", "PRODUCT_BUNDLE_IDENTIFIER: com.openlarp.app"],
    ["contract target generated plist", "        GENERATE_INFOPLIST_FILE: YES", "        GENERATE_INFOPLIST_FILE: NO"],
    ["Debug scheme test target", "    scheme:\n      testTargets:\n        - OpenLARPTests", "    scheme:\n      testTargets:\n        - OpenLARPReleaseContractTests"],
    ["contract scheme", "  OpenLARPReleaseContract:\n", "  RenamedReleaseContract:\n"],
    ["shared scheme marker", "      shared: true", "      shared: false"],
    ["explicit dependency closure", "      buildImplicitDependencies: false", "      buildImplicitDependencies: true"],
    ["app build-for-test entry", "        OpenLARP:\n          - test", "        OpenLARP:\n          - all"],
    ["contract build entry", "        OpenLARPReleaseContractTests:\n          - test", "        OpenLARPReleaseContractTests:\n          - run"],
    ["Release test configuration", "      config: Release", "      config: Debug"],
    ["contract test target", "      targets:\n        - OpenLARPReleaseContractTests", "      targets:\n        - OpenLARPTests"]
  ])("blocks a missing or weakened %s", (_name, from, to) => {
    expectBlocker(replacing("project.yml", from, to), projectContractBlocker);
  });

  it.each([
    ["Info key", "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)"],
    ["Debug channel", "OPENLARP_RELEASE_CHANNEL: internal-beta"],
    ["Release channel", "OPENLARP_RELEASE_CHANNEL: app-store"]
  ])("blocks a missing %s release channel value", (_name, marker) => {
    expectBlocker(replacing("project.yml", marker, ""), releaseChannelBlocker);
  });

  it.each([
    ["Firebase copy guard", "Copy Local Firebase Configuration", "Copy Legacy Firebase Configuration"],
    ["RevenueCat copy guard", "Copy Local RevenueCat Configuration", "Copy Legacy RevenueCat Configuration"],
    ["internal-only branch", "if [ \"${OPENLARP_RELEASE_CHANNEL}\" != \"internal-beta\" ]; then", "if false; then"],
    ["stale-copy removal", "rm -f \"$TARGET_FILE\"", "true"]
  ])("blocks a weakened %s", (_name, from, to) => {
    expectBlocker(replacing("project.yml", from, to), serviceCopyBlocker);
  });

  it.each([
    ["conditional simulator selection", "        id: simulator\n", "        id: simulator\n        if: success()\n"],
    ["continue-on-error simulator selection", "        id: simulator\n", "        id: simulator\n        continue-on-error: true\n"],
    ["timeout success", "              sys.exit(1)", "              sys.exit(0)"],
    ["simctl failure success", "              sys.exit(result.returncode or 1)", "              sys.exit(0)"],
    ["no-device success", "            exit 1\n          fi", "            exit 0\n          fi"],
    ["conditional Debug tests", "      - name: Run Debug simulator tests\n", "      - name: Run Debug simulator tests\n        if: success()\n"],
    ["continue-on-error Debug tests", "      - name: Run Debug simulator tests\n", "      - name: Run Debug simulator tests\n        continue-on-error: true\n"],
    ["missing Debug configuration", "-configuration Debug", ""],
    ["missing selected simulator in Debug tests", "-configuration Debug -destination \"id=${{ steps.simulator.outputs.device_id }}\"", "-configuration Debug"],
    ["Debug result bundle", "-resultBundlePath \"$DEBUG_RESULT_BUNDLE\"", ""],
    ["Debug xcresult summary", "xcrun xcresulttool get test-results summary --path \"$DEBUG_RESULT_BUNDLE\"", "echo"],
    ["Debug nonzero test count", "total <= 0", "total < 0"],
    ["Debug all-tests-passed count", "passed != total", "passed < total"],
    ["Debug failed test count", "failed != 0", "failed < 0"],
    ["Debug skipped test count", "skipped != 0", "skipped < 0"],
    ["conditional Release contract", "      - name: Run optimized App Store Release contract\n", "      - name: Run optimized App Store Release contract\n        if: success()\n"],
    ["continue-on-error Release contract", "      - name: Run optimized App Store Release contract\n", "      - name: Run optimized App Store Release contract\n        continue-on-error: true\n"],
    ["contract scheme", "-scheme OpenLARPReleaseContract", "-scheme OpenLARP"],
    ["contract Release configuration", "-scheme OpenLARPReleaseContract -configuration Release", "-scheme OpenLARPReleaseContract -configuration Debug"],
    ["missing selected simulator in Release contract", "-scheme OpenLARPReleaseContract -configuration Release -destination \"id=${{ steps.simulator.outputs.device_id }}\"", "-scheme OpenLARPReleaseContract -configuration Release"],
    ["named only-testing filter", "-only-testing:OpenLARPReleaseContractTests/OpenLARPReleaseContractTests/testAppStoreReleaseContract", ""],
    ["result bundle", "-resultBundlePath \"$RESULT_BUNDLE\"", ""],
    ["unique result bundle path", "OpenLARPReleaseContract-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.xcresult", "OpenLARPReleaseContract.xcresult"],
    ["xcresult summary", "xcrun xcresulttool get test-results summary", "echo"],
    ["exact total test count", "\"totalTestCount\": 1", "\"totalTestCount\": 0"],
    ["exact passed test count", "\"passedTests\": 1", "\"passedTests\": 0"],
    ["exact failed test count", "\"failedTests\": 0", "\"failedTests\": 1"],
    ["exact skipped test count", "\"skippedTests\": 0", "\"skippedTests\": 1"],
    ["Release testability query", "-target OpenLARP -configuration Release -showBuildSettings", "-target OpenLARP -configuration Debug -showBuildSettings"],
    ["Release testability assertion", "[ \"$ENABLE_TESTABILITY\" != \"NO\" ]", "[ \"$ENABLE_TESTABILITY\" != \"YES\" ]"],
    ["generic Release build", "-scheme OpenLARP -configuration Release -destination generic/platform=iOS", "-scheme OpenLARP -destination generic/platform=iOS"]
  ])("blocks %s weakening", (_name, from, to) => {
    expectBlocker(replacing(".github/workflows/ios-ci.yml", from, to), workflowBlocker);
  });

  it("blocks duplicate required Release contract steps", () => {
    const duplicate = workflowFixture.replace(
      "      - name: Run optimized App Store Release contract\n",
      "      - name: Run optimized App Store Release contract\n        run: echo decoy\n      - name: Run optimized App Store Release contract\n"
    );
    const files = new Map(completeFiles);
    files.set(".github/workflows/ios-ci.yml", duplicate);
    expectBlocker(files, workflowBlocker);
  });

  it.each([
    ["simulator", "      - name: Select available iPhone simulator\n", "      - name: Select available iPhone simulator\n        run: echo decoy\n      - name: Select available iPhone simulator\n"],
    ["Debug test", "      - name: Run Debug simulator tests\n", "      - name: Run Debug simulator tests\n        run: echo decoy\n      - name: Run Debug simulator tests\n"]
  ])("blocks duplicate required %s steps", (_name, from, to) => {
    expectBlocker(
      replacing(".github/workflows/ios-ci.yml", from, to),
      workflowBlocker
    );
  });

  it.each([
    ["job if", "  build-and-test:\n    steps:", "  build-and-test:\n    if: success()\n    steps:"],
    ["job continue-on-error", "  build-and-test:\n    steps:", "  build-and-test:\n    continue-on-error: true\n    steps:"],
    ["legacy has_simulator output", "          echo \"device_id=$DEVICE_ID\" >> \"$GITHUB_OUTPUT\"", "          echo \"device_id=$DEVICE_ID\" >> \"$GITHUB_OUTPUT\"\n          echo \"has_simulator=true\" >> \"$GITHUB_OUTPUT\""],
    ["warning-only skip marker", "          echo \"device_id=$DEVICE_ID\" >> \"$GITHUB_OUTPUT\"", "          echo \"device_id=$DEVICE_ID\" >> \"$GITHUB_OUTPUT\"\n          echo \"::warning::simulator tests will be skipped\""],
    ["skipped-test report step", "      - name: Build unsigned iOS app\n", "      - name: Report skipped simulator tests\n        run: echo skipped\n      - name: Build unsigned iOS app\n"]
  ])("blocks %s bypass", (_name, from, to) => {
    expectBlocker(
      replacing(".github/workflows/ios-ci.yml", from, to),
      workflowBlocker
    );
  });
});
