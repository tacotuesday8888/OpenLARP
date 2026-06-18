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
