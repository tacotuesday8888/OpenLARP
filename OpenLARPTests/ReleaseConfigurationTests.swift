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

    func testAppStorePresentationPolicyExposesOnlyCoreMVPContentInOrder() {
        XCTAssertEqual(
            AppTab.visibleTabs(for: .appStoreMVP),
            [.today, .map, .progress, .profile]
        )
        XCTAssertEqual(
            TodaySection.visibleSections(for: .appStoreMVP),
            [.header, .quest, .diagnostic, .progress, .outcome]
        )
        XCTAssertEqual(
            ProfileSection.visibleSections(for: .appStoreMVP),
            [
                .hero,
                .careerSummary,
                .activeGoal,
                .recentOutcomes,
                .streak,
                .privacy,
                .localData,
                .badges,
                .proof,
                .rules
            ]
        )
        XCTAssertEqual(
            ProfilePrivacyPresentation.mode(for: .appStoreMVP),
            .localOnlyNotice
        )

        let privacyPresentation = ProfilePrivacyPresentation.mode(for: .appStoreMVP)
        XCTAssertEqual(privacyPresentation.visibleControls, [])
        XCTAssertEqual(
            privacyPresentation.localOnlyContent?.dataHandlingStatement,
            "OpenLARP does not upload or sync career data in this release."
        )
        XCTAssertEqual(
            privacyPresentation.localOnlyContent?.committedDataBackupStatement,
            "Committed OpenLARP data follows your iOS device backup settings."
        )
        XCTAssertEqual(
            privacyPresentation.localOnlyContent?.temporaryDataBackupStatement,
            "Proof drafts and temporary files are marked for exclusion from iOS device backups."
        )
        XCTAssertEqual(
            privacyPresentation.localOnlyContent?.deviceBackupStatement,
            "Committed OpenLARP data follows your iOS device backup settings.\n\nProof drafts and temporary files are marked for exclusion from iOS device backups."
        )
    }

    func testInternalBetaPresentationPolicyRetainsInfrastructureContentInOrder() {
        XCTAssertEqual(
            AppTab.visibleTabs(for: .internalBeta),
            [.today, .map, .progress, .agent, .profile]
        )
        XCTAssertEqual(
            TodaySection.visibleSections(for: .internalBeta),
            [
                .header,
                .subscriptionAccess,
                .quest,
                .diagnostic,
                .progress,
                .agentBrief,
                .agentAction,
                .outcome
            ]
        )
        XCTAssertEqual(
            ProfileSection.visibleSections(for: .internalBeta),
            [
                .hero,
                .careerSummary,
                .accountProfile,
                .accountDataControls,
                .subscriptionStatus,
                .careerGraphStatus,
                .betaMeasurement,
                .activeGoal,
                .recentOutcomes,
                .streak,
                .privacy,
                .localData,
                .badges,
                .proof,
                .rules
            ]
        )
        XCTAssertEqual(
            ProfilePrivacyPresentation.mode(for: .internalBeta),
            .cloudControls
        )

        let privacyPresentation = ProfilePrivacyPresentation.mode(for: .internalBeta)
        XCTAssertEqual(
            privacyPresentation.visibleControls,
            [.privateEvidenceCloudSync]
        )
        XCTAssertNil(privacyPresentation.localOnlyContent)
    }
}
