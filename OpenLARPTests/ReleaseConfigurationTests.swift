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

    func testPublicRootAndTodayConsumeReleaseGates() throws {
        let rootView = try source("OpenLARP/AppRootView.swift")
        let todayView = try source("OpenLARP/Views/TodayView.swift")

        XCTAssertTrue(rootView.contains("releaseConfiguration.isEnabled(.agent)"))
        XCTAssertTrue(todayView.contains("releaseConfiguration.isEnabled(.subscriptions)"))
        XCTAssertTrue(todayView.contains("releaseConfiguration.isEnabled(.agent)"))
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
        XCTAssertTrue(normalizedProfileView.contains("""
        if store.releaseConfiguration.isEnabled(.cloudSync) {
        PrivacyToggleRow(
        """))
        XCTAssertTrue(profileView.contains("isOn: privateEvidenceCloudSyncBinding"))
        XCTAssertTrue(profileView.contains("Career context and proof stay on this device in this release."))
        XCTAssertTrue(profileView.contains("OpenLARP suggests next steps. You approve every external action."))
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
