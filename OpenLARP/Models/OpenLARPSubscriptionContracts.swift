import Foundation

struct OpenLARPSubscriptionConfiguration: Codable, Equatable {
    var revenueCatEntitlementID: String
    var monthlyProductID: String
    var defaultOfferingID: String
    var studentMonthlyProductID: String
    var freeSprintDurationDays: Int

    var revenueCatOfferingID: String { defaultOfferingID }
    var configuredPurchaseProductIDs: [String] {
        var seenProductIDs = Set<String>()
        return [monthlyProductID, studentMonthlyProductID]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seenProductIDs.insert($0).inserted }
    }

    static let placeholder = OpenLARPSubscriptionConfiguration(
        revenueCatEntitlementID: "openlarp_beta_sprint_entitlement_placeholder",
        monthlyProductID: "openlarp_beta_monthly_placeholder",
        defaultOfferingID: "openlarp_beta_offering_placeholder",
        studentMonthlyProductID: "openlarp_beta_student_monthly_placeholder",
        freeSprintDurationDays: 14
    )

    init(
        revenueCatEntitlementID: String,
        monthlyProductID: String,
        defaultOfferingID: String,
        studentMonthlyProductID: String = "openlarp_beta_student_monthly_placeholder",
        freeSprintDurationDays: Int = 14
    ) {
        self.revenueCatEntitlementID = revenueCatEntitlementID
        self.monthlyProductID = monthlyProductID
        self.defaultOfferingID = defaultOfferingID
        self.studentMonthlyProductID = studentMonthlyProductID
        self.freeSprintDurationDays = freeSprintDurationDays
    }

    func isConfiguredPurchaseProductID(_ productID: String) -> Bool {
        configuredPurchaseProductIDs.contains(productID)
    }
}

struct OpenLARPFreeSprintEntitlement: Codable, Equatable {
    var startedAt: Date
    var durationDays: Int

    init(startedAt: Date, durationDays: Int = 14) {
        self.startedAt = startedAt
        self.durationDays = durationDays
    }

    func expiresAt(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: durationDays, to: startedAt) ??
            startedAt.addingTimeInterval(TimeInterval(durationDays * 86_400))
    }

    func isActive(at timestamp: Date, calendar: Calendar) -> Bool {
        timestamp < expiresAt(calendar: calendar)
    }

    func daysRemaining(at timestamp: Date, calendar: Calendar) -> Int {
        guard isActive(at: timestamp, calendar: calendar) else { return 0 }
        let seconds = expiresAt(calendar: calendar).timeIntervalSince(timestamp)
        return max(1, Int(ceil(seconds / 86_400)))
    }
}

struct RevenueCatCustomerInfoSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var activeEntitlementIDs: [String]
    var activeProductIDs: [String]
    var entitlementExpirationDate: Date?
    var managementURLString: String?
    var isOfflineEntitlement: Bool

    init(
        fetchedAt: Date,
        activeEntitlementIDs: [String] = [],
        activeProductIDs: [String] = [],
        entitlementExpirationDate: Date? = nil,
        managementURLString: String? = nil,
        isOfflineEntitlement: Bool = false
    ) {
        self.fetchedAt = fetchedAt
        self.activeEntitlementIDs = activeEntitlementIDs
        self.activeProductIDs = activeProductIDs
        self.entitlementExpirationDate = entitlementExpirationDate
        self.managementURLString = managementURLString
        self.isOfflineEntitlement = isOfflineEntitlement
    }

    func hasActiveEntitlement(
        _ entitlementID: String,
        at timestamp: Date
    ) -> Bool {
        guard activeEntitlementIDs.contains(entitlementID) else { return false }
        guard let entitlementExpirationDate else { return true }
        return timestamp < entitlementExpirationDate
    }
}

enum OpenLARPSubscriptionConnectionStatus: String, Codable, Equatable {
    case notConfigured
    case online
    case offline
    case failed
}

enum OpenLARPRestoreStatus: String, Codable, Equatable {
    case notStarted
    case inProgress
    case restored
    case failed

    var label: String {
        switch self {
        case .notStarted: "Not requested"
        case .inProgress: "In progress"
        case .restored: "Restored"
        case .failed: "Failed"
        }
    }
}

typealias OpenLARPSubscriptionRestoreStatus = OpenLARPRestoreStatus

struct OpenLARPRestoreState: Codable, Equatable {
    var status: OpenLARPRestoreStatus
    var requestedAt: Date?
    var completedAt: Date?

    static let empty = OpenLARPRestoreState(status: .notStarted)
    static let idle = OpenLARPRestoreState(status: .notStarted)
}

typealias OpenLARPSubscriptionRestoreState = OpenLARPRestoreState

enum OpenLARPSubscriptionAccessStatus: String, Codable, Equatable {
    case notStarted
    case active
    case freeSprint
    case expired
    case offline
    case restoreInProgress
    case restoreFailed

    var label: String {
        switch self {
        case .notStarted: "Not started"
        case .active: "Active"
        case .freeSprint: "Free sprint"
        case .expired: "Expired"
        case .offline: "Offline access"
        case .restoreInProgress: "Restore in progress"
        case .restoreFailed: "Restore failed"
        }
    }
}

enum OpenLARPSubscriptionAccessSource: String, Codable, Equatable {
    case revenueCatCustomerInfo
    case revenueCatOfflineEntitlement
    case localFreeSprint
    case none

    var label: String {
        switch self {
        case .revenueCatCustomerInfo: "RevenueCat customer info"
        case .revenueCatOfflineEntitlement: "RevenueCat offline entitlement"
        case .localFreeSprint: "Local free sprint"
        case .none: "None"
        }
    }
}

struct RevenueCatProductSnapshot: Codable, Equatable, Identifiable {
    var id: String { productID }
    var productID: String
    var displayName: String
    var displayPrice: String
    var subscriptionPeriod: String?
}

struct RevenueCatPackageSnapshot: Codable, Equatable, Identifiable {
    var id: String { identifier }
    var identifier: String
    var product: RevenueCatProductSnapshot
}

struct RevenueCatOfferingSnapshot: Codable, Equatable, Identifiable {
    var id: String { identifier }
    var identifier: String
    var packages: [RevenueCatPackageSnapshot]

    func preferredPurchasePackage(
        for configuration: OpenLARPSubscriptionConfiguration
    ) -> RevenueCatPackageSnapshot? {
        for productID in configuration.configuredPurchaseProductIDs {
            if let package = packages.first(where: { $0.product.productID == productID }) {
                return package
            }
        }
        return nil
    }
}

enum OpenLARPSubscriptionPurchaseFailure: String, Codable, Equatable {
    case notConfigured
    case noCurrentOffering
    case packageUnavailable
    case entitlementMissingAfterPurchase
    case storeError

    var message: String {
        switch self {
        case .notConfigured:
            "Subscriptions are not configured for this build yet."
        case .noCurrentOffering:
            "No subscription offering is available yet."
        case .packageUnavailable:
            "That subscription option is no longer available."
        case .entitlementMissingAfterPurchase:
            "Purchase completed, but the required entitlement was not active."
        case .storeError:
            "The store could not complete the purchase."
        }
    }
}

enum OpenLARPSubscriptionPurchaseOutcome: Equatable {
    case purchased
    case cancelled
    case failed(OpenLARPSubscriptionPurchaseFailure)
}

struct OpenLARPSubscriptionPurchaseResult: Equatable {
    var outcome: OpenLARPSubscriptionPurchaseOutcome
    var subscriptionState: OpenLARPSubscriptionState
}

protocol RevenueCatCustomerInfoProviding {
    func customerInfoSnapshot() async throws -> RevenueCatCustomerInfoSnapshot
}

protocol RevenueCatOfferingProviding {
    func offeringSnapshot(
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatOfferingSnapshot?
}

protocol RevenueCatPurchaseRestoring {
    func restorePurchasesSnapshot() async throws -> RevenueCatCustomerInfoSnapshot
}

protocol RevenueCatSubscriptionServicing:
    RevenueCatCustomerInfoProviding,
    RevenueCatOfferingProviding,
    RevenueCatPurchaseRestoring {}

struct OpenLARPSubscriptionAccess: Codable, Equatable {
    var isEntitled: Bool
    var status: OpenLARPSubscriptionAccessStatus
    var source: OpenLARPSubscriptionAccessSource
    var expiresAt: Date?
    var daysRemaining: Int
    var shouldShowPaywall: Bool
}

enum OpenLARPAccessControlledAction: String, Codable, CaseIterable, Identifiable {
    case confirmGoal
    case startQuest
    case swapQuest
    case skipQuest
    case submitProof
    case claimProofXP
    case runAgentScan
    case syncCareerGraph

    var id: String { rawValue }

    var label: String {
        switch self {
        case .confirmGoal: "Start a new sprint"
        case .startQuest: "Start today's quest"
        case .swapQuest: "Swap today's quest"
        case .skipQuest: "Skip today's quest"
        case .submitProof: "Submit proof"
        case .claimProofXP: "Claim proof XP"
        case .runAgentScan: "Run an agent scan"
        case .syncCareerGraph: "Sync career graph"
        }
    }
}

struct OpenLARPAccessGateDecision: Codable, Equatable {
    var action: OpenLARPAccessControlledAction
    var isAllowed: Bool
    var accessStatus: OpenLARPSubscriptionAccessStatus
    var title: String
    var message: String
    var primaryActionTitle: String
}

enum OpenLARPAccessGate {
    static func unrestrictedDecision(
        for action: OpenLARPAccessControlledAction
    ) -> OpenLARPAccessGateDecision {
        allowedDecision(action: action, accessStatus: .active)
    }

    static func decision(
        for action: OpenLARPAccessControlledAction,
        access: OpenLARPSubscriptionAccess
    ) -> OpenLARPAccessGateDecision {
        if access.isEntitled {
            return allowedDecision(action: action, accessStatus: access.status)
        }

        switch access.status {
        case .notStarted:
            if action == .confirmGoal {
                return allowedDecision(action: action, accessStatus: access.status)
            }

            return blockedDecision(
                action: action,
                accessStatus: access.status,
                title: "Start a sprint first",
                message: "Set a career goal to start your first OpenLARP sprint before using quest, proof, agent, or sync actions.",
                primaryActionTitle: "Set Goal"
            )
        case .restoreInProgress:
            return blockedDecision(
                action: action,
                accessStatus: access.status,
                title: "Restore in progress",
                message: "OpenLARP is checking your purchase status. Wait for restore to finish before continuing sprint work.",
                primaryActionTitle: "Restoring Purchases"
            )
        case .restoreFailed:
            return blockedDecision(
                action: action,
                accessStatus: access.status,
                title: "Restore needed",
                message: "OpenLARP could not restore an active subscription. Restore purchases or start a new subscription before continuing sprint work.",
                primaryActionTitle: "Restore Purchases"
            )
        case .expired:
            return blockedDecision(
                action: action,
                accessStatus: access.status,
                title: "Sprint access ended",
                message: "Your free sprint or subscription access has ended. Your saved proof stays available, but new sprint actions need active access.",
                primaryActionTitle: "Continue OpenLARP"
            )
        case .active, .freeSprint, .offline:
            return allowedDecision(action: action, accessStatus: access.status)
        }
    }

    private static func allowedDecision(
        action: OpenLARPAccessControlledAction,
        accessStatus: OpenLARPSubscriptionAccessStatus
    ) -> OpenLARPAccessGateDecision {
        OpenLARPAccessGateDecision(
            action: action,
            isAllowed: true,
            accessStatus: accessStatus,
            title: "Access ready",
            message: "Your OpenLARP sprint access is ready.",
            primaryActionTitle: action.label
        )
    }

    private static func blockedDecision(
        action: OpenLARPAccessControlledAction,
        accessStatus: OpenLARPSubscriptionAccessStatus,
        title: String,
        message: String,
        primaryActionTitle: String
    ) -> OpenLARPAccessGateDecision {
        OpenLARPAccessGateDecision(
            action: action,
            isAllowed: false,
            accessStatus: accessStatus,
            title: title,
            message: message,
            primaryActionTitle: primaryActionTitle
        )
    }
}

struct OpenLARPSubscriptionState: Codable, Equatable {
    var schemaVersion: Int
    var configuration: OpenLARPSubscriptionConfiguration
    var freeSprint: OpenLARPFreeSprintEntitlement?
    var customerInfo: RevenueCatCustomerInfoSnapshot?
    var connectionStatus: OpenLARPSubscriptionConnectionStatus
    var restoreState: OpenLARPRestoreState
    var lastUpdatedAt: Date

    init(
        schemaVersion: Int = 1,
        configuration: OpenLARPSubscriptionConfiguration = .placeholder,
        freeSprint: OpenLARPFreeSprintEntitlement? = nil,
        customerInfo: RevenueCatCustomerInfoSnapshot? = nil,
        connectionStatus: OpenLARPSubscriptionConnectionStatus = .notConfigured,
        restoreState: OpenLARPRestoreState = .empty,
        lastUpdatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.configuration = configuration
        self.freeSprint = freeSprint
        self.customerInfo = customerInfo
        self.connectionStatus = connectionStatus
        self.restoreState = restoreState
        self.lastUpdatedAt = lastUpdatedAt
    }

    static func localFreeSprint(startedAt: Date) -> OpenLARPSubscriptionState {
        OpenLARPSubscriptionState(
            freeSprint: OpenLARPFreeSprintEntitlement(
                startedAt: startedAt,
                durationDays: OpenLARPSubscriptionConfiguration.placeholder.freeSprintDurationDays
            ),
            lastUpdatedAt: startedAt
        )
    }

    static func notStarted() -> OpenLARPSubscriptionState {
        OpenLARPSubscriptionState(lastUpdatedAt: Date(timeIntervalSince1970: 0))
    }

    static func migrationDefault(startedAt: Date) -> OpenLARPSubscriptionState {
        localFreeSprint(startedAt: startedAt)
    }

    var hasStartedAccessLifecycle: Bool {
        freeSprint != nil ||
            customerInfo != nil ||
            connectionStatus != .notConfigured ||
            restoreState.status != .notStarted
    }

    func access(
        at timestamp: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> OpenLARPSubscriptionAccess {
        if let customerInfo,
           customerInfo.hasActiveEntitlement(configuration.revenueCatEntitlementID, at: timestamp) {
            return OpenLARPSubscriptionAccess(
                isEntitled: true,
                status: connectionStatus == .offline || customerInfo.isOfflineEntitlement ? .offline : .active,
                source: connectionStatus == .offline || customerInfo.isOfflineEntitlement
                    ? .revenueCatOfflineEntitlement
                    : .revenueCatCustomerInfo,
                expiresAt: customerInfo.entitlementExpirationDate,
                daysRemaining: daysRemaining(until: customerInfo.entitlementExpirationDate, at: timestamp),
                shouldShowPaywall: false
            )
        }

        if let freeSprint, freeSprint.isActive(at: timestamp, calendar: calendar) {
            return OpenLARPSubscriptionAccess(
                isEntitled: true,
                status: .freeSprint,
                source: .localFreeSprint,
                expiresAt: freeSprint.expiresAt(calendar: calendar),
                daysRemaining: freeSprint.daysRemaining(at: timestamp, calendar: calendar),
                shouldShowPaywall: false
            )
        }

        switch restoreState.status {
        case .inProgress:
            return OpenLARPSubscriptionAccess(
                isEntitled: false,
                status: .restoreInProgress,
                source: .none,
                expiresAt: nil,
                daysRemaining: 0,
                shouldShowPaywall: true
            )
        case .failed:
            return OpenLARPSubscriptionAccess(
                isEntitled: false,
                status: .restoreFailed,
                source: .none,
                expiresAt: nil,
                daysRemaining: 0,
                shouldShowPaywall: true
            )
        case .notStarted, .restored:
            break
        }

        if !hasStartedAccessLifecycle {
            return OpenLARPSubscriptionAccess(
                isEntitled: false,
                status: .notStarted,
                source: .none,
                expiresAt: nil,
                daysRemaining: 0,
                shouldShowPaywall: false
            )
        }

        return OpenLARPSubscriptionAccess(
            isEntitled: false,
            status: .expired,
            source: .none,
            expiresAt: nil,
            daysRemaining: 0,
            shouldShowPaywall: true
        )
    }

    func restoreRequested(at timestamp: Date) -> OpenLARPSubscriptionState {
        var state = self
        state.restoreState = OpenLARPRestoreState(
            status: .inProgress,
            requestedAt: timestamp,
            completedAt: nil
        )
        state.lastUpdatedAt = timestamp
        return state
    }

    func restoreSucceeded(
        with customerInfo: RevenueCatCustomerInfoSnapshot,
        at timestamp: Date
    ) -> OpenLARPSubscriptionState {
        var state = self
        state.customerInfo = customerInfo
        state.connectionStatus = .online
        state.restoreState = OpenLARPRestoreState(
            status: .restored,
            requestedAt: restoreState.requestedAt,
            completedAt: timestamp
        )
        state.lastUpdatedAt = timestamp
        return state
    }

    func restoreFailed(at timestamp: Date) -> OpenLARPSubscriptionState {
        var state = self
        state.restoreState = OpenLARPRestoreState(
            status: .failed,
            requestedAt: restoreState.requestedAt,
            completedAt: timestamp
        )
        state.lastUpdatedAt = timestamp
        return state
    }

    private func daysRemaining(until expiration: Date?, at timestamp: Date) -> Int {
        guard let expiration, timestamp < expiration else { return 0 }
        return max(1, Int(ceil(expiration.timeIntervalSince(timestamp) / 86_400)))
    }
}

@MainActor
protocol OpenLARPSubscriptionServicing {
    var subscriptionConfiguration: OpenLARPSubscriptionConfiguration { get }

    func currentOffering() async throws -> RevenueCatOfferingSnapshot?

    func synchronizeSubscriberIdentity(
        session: BackendUserSession,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState

    func resetSubscriberIdentity(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState

    func refreshSubscriptionState(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState

    func restorePurchases(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState

    func purchasePackage(
        identifier: String,
        expectedProductID: String,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionPurchaseResult
}

struct MockOpenLARPSubscriptionService: OpenLARPSubscriptionServicing {
    var subscriptionConfiguration: OpenLARPSubscriptionConfiguration
    var offering: RevenueCatOfferingSnapshot?
    var synchronizedState: OpenLARPSubscriptionState?
    var resetState: OpenLARPSubscriptionState?
    var refreshedState: OpenLARPSubscriptionState?
    var restoredCustomerInfo: RevenueCatCustomerInfoSnapshot?
    var purchaseResult: OpenLARPSubscriptionPurchaseResult?

    init(
        subscriptionConfiguration: OpenLARPSubscriptionConfiguration = .placeholder,
        offering: RevenueCatOfferingSnapshot? = nil,
        synchronizedState: OpenLARPSubscriptionState? = nil,
        resetState: OpenLARPSubscriptionState? = nil,
        refreshedState: OpenLARPSubscriptionState? = nil,
        restoredCustomerInfo: RevenueCatCustomerInfoSnapshot? = nil,
        purchaseResult: OpenLARPSubscriptionPurchaseResult? = nil
    ) {
        self.subscriptionConfiguration = subscriptionConfiguration
        self.offering = offering
        self.synchronizedState = synchronizedState
        self.resetState = resetState
        self.refreshedState = refreshedState
        self.restoredCustomerInfo = restoredCustomerInfo
        self.purchaseResult = purchaseResult
    }

    func currentOffering() async throws -> RevenueCatOfferingSnapshot? {
        offering
    }

    func synchronizeSubscriberIdentity(
        session: BackendUserSession,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        var state = synchronizedState ?? currentState
        state.lastUpdatedAt = timestamp
        return state
    }

    func resetSubscriberIdentity(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        var state = resetState ?? currentState
        state.lastUpdatedAt = timestamp
        return state
    }

    func refreshSubscriptionState(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        refreshedState ?? currentState
    }

    func restorePurchases(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        guard let restoredCustomerInfo else {
            return currentState.restoreFailed(at: timestamp)
        }
        return currentState
            .restoreRequested(at: timestamp)
            .restoreSucceeded(with: restoredCustomerInfo, at: timestamp)
    }

    func purchasePackage(
        identifier: String,
        expectedProductID: String,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionPurchaseResult {
        purchaseResult ?? OpenLARPSubscriptionPurchaseResult(
            outcome: .failed(.notConfigured),
            subscriptionState: currentState
        )
    }
}
