#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const REQUIRED_INTERNAL_PRIVACY_DATA_TYPES = [
  "NSPrivacyCollectedDataTypeUserID",
  "NSPrivacyCollectedDataTypeEmailAddress",
  "NSPrivacyCollectedDataTypeOtherUserContent",
  "NSPrivacyCollectedDataTypePhotosorVideos",
  "NSPrivacyCollectedDataTypePurchaseHistory",
  "NSPrivacyCollectedDataTypeProductInteraction"
];

const REQUIRED_FILES = [
  "OpenLARP/PrivacyInfo.xcprivacy",
  "OpenLARPInternal/PrivacyInfo.xcprivacy",
  "OpenLARPInternal/OpenLARPInternal.entitlements",
  "OpenLARP/Models/OpenLARPReleaseConfiguration.swift",
  "OpenLARP/Models/OpenLARPReleasePresentationPolicy.swift",
  "OpenLARP/Models/OpenLARPReleaseContractSnapshot.swift",
  "OpenLARPReleaseContractTests/OpenLARPReleaseContractTests.swift",
  "OpenLARP.xcodeproj/xcshareddata/xcschemes/OpenLARP.xcscheme",
  "docs/APP_STORE_TESTFLIGHT_READINESS.md",
  "docs/BETA_TESTFLIGHT_PATH.md",
  "docs/FIREBASE_BACKEND_SETUP.md",
  "docs/REVENUECAT_SETUP.md",
  ".github/workflows/ios-ci.yml",
  "project.yml",
  "firestore.rules",
  "storage.rules"
];

const PROJECT_CONTRACT_BLOCKER =
  "project.yml must define the isolated Release contract target and scheme.";
const RELEASE_CHANNEL_BLOCKER =
  "Debug or Release build channel configuration is missing.";
const SERVICE_COPY_BLOCKER =
  "Local service configuration copy hooks must be restricted to internal-beta builds.";
const PUBLIC_TARGET_BOUNDARY_BLOCKER =
  "The App Store target must be isolated from internal service SDKs, auth metadata, and entitlements.";
const PUBLIC_PRIVACY_BLOCKER =
  "The App Store privacy manifest must declare no tracking and no collected data.";
const PUBLIC_SCHEME_BLOCKER =
  "The shared OpenLARP scheme must build only the App Store target.";
const WORKFLOW_BLOCKER =
  "CI workflow must fail closed and execute Debug tests plus the verified Release contract.";

function textIncludesAll(text, values) {
  return values.every((value) => text.includes(value));
}

function normalizedShell(script) {
  return script
    .replace(/\\\r?\n/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function hasSuccessfulShellExit(script) {
  return script.split(/\r?\n/).some((line) => {
    const code = line.trim().replace(/\s+#.*$/, "");
    return /(?:^|;\s*|\bthen\s+)(?:exit|return)(?:\s+0)?(?=\s*(?:;|&&|\|\||$))/.test(code);
  });
}

function hasCanonicalShellContract(script, firstExecutableLinePattern) {
  if (typeof script !== "string") {
    return false;
  }
  const executableLines = script
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));
  if (!executableLines.length ||
      !firstExecutableLinePattern.test(executableLines[0])) {
    return false;
  }

  return !hasSuccessfulShellExit(executableLines.join("\n"));
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

function parseYaml(text) {
  try {
    const value = parse(text);
    return value && typeof value === "object" ? value : null;
  } catch {
    return null;
  }
}

function isExactArray(value, expected) {
  return Array.isArray(value) &&
    value.length === expected.length &&
    value.every((item, index) => item === expected[index]);
}

function hasXmlAttribute(text, name, value) {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedValue = value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`\\b${escapedName}\\s*=\\s*"${escapedValue}"`).test(text);
}

function validateGeneratedPublicScheme(text) {
  if (typeof text !== "string" || !text) {
    return false;
  }

  const entries = text.match(/<BuildActionEntry\b[\s\S]*?<\/BuildActionEntry>/g) ?? [];
  if (entries.length !== 1 ||
      !hasXmlAttribute(text, "buildImplicitDependencies", "NO")) {
    return false;
  }

  const entry = entries[0];
  return hasXmlAttribute(entry, "buildForTesting", "YES") &&
    hasXmlAttribute(entry, "buildForRunning", "YES") &&
    hasXmlAttribute(entry, "buildForProfiling", "YES") &&
    hasXmlAttribute(entry, "buildForArchiving", "YES") &&
    hasXmlAttribute(entry, "buildForAnalyzing", "YES") &&
    hasXmlAttribute(entry, "BuildableName", "OpenLARP.app") &&
    hasXmlAttribute(entry, "BlueprintName", "OpenLARP");
}

function dependenciesInclude(dependencies, expected) {
  return Array.isArray(dependencies) && dependencies.some((dependency) =>
    dependency && typeof dependency === "object" &&
    Object.entries(expected).every(([key, value]) => dependency[key] === value)
  );
}

function sourceDefinition(target, path) {
  return Array.isArray(target?.sources)
    ? target.sources.find((source) => source?.path === path)
    : null;
}

function sourceExcludes(target, path, excludedPath) {
  const source = sourceDefinition(target, path);
  return Array.isArray(source?.excludes) && source.excludes.includes(excludedPath);
}

function hasEmptyPlistArray(text, key) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`<key>\\s*${escapedKey}\\s*</key>\\s*<array\\s*/>`, "m").test(text);
}

function hasFalsePlistBoolean(text, key) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`<key>\\s*${escapedKey}\\s*</key>\\s*<false\\s*/>`, "m").test(text);
}

function hasInternalOnlyCopyScript(scriptDefinition, fileName) {
  if (!scriptDefinition || typeof scriptDefinition !== "object") {
    return false;
  }
  const script = scriptDefinition.script;
  if (typeof script !== "string") {
    return false;
  }

  const guard = 'if [ "${OPENLARP_RELEASE_CHANNEL}" != "internal-beta" ]; then';
  const guardIndex = script.indexOf(guard);
  const exitIndex = script.indexOf("exit 0", guardIndex);
  const copyIndex = script.indexOf('cp "$CONFIG_FILE" "$TARGET_FILE"');
  const staleRemovalOffsets = [
    ...script.matchAll(/rm -f "\$TARGET_FILE"/g)
  ].map((match) => match.index);
  const removesBeforePublicExit = staleRemovalOffsets.some((offset) =>
    offset > guardIndex && offset < exitIndex
  );
  const hasNoEarlySuccessfulExit = exitIndex >= 0 &&
    !hasSuccessfulShellExit(script.slice(0, exitIndex));

  return scriptDefinition.name === `Copy Local ${fileName === "GoogleService-Info.plist" ? "Firebase" : "RevenueCat"} Configuration` &&
    script.includes(`/OpenLARP/${fileName}`) &&
    script.includes(`.app/${fileName}`) &&
    guardIndex >= 0 &&
    exitIndex > guardIndex &&
    copyIndex > exitIndex &&
    staleRemovalOffsets.length >= 2 &&
    removesBeforePublicExit &&
    hasNoEarlySuccessfulExit;
}

function validateProjectDefinition(project) {
  const appTarget = project?.targets?.OpenLARP;
  const internalTarget = project?.targets?.OpenLARPInternal;
  const appSettings = appTarget?.settings;
  const internalSettings = internalTarget?.settings;

  const expectedInternalDependencies = [
    ["Firebase", "FirebaseCore"],
    ["Firebase", "FirebaseAuth"],
    ["Firebase", "FirebaseFirestore"],
    ["Firebase", "FirebaseStorage"],
    ["Firebase", "FirebaseFunctions"],
    ["Firebase", "FirebaseAppCheck"],
    ["GoogleSignIn", "GoogleSignIn"],
    ["GoogleSignIn", "GoogleSignInSwift"],
    ["RevenueCat", "RevenueCat"]
  ];

  const baseConfigurationValid =
    project?.packages?.Firebase &&
    project?.packages?.GoogleSignIn &&
    project?.packages?.RevenueCat &&
    internalTarget?.type === "application" &&
    expectedInternalDependencies.every(([packageName, product]) =>
      dependenciesInclude(internalTarget?.dependencies, {
        package: packageName,
        product
      })
    );

  const publicInfoProperties = appTarget?.info?.properties;
  const publicBaseSettings = appSettings?.base;
  const publicConditions = publicBaseSettings?.SWIFT_ACTIVE_COMPILATION_CONDITIONS;
  const internalInfoProperties = internalTarget?.info?.properties;
  const internalBaseSettings = internalSettings?.base;
  const internalConditions = internalBaseSettings?.SWIFT_ACTIVE_COMPILATION_CONDITIONS;
  const internalURLTypes = internalInfoProperties?.CFBundleURLTypes;
  const internalConfigurationValid =
    internalBaseSettings?.PRODUCT_BUNDLE_IDENTIFIER === "com.openlarp.app.internal" &&
    internalBaseSettings?.PRODUCT_NAME === "OpenLARPInternal" &&
    internalBaseSettings?.PRODUCT_MODULE_NAME === "OpenLARP" &&
    internalBaseSettings?.CODE_SIGN_ENTITLEMENTS ===
      "OpenLARPInternal/OpenLARPInternal.entitlements" &&
    typeof internalConditions === "string" &&
    internalConditions.includes("OPENLARP_INTERNAL_SERVICES") &&
    sourceDefinition(internalTarget, "OpenLARPInternal") !== null &&
    sourceExcludes(internalTarget, "OpenLARP", "PrivacyInfo.xcprivacy") &&
    sourceExcludes(internalTarget, "OpenLARP", "Info.plist") &&
    Array.isArray(internalURLTypes) &&
    internalURLTypes.length === 1 &&
    internalURLTypes[0]?.CFBundleURLName === "Google Sign-In" &&
    isExactArray(
      internalURLTypes[0]?.CFBundleURLSchemes,
      ["$(GOOGLE_REVERSED_CLIENT_ID)"]
    );
  const publicTargetBoundaryValid =
    appTarget?.type === "application" &&
    appSettings?.base?.PRODUCT_BUNDLE_IDENTIFIER === "com.openlarp.app" &&
    appSettings?.base?.PRODUCT_NAME === "OpenLARP" &&
    appSettings?.base?.PRODUCT_MODULE_NAME === "OpenLARP" &&
    Array.isArray(appTarget?.dependencies) &&
    appTarget.dependencies.length === 0 &&
    sourceDefinition(appTarget, "OpenLARP") !== null &&
    sourceExcludes(appTarget, "OpenLARP", "GoogleService-Info.plist") &&
    sourceExcludes(appTarget, "OpenLARP", "RevenueCat-Info.plist") &&
    sourceExcludes(
      appTarget,
      "OpenLARP",
      "Models/OpenLARPRevenueCatSubscriptionService.swift"
    ) &&
    !Object.hasOwn(publicInfoProperties ?? {}, "CFBundleURLTypes") &&
    !Object.hasOwn(publicBaseSettings ?? {}, "CODE_SIGN_ENTITLEMENTS") &&
    !(typeof publicConditions === "string" &&
      publicConditions.includes("OPENLARP_INTERNAL_SERVICES")) &&
    (!Array.isArray(appTarget?.postBuildScripts) || appTarget.postBuildScripts.length === 0);

  const channelsValid =
    appTarget?.info?.properties?.OpenLARPReleaseChannel === "$(OPENLARP_RELEASE_CHANNEL)" &&
    appSettings?.configs?.Debug?.OPENLARP_RELEASE_CHANNEL === "app-store" &&
    appSettings?.configs?.Release?.OPENLARP_RELEASE_CHANNEL === "app-store" &&
    internalTarget?.info?.properties?.OpenLARPReleaseChannel === "$(OPENLARP_RELEASE_CHANNEL)" &&
    internalSettings?.configs?.Debug?.OPENLARP_RELEASE_CHANNEL === "internal-beta" &&
    internalSettings?.configs?.Release?.OPENLARP_RELEASE_CHANNEL === "internal-beta";

  const copyScripts = internalTarget?.postBuildScripts;
  const firebaseScripts = Array.isArray(copyScripts)
    ? copyScripts.filter((script) => script?.name === "Copy Local Firebase Configuration")
    : [];
  const revenueCatScripts = Array.isArray(copyScripts)
    ? copyScripts.filter((script) => script?.name === "Copy Local RevenueCat Configuration")
    : [];
  const serviceCopiesValid =
    firebaseScripts.length === 1 &&
    revenueCatScripts.length === 1 &&
    hasInternalOnlyCopyScript(firebaseScripts[0], "GoogleService-Info.plist") &&
    hasInternalOnlyCopyScript(revenueCatScripts[0], "RevenueCat-Info.plist");

  const contractTarget = project?.targets?.OpenLARPReleaseContractTests;
  const publicScheme = project?.schemes?.OpenLARP;
  const publicSchemeBuildTargets = publicScheme?.build?.targets;
  const publicSchemeValid =
    publicScheme?.management?.shared === true &&
    publicScheme?.build?.buildImplicitDependencies === false &&
    publicSchemeBuildTargets &&
    isExactArray(Object.keys(publicSchemeBuildTargets), ["OpenLARP"]) &&
    publicSchemeBuildTargets.OpenLARP === "all" &&
    publicScheme?.run?.config === "Debug" &&
    publicScheme?.profile?.config === "Release" &&
    publicScheme?.archive?.config === "Release";
  const contractScheme = project?.schemes?.OpenLARPReleaseContract;
  const buildTargets = contractScheme?.build?.targets;
  const contractValid =
    isExactArray(internalTarget?.scheme?.testTargets, ["OpenLARPTests"]) &&
    Array.isArray(project?.targets?.OpenLARPTests?.dependencies) &&
    project.targets.OpenLARPTests.dependencies.length === 1 &&
    dependenciesInclude(project.targets.OpenLARPTests.dependencies, {
      target: "OpenLARPInternal"
    }) &&
    contractTarget?.type === "bundle.unit-test" &&
    contractTarget?.platform === "iOS" &&
    isExactArray(contractTarget?.sources, ["OpenLARPReleaseContractTests"]) &&
    Array.isArray(contractTarget?.dependencies) &&
    contractTarget.dependencies.length === 1 &&
    dependenciesInclude(contractTarget.dependencies, { target: "OpenLARP" }) &&
    contractTarget?.settings?.base?.PRODUCT_BUNDLE_IDENTIFIER ===
      "com.openlarp.release-contract-tests" &&
    contractTarget?.settings?.base?.GENERATE_INFOPLIST_FILE === "YES" &&
    contractScheme?.management?.shared === true &&
    contractScheme?.build?.buildImplicitDependencies === false &&
    buildTargets &&
    isExactArray(Object.keys(buildTargets).sort(), ["OpenLARP", "OpenLARPReleaseContractTests"]) &&
    isExactArray(buildTargets.OpenLARP, ["test"]) &&
    isExactArray(buildTargets.OpenLARPReleaseContractTests, ["test"]) &&
    contractScheme?.test?.config === "Release" &&
    isExactArray(contractScheme?.test?.targets, ["OpenLARPReleaseContractTests"]);

  return {
    baseConfigurationValid: baseConfigurationValid && internalConfigurationValid,
    publicTargetBoundaryValid,
    channelsValid,
    serviceCopiesValid,
    publicSchemeValid,
    contractValid
  };
}

function uniqueRequiredStep(steps, name) {
  if (!Array.isArray(steps)) {
    return null;
  }
  const matches = steps.filter((step) => step?.name === name);
  if (matches.length !== 1) {
    return null;
  }
  const step = matches[0];
  if (Object.hasOwn(step, "if") || Object.hasOwn(step, "continue-on-error")) {
    return null;
  }
  return typeof step.run === "string" ? step : null;
}

function validateWorkflowDefinition(workflow) {
  const job = workflow?.jobs?.["build-and-test"];
  const steps = job?.steps;
  if (!Array.isArray(steps)) {
    return false;
  }
  if (Object.hasOwn(job, "if") || Object.hasOwn(job, "continue-on-error")) {
    return false;
  }

  const serializedWorkflow = JSON.stringify(workflow).toLowerCase();
  if (serializedWorkflow.includes("has_simulator") ||
      serializedWorkflow.includes("will be skipped") ||
      serializedWorkflow.includes("skipped simulator")) {
    return false;
  }

  const publicSafety = uniqueRequiredStep(steps, "Check public repo safety");
  const betaGate = uniqueRequiredStep(steps, "Check beta release gate");
  const backendTests = uniqueRequiredStep(steps, "Test Genkit backend");
  const backendBuild = uniqueRequiredStep(steps, "Build Firebase Functions backend");
  const rulesTests = uniqueRequiredStep(steps, "Test Firebase security rules");
  const projectGeneration = uniqueRequiredStep(steps, "Generate Xcode project");
  const simulator = uniqueRequiredStep(steps, "Select available iPhone simulator");
  const unsignedBuild = uniqueRequiredStep(steps, "Build unsigned iOS app");
  const debugTests = uniqueRequiredStep(steps, "Run Debug simulator tests");
  const releaseContract = uniqueRequiredStep(
    steps,
    "Run optimized App Store Release contract"
  );

  if (!publicSafety || !betaGate || !backendTests || !backendBuild || !rulesTests ||
      !projectGeneration || !simulator || !unsignedBuild || !debugTests ||
      !releaseContract) {
    return false;
  }

  const projectGenerationIndex = steps.indexOf(projectGeneration);
  const simulatorIndex = steps.indexOf(simulator);
  const unsignedBuildIndex = steps.indexOf(unsignedBuild);
  const debugTestsIndex = steps.indexOf(debugTests);
  const releaseContractIndex = steps.indexOf(releaseContract);
  const requiredStepOrderValid =
    projectGenerationIndex < unsignedBuildIndex &&
    projectGenerationIndex < debugTestsIndex &&
    projectGenerationIndex < releaseContractIndex &&
    simulatorIndex < debugTestsIndex &&
    simulatorIndex < releaseContractIndex;

  const simulatorRun = simulator.run;
  const simulatorFailsClosed =
    hasCanonicalShellContract(simulatorRun, /^DEVICE_ID="\$\(/) &&
    simulator.id === "simulator" &&
    simulatorRun.includes("subprocess.TimeoutExpired") &&
    simulatorRun.includes("sys.exit(1)") &&
    simulatorRun.includes("sys.exit(result.returncode or 1)") &&
    simulatorRun.includes('if [ -z "$DEVICE_ID" ]; then') &&
    simulatorRun.includes("exit 1") &&
    simulatorRun.includes('device_id=$DEVICE_ID') &&
    !simulatorRun.includes("has_simulator") &&
    !simulatorRun.includes("will be skipped");

  const unsignedBuildScript = unsignedBuild.run;
  const unsignedBuildRun = normalizedShell(unsignedBuildScript);
  const unsignedReleaseBuild =
    hasCanonicalShellContract(unsignedBuildScript, /^xcodebuild(?:\s|$)/) &&
    textIncludesAll(unsignedBuildRun, [
    "-project OpenLARP.xcodeproj",
    "-scheme OpenLARP",
    "-configuration Release",
    "-destination generic/platform=iOS",
    "CODE_SIGNING_ALLOWED=NO",
    "build"
    ]);

  const debugScript = debugTests.run;
  const debugRun = normalizedShell(debugScript);
  const debugSuite =
    hasCanonicalShellContract(debugScript, /^set -euo pipefail$/) &&
    textIncludesAll(debugRun, [
    "set -euo pipefail",
    "-project OpenLARP.xcodeproj",
    "-scheme OpenLARPInternal",
    "-configuration Debug",
    "steps.simulator.outputs.device_id",
    "OpenLARPDebug-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.xcresult",
    '-resultBundlePath "$DEBUG_RESULT_BUNDLE"',
    'xcrun xcresulttool get test-results summary --path "$DEBUG_RESULT_BUNDLE"',
    'summary.get("totalTestCount")',
    'summary.get("passedTests")',
    'summary.get("failedTests")',
    'summary.get("skippedTests")',
    "total <= 0",
    "passed != total",
    "failed != 0",
    "skipped != 0",
    "sys.exit(1)",
    "test"
    ]);

  const contractRun = releaseContract.run;
  const normalizedContractRun = normalizedShell(contractRun);
  const releaseContractVerified =
    hasCanonicalShellContract(contractRun, /^set -euo pipefail$/) &&
    textIncludesAll(normalizedContractRun, [
    "set -euo pipefail",
    "-target OpenLARP -configuration Release -showBuildSettings",
    '[ "$ENABLE_TESTABILITY" != "NO" ]',
    "-scheme OpenLARPReleaseContract -configuration Release",
    "steps.simulator.outputs.device_id",
    "OpenLARPReleaseContract-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.xcresult",
    '-resultBundlePath "$RESULT_BUNDLE"',
    "-only-testing:OpenLARPReleaseContractTests/OpenLARPReleaseContractTests/testAppStoreReleaseContract",
    "xcrun xcresulttool get test-results summary",
    '"totalTestCount": 1',
    '"passedTests": 1',
    '"failedTests": 0',
    '"skippedTests": 0',
    "actual != expected",
    "sys.exit(1)"
    ]) && !contractRun.includes("rm -rf");

  const requiredCommandsValid =
    publicSafety.run.trim() === "npm run public:safety" &&
    betaGate.run.trim() === "npm run beta:gate" &&
    backendTests.run.trim() === "npm run test:backend" &&
    backendBuild.run.trim() === "npm run build:backend" &&
    rulesTests.run.trim() === "npm run test:rules:emulators" &&
    projectGeneration.run.trim() === "xcodegen generate";

  const hasSkipStep = steps.some((step) =>
    typeof step?.name === "string" && step.name.toLowerCase().includes("skipped simulator")
  );

  return requiredCommandsValid && simulatorFailsClosed && unsignedReleaseBuild &&
    debugSuite && releaseContractVerified && requiredStepOrderValid && !hasSkipStep;
}

export function evaluateBetaReleaseGate(readText = readTrackedText, fileExists = existsSync) {
  const results = [];
  const generatedPublicSchemeValid = validateGeneratedPublicScheme(
    readText("OpenLARP.xcodeproj/xcshareddata/xcschemes/OpenLARP.xcscheme")
  );

  for (const path of REQUIRED_FILES) {
    if (fileExists(path)) {
      addResult(results, "pass", `Required file exists: ${path}`);
    } else {
      addResult(results, "blocker", `Missing required beta readiness file: ${path}`);
    }
  }

  const appIconDirectory =
    "OpenLARP/Resources/Assets.xcassets/AppIcon.appiconset";
  const appIconContents = readText(`${appIconDirectory}/Contents.json`);
  let hasReferencedAppStoreIcon = false;
  try {
    const catalog = JSON.parse(appIconContents);
    hasReferencedAppStoreIcon = Array.isArray(catalog?.images) &&
      catalog.images.some((image) =>
        image?.size === "1024x1024" &&
        typeof image?.filename === "string" &&
        image.filename.trim().length > 0 &&
        fileExists(`${appIconDirectory}/${image.filename}`)
      );
  } catch {
    hasReferencedAppStoreIcon = false;
  }
  if (hasReferencedAppStoreIcon) {
    addResult(results, "pass", "A referenced 1024x1024 App Store icon file is present.");
  } else {
    addResult(
      results,
      "warn",
      "A referenced 1024x1024 App Store icon file is still required before submission."
    );
  }

  const privacyManifest = readText("OpenLARP/PrivacyInfo.xcprivacy");
  if (privacyManifest) {
    const publicPrivacyValid =
      hasFalsePlistBoolean(privacyManifest, "NSPrivacyTracking") &&
      hasEmptyPlistArray(privacyManifest, "NSPrivacyTrackingDomains") &&
      hasEmptyPlistArray(privacyManifest, "NSPrivacyCollectedDataTypes") &&
      hasEmptyPlistArray(privacyManifest, "NSPrivacyAccessedAPITypes");
    if (publicPrivacyValid) {
      addResult(results, "pass", "The App Store privacy manifest declares no tracking or collected data.");
    } else {
      addResult(results, "blocker", PUBLIC_PRIVACY_BLOCKER);
    }
  }

  const internalPrivacyManifest = readText("OpenLARPInternal/PrivacyInfo.xcprivacy");
  if (internalPrivacyManifest) {
    if (hasFalsePlistBoolean(internalPrivacyManifest, "NSPrivacyTracking") &&
        textIncludesAll(internalPrivacyManifest, REQUIRED_INTERNAL_PRIVACY_DATA_TYPES)) {
      addResult(results, "pass", "The internal privacy manifest covers current service data categories without tracking.");
    } else {
      addResult(results, "blocker", "Internal privacy manifest is missing one or more required service data categories.");
    }
  }

  const projectText = readText("project.yml");
  if (projectText) {
    const project = parseYaml(projectText);
    if (!project) {
      addResult(results, "blocker", "project.yml is not valid YAML.");
      addResult(results, "blocker", RELEASE_CHANNEL_BLOCKER);
      addResult(results, "blocker", SERVICE_COPY_BLOCKER);
      addResult(results, "blocker", PUBLIC_SCHEME_BLOCKER);
      addResult(results, "blocker", PROJECT_CONTRACT_BLOCKER);
    } else {
      const validation = validateProjectDefinition(project);
      if (validation.baseConfigurationValid) {
        addResult(results, "pass", "Internal service package wiring and auth configuration are declared in project.yml.");
      } else {
        addResult(results, "blocker", "project.yml is missing required internal service package or auth wiring.");
      }

      if (validation.publicTargetBoundaryValid) {
        addResult(results, "pass", "The App Store target has no service SDK, auth URL, entitlement, or config-copy wiring.");
      } else {
        addResult(results, "blocker", PUBLIC_TARGET_BOUNDARY_BLOCKER);
      }

      if (validation.channelsValid) {
        addResult(results, "pass", "Debug and Release builds declare explicit release channels.");
      } else {
        addResult(results, "blocker", RELEASE_CHANNEL_BLOCKER);
      }

      if (validation.serviceCopiesValid) {
        addResult(results, "pass", "Local service plists are copied only into internal-beta builds.");
      } else {
        addResult(results, "blocker", SERVICE_COPY_BLOCKER);
      }

      if (validation.publicSchemeValid && generatedPublicSchemeValid) {
        addResult(results, "pass", "The shared OpenLARP scheme builds only the App Store target.");
      } else {
        addResult(results, "blocker", PUBLIC_SCHEME_BLOCKER);
      }

      if (validation.contractValid) {
        addResult(results, "pass", "The isolated shared Release contract target and scheme are configured.");
      } else {
        addResult(results, "blocker", PROJECT_CONTRACT_BLOCKER);
      }
    }
  }

  const entitlements = readText("OpenLARPInternal/OpenLARPInternal.entitlements");
  if (entitlements) {
    if (textIncludesAll(entitlements, [
      "com.apple.developer.applesignin",
      "com.apple.developer.devicecheck.appattest-environment",
      "production"
    ])) {
      addResult(results, "pass", "Internal Sign in with Apple and production App Attest entitlements are declared.");
    } else {
      addResult(results, "blocker", "Apple sign-in or production App Attest entitlement is missing.");
    }
  }

  const workflowText = readText(".github/workflows/ios-ci.yml");
  if (workflowText) {
    const workflow = parseYaml(workflowText);
    if (workflow && validateWorkflowDefinition(workflow)) {
      addResult(results, "pass", "CI fails closed and verifies Debug plus the optimized App Store Release contract.");
    } else {
      addResult(results, "blocker", WORKFLOW_BLOCKER);
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
    addResult(results, "warn", "Ignored GoogleService-Info.plist is absent; separate internal-beta Firebase smoke requires local configuration.");
  }

  if (!fileExists("OpenLARP/RevenueCat-Info.plist")) {
    addResult(results, "warn", "Ignored RevenueCat-Info.plist is absent; separate internal-beta purchase smoke requires local configuration.");
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
