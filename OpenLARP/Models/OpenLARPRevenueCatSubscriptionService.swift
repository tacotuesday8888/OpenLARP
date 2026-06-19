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
    func currentOfferingSnapshot() async throws -> RevenueCatOfferingSnapshot?
}

struct OpenLARPRevenueCatSubscriptionService: OpenLARPSubscriptionServicing {
    var runtimeConfiguration: OpenLARPRevenueCatRuntimeConfiguration
    var client: any OpenLARPRevenueCatClient

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

    func currentOfferingSnapshot() async throws -> RevenueCatOfferingSnapshot? {
        guard Purchases.isConfigured else {
            throw OpenLARPRevenueCatAdapterError.notConfigured
        }

        guard let currentOffering = try await Purchases.shared.offerings().current else {
            return nil
        }

        return OpenLARPRevenueCatSnapshotMapper.snapshot(from: currentOffering)
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
