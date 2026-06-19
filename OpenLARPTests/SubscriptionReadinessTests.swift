import Foundation
import XCTest
@testable import OpenLARP

final class SubscriptionReadinessTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testActiveRevenueCatEntitlementGrantsAccessWithoutSDKTypes() {
        let now = date(year: 2026, month: 6, day: 1)
        let expiration = date(year: 2026, month: 7, day: 1)
        let state = OpenLARPSubscriptionState(
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: expiration
            ),
            lastUpdatedAt: now
        )

        let access = state.access(at: now, calendar: calendar)

        XCTAssertTrue(access.isEntitled)
        XCTAssertEqual(access.status, .active)
        XCTAssertEqual(access.source, .revenueCatCustomerInfo)
        XCTAssertEqual(access.expiresAt, expiration)
        XCTAssertFalse(access.shouldShowPaywall)
    }

    func testFourteenDayFreeSprintGrantsLocalMockAccessThenExpires() {
        let start = date(year: 2026, month: 6, day: 1)
        let dayFourteen = date(year: 2026, month: 6, day: 14, hour: 23)
        let exactEnd = date(year: 2026, month: 6, day: 15)
        let state = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)

        let activeAccess = state.access(at: dayFourteen, calendar: calendar)
        let expiredAccess = state.access(at: exactEnd, calendar: calendar)

        XCTAssertTrue(activeAccess.isEntitled)
        XCTAssertEqual(activeAccess.status, .freeSprint)
        XCTAssertEqual(activeAccess.source, .localFreeSprint)
        XCTAssertEqual(activeAccess.expiresAt, exactEnd)
        XCTAssertEqual(activeAccess.daysRemaining, 1)
        XCTAssertFalse(activeAccess.shouldShowPaywall)
        XCTAssertFalse(expiredAccess.isEntitled)
        XCTAssertEqual(expiredAccess.status, .expired)
        XCTAssertTrue(expiredAccess.shouldShowPaywall)
    }

    func testExpiredRevenueCatEntitlementFallsBackToExpiredWhenFreeSprintIsOver() {
        let start = date(year: 2026, month: 6, day: 1)
        let now = date(year: 2026, month: 6, day: 20)
        let state = OpenLARPSubscriptionState(
            freeSprint: OpenLARPFreeSprintEntitlement(startedAt: start),
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: date(year: 2026, month: 6, day: 2),
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: date(year: 2026, month: 6, day: 10)
            ),
            lastUpdatedAt: now
        )

        let access = state.access(at: now, calendar: calendar)

        XCTAssertFalse(access.isEntitled)
        XCTAssertEqual(access.status, .expired)
        XCTAssertEqual(access.source, .none)
        XCTAssertTrue(access.shouldShowPaywall)
    }

    func testOfflineRevenueCatEntitlementUsesCachedCustomerInfoSafely() {
        let now = date(year: 2026, month: 6, day: 1)
        let state = OpenLARPSubscriptionState(
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: nil,
                isOfflineEntitlement: true
            ),
            connectionStatus: .offline,
            lastUpdatedAt: now
        )

        let access = state.access(at: now, calendar: calendar)

        XCTAssertTrue(access.isEntitled)
        XCTAssertEqual(access.status, .offline)
        XCTAssertEqual(access.source, .revenueCatOfflineEntitlement)
        XCTAssertFalse(access.shouldShowPaywall)
    }

    func testRestoreStateTransitionsCanGrantRecoveredAccess() {
        let start = date(year: 2026, month: 6, day: 1)
        let restoreStarted = date(year: 2026, month: 6, day: 20)
        let restoreFinished = date(year: 2026, month: 6, day: 20, hour: 1)
        let restoredExpiration = date(year: 2026, month: 7, day: 20)
        let expired = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)

        let restoring = expired.restoreRequested(at: restoreStarted)
        let restored = restoring.restoreSucceeded(
            with: RevenueCatCustomerInfoSnapshot(
                fetchedAt: restoreFinished,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: restoredExpiration
            ),
            at: restoreFinished
        )

        XCTAssertEqual(restoring.restoreState.status, .inProgress)
        XCTAssertEqual(restoring.access(at: restoreStarted, calendar: calendar).status, .restoreInProgress)
        XCTAssertEqual(restored.restoreState.status, .restored)
        XCTAssertEqual(restored.access(at: restoreFinished, calendar: calendar).status, .active)
        XCTAssertEqual(restored.access(at: restoreFinished, calendar: calendar).expiresAt, restoredExpiration)
    }

    func testFailedRestoreDoesNotInventAccess() {
        let start = date(year: 2026, month: 6, day: 1)
        let restoreStarted = date(year: 2026, month: 6, day: 20)
        let failedAt = date(year: 2026, month: 6, day: 20, hour: 1)
        let expired = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)

        let failed = expired
            .restoreRequested(at: restoreStarted)
            .restoreFailed(at: failedAt)

        let access = failed.access(at: failedAt, calendar: calendar)

        XCTAssertEqual(failed.restoreState.status, .failed)
        XCTAssertFalse(access.isEntitled)
        XCTAssertEqual(access.status, .restoreFailed)
        XCTAssertTrue(access.shouldShowPaywall)
    }

    func testActiveEntitlementKeepsAccessWhenRestoreFailedMetadataRemains() {
        let now = date(year: 2026, month: 6, day: 20)
        let expiration = date(year: 2026, month: 7, day: 20)
        let state = OpenLARPSubscriptionState(
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: expiration
            ),
            restoreState: OpenLARPRestoreState(
                status: .failed,
                requestedAt: date(year: 2026, month: 6, day: 19),
                completedAt: now
            ),
            lastUpdatedAt: now
        )

        let access = state.access(at: now, calendar: calendar)

        XCTAssertTrue(access.isEntitled)
        XCTAssertEqual(access.status, .active)
        XCTAssertEqual(access.source, .revenueCatCustomerInfo)
        XCTAssertEqual(access.expiresAt, expiration)
        XCTAssertFalse(access.shouldShowPaywall)
    }

    func testLegacyStateWithoutSubscriptionDecodesWithFreeSprintMigrationDefault() throws {
        let original = OpenLARPEngine.confirmGoal(
            goal,
            now: date(year: 2026, month: 6, day: 1)
        )
        let encoded = try JSONEncoder.openLARPPersistence.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "subscriptionState")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: legacyData)
        let access = decoded.subscriptionState.access(
            at: date(year: 2026, month: 6, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(decoded.subscriptionState.freeSprint?.startedAt, original.updatedAt)
        XCTAssertTrue(access.isEntitled)
        XCTAssertEqual(access.status, .freeSprint)
    }

    func testBetaSummaryIncludesPaymentReadinessWithoutPrivatePaymentIdentifiers() throws {
        let now = date(year: 2026, month: 6, day: 1)
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.subscriptionState = OpenLARPSubscriptionState(
            freeSprint: OpenLARPFreeSprintEntitlement(startedAt: now),
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [
                    OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID,
                    "private-product-id-should-not-export"
                ],
                entitlementExpirationDate: date(year: 2026, month: 7, day: 1),
                managementURLString: "https://billing.example.com/private/customer"
            ),
            lastUpdatedAt: now
        )
        state.betaEvents = [
            BetaEventRecord(kind: .freeSprintStarted, occurredAt: now),
            BetaEventRecord(kind: .subscriptionRestoreRequested, occurredAt: date(year: 2026, month: 6, day: 2)),
            BetaEventRecord(kind: .subscriptionRestoreCompleted, occurredAt: date(year: 2026, month: 6, day: 2, hour: 1))
        ]

        let summary = BetaMeasurementSummaryContent(state: state, generatedAt: now)
        let exportedText = summary.searchableText
        let exportedJSON = String(
            decoding: try JSONEncoder.openLARPBetaExport.encode(summary),
            as: UTF8.self
        )

        XCTAssertEqual(summary.paymentEventCount, 3)
        XCTAssertEqual(summary.subscriptionAccessStatus, .active)
        XCTAssertEqual(summary.subscriptionAccessSource, .revenueCatCustomerInfo)
        XCTAssertTrue(summary.subscriptionHasAccess)
        XCTAssertFalse(summary.subscriptionNeedsPaywall)
        XCTAssertTrue(exportedText.contains("Payment events: 3"))
        XCTAssertTrue(exportedText.contains("Subscription access: Active"))
        XCTAssertFalse(exportedText.contains(OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID))
        XCTAssertFalse(exportedText.contains("private-product-id-should-not-export"))
        XCTAssertFalse(exportedText.contains("billing.example.com"))
        XCTAssertFalse(exportedJSON.contains(OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID))
        XCTAssertFalse(exportedJSON.contains("private-product-id-should-not-export"))
        XCTAssertFalse(exportedJSON.contains("billing.example.com"))
    }

    func testNotStartedSubscriptionAccessIsDistinctFromExpired() {
        let now = date(year: 2026, month: 6, day: 1)
        let state = OpenLARPSubscriptionState.notStarted()

        let access = state.access(at: now, calendar: calendar)

        XCTAssertFalse(access.isEntitled)
        XCTAssertEqual(access.status, .notStarted)
        XCTAssertEqual(access.source, .none)
        XCTAssertFalse(access.shouldShowPaywall)
    }

    func testAccessGateAllowsFirstSetupAndBlocksExpiredProgression() {
        let now = date(year: 2026, month: 6, day: 20)
        let notStarted = OpenLARPSubscriptionState.notStarted().access(at: now, calendar: calendar)
        let active = OpenLARPSubscriptionState.localFreeSprint(startedAt: now).access(at: now, calendar: calendar)
        let expired = OpenLARPSubscriptionState.localFreeSprint(
            startedAt: date(year: 2026, month: 6, day: 1)
        )
        .access(at: now, calendar: calendar)

        XCTAssertTrue(OpenLARPAccessGate.decision(for: .confirmGoal, access: notStarted).isAllowed)
        XCTAssertFalse(OpenLARPAccessGate.decision(for: .startQuest, access: notStarted).isAllowed)
        XCTAssertTrue(OpenLARPAccessGate.decision(for: .startQuest, access: active).isAllowed)

        let expiredDecision = OpenLARPAccessGate.decision(for: .submitProof, access: expired)
        XCTAssertFalse(expiredDecision.isAllowed)
        XCTAssertEqual(expiredDecision.accessStatus, .expired)
        XCTAssertEqual(expiredDecision.primaryActionTitle, "Continue OpenLARP")
        XCTAssertTrue(expiredDecision.message.contains("saved proof stays available"))
    }

    @MainActor
    func testStoreRefreshSubscriptionStatusAppliesInjectedServiceAndPersistsEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let now = date(year: 2026, month: 6, day: 20)
        let activeState = OpenLARPSubscriptionState(
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: date(year: 2026, month: 7, day: 20)
            ),
            connectionStatus: .online,
            lastUpdatedAt: now
        )
        let service = CapturingSubscriptionService(refreshedState: activeState)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            subscriptionService: service,
            now: { now },
            calendar: calendar
        )

        await store.refreshSubscriptionStatus()

        XCTAssertEqual(service.refreshRequestCount, 1)
        XCTAssertEqual(store.state.subscriptionState, activeState)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionStatusChecked)
        XCTAssertEqual(store.subscriptionAccess().status, .active)
        XCTAssertEqual(try persistence.load().subscriptionState, activeState)
    }

    @MainActor
    func testStoreRestorePurchasesSuccessRecordsEventsAndRecoveredAccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let now = date(year: 2026, month: 6, day: 20)
        let restoredExpiration = date(year: 2026, month: 7, day: 20)
        let service = CapturingSubscriptionService(
            restoredCustomerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: restoredExpiration
            )
        )
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            subscriptionService: service,
            now: { now },
            calendar: calendar
        )

        await store.restorePurchases()

        XCTAssertEqual(service.restoreRequestCount, 1)
        XCTAssertEqual(store.state.subscriptionState.restoreState.status, .restored)
        XCTAssertEqual(store.subscriptionAccess().status, .active)
        XCTAssertEqual(store.subscriptionAccess().expiresAt, restoredExpiration)
        XCTAssertEqual(store.state.betaEvents.map(\.kind), [
            .subscriptionRestoreRequested,
            .subscriptionRestoreCompleted
        ])
        XCTAssertEqual(try persistence.load().subscriptionState.restoreState.status, .restored)
    }

    @MainActor
    func testStoreRestorePurchasesFailureRecordsFailureWithoutInventingAccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let now = date(year: 2026, month: 6, day: 20)
        let service = CapturingSubscriptionService()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            subscriptionService: service,
            now: { now },
            calendar: calendar
        )

        await store.restorePurchases()

        XCTAssertEqual(service.restoreRequestCount, 1)
        XCTAssertEqual(store.state.subscriptionState.restoreState.status, .failed)
        XCTAssertEqual(store.subscriptionAccess().status, .restoreFailed)
        XCTAssertFalse(store.subscriptionAccess().isEntitled)
        XCTAssertEqual(store.state.betaEvents.map(\.kind), [
            .subscriptionRestoreRequested,
            .subscriptionRestoreFailed
        ])
        XCTAssertEqual(try persistence.load().subscriptionState.restoreState.status, .failed)
    }

    func testRevenueCatRuntimeConfigurationMapsPlistLikeValues() {
        let configuration = OpenLARPRevenueCatRuntimeConfiguration.fromDictionary([
            OpenLARPRevenueCatConfigurationKey.iosAPIKey.rawValue: "  appl_public_test_key  ",
            OpenLARPRevenueCatConfigurationKey.entitlementID.rawValue: "openlarp_pro",
            OpenLARPRevenueCatConfigurationKey.offeringID.rawValue: "beta",
            OpenLARPRevenueCatConfigurationKey.monthlyProductID.rawValue: "com.openlarp.monthly",
            OpenLARPRevenueCatConfigurationKey.studentMonthlyProductID.rawValue: "com.openlarp.student.monthly"
        ])

        XCTAssertEqual(configuration.normalizedPublicIOSAPIKey, "appl_public_test_key")
        XCTAssertTrue(configuration.canConfigureLiveSDK)
        XCTAssertEqual(configuration.subscriptionConfiguration.revenueCatEntitlementID, "openlarp_pro")
        XCTAssertEqual(configuration.subscriptionConfiguration.defaultOfferingID, "beta")
        XCTAssertEqual(configuration.subscriptionConfiguration.monthlyProductID, "com.openlarp.monthly")
        XCTAssertEqual(configuration.subscriptionConfiguration.studentMonthlyProductID, "com.openlarp.student.monthly")
    }

    func testRevenueCatRuntimeConfigurationSupportsRevenueCatTestStoreKey() {
        let configuration = OpenLARPRevenueCatRuntimeConfiguration.fromDictionary([
            OpenLARPRevenueCatConfigurationKey.iosAPIKey.rawValue: "test_public_store_key",
            OpenLARPRevenueCatConfigurationKey.entitlementID.rawValue: "openlarp_pro"
        ])

        XCTAssertEqual(configuration.normalizedPublicIOSAPIKey, "test_public_store_key")
        XCTAssertTrue(configuration.canConfigureLiveSDK)
    }

    func testRevenueCatRuntimeConfigurationRejectsMissingOrNonIOSSDKKey() {
        let missingKeyConfiguration = OpenLARPRevenueCatRuntimeConfiguration.fromDictionary([
            OpenLARPRevenueCatConfigurationKey.iosAPIKey.rawValue: "   ",
            OpenLARPRevenueCatConfigurationKey.entitlementID.rawValue: "openlarp_pro"
        ])
        let wrongPlatformConfiguration = OpenLARPRevenueCatRuntimeConfiguration.fromDictionary([
            OpenLARPRevenueCatConfigurationKey.iosAPIKey.rawValue: "goog_public_test_key",
            OpenLARPRevenueCatConfigurationKey.entitlementID.rawValue: "openlarp_pro"
        ])

        XCTAssertNil(missingKeyConfiguration.normalizedPublicIOSAPIKey)
        XCTAssertFalse(missingKeyConfiguration.canConfigureLiveSDK)
        XCTAssertNil(wrongPlatformConfiguration.normalizedPublicIOSAPIKey)
        XCTAssertFalse(wrongPlatformConfiguration.canConfigureLiveSDK)
    }

    @MainActor
    func testRevenueCatServiceMissingConfigurationDoesNotCallSDKAndPreservesCurrentState() async throws {
        let now = date(year: 2026, month: 6, day: 20)
        let currentState = OpenLARPSubscriptionState.localFreeSprint(startedAt: now)
        let client = FakeRevenueCatClient()
        let service = OpenLARPRevenueCatSubscriptionService(
            runtimeConfiguration: OpenLARPRevenueCatRuntimeConfiguration(),
            client: client
        )

        let refreshed = try await service.refreshSubscriptionState(currentState: currentState, at: now)

        XCTAssertEqual(client.configuredPublicIOSAPIKeys, [])
        XCTAssertEqual(client.customerInfoRequestCount, 0)
        XCTAssertEqual(refreshed.freeSprint, currentState.freeSprint)
        XCTAssertEqual(refreshed.connectionStatus, .notConfigured)
        XCTAssertEqual(refreshed.lastUpdatedAt, now)
    }

    @MainActor
    func testRevenueCatServiceRefreshAppliesActiveConfiguredEntitlement() async throws {
        let now = date(year: 2026, month: 6, day: 20)
        let expiration = date(year: 2026, month: 7, day: 20)
        let client = FakeRevenueCatClient()
        client.customerInfoSnapshot = RevenueCatCustomerInfoSnapshot(
            fetchedAt: now,
            activeEntitlementIDs: ["openlarp_pro"],
            activeProductIDs: ["com.openlarp.monthly"],
            entitlementExpirationDate: expiration
        )
        let service = OpenLARPRevenueCatSubscriptionService(
            runtimeConfiguration: revenueCatConfiguration(),
            client: client
        )

        let refreshed = try await service.refreshSubscriptionState(
            currentState: .notStarted(),
            at: now
        )

        XCTAssertEqual(client.configuredPublicIOSAPIKeys, ["appl_public_test_key"])
        XCTAssertEqual(client.customerInfoRequestCount, 1)
        XCTAssertEqual(refreshed.connectionStatus, .online)
        XCTAssertEqual(refreshed.configuration.revenueCatEntitlementID, "openlarp_pro")
        XCTAssertEqual(refreshed.access(at: now, calendar: calendar).status, .active)
        XCTAssertEqual(refreshed.access(at: now, calendar: calendar).expiresAt, expiration)
    }

    @MainActor
    func testRevenueCatServiceRefreshFailurePreservesCachedAccessAsOffline() async throws {
        let now = date(year: 2026, month: 6, day: 20)
        let expiration = date(year: 2026, month: 7, day: 20)
        let currentState = OpenLARPSubscriptionState(
            configuration: revenueCatConfiguration().subscriptionConfiguration,
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: date(year: 2026, month: 6, day: 19),
                activeEntitlementIDs: ["openlarp_pro"],
                activeProductIDs: ["com.openlarp.monthly"],
                entitlementExpirationDate: expiration
            ),
            connectionStatus: .online,
            lastUpdatedAt: date(year: 2026, month: 6, day: 19)
        )
        let client = FakeRevenueCatClient()
        client.customerInfoError = RevenueCatAdapterTestError.offline
        let service = OpenLARPRevenueCatSubscriptionService(
            runtimeConfiguration: revenueCatConfiguration(),
            client: client
        )

        let refreshed = try await service.refreshSubscriptionState(currentState: currentState, at: now)

        XCTAssertEqual(client.customerInfoRequestCount, 1)
        XCTAssertEqual(refreshed.customerInfo, currentState.customerInfo)
        XCTAssertEqual(refreshed.connectionStatus, .offline)
        XCTAssertEqual(refreshed.access(at: now, calendar: calendar).status, .offline)
        XCTAssertEqual(refreshed.access(at: now, calendar: calendar).source, .revenueCatOfflineEntitlement)
    }

    @MainActor
    func testRevenueCatServiceRestoreWithoutConfiguredEntitlementFails() async throws {
        let now = date(year: 2026, month: 6, day: 20)
        let startedAt = date(year: 2026, month: 6, day: 1)
        let client = FakeRevenueCatClient()
        client.restoreSnapshot = RevenueCatCustomerInfoSnapshot(
            fetchedAt: now,
            activeEntitlementIDs: ["different_entitlement"],
            activeProductIDs: ["com.openlarp.monthly"],
            entitlementExpirationDate: date(year: 2026, month: 7, day: 20)
        )
        let service = OpenLARPRevenueCatSubscriptionService(
            runtimeConfiguration: revenueCatConfiguration(),
            client: client
        )
        let restoring = OpenLARPSubscriptionState
            .localFreeSprint(startedAt: startedAt)
            .restoreRequested(at: now)

        let restored = try await service.restorePurchases(currentState: restoring, at: now)

        XCTAssertEqual(client.restoreRequestCount, 1)
        XCTAssertEqual(restored.connectionStatus, .online)
        XCTAssertEqual(restored.restoreState.status, .failed)
        XCTAssertEqual(restored.restoreState.requestedAt, now)
        XCTAssertFalse(restored.access(at: now, calendar: calendar).isEntitled)
        XCTAssertEqual(restored.access(at: now, calendar: calendar).status, .restoreFailed)
    }

    func testRevenueCatPureMapperSortsAndDeduplicatesPrivateIdentifiers() {
        let now = date(year: 2026, month: 6, day: 20)

        let snapshot = OpenLARPRevenueCatSnapshotMapper.snapshot(
            fetchedAt: now,
            activeEntitlementIDs: ["openlarp_pro", "openlarp_pro", "student"],
            activeProductIDs: ["com.openlarp.monthly", "com.openlarp.monthly", "com.openlarp.student.monthly"],
            entitlementExpirationDate: nil,
            managementURLString: "https://apps.apple.com/account/subscriptions"
        )

        XCTAssertEqual(snapshot.activeEntitlementIDs, ["openlarp_pro", "student"])
        XCTAssertEqual(snapshot.activeProductIDs, ["com.openlarp.monthly", "com.openlarp.student.monthly"])
        XCTAssertEqual(OpenLARPRevenueCatSnapshotMapper.subscriptionPeriodDescription(value: 1, unit: "month"), "1 month")
        XCTAssertEqual(OpenLARPRevenueCatSnapshotMapper.subscriptionPeriodDescription(value: 2, unit: "month"), "2 months")
    }

    @MainActor
    func testExpiredSprintBlocksQuestProgressionAndRecordsPaywallExposure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let start = date(year: 2026, month: 6, day: 1)
        let expiredAt = date(year: 2026, month: 6, day: 20)
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { expiredAt },
            calendar: calendar
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: start)
        store.state.subscriptionState = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)

        store.startCurrentQuest()

        XCTAssertEqual(store.state.currentQuest?.status, .available)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
        XCTAssertTrue(store.errorMessage?.contains("Sprint access ended") == true)
        XCTAssertEqual(try persistence.load().currentQuest?.status, .available)
    }

    @MainActor
    func testExpiredSprintBlocksProofSubmissionBeforeAIReview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let start = date(year: 2026, month: 6, day: 1)
        let expiredAt = date(year: 2026, month: 6, day: 20)
        var state = OpenLARPEngine.confirmGoal(goal, now: start)
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: start)
        state.subscriptionState = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            aiWorkflowService: FailingSubscriptionGateAIWorkflowService(),
            now: { expiredAt },
            calendar: calendar
        )
        store.state = state

        await store.checkProof(
            kind: .proof,
            text: "I shipped a small feature and saved the pull request.",
            link: "",
            attachments: []
        )

        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.pendingQualityResult)
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .proofSubmitted })
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
    }

    @MainActor
    func testExpiredSprintBlocksPendingProofClaimBeforeProgressMoves() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let start = date(year: 2026, month: 6, day: 1)
        let expiredAt = date(year: 2026, month: 6, day: 20)
        var state = OpenLARPEngine.confirmGoal(goal, now: start)
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: start)
        state.subscriptionState = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)
        let proof = ProofSubmission(
            kind: .proof,
            text: "I shipped a small feature, wrote implementation notes, attached the pull request, and saved the review feedback.",
            link: "https://example.com/proof",
            submittedAt: start
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { expiredAt },
            calendar: calendar
        )
        store.state = state
        store.pendingProof = proof
        store.pendingQualityResult = result

        store.claimPendingQualityResult()

        XCTAssertEqual(store.state.progress.xp, 0)
        XCTAssertEqual(store.state.currentQuest?.status, .inProgress)
        XCTAssertEqual(store.pendingProof, proof)
        XCTAssertEqual(store.pendingQualityResult, result)
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .xpClaimed })
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
    }

    @MainActor
    func testExpiredSprintBlocksCareerGraphSyncPreparationBeforeBackendWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let start = date(year: 2026, month: 6, day: 1)
        let expiredAt = date(year: 2026, month: 6, day: 20)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            careerGraphSyncService: FailingSubscriptionGateCareerGraphSyncService(),
            now: { expiredAt },
            calendar: calendar
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: start)
        store.state.subscriptionState = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)

        await store.prepareCareerGraphSyncPreview()

        XCTAssertNil(store.careerGraphSyncPreview)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
        XCTAssertTrue(store.errorMessage?.contains("Sprint access ended") == true)
    }

    @MainActor
    func testExpiredSprintBlocksAgentScanButAllowsRestoreAttempt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let start = date(year: 2026, month: 6, day: 1)
        let expiredAt = date(year: 2026, month: 6, day: 20)
        let service = CapturingSubscriptionService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            subscriptionService: service,
            now: { expiredAt },
            calendar: calendar
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: start)
        store.state.subscriptionState = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)
        let originalBrief = store.state.agentBrief

        await store.runAgentScan()
        await store.restorePurchases()

        XCTAssertEqual(store.state.agentBrief, originalBrief)
        XCTAssertEqual(service.restoreRequestCount, 1)
        XCTAssertEqual(Array(store.state.betaEvents.map(\.kind).suffix(3)), [
            .subscriptionPaywallViewed,
            .subscriptionRestoreRequested,
            .subscriptionRestoreFailed
        ])
    }

    @MainActor
    func testExpiredLifecycleBlocksNewGoalAfterReset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let start = date(year: 2026, month: 6, day: 1)
        let expiredAt = date(year: 2026, month: 6, day: 20)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { expiredAt },
            calendar: calendar
        )
        store.state = .empty
        store.state.subscriptionState = OpenLARPSubscriptionState.localFreeSprint(startedAt: start)

        await store.confirmGoal(goal)

        XCTAssertTrue(store.state.needsGoalSetup)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
        XCTAssertTrue(store.errorMessage?.contains("Sprint access ended") == true)
    }

    @MainActor
    func testGoalConfirmationRecordsFreeSprintStartOnlyOnceAndPreservesResetLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayOne = date(year: 2026, month: 6, day: 1)
        let dayFive = date(year: 2026, month: 6, day: 5)
        var currentDate = dayOne
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { currentDate },
            calendar: calendar
        )

        await store.confirmGoal(goal)
        let originalFreeSprintStart = store.state.subscriptionState.freeSprint?.startedAt
        XCTAssertEqual(store.state.betaEvents.filter { $0.kind == .freeSprintStarted }.count, 1)

        store.resetGoal()
        currentDate = dayFive
        await store.confirmGoal(goal)

        XCTAssertEqual(store.state.subscriptionState.freeSprint?.startedAt, originalFreeSprintStart)
        XCTAssertEqual(store.state.betaEvents.filter { $0.kind == .freeSprintStarted }.count, 1)
    }

    private var goal: CareerGoal {
        CareerGoal(
            currentStatus: .student,
            targetRole: "iOS engineering internship",
            timeline: "30 days",
            background: "Second-year CS student with one class project.",
            existingProof: "Class project",
            confidence: 3,
            biggestBlocker: "Need stronger proof."
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func revenueCatConfiguration() -> OpenLARPRevenueCatRuntimeConfiguration {
        OpenLARPRevenueCatRuntimeConfiguration(
            publicIOSAPIKey: "appl_public_test_key",
            subscriptionConfiguration: OpenLARPSubscriptionConfiguration(
                revenueCatEntitlementID: "openlarp_pro",
                monthlyProductID: "com.openlarp.monthly",
                defaultOfferingID: "beta",
                studentMonthlyProductID: "com.openlarp.student.monthly"
            )
        )
    }
}

private struct FailingSubscriptionGateAIWorkflowService: V0AIWorkflowServicing {
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        throw OpenLARPError.invalidQuestPlan
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        throw OpenLARPError.invalidQuestPlan
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        XCTFail("Expired sprint should block proof review before AI workflow dispatch.")
        throw OpenLARPError.invalidQuestPlan
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        throw OpenLARPError.invalidQuestPlan
    }
}

private struct FailingSubscriptionGateCareerGraphSyncService: CareerGraphSyncServicing {
    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        XCTFail("Expired sprint should block career graph sync before backend preparation.")
        throw OpenLARPError.invalidQuestPlan
    }
}

@MainActor
private final class CapturingSubscriptionService: OpenLARPSubscriptionServicing {
    var refreshedState: OpenLARPSubscriptionState?
    var restoredCustomerInfo: RevenueCatCustomerInfoSnapshot?
    private(set) var refreshRequestCount = 0
    private(set) var restoreRequestCount = 0

    init(
        refreshedState: OpenLARPSubscriptionState? = nil,
        restoredCustomerInfo: RevenueCatCustomerInfoSnapshot? = nil
    ) {
        self.refreshedState = refreshedState
        self.restoredCustomerInfo = restoredCustomerInfo
    }

    func refreshSubscriptionState(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        refreshRequestCount += 1
        return refreshedState ?? currentState
    }

    func restorePurchases(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        restoreRequestCount += 1
        guard let restoredCustomerInfo else {
            return currentState.restoreFailed(at: timestamp)
        }
        return currentState.restoreSucceeded(with: restoredCustomerInfo, at: timestamp)
    }
}

private enum RevenueCatAdapterTestError: Error {
    case offline
}

@MainActor
private final class FakeRevenueCatClient: OpenLARPRevenueCatClient {
    var customerInfoSnapshot: RevenueCatCustomerInfoSnapshot?
    var restoreSnapshot: RevenueCatCustomerInfoSnapshot?
    var currentOffering: RevenueCatOfferingSnapshot?
    var customerInfoError: Error?
    var restoreError: Error?
    var offeringError: Error?
    private(set) var configuredPublicIOSAPIKeys: [String] = []
    private(set) var customerInfoRequestCount = 0
    private(set) var restoreRequestCount = 0
    private(set) var offeringRequestCount = 0

    func configureIfNeeded(publicIOSAPIKey: String) {
        configuredPublicIOSAPIKeys.append(publicIOSAPIKey)
    }

    func customerInfoSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot {
        customerInfoRequestCount += 1
        if let customerInfoError {
            throw customerInfoError
        }
        return customerInfoSnapshot ?? RevenueCatCustomerInfoSnapshot(fetchedAt: timestamp)
    }

    func restorePurchasesSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot {
        restoreRequestCount += 1
        if let restoreError {
            throw restoreError
        }
        return restoreSnapshot ?? RevenueCatCustomerInfoSnapshot(fetchedAt: timestamp)
    }

    func currentOfferingSnapshot() async throws -> RevenueCatOfferingSnapshot? {
        offeringRequestCount += 1
        if let offeringError {
            throw offeringError
        }
        return currentOffering
    }
}
