import XCTest
@testable import OpenLARP

final class ReleaseConfigurationTests: XCTestCase {
    func testAppStoreMVPIsFreeAndExposesNoUnfinishedCapabilities() {
        let configuration = OpenLARPReleaseConfiguration.appStoreMVP

        XCTAssertEqual(configuration.channel, .appStore)
        XCTAssertEqual(configuration.accessMode, .free)
        XCTAssertEqual(configuration.serviceMode, .localOnly)
        XCTAssertTrue(configuration.enabledCapabilities.isEmpty)
        XCTAssertFalse(configuration.runsAuthenticationLifecycle)
        XCTAssertFalse(configuration.runsSubscriptionLifecycle)
        XCTAssertFalse(configuration.runsBackendEventSync)
    }

    func testInternalBetaRetainsExistingInfrastructureWithoutLiveAI() {
        let configuration = OpenLARPReleaseConfiguration.internalBeta

        XCTAssertEqual(configuration.channel, .internalBeta)
        XCTAssertEqual(configuration.accessMode, .subscription)
        XCTAssertEqual(configuration.serviceMode, .firebaseBeta)
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

    func testAppStoreActivationRequestsOnlyDailyAvailabilityRefresh() {
        XCTAssertEqual(
            AppLifecyclePolicy.activationOperations(for: .appStoreMVP),
            [.refreshDailyAvailability]
        )
    }

    func testInternalActivationRequestsServiceWorkInOrder() {
        XCTAssertEqual(
            AppLifecyclePolicy.activationOperations(for: .internalBeta),
            [
                .refreshDailyAvailability,
                .restoreAuthentication,
                .refreshSubscription,
                .syncBackendEvents
            ]
        )
    }

    func testTabChangesAlwaysRefreshDailyAvailabilityAndOnlySyncWhenEnabled() {
        XCTAssertEqual(
            AppLifecyclePolicy.tabChangeOperations(for: .appStoreMVP),
            [.refreshDailyAvailability]
        )
        XCTAssertEqual(
            AppLifecyclePolicy.tabChangeOperations(for: .internalBeta),
            [.refreshDailyAvailability, .syncBackendEvents]
        )
    }

    func testPublicRootAndTodayUseBoundedCapabilityBlocks() throws {
        let rootView = try source("OpenLARP/AppRootView.swift")
        let todayView = try source("OpenLARP/Views/TodayView.swift")

        XCTAssertTrue(containsGatedStandaloneInvocations(
            rootView,
            typeDeclaration: "struct AppRootView: View {",
            capabilityGuard: "if store.releaseConfiguration.isEnabled(.agent) {",
            protectedInvocations: ["AgentDashboardView(store: store)"]
        ))
        XCTAssertTrue(containsGatedStandaloneInvocations(
            todayView,
            typeDeclaration: "struct TodayView: View {",
            capabilityGuard: "if store.releaseConfiguration.isEnabled(.subscriptions) {",
            protectedInvocations: ["subscriptionAccessCard"]
        ))
        XCTAssertTrue(containsGatedStandaloneInvocations(
            todayView,
            typeDeclaration: "struct TodayView: View {",
            capabilityGuard: "if store.releaseConfiguration.isEnabled(.agent) {",
            protectedInvocations: ["dailyAgentBrief", "showingAgent = true"]
        ))
    }

    func testPublicSurfaceMatcherRejectsUnconditionalDuplicatesBesideSafeGates() {
        let rootFixture = """
        struct AppRootView: View {
            var body: some View {
                TabView {
                    if store.releaseConfiguration.isEnabled(.agent) {
                        AgentDashboardView(store: store)
                    }
                    AgentDashboardView(store: store)
                }
            }
        }

        struct AgentDashboardView: View {}
        """
        let subscriptionFixture = """
        struct TodayView: View {
            var body: some View {
                VStack {
                    if store.releaseConfiguration.isEnabled(.subscriptions) {
                        subscriptionAccessCard
                    }
                    subscriptionAccessCard
                }
            }

            private var subscriptionAccessCard: some View { EmptyView() }
        }
        """
        let agentFixture = """
        struct TodayView: View {
            var body: some View {
                VStack {
                    if store.releaseConfiguration.isEnabled(.agent) {
                        dailyAgentBrief
                        Button {
                            showingAgent = true
                        } label: {
                            Text("Safe")
                        }
                    }
                    dailyAgentBrief
                    Button {
                        showingAgent = true
                    } label: {
                        Text("Unsafe")
                    }
                }
            }

            private var dailyAgentBrief: some View { EmptyView() }
        }
        """

        XCTAssertFalse(containsGatedStandaloneInvocations(
            rootFixture,
            typeDeclaration: "struct AppRootView: View {",
            capabilityGuard: "if store.releaseConfiguration.isEnabled(.agent) {",
            protectedInvocations: ["AgentDashboardView(store: store)"]
        ))
        XCTAssertFalse(containsGatedStandaloneInvocations(
            subscriptionFixture,
            typeDeclaration: "struct TodayView: View {",
            capabilityGuard: "if store.releaseConfiguration.isEnabled(.subscriptions) {",
            protectedInvocations: ["subscriptionAccessCard"]
        ))
        XCTAssertFalse(containsGatedStandaloneInvocations(
            agentFixture,
            typeDeclaration: "struct TodayView: View {",
            capabilityGuard: "if store.releaseConfiguration.isEnabled(.agent) {",
            protectedInvocations: ["dailyAgentBrief", "showingAgent = true"]
        ))
    }

    func testPublicProfileConsumesEveryInfrastructureGate() throws {
        let profileView = try source("OpenLARP/Views/ProfileView.swift")
        let normalizedProfileView = profileView
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        XCTAssertTrue(normalizedProfileView.contains("""
        if store.releaseConfiguration.isEnabled(.account) {
        accountProfileCard
        accountDataControlsCard
        }
        """))
        XCTAssertTrue(normalizedProfileView.contains("""
        if store.releaseConfiguration.isEnabled(.cloudSync) {
        careerGraphSetupStatusCard
        }
        """))
        XCTAssertTrue(normalizedProfileView.contains("""
        if store.releaseConfiguration.isEnabled(.subscriptions) {
        subscriptionStatusCard
        }
        """))
        XCTAssertTrue(normalizedProfileView.contains("""
        if store.releaseConfiguration.isEnabled(.developerTools) {
        betaMeasurementCard
        }
        """))
        XCTAssertTrue(containsGatedPrivateEvidenceCloudControl(profileView))
        XCTAssertTrue(profileView.contains("OpenLARP suggests next steps. You approve every external action."))
    }

    func testProfileCloudPrivacyGateMatcherRejectsMovedPrivateEvidenceControl() {
        let weakenedProfileView = """
        if store.releaseConfiguration.isEnabled(.cloudSync) {
            PrivacyToggleRow(
                title: "Shareable wins",
                detail: "Allow proof wins to be shared later.",
                isOn: shareWinsBinding
            )
        } else {
            Label("Career context and proof stay on this device in this release.", systemImage: "iphone.and.arrow.forward")
        }

        PrivacyToggleRow(
            title: "Private evidence cloud sync",
            detail: "Allow future proof, files, links, and private notes in account backup.",
            isOn: privateEvidenceCloudSyncBinding
        )
        .disabled(store.isUpdatingPrivateEvidenceCloudSyncConsent)

        Text("Turning this off stops future private evidence sync. Removing already synced proof backups is a separate cleanup request and is not full account deletion.")
        """

        XCTAssertFalse(containsGatedPrivateEvidenceCloudControl(weakenedProfileView))
    }

    private func containsGatedStandaloneInvocations(
        _ source: String,
        typeDeclaration: String,
        capabilityGuard: String,
        protectedInvocations: [String]
    ) -> Bool {
        guard let typeBody = balancedBlock(
            in: source,
            afterExactLine: typeDeclaration,
            opening: "{",
            closing: "}"
        ),
        let viewBody = balancedBlock(
            in: typeBody,
            afterExactLine: "var body: some View {",
            opening: "{",
            closing: "}"
        ),
        let capabilityBlock = balancedBlock(
            in: viewBody,
            afterExactLine: capabilityGuard,
            opening: "{",
            closing: "}"
        ) else {
            return false
        }

        return protectedInvocations.allSatisfy { invocation in
            exactLineCount(invocation, in: viewBody) == 1 &&
                exactLineCount(invocation, in: capabilityBlock) == 1
        }
    }

    private func balancedBlock(
        in source: String,
        afterExactLine expectedLine: String,
        opening: Character,
        closing: Character
    ) -> String? {
        let matchingOffsets = exactLineOffsets(expectedLine, in: source)
        guard matchingOffsets.count == 1 else { return nil }
        let start = source.index(source.startIndex, offsetBy: matchingOffsets[0])
        guard let openingIndex = source[start...].firstIndex(of: opening) else { return nil }

        var depth = 0
        var index = openingIndex
        while index < source.endIndex {
            let character = source[index]
            if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return String(source[source.index(after: openingIndex)..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func exactLineOffsets(_ expectedLine: String, in source: String) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let string = String(line)
            if string.trimmingCharacters(in: .whitespaces) == expectedLine,
               let firstCodeCharacter = string.firstIndex(where: { !$0.isWhitespace }) {
                offsets.append(offset + string.distance(from: string.startIndex, to: firstCodeCharacter))
            }
            offset += string.count + 1
        }
        return offsets
    }

    private func exactLineCount(_ expectedLine: String, in source: String) -> Int {
        exactLineOffsets(expectedLine, in: source).count
    }

    private func containsGatedPrivateEvidenceCloudControl(_ profileView: String) -> Bool {
        let normalizedProfileView = profileView
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        return normalizedProfileView.contains("""
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
        """)
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
}
