# Public Beta V0 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current local-first OpenLARP iOS app credible for a public beta V0 by removing static/demo app-shell behavior, preserving the tested quest loop, tightening attachment cleanup, and updating stale docs.

**Architecture:** Keep `OpenLARPStore` as the root source of truth. Use a simple SwiftUI `TabView` app shell that routes to the existing state-driven Today, Map, Progress, and Profile screens, because those screens already use the tested engine, persistence, proof receipt, archive, cadence, skip, and recovery models.

**Tech Stack:** Swift 6, SwiftUI, Observation, PhotosUI, XCTest, local JSON persistence, local app-private proof attachment storage.

---

### Task 1: Replace Static Demo Shell With Product-State Shell

**Files:**
- Modify: `OpenLARP/AppRootView.swift`
- Modify: `OpenLARPTests/V0EngineTests.swift`

- [x] **Step 1: Write failing app-shell tests**

Add tests proving the visible app tabs are the V0 product surfaces:

```swift
func testAppTabsMatchV0ProductSurfaces() {
    XCTAssertEqual(AppTab.allCases.map(\.title), ["Today", "Map", "Progress", "Profile"])
    XCTAssertEqual(AppTab.allCases.map(\.systemImage), ["bolt.fill", "map.fill", "chart.line.uptrend.xyaxis", "person.crop.circle"])
}
```

Remove the stale `OpenLARPDesignCatalog` assertion from `testDesignCatalogMatchesHTMLReferenceScreensAndTabs` and rename the test to the new shell behavior.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/OpenLARPDerivedData CODE_SIGNING_ALLOWED=NO -only-testing:OpenLARPTests/V0EngineTests/testAppTabsMatchV0ProductSurfaces
```

Expected: the test fails because the active app tabs are still `Path`, `Quest`, `Cooked`, `Proof`, and `Stats`.

- [x] **Step 3: Implement the minimal state-driven root shell**

Replace `AppRootView.swift` with:

```swift
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case map
    case progress
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .map: "Map"
        case .progress: "Progress"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "bolt.fill"
        case .map: "map.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}

struct AppRootView: View {
    let store: OpenLARPStore
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(store: store)
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
            .tag(AppTab.today)

            NavigationStack {
                QuestMapView(
                    state: store.state,
                    attachmentURL: { attachment in store.localURL(for: attachment) },
                    viewToday: { selectedTab = .today }
                )
            }
            .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.systemImage) }
            .tag(AppTab.map)

            NavigationStack {
                ProgressTabView(
                    state: store.state,
                    attachmentURL: { attachment in store.localURL(for: attachment) },
                    improveWeakestArea: { selectedTab = .today }
                )
            }
            .tabItem { Label(AppTab.progress.title, systemImage: AppTab.progress.systemImage) }
            .tag(AppTab.progress)

            NavigationStack {
                ProfileView(store: store)
            }
            .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
            .tag(AppTab.profile)
        }
        .tint(.openLARPBlue)
        .onAppear { store.refreshDailyAvailability() }
        .onChange(of: selectedTab) { store.refreshDailyAvailability() }
    }
}
```

- [x] **Step 4: Run focused test and verify GREEN**

Run the focused app-shell test. Expected: it passes.

### Task 2: Clean Up Pending Attachment Files

**Files:**
- Modify: `OpenLARP/Models/OpenLARPStore.swift`
- Modify: `OpenLARPTests/V0EngineTests.swift`

- [x] **Step 1: Write failing cleanup tests**

Add tests that save image attachments, check proof to make them pending, discard or skip the pending result, verify abandoned image files are removed from disk, and verify re-checking proof with the same attachment keeps the retained image file.

- [x] **Step 2: Run focused cleanup test and verify RED**

Run the focused test. Expected: it fails because `discardPendingQualityResult()` currently clears metadata but does not delete the saved pending image.

- [x] **Step 3: Delete pending attachments before clearing transient proof**

Add a private `deletePendingProofAttachments()` helper in `OpenLARPStore`, call it before clearing `pendingProof` in `discardPendingQualityResult()`, `skipCurrentQuest()`, and `resetGoal()`.

- [x] **Step 4: Run focused cleanup test and verify GREEN**

Run the cleanup test and confirm it passes.

### Task 3: Update Stale Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/DEVELOPMENT_ROADMAP.md`

- [x] **Step 1: Update current-state docs**

Replace starter-shell claims with the actual local V0 state: state-driven onboarding, deterministic mock diagnostic and quest plan, local JSON persistence, proof text/link/photo metadata, local attachment files, proof receipts/archive/detail, quest cadence, skip/recovery flows, and XCTest coverage.

- [x] **Step 2: Keep future limits explicit**

Document that V0 remains local/mock for AI, accounts/backend, push notifications, payments/subscriptions, analytics, TestFlight/App Store release, and cross-device sync.

### Task 4: Validate, Commit, Push

**Files:**
- Inspect all changed source, tests, docs, and plan files.

- [x] **Step 1: Run full tests**

Run:

```bash
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/OpenLARPDerivedData CODE_SIGNING_ALLOWED=NO
```

- [x] **Step 2: Run required unsigned build**

Run:

```bash
xcodebuild -project OpenLARP.xcodeproj -scheme OpenLARP -destination generic/platform=iOS -derivedDataPath /private/tmp/OpenLARPDerivedData CODE_SIGNING_ALLOWED=NO build
```

- [x] **Step 3: Inspect diff and secret risk**

Run `git diff --check`, `git diff --stat`, `git diff`, `git status --short`, and scan changed lines for secrets, local machine config, generated build output, and fake account/payment claims.

- [ ] **Step 4: Commit and push**

Stage only intentional files, commit with a focused message, push `codex/public-beta-v0-hardening`, and confirm the working tree is clean.
