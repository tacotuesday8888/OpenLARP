# App Store MVP Release Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-safe App Store release profile that keeps the core sprint free and non-expiring while hiding unfinished Agent, account, cloud, subscription, and developer surfaces from public builds without deleting their implementation.

**Architecture:** A single immutable `OpenLARPReleaseConfiguration` resolves from an Info.plist build setting and exposes an explicit capability set. `OpenLARPStore`, `AppRootView`, `TodayView`, and `ProfileView` consume that configuration instead of inferring release behavior independently. Debug builds remain internal-beta builds; Release builds default to the restricted App Store MVP profile, and the repository release gate verifies that contract.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XcodeGen, Node.js 22, Vitest, existing Firebase/RevenueCat adapters retained behind gates.

## Global Constraints

- The public App Store MVP has exactly four tabs: Today, Map, Progress, and Profile.
- The App Store MVP is free and non-expiring until purchases are completely configured and verified.
- Agent, account, cloud sync, subscription, and developer tools remain available to internal builds and remain hidden in the App Store profile.
- Live AI remains disabled in both profiles during this workstream.
- Unknown or missing release-channel configuration fails closed to the App Store MVP profile.
- Public activation must not restore authentication, refresh RevenueCat, or sync backend events while those capabilities are hidden.
- Existing deterministic core behavior, Firebase/RevenueCat code, persisted subscription state, and internal tests remain intact.
- Every behavior change begins with a failing test and ends with focused and regression verification.
- No provider secret, local plist, signing material, or user data is added to Git.

---

## File Structure

### New files

- `OpenLARP/Models/OpenLARPReleaseConfiguration.swift` — release channel, access mode, capability enum, fail-safe resolver, and activation policy.
- `OpenLARPTests/ReleaseConfigurationTests.swift` — pure release-profile and access-policy tests.

### Modified files

- `project.yml` — Debug/Release channel values and generated Info.plist key.
- `OpenLARP.xcodeproj/project.pbxproj` — regenerated output from `project.yml`.
- `OpenLARP/OpenLARPApp.swift` — resolve one configuration and inject it into the Store.
- `OpenLARP/Models/OpenLARPStore.swift` — retain the configuration and bypass subscription expiry only for the free App Store profile.
- `OpenLARP/Models/OpenLARPSubscriptionContracts.swift` — expose a tested unrestricted access decision factory.
- `OpenLARP/AppRootView.swift` — four-tab public shell and capability-aware activation work.
- `OpenLARP/Views/TodayView.swift` — hide subscription and Agent surfaces publicly.
- `OpenLARP/Views/ProfileView.swift` — hide account, cloud, subscription, and developer cards publicly and use local-only privacy copy.
- `OpenLARPTests/V0EngineTests.swift` — replace the single five-tab expectation with public/internal tab expectations.
- `OpenLARPTests/SubscriptionReadinessTests.swift` — prove expired persisted state cannot block the free public profile and still blocks the internal subscription profile.
- `scripts/beta-release-gate.mjs` — block unsafe or missing App Store release-profile wiring.
- `scripts/tests/beta-release-gate.test.mjs` — exercise the new gate requirements.
- `docs/APP_STORE_TESTFLIGHT_READINESS.md` — record the public-profile behavior and remaining external gates.

---

### Task 1: Define the fail-safe release configuration

**Files:**
- Create: `OpenLARP/Models/OpenLARPReleaseConfiguration.swift`
- Create: `OpenLARPTests/ReleaseConfigurationTests.swift`
- Modify: `project.yml`
- Regenerate: `OpenLARP.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `OpenLARPReleaseChannel`, `OpenLARPReleaseAccessMode`, `OpenLARPReleaseCapability`, and `OpenLARPReleaseConfiguration`.
- Produces: `OpenLARPReleaseConfiguration.current(infoDictionary:)`, `.appStoreMVP`, `.internalBeta`, `isEnabled(_:)`, and activation-policy booleans.
- Consumed by: Tasks 2–5.

- [ ] **Step 1: Write failing release-configuration tests**

Create `OpenLARPTests/ReleaseConfigurationTests.swift`:

```swift
import XCTest
@testable import OpenLARP

final class ReleaseConfigurationTests: XCTestCase {
    func testAppStoreMVPIsFreeAndExposesNoUnfinishedCapabilities() {
        let configuration = OpenLARPReleaseConfiguration.appStoreMVP

        XCTAssertEqual(configuration.channel, .appStore)
        XCTAssertEqual(configuration.accessMode, .free)
        XCTAssertTrue(configuration.enabledCapabilities.isEmpty)
        XCTAssertFalse(configuration.runsAuthenticationLifecycle)
        XCTAssertFalse(configuration.runsSubscriptionLifecycle)
        XCTAssertFalse(configuration.runsBackendEventSync)
    }

    func testInternalBetaRetainsExistingInfrastructureWithoutLiveAI() {
        let configuration = OpenLARPReleaseConfiguration.internalBeta

        XCTAssertEqual(configuration.channel, .internalBeta)
        XCTAssertEqual(configuration.accessMode, .subscription)
        XCTAssertTrue(configuration.isEnabled(.agent))
        XCTAssertTrue(configuration.isEnabled(.account))
        XCTAssertTrue(configuration.isEnabled(.cloudSync))
        XCTAssertTrue(configuration.isEnabled(.subscriptions))
        XCTAssertTrue(configuration.isEnabled(.developerTools))
        XCTAssertFalse(configuration.isEnabled(.liveAI))
        XCTAssertTrue(configuration.runsAuthenticationLifecycle)
        XCTAssertTrue(configuration.runsSubscriptionLifecycle)
        XCTAssertTrue(configuration.runsBackendEventSync)
    }

    func testReleaseChannelResolverUsesKnownProfiles() {
        XCTAssertEqual(
            OpenLARPReleaseConfiguration.current(
                infoDictionary: [OpenLARPReleaseConfiguration.infoDictionaryKey: "app-store"]
            ),
            .appStoreMVP
        )
        XCTAssertEqual(
            OpenLARPReleaseConfiguration.current(
                infoDictionary: [OpenLARPReleaseConfiguration.infoDictionaryKey: "internal-beta"]
            ),
            .internalBeta
        )
    }

    func testMissingOrUnknownReleaseChannelFailsClosedToAppStore() {
        XCTAssertEqual(
            OpenLARPReleaseConfiguration.current(infoDictionary: [:]),
            .appStoreMVP
        )
        XCTAssertEqual(
            OpenLARPReleaseConfiguration.current(
                infoDictionary: [OpenLARPReleaseConfiguration.infoDictionaryKey: "unexpected"]
            ),
            .appStoreMVP
        )
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run after regenerating the test project only if Xcode does not yet discover the new file:

```bash
xcodegen generate
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/ReleaseConfigurationTests \
  test
```

Expected: FAIL because the release-configuration types do not exist.

- [ ] **Step 3: Add the release configuration**

Create `OpenLARP/Models/OpenLARPReleaseConfiguration.swift`:

```swift
import Foundation

enum OpenLARPReleaseChannel: String, Equatable, Sendable {
    case appStore = "app-store"
    case internalBeta = "internal-beta"
}

enum OpenLARPReleaseAccessMode: Equatable, Sendable {
    case free
    case subscription
}

enum OpenLARPReleaseCapability: String, CaseIterable, Hashable, Sendable {
    case agent
    case account
    case cloudSync
    case subscriptions
    case developerTools
    case liveAI
}

struct OpenLARPReleaseConfiguration: Equatable, Sendable {
    static let infoDictionaryKey = "OpenLARPReleaseChannel"

    let channel: OpenLARPReleaseChannel
    let accessMode: OpenLARPReleaseAccessMode
    let enabledCapabilities: Set<OpenLARPReleaseCapability>

    static let appStoreMVP = OpenLARPReleaseConfiguration(
        channel: .appStore,
        accessMode: .free,
        enabledCapabilities: []
    )

    static let internalBeta = OpenLARPReleaseConfiguration(
        channel: .internalBeta,
        accessMode: .subscription,
        enabledCapabilities: [
            .agent,
            .account,
            .cloudSync,
            .subscriptions,
            .developerTools
        ]
    )

    static func current(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> OpenLARPReleaseConfiguration {
        guard let rawChannel = infoDictionary[infoDictionaryKey] as? String,
              let channel = OpenLARPReleaseChannel(rawValue: rawChannel) else {
            return .appStoreMVP
        }

        switch channel {
        case .appStore:
            return .appStoreMVP
        case .internalBeta:
            return .internalBeta
        }
    }

    func isEnabled(_ capability: OpenLARPReleaseCapability) -> Bool {
        enabledCapabilities.contains(capability)
    }

    var runsAuthenticationLifecycle: Bool { isEnabled(.account) }
    var runsSubscriptionLifecycle: Bool { isEnabled(.subscriptions) }
    var runsBackendEventSync: Bool { isEnabled(.cloudSync) }
}
```

- [ ] **Step 4: Configure Debug and Release channels in XcodeGen**

Add the generated Info.plist property under `targets.OpenLARP.info.properties` in `project.yml`:

```yaml
        OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)
```

Add per-configuration target settings under `targets.OpenLARP.settings`:

```yaml
      configs:
        Debug:
          OPENLARP_RELEASE_CHANNEL: internal-beta
        Release:
          OPENLARP_RELEASE_CHANNEL: app-store
```

Regenerate the project:

```bash
xcodegen generate
```

Expected: `OpenLARP.xcodeproj/project.pbxproj` contains `OPENLARP_RELEASE_CHANNEL = "internal-beta"` for Debug and `OPENLARP_RELEASE_CHANNEL = "app-store"` for Release.

- [ ] **Step 5: Run the focused tests and verify they pass**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/ReleaseConfigurationTests \
  test
```

Expected: `ReleaseConfigurationTests` PASS.

- [ ] **Step 6: Commit the release configuration**

```bash
git add \
  OpenLARP/Models/OpenLARPReleaseConfiguration.swift \
  OpenLARPTests/ReleaseConfigurationTests.swift \
  project.yml \
  OpenLARP.xcodeproj/project.pbxproj
git commit -m "Add fail-safe App Store release profile"
```

---

### Task 2: Make public core access free and non-expiring

**Files:**
- Modify: `OpenLARP/Models/OpenLARPStore.swift`
- Modify: `OpenLARP/Models/OpenLARPSubscriptionContracts.swift`
- Modify: `OpenLARPTests/SubscriptionReadinessTests.swift`

**Interfaces:**
- Consumes: `OpenLARPReleaseConfiguration` from Task 1.
- Produces: `OpenLARPStore.releaseConfiguration`.
- Produces: `OpenLARPAccessGate.unrestrictedDecision(for:)`.

- [ ] **Step 1: Write failing public/internal access tests**

Add to `OpenLARPTests/SubscriptionReadinessTests.swift`:

```swift
@MainActor
func testAppStoreMVPAllowsCoreProgressAfterPersistedFreeSprintExpired() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let start = date(year: 2026, month: 6, day: 1)
    let now = date(year: 2026, month: 6, day: 20)
    let store = OpenLARPStore(
        persistence: OpenLARPPersistence(directory: directory),
        attachmentStore: OpenLARPAttachmentStore(directory: directory),
        releaseConfiguration: .appStoreMVP,
        now: { now },
        calendar: calendar
    )
    store.state = OpenLARPEngine.confirmGoal(goal, now: start)
    store.state.subscriptionState = .localFreeSprint(startedAt: start)

    store.startCurrentQuest()

    XCTAssertEqual(store.state.currentQuest?.status, .inProgress)
    XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .subscriptionPaywallViewed })
    XCTAssertNil(store.errorMessage)
}

@MainActor
func testInternalBetaStillEnforcesExpiredSubscriptionAccess() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let start = date(year: 2026, month: 6, day: 1)
    let now = date(year: 2026, month: 6, day: 20)
    let store = OpenLARPStore(
        persistence: OpenLARPPersistence(directory: directory),
        attachmentStore: OpenLARPAttachmentStore(directory: directory),
        releaseConfiguration: .internalBeta,
        now: { now },
        calendar: calendar
    )
    store.state = OpenLARPEngine.confirmGoal(goal, now: start)
    store.state.subscriptionState = .localFreeSprint(startedAt: start)

    store.startCurrentQuest()

    XCTAssertEqual(store.state.currentQuest?.status, .available)
    XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
    XCTAssertTrue(store.errorMessage?.contains("Sprint access ended") == true)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/SubscriptionReadinessTests/testAppStoreMVPAllowsCoreProgressAfterPersistedFreeSprintExpired \
  -only-testing:OpenLARPTests/SubscriptionReadinessTests/testInternalBetaStillEnforcesExpiredSubscriptionAccess \
  test
```

Expected: FAIL because `OpenLARPStore` does not accept a release configuration and the expired access gate still blocks all profiles.

- [ ] **Step 3: Expose an unrestricted access decision**

Add to `OpenLARPAccessGate` in `OpenLARP/Models/OpenLARPSubscriptionContracts.swift`:

```swift
    static func unrestrictedDecision(
        for action: OpenLARPAccessControlledAction
    ) -> OpenLARPAccessGateDecision {
        allowedDecision(action: action, accessStatus: .active)
    }
```

- [ ] **Step 4: Inject release configuration into the Store**

Add a stored property near the Store's other dependencies:

```swift
    let releaseConfiguration: OpenLARPReleaseConfiguration
```

Add an initializer argument that preserves existing internal-test behavior:

```swift
        releaseConfiguration: OpenLARPReleaseConfiguration = .internalBeta,
```

Assign it before loading state:

```swift
        self.releaseConfiguration = releaseConfiguration
```

Replace `subscriptionGateDecision(for:)` with:

```swift
    func subscriptionGateDecision(
        for action: OpenLARPAccessControlledAction
    ) -> OpenLARPAccessGateDecision {
        if releaseConfiguration.accessMode == .free {
            return OpenLARPAccessGate.unrestrictedDecision(for: action)
        }

        return OpenLARPAccessGate.decision(for: action, access: subscriptionAccess())
    }
```

Prevent public-free mode from recording a fake 14-day lifecycle in `recordFreeSprintStartedIfNeeded(at:)`:

```swift
    private func recordFreeSprintStartedIfNeeded(at timestamp: Date) {
        guard releaseConfiguration.accessMode == .subscription else { return }
        let access = state.subscriptionState.access(at: timestamp, calendar: calendar)
        guard access.status == .freeSprint else { return }
        guard !state.betaEvents.contains(where: { $0.kind == .freeSprintStarted }) else { return }

        recordBetaEvent(
            .freeSprintStarted,
            occurredAt: state.subscriptionState.freeSprint?.startedAt ?? timestamp
        )
    }
```

- [ ] **Step 5: Run subscription tests**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/SubscriptionReadinessTests \
  test
```

Expected: all `SubscriptionReadinessTests` PASS, including the existing internal subscription lifecycle tests.

- [ ] **Step 6: Commit the access policy**

```bash
git add \
  OpenLARP/Models/OpenLARPStore.swift \
  OpenLARP/Models/OpenLARPSubscriptionContracts.swift \
  OpenLARPTests/SubscriptionReadinessTests.swift
git commit -m "Keep App Store MVP access free"
```

---

### Task 3: Gate public navigation, Agent UI, and activation work

**Files:**
- Modify: `OpenLARP/OpenLARPApp.swift`
- Modify: `OpenLARP/AppRootView.swift`
- Modify: `OpenLARP/Views/TodayView.swift`
- Modify: `OpenLARPTests/V0EngineTests.swift`
- Modify: `OpenLARPTests/ReleaseConfigurationTests.swift`

**Interfaces:**
- Consumes: `OpenLARPStore.releaseConfiguration` from Task 2.
- Produces: `AppTab.visibleTabs(for:)`.
- Produces: capability-aware app activation and tab-change work.

- [ ] **Step 1: Write failing tab-surface tests**

Replace the existing `testAppTabsMatchProductSurfaces` in `OpenLARPTests/V0EngineTests.swift` with:

```swift
func testAppTabsMatchInternalAndPublicProductSurfaces() {
    XCTAssertEqual(
        AppTab.allCases.map(\.title),
        ["Today", "Map", "Progress", "Agent", "Profile"]
    )
    XCTAssertEqual(
        AppTab.visibleTabs(for: .appStoreMVP).map(\.title),
        ["Today", "Map", "Progress", "Profile"]
    )
    XCTAssertEqual(
        AppTab.visibleTabs(for: .internalBeta).map(\.title),
        ["Today", "Map", "Progress", "Agent", "Profile"]
    )
}
```

Add to `ReleaseConfigurationTests.swift`:

```swift
func testAppStoreActivationDoesNotRunHiddenServiceLifecycles() {
    let configuration = OpenLARPReleaseConfiguration.appStoreMVP

    XCTAssertFalse(configuration.runsAuthenticationLifecycle)
    XCTAssertFalse(configuration.runsSubscriptionLifecycle)
    XCTAssertFalse(configuration.runsBackendEventSync)
}

func testPublicRootAndTodayConsumeReleaseGates() throws {
    let rootView = try source("OpenLARP/AppRootView.swift")
    let todayView = try source("OpenLARP/Views/TodayView.swift")

    XCTAssertTrue(rootView.contains("releaseConfiguration.isEnabled(.agent)"))
    XCTAssertTrue(todayView.contains("releaseConfiguration.isEnabled(.subscriptions)"))
    XCTAssertTrue(todayView.contains("releaseConfiguration.isEnabled(.agent)"))
}

private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repositoryRoot.appendingPathComponent(relativePath),
        encoding: .utf8
    )
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/V0EngineTests/testAppTabsMatchInternalAndPublicProductSurfaces \
  -only-testing:OpenLARPTests/ReleaseConfigurationTests/testPublicRootAndTodayConsumeReleaseGates \
  test
```

Expected: FAIL because `AppTab.visibleTabs(for:)` does not exist and the public views do not yet consume the release gates.

- [ ] **Step 3: Resolve and inject one app configuration**

Update `OpenLARP/OpenLARPApp.swift` so its initializer starts with:

```swift
    init() {
        let releaseConfiguration = OpenLARPReleaseConfiguration.current()
        OpenLARPFirebaseBootstrap.configureIfAvailable()
        let attachmentStore = OpenLARPAttachmentStore.live
```

Pass it to `OpenLARPStore`:

```swift
                releaseConfiguration: releaseConfiguration,
```

- [ ] **Step 4: Add visible-tab policy and conditionally build the Agent tab**

Add to `AppTab` in `OpenLARP/AppRootView.swift`:

```swift
    static func visibleTabs(
        for configuration: OpenLARPReleaseConfiguration
    ) -> [AppTab] {
        allCases.filter { tab in
            tab != .agent || configuration.isEnabled(.agent)
        }
    }
```

Wrap the Agent tab in `AppRootView.body`:

```swift
            if store.releaseConfiguration.isEnabled(.agent) {
                NavigationStack {
                    AgentDashboardView(store: store)
                }
                .tabItem {
                    Label(AppTab.agent.title, systemImage: AppTab.agent.systemImage)
                }
                .tag(AppTab.agent)
            }
```

- [ ] **Step 5: Gate service activation and background refresh**

Replace repeated lifecycle tasks in `AppRootView` with:

```swift
        .onAppear {
            refreshForActiveState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshForActiveState()
        }
        .onChange(of: selectedTab) {
            store.refreshDailyAvailability()
            guard store.releaseConfiguration.runsBackendEventSync else { return }
            Task { await store.syncBackendEvents() }
        }
```

Add inside `AppRootView`:

```swift
    private func refreshForActiveState() {
        store.refreshDailyAvailability()
        let configuration = store.releaseConfiguration

        Task {
            if configuration.runsAuthenticationLifecycle {
                await store.restorePreviousAuthenticationSession()
            }
            if configuration.runsSubscriptionLifecycle {
                await store.refreshSubscriptionStatus()
            }
            if configuration.runsBackendEventSync {
                await store.syncBackendEvents()
            }
        }
    }
```

- [ ] **Step 6: Hide subscription and Agent cards from public Today**

In `OpenLARP/Views/TodayView.swift`, replace the unconditional block after `header` with:

```swift
                    header
                    if store.releaseConfiguration.isEnabled(.subscriptions) {
                        subscriptionAccessCard
                    }
                    questCard
                    diagnosticCard
                    progressStrip
                    if store.releaseConfiguration.isEnabled(.agent) {
                        dailyAgentBrief
                        Button {
                            showingAgent = true
                        } label: {
                            Label("Ask Agent about this quest", systemImage: "sparkles")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    logOutcomeAction
```

- [ ] **Step 7: Run focused tests and compile the app**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/V0EngineTests/testAppTabsMatchInternalAndPublicProductSurfaces \
  -only-testing:OpenLARPTests/ReleaseConfigurationTests \
  test

xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/OpenLARPDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: focused tests PASS and `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit the public app shell**

```bash
git add \
  OpenLARP/OpenLARPApp.swift \
  OpenLARP/AppRootView.swift \
  OpenLARP/Views/TodayView.swift \
  OpenLARPTests/V0EngineTests.swift \
  OpenLARPTests/ReleaseConfigurationTests.swift
git commit -m "Gate unfinished public app surfaces"
```

---

### Task 4: Gate Profile infrastructure and use truthful local-only copy

**Files:**
- Modify: `OpenLARP/Views/ProfileView.swift`
- Modify: `OpenLARPTests/ReleaseConfigurationTests.swift`

**Interfaces:**
- Consumes: release capabilities from Task 1.
- Produces: public Profile containing only user-facing local product controls.

- [ ] **Step 1: Add a failing Profile source-integration test**

Add to `OpenLARPTests/ReleaseConfigurationTests.swift`:

```swift
func testPublicProfileConsumesEveryInfrastructureGate() throws {
    let profileView = try source("OpenLARP/Views/ProfileView.swift")

    XCTAssertTrue(profileView.contains("releaseConfiguration.isEnabled(.account)"))
    XCTAssertTrue(profileView.contains("releaseConfiguration.isEnabled(.cloudSync)"))
    XCTAssertTrue(profileView.contains("releaseConfiguration.isEnabled(.subscriptions)"))
    XCTAssertTrue(profileView.contains("releaseConfiguration.isEnabled(.developerTools)"))
}
```

- [ ] **Step 2: Run the focused test before changing Profile**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/ReleaseConfigurationTests/testPublicProfileConsumesEveryInfrastructureGate \
  test
```

Expected: FAIL because `ProfileView` still renders account, cloud, subscription, and developer cards unconditionally.

- [ ] **Step 3: Gate Profile cards at their composition point**

Change the beginning of `ProfileView.body` to render capabilities explicitly:

```swift
                careerSummaryCard
                if store.releaseConfiguration.isEnabled(.account) {
                    accountProfileCard
                    accountDataControlsCard
                }
                if store.releaseConfiguration.isEnabled(.subscriptions) {
                    subscriptionStatusCard
                }
                if store.releaseConfiguration.isEnabled(.cloudSync) {
                    careerGraphSetupStatusCard
                }
                if store.releaseConfiguration.isEnabled(.developerTools) {
                    betaMeasurementCard
                }
                activeGoalCard
                recentOutcomesCard
                streakCard
                privacyCard
                badgeCard
                proofCard
                rulesCard
```

- [ ] **Step 4: Make privacy controls local-only when cloud is hidden**

Inside `privacyCard`, keep the memory and sharing toggles, then gate the cloud control:

```swift
                    if store.releaseConfiguration.isEnabled(.cloudSync) {
                        PrivacyToggleRow(
                            title: "Private evidence cloud sync",
                            detail: "Allow future proof, files, links, and private notes in account backup.",
                            isOn: privateEvidenceCloudSyncBinding
                        )
                        .disabled(store.isUpdatingPrivateEvidenceCloudSyncConsent)

                        Text("Turning this off stops future private evidence sync. Removing already synced proof backups is a separate cleanup request and is not full account deletion.")
                            .font(.caption)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Career context and proof stay on this device in this release.", systemImage: "iphone.and.arrow.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(memoryEnabled
                        ? "Local career context is available on this device."
                        : "Local career context is off.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
```

- [ ] **Step 5: Remove future-Agent wording from public guardrails**

Replace the final label in `rulesCard` with provider-independent copy:

```swift
                Label("OpenLARP suggests next steps. You approve every external action.", systemImage: "hand.tap")
```

- [ ] **Step 6: Compile and run release-configuration tests**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  -only-testing:OpenLARPTests/ReleaseConfigurationTests \
  test

xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/OpenLARPDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: tests PASS and `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit Profile gating**

```bash
git add OpenLARP/Views/ProfileView.swift OpenLARPTests/ReleaseConfigurationTests.swift
git commit -m "Hide internal infrastructure from public Profile"
```

---

### Task 5: Make the repository gate enforce the App Store profile

**Files:**
- Modify: `scripts/beta-release-gate.mjs`
- Modify: `scripts/tests/beta-release-gate.test.mjs`

**Interfaces:**
- Consumes: release configuration and project markers from Tasks 1–4.
- Produces: blocking CI results when the public profile is missing, paid, or exposes unfinished capabilities.

- [ ] **Step 1: Extend the gate fixture and write failing gate tests**

Add these entries to `completeFiles` in `scripts/tests/beta-release-gate.test.mjs`:

```javascript
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
```

Extend the existing `project.yml` fixture text with:

```javascript
    "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)",
    "OPENLARP_RELEASE_CHANNEL: internal-beta",
    "OPENLARP_RELEASE_CHANNEL: app-store"
```

Add two tests:

```javascript
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
```

- [ ] **Step 2: Run script tests and verify they fail**

```bash
npm run test:scripts
```

Expected: FAIL because `evaluateBetaReleaseGate` does not enforce the new profile or surface markers.

- [ ] **Step 3: Add release-profile files and checks to the gate**

Add the configuration file to `REQUIRED_FILES`:

```javascript
  "OpenLARP/Models/OpenLARPReleaseConfiguration.swift",
```

After the existing project checks, add:

```javascript
    if (textIncludesAll(project, [
      "OpenLARPReleaseChannel: $(OPENLARP_RELEASE_CHANNEL)",
      "OPENLARP_RELEASE_CHANNEL: internal-beta",
      "OPENLARP_RELEASE_CHANNEL: app-store"
    ])) {
      addResult(results, "pass", "Debug and Release builds declare explicit release channels.");
    } else {
      addResult(results, "blocker", "Debug or Release build channel configuration is missing.");
    }
```

Add release-profile validation:

```javascript
  const releaseConfiguration = readText("OpenLARP/Models/OpenLARPReleaseConfiguration.swift");
  if (textIncludesAll(releaseConfiguration, [
    "static let appStoreMVP",
    "accessMode: .free",
    "enabledCapabilities: []",
    "return .appStoreMVP"
  ])) {
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
```

- [ ] **Step 4: Run script tests and the real gate**

```bash
npm run test:scripts
npm run beta:gate
```

Expected: all script tests PASS; the real gate has no repo-controlled blocker. Existing warnings for external privacy/support and ignored local service configuration may remain.

- [ ] **Step 5: Commit the repository gate**

```bash
git add scripts/beta-release-gate.mjs scripts/tests/beta-release-gate.test.mjs
git commit -m "Enforce public release profile in CI gate"
```

---

### Task 6: Document and verify the complete workstream

**Files:**
- Modify: `docs/APP_STORE_TESTFLIGHT_READINESS.md`
- Verify: all files changed in Tasks 1–5

**Interfaces:**
- Consumes: the complete release-profile implementation.
- Produces: verified public-profile readiness evidence and a clean handoff to identity-safe persistence work.

- [ ] **Step 1: Update the launch packet with exact release-profile status**

Add a section near the current baseline in `docs/APP_STORE_TESTFLIGHT_READINESS.md`:

```markdown
## App Store MVP Release Profile

- Release builds resolve to the fail-safe `app-store` profile.
- The public profile is free and non-expiring.
- Public navigation contains Today, Map, Progress, and Profile.
- Agent, account, cloud-sync, subscription, and developer infrastructure remains internal-only.
- Debug builds retain the `internal-beta` profile for continued development and verification.
- Live AI remains disabled pending provider, safety, evaluation, observability, and audience-terms approval.
```

- [ ] **Step 2: Run formatting and repository gates**

```bash
git diff --check
npm run public:safety
npm run test:scripts
npm run beta:gate
```

Expected: all commands exit 0. `beta:gate` may report only documented external-setup warnings.

- [ ] **Step 3: Run the full iOS test suite**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/OpenLARPReleaseProfileTests \
  test
```

Expected: `TEST SUCCEEDED` with zero failed tests.

- [ ] **Step 4: Run the documented unsigned production build**

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -configuration Release \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/OpenLARPDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Inspect the generated Release app configuration**

```bash
/usr/libexec/PlistBuddy \
  -c 'Print :OpenLARPReleaseChannel' \
  /private/tmp/OpenLARPDerivedData/Build/Products/Release-iphoneos/OpenLARP.app/Info.plist
```

Expected: `app-store`.

Confirm the built public app does not contain public navigation labels for unfinished surfaces by inspecting the compiled Info/configuration and then exercising the release build during the later visual QA workstream. Do not treat string absence alone as UI proof.

- [ ] **Step 6: Review the final diff and scan for secrets**

```bash
git status --short
git diff --stat main...HEAD
git diff --check main...HEAD
git grep -n -E 'AIza[0-9A-Za-z_-]{30,}|BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY' -- . ':!Package.resolved'
```

Expected: only intended source, tests, generated project, scripts, and documentation changed; no secret matches.

- [ ] **Step 7: Commit verification documentation**

```bash
git add docs/APP_STORE_TESTFLIGHT_READINESS.md
git commit -m "Document App Store release profile"
```

- [ ] **Step 8: Record the next workstream**

Update the active task plan so the next implementation plan covers identity-safe persistence, guest/account containers, legacy-state migration, and complete local erase. Do not enable public account controls until that workstream passes its tests and signed-device verification.
