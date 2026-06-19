import Foundation
import RevenueCat

enum OpenLARPRevenueCatConfigurationKey: String, CaseIterable {
    case iosAPIKey = "REVENUECAT_IOS_API_KEY"
    case entitlementID = "REVENUECAT_ENTITLEMENT_ID"
    case offeringID = "REVENUECAT_OFFERING_ID"
    case monthlyProductID = "REVENUECAT_MONTHLY_PRODUCT_ID"
    case studentMonthlyProductID = "REVENUECAT_STUDENT_MONTHLY_PRODUCT_ID"
}

enum OpenLARPRevenueCatAdapterError: Error, Equatable {
    case notConfigured
    case noCurrentOffering
    case packageUnavailable
}

struct OpenLARPRevenueCatRuntimeConfiguration: Equatable {
    static let defaultPlistName = "RevenueCat-Info"

    var publicIOSAPIKey: String?
    var subscriptionConfiguration: OpenLARPSubscriptionConfiguration

    var normalizedPublicIOSAPIKey: String? {
        guard let apiKey = publicIOSAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              (apiKey.hasPrefix("appl_") || apiKey.hasPrefix("test_")),
              apiKey.count > "test_".count
        else {
            return nil
        }
        return apiKey
    }

    var canConfigureLiveSDK: Bool {
        normalizedPublicIOSAPIKey != nil
    }

    init(
        publicIOSAPIKey: String? = nil,
        subscriptionConfiguration: OpenLARPSubscriptionConfiguration = .placeholder
    ) {
        self.publicIOSAPIKey = publicIOSAPIKey
        self.subscriptionConfiguration = subscriptionConfiguration
    }

    static func fromMainBundle(
        bundle: Bundle = .main,
        plistName: String = defaultPlistName
    ) -> OpenLARPRevenueCatRuntimeConfiguration {
        guard let url = bundle.url(forResource: plistName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else {
            return OpenLARPRevenueCatRuntimeConfiguration()
        }

        return fromDictionary(values)
    }

    static func fromDictionary(_ values: [String: Any]) -> OpenLARPRevenueCatRuntimeConfiguration {
        let placeholder = OpenLARPSubscriptionConfiguration.placeholder
        let configuration = OpenLARPSubscriptionConfiguration(
            revenueCatEntitlementID: stringValue(
                for: .entitlementID,
                in: values
            ) ?? placeholder.revenueCatEntitlementID,
            monthlyProductID: stringValue(for: .monthlyProductID, in: values) ?? placeholder.monthlyProductID,
            defaultOfferingID: stringValue(for: .offeringID, in: values) ?? placeholder.defaultOfferingID,
            studentMonthlyProductID: stringValue(
                for: .studentMonthlyProductID,
                in: values
            ) ?? placeholder.studentMonthlyProductID,
            freeSprintDurationDays: placeholder.freeSprintDurationDays
        )

        return OpenLARPRevenueCatRuntimeConfiguration(
            publicIOSAPIKey: stringValue(for: .iosAPIKey, in: values),
            subscriptionConfiguration: configuration
        )
    }

    private static func stringValue(
        for key: OpenLARPRevenueCatConfigurationKey,
        in values: [String: Any]
    ) -> String? {
        guard let rawValue = values[key.rawValue] as? String else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
protocol OpenLARPRevenueCatClient {
    func configureIfNeeded(publicIOSAPIKey: String)
    func customerInfoSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot
    func restorePurchasesSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot
    func logInSubscriberSnapshot(
        appUserID: String,
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot
    func logOutSubscriberSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot
    func offeringSnapshot(
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatOfferingSnapshot?
    func purchasePackageSnapshot(
        identifier: String,
        expectedProductID: String,
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> OpenLARPRevenueCatPurchaseClientResult
}

enum OpenLARPRevenueCatPurchaseClientResult: Equatable {
    case purchased(RevenueCatCustomerInfoSnapshot)
    case cancelled
}

enum OpenLARPRevenueCatPurchaseValidator {
    static func isExpectedConfiguredProduct(
        productID: String,
        expectedProductID: String,
        configuration: OpenLARPSubscriptionConfiguration
    ) -> Bool {
        let normalizedProductID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExpectedProductID = expectedProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedProductID == normalizedExpectedProductID &&
            configuration.isConfiguredPurchaseProductID(normalizedProductID)
    }
}

struct OpenLARPRevenueCatSubscriptionService: OpenLARPSubscriptionServicing {
    var runtimeConfiguration: OpenLARPRevenueCatRuntimeConfiguration
    var client: any OpenLARPRevenueCatClient
    var subscriptionConfiguration: OpenLARPSubscriptionConfiguration {
        runtimeConfiguration.subscriptionConfiguration
    }

    init(
        runtimeConfiguration: OpenLARPRevenueCatRuntimeConfiguration = .fromMainBundle(),
        client: any OpenLARPRevenueCatClient = OpenLARPRevenueCatPurchasesClient.shared
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.client = client
    }

    static func live(bundle: Bundle = .main) -> OpenLARPRevenueCatSubscriptionService {
        OpenLARPRevenueCatSubscriptionService(
            runtimeConfiguration: .fromMainBundle(bundle: bundle),
            client: OpenLARPRevenueCatPurchasesClient.shared
        )
    }

    func currentOffering() async throws -> RevenueCatOfferingSnapshot? {
        guard let publicIOSAPIKey = runtimeConfiguration.normalizedPublicIOSAPIKey else {
            return nil
        }

        client.configureIfNeeded(publicIOSAPIKey: publicIOSAPIKey)
        return try await client.offeringSnapshot(
            configuration: runtimeConfiguration.subscriptionConfiguration
        )
    }

    func synchronizeSubscriberIdentity(
        session: BackendUserSession,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        var synced = currentState
        synced.configuration = runtimeConfiguration.subscriptionConfiguration
        synced.lastUpdatedAt = timestamp

        guard session.isAuthenticated else { return synced }
        let appUserID = session.ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appUserID.isEmpty else { return synced }
        synced.customerInfo = nil
        guard let publicIOSAPIKey = runtimeConfiguration.normalizedPublicIOSAPIKey else {
            synced.connectionStatus = .notConfigured
            return synced
        }

        client.configureIfNeeded(publicIOSAPIKey: publicIOSAPIKey)

        do {
            synced.customerInfo = try await client.logInSubscriberSnapshot(
                appUserID: appUserID,
                at: timestamp,
                configuration: runtimeConfiguration.subscriptionConfiguration
            )
            synced.connectionStatus = .online
            synced.lastUpdatedAt = timestamp
            return synced
        } catch {
            synced.connectionStatus = .failed
            synced.lastUpdatedAt = timestamp
            return synced
        }
    }

    func resetSubscriberIdentity(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        var reset = currentState
        reset.configuration = runtimeConfiguration.subscriptionConfiguration
        reset.customerInfo = nil
        reset.connectionStatus = .notConfigured
        reset.lastUpdatedAt = timestamp

        guard let publicIOSAPIKey = runtimeConfiguration.normalizedPublicIOSAPIKey else {
            return reset
        }

        client.configureIfNeeded(publicIOSAPIKey: publicIOSAPIKey)

        do {
            reset.customerInfo = try await client.logOutSubscriberSnapshot(
                at: timestamp,
                configuration: runtimeConfiguration.subscriptionConfiguration
            )
            reset.connectionStatus = .online
            reset.lastUpdatedAt = timestamp
            return reset
        } catch {
            reset.connectionStatus = .failed
            reset.lastUpdatedAt = timestamp
            return reset
        }
    }

    func refreshSubscriptionState(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        var refreshed = currentState
        refreshed.configuration = runtimeConfiguration.subscriptionConfiguration
        refreshed.lastUpdatedAt = timestamp

        guard let publicIOSAPIKey = runtimeConfiguration.normalizedPublicIOSAPIKey else {
            refreshed.connectionStatus = .notConfigured
            return refreshed
        }

        client.configureIfNeeded(publicIOSAPIKey: publicIOSAPIKey)

        do {
            refreshed.customerInfo = try await client.customerInfoSnapshot(
                at: timestamp,
                configuration: runtimeConfiguration.subscriptionConfiguration
            )
            refreshed.connectionStatus = .online
            refreshed.lastUpdatedAt = timestamp
            return refreshed
        } catch {
            refreshed.connectionStatus = refreshed.customerInfo?.hasActiveEntitlement(
                runtimeConfiguration.subscriptionConfiguration.revenueCatEntitlementID,
                at: timestamp
            ) == true ? .offline : .failed
            refreshed.lastUpdatedAt = timestamp
            return refreshed
        }
    }

    func restorePurchases(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        var restoring = currentState
        restoring.configuration = runtimeConfiguration.subscriptionConfiguration
        restoring.lastUpdatedAt = timestamp

        guard let publicIOSAPIKey = runtimeConfiguration.normalizedPublicIOSAPIKey else {
            return restoring.restoreFailed(at: timestamp)
        }

        client.configureIfNeeded(publicIOSAPIKey: publicIOSAPIKey)

        do {
            let customerInfo = try await client.restorePurchasesSnapshot(
                at: timestamp,
                configuration: runtimeConfiguration.subscriptionConfiguration
            )
            restoring.customerInfo = customerInfo
            restoring.connectionStatus = .online

            guard customerInfo.hasActiveEntitlement(
                runtimeConfiguration.subscriptionConfiguration.revenueCatEntitlementID,
                at: timestamp
            ) else {
                return restoring.restoreFailed(at: timestamp)
            }

            return restoring.restoreSucceeded(with: customerInfo, at: timestamp)
        } catch {
            return restoring.restoreFailed(at: timestamp)
        }
    }

    func purchasePackage(
        identifier: String,
        expectedProductID: String,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionPurchaseResult {
        var purchasedState = currentState
        purchasedState.configuration = runtimeConfiguration.subscriptionConfiguration
        purchasedState.lastUpdatedAt = timestamp

        guard let publicIOSAPIKey = runtimeConfiguration.normalizedPublicIOSAPIKey else {
            return OpenLARPSubscriptionPurchaseResult(
                outcome: .failed(.notConfigured),
                subscriptionState: purchasedState
            )
        }

        guard OpenLARPRevenueCatPurchaseValidator.isExpectedConfiguredProduct(
            productID: expectedProductID,
            expectedProductID: expectedProductID,
            configuration: runtimeConfiguration.subscriptionConfiguration
        ) else {
            return OpenLARPSubscriptionPurchaseResult(
                outcome: .failed(.packageUnavailable),
                subscriptionState: purchasedState
            )
        }

        client.configureIfNeeded(publicIOSAPIKey: publicIOSAPIKey)

        do {
            let result = try await client.purchasePackageSnapshot(
                identifier: identifier,
                expectedProductID: expectedProductID,
                at: timestamp,
                configuration: runtimeConfiguration.subscriptionConfiguration
            )

            switch result {
            case .cancelled:
                return OpenLARPSubscriptionPurchaseResult(
                    outcome: .cancelled,
                    subscriptionState: purchasedState
                )
            case .purchased(let customerInfo):
                purchasedState.customerInfo = customerInfo
                purchasedState.connectionStatus = .online

                guard customerInfo.hasActiveEntitlement(
                    runtimeConfiguration.subscriptionConfiguration.revenueCatEntitlementID,
                    at: timestamp
                ) else {
                    return OpenLARPSubscriptionPurchaseResult(
                        outcome: .failed(.entitlementMissingAfterPurchase),
                        subscriptionState: purchasedState
                    )
                }

                return OpenLARPSubscriptionPurchaseResult(
                    outcome: .purchased,
                    subscriptionState: purchasedState
                )
            }
        } catch let error as OpenLARPRevenueCatAdapterError {
            return OpenLARPSubscriptionPurchaseResult(
                outcome: .failed(subscriptionPurchaseFailure(for: error)),
                subscriptionState: purchasedState
            )
        } catch {
            return OpenLARPSubscriptionPurchaseResult(
                outcome: .failed(.storeError),
                subscriptionState: purchasedState
            )
        }
    }

    private func subscriptionPurchaseFailure(
        for error: OpenLARPRevenueCatAdapterError
    ) -> OpenLARPSubscriptionPurchaseFailure {
        switch error {
        case .notConfigured:
            .notConfigured
        case .noCurrentOffering:
            .noCurrentOffering
        case .packageUnavailable:
            .packageUnavailable
        }
    }
}

@MainActor
final class OpenLARPRevenueCatPurchasesClient: OpenLARPRevenueCatClient {
    static let shared = OpenLARPRevenueCatPurchasesClient()

    private var configuredPublicIOSAPIKey: String?

    private init() {}

    func configureIfNeeded(publicIOSAPIKey: String) {
        if Purchases.isConfigured {
            configuredPublicIOSAPIKey = configuredPublicIOSAPIKey ?? publicIOSAPIKey
            return
        }

        Purchases.configure(withAPIKey: publicIOSAPIKey)
        configuredPublicIOSAPIKey = publicIOSAPIKey
    }

    func customerInfoSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        let customerInfo = try await Purchases.shared.customerInfo()
        return OpenLARPRevenueCatSnapshotMapper.snapshot(
            from: customerInfo,
            fallbackFetchedAt: timestamp,
            configuration: configuration
        )
    }

    func restorePurchasesSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        let customerInfo = try await Purchases.shared.restorePurchases()
        return OpenLARPRevenueCatSnapshotMapper.snapshot(
            from: customerInfo,
            fallbackFetchedAt: timestamp,
            configuration: configuration
        )
    }

    func logInSubscriberSnapshot(
        appUserID: String,
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        let result = try await Purchases.shared.logIn(appUserID)
        return OpenLARPRevenueCatSnapshotMapper.snapshot(
            from: result.customerInfo,
            fallbackFetchedAt: timestamp,
            configuration: configuration
        )
    }

    func logOutSubscriberSnapshot(
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatCustomerInfoSnapshot {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        let customerInfo: CustomerInfo
        if Purchases.shared.isAnonymous {
            customerInfo = try await Purchases.shared.customerInfo()
        } else {
            customerInfo = try await Purchases.shared.logOut()
        }

        return OpenLARPRevenueCatSnapshotMapper.snapshot(
            from: customerInfo,
            fallbackFetchedAt: timestamp,
            configuration: configuration
        )
    }

    func offeringSnapshot(
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> RevenueCatOfferingSnapshot? {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        guard let offering = try await Purchases.shared.offerings().offering(
            identifier: configuration.revenueCatOfferingID
        ) else {
            return nil
        }

        return OpenLARPRevenueCatSnapshotMapper.snapshot(from: offering)
    }

    func purchasePackageSnapshot(
        identifier: String,
        expectedProductID: String,
        at timestamp: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) async throws -> OpenLARPRevenueCatPurchaseClientResult {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        guard let offering = try await Purchases.shared.offerings().offering(
            identifier: configuration.revenueCatOfferingID
        ) else {
            throw OpenLARPRevenueCatAdapterError.noCurrentOffering
        }
        guard let package = offering.availablePackages.first(where: { $0.identifier == identifier }) else {
            throw OpenLARPRevenueCatAdapterError.packageUnavailable
        }
        guard OpenLARPRevenueCatPurchaseValidator.isExpectedConfiguredProduct(
            productID: package.storeProduct.productIdentifier,
            expectedProductID: expectedProductID,
            configuration: configuration
        ) else {
            throw OpenLARPRevenueCatAdapterError.packageUnavailable
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return .cancelled
            }

            return .purchased(
                OpenLARPRevenueCatSnapshotMapper.snapshot(
                    from: result.customerInfo,
                    fallbackFetchedAt: timestamp,
                    configuration: configuration
                )
            )
        } catch {
            if Self.isPurchaseCancellation(error) {
                return .cancelled
            }
            throw error
        }
    }

    private static func isPurchaseCancellation(_ error: Error) -> Bool {
        if let revenueCatError = error as? ErrorCode,
           revenueCatError == .purchaseCancelledError {
            return true
        }

        let nsError = error as NSError
        let purchaseCancelledError = ErrorCode.purchaseCancelledError as NSError
        return nsError.domain == purchaseCancelledError.domain &&
            nsError.code == purchaseCancelledError.code
    }
}

enum OpenLARPRevenueCatSnapshotMapper {
    static func snapshot(
        fetchedAt: Date,
        activeEntitlementIDs: [String],
        activeProductIDs: [String],
        entitlementExpirationDate: Date?,
        managementURLString: String?,
        isOfflineEntitlement: Bool = false
    ) -> RevenueCatCustomerInfoSnapshot {
        RevenueCatCustomerInfoSnapshot(
            fetchedAt: fetchedAt,
            activeEntitlementIDs: Array(Set(activeEntitlementIDs)).sorted(),
            activeProductIDs: Array(Set(activeProductIDs)).sorted(),
            entitlementExpirationDate: entitlementExpirationDate,
            managementURLString: managementURLString,
            isOfflineEntitlement: isOfflineEntitlement
        )
    }

    static func subscriptionPeriodDescription(value: Int, unit: String) -> String {
        let normalizedUnit = value == 1 ? unit : "\(unit)s"
        return "\(value) \(normalizedUnit)"
    }

    static func subscriptionPeriodDescription(from period: SubscriptionPeriod?) -> String? {
        guard let period else { return nil }

        switch period.unit {
        case .day:
            return subscriptionPeriodDescription(value: period.value, unit: "day")
        case .week:
            return subscriptionPeriodDescription(value: period.value, unit: "week")
        case .month:
            return subscriptionPeriodDescription(value: period.value, unit: "month")
        case .year:
            return subscriptionPeriodDescription(value: period.value, unit: "year")
        @unknown default:
            return nil
        }
    }

    static func snapshot(
        from customerInfo: CustomerInfo,
        fallbackFetchedAt: Date,
        configuration: OpenLARPSubscriptionConfiguration
    ) -> RevenueCatCustomerInfoSnapshot {
        let activeEntitlements = customerInfo.entitlements.activeInCurrentEnvironment
        let activeProductIDs = Set(customerInfo.activeSubscriptions)
            .union(activeEntitlements.values.map(\.productIdentifier))

        return snapshot(
            fetchedAt: customerInfo.requestDate,
            activeEntitlementIDs: Array(activeEntitlements.keys),
            activeProductIDs: Array(activeProductIDs),
            entitlementExpirationDate: customerInfo.expirationDate(
                forEntitlement: configuration.revenueCatEntitlementID
            ),
            managementURLString: customerInfo.managementURL?.absoluteString,
            isOfflineEntitlement: false
        )
    }

    static func snapshot(from offering: Offering) -> RevenueCatOfferingSnapshot {
        RevenueCatOfferingSnapshot(
            identifier: offering.identifier,
            packages: offering.availablePackages.map(snapshot(from:))
        )
    }

    static func snapshot(from package: Package) -> RevenueCatPackageSnapshot {
        RevenueCatPackageSnapshot(
            identifier: package.identifier,
            product: snapshot(from: package.storeProduct)
        )
    }

    static func snapshot(from product: StoreProduct) -> RevenueCatProductSnapshot {
        RevenueCatProductSnapshot(
            productID: product.productIdentifier,
            displayName: product.localizedTitle,
            displayPrice: product.localizedPriceString,
            subscriptionPeriod: subscriptionPeriodDescription(from: product.subscriptionPeriod)
        )
    }
}
