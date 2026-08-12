import Foundation

@MainActor
struct OpenLARPAppStoreFactory {
    #if OPENLARP_INTERNAL_SERVICES
    typealias FirebaseBootstrap = @MainActor () -> Void
    typealias InternalStoreBuilder = @MainActor (OpenLARPReleaseConfiguration) -> OpenLARPStore
    #endif

    private let localPersistence: OpenLARPPersistence
    private let localAttachmentStore: OpenLARPAttachmentStore
    private let localDataStore: OpenLARPLocalDataStore?
    private let now: () -> Date
    #if OPENLARP_INTERNAL_SERVICES
    private let firebaseBootstrap: FirebaseBootstrap
    private let internalStoreBuilder: InternalStoreBuilder
    #endif

    #if OPENLARP_INTERNAL_SERVICES
    init(
        localPersistence: OpenLARPPersistence = .live,
        localAttachmentStore: OpenLARPAttachmentStore = .live,
        localDataStore: OpenLARPLocalDataStore? = nil,
        now: @escaping () -> Date = { Date() },
        firebaseBootstrap: @escaping FirebaseBootstrap = {
            _ = OpenLARPFirebaseBootstrap.configureIfAvailable()
        },
        internalStoreBuilder: @escaping InternalStoreBuilder = OpenLARPAppStoreFactory.makeFirebaseBetaStore
    ) {
        self.localPersistence = localPersistence
        self.localAttachmentStore = localAttachmentStore
        self.localDataStore = localDataStore
        self.now = now
        self.firebaseBootstrap = firebaseBootstrap
        self.internalStoreBuilder = internalStoreBuilder
    }
    #else
    init(
        localPersistence: OpenLARPPersistence = .live,
        localAttachmentStore: OpenLARPAttachmentStore = .live,
        localDataStore: OpenLARPLocalDataStore? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.localPersistence = localPersistence
        self.localAttachmentStore = localAttachmentStore
        self.localDataStore = localDataStore
        self.now = now
    }
    #endif

    func makeStore(for configuration: OpenLARPReleaseConfiguration) -> OpenLARPStore {
        switch configuration.serviceMode {
        case .localOnly:
            return makeLocalStore(for: configuration)
        case .firebaseBeta:
            #if OPENLARP_INTERNAL_SERVICES
            firebaseBootstrap()
            return internalStoreBuilder(configuration)
            #else
            return makeLocalStore(for: .appStoreMVP)
            #endif
        }
    }

    private func makeLocalStore(
        for configuration: OpenLARPReleaseConfiguration
    ) -> OpenLARPStore {
        OpenLARPStore(
            persistence: localPersistence,
            attachmentStore: localAttachmentStore,
            localDataStore: localDataStore,
            aiWorkflowService: LocalMockV0AIWorkflowService(),
            agentService: MockCareerAgentService(),
            careerGraphSyncService: LocalMockCareerGraphSyncService(),
            careerStateSyncService: LocalMockCareerStateSyncService(),
            authenticationService: MockOpenLARPAuthenticationService(),
            backendEventSyncService: LocalMockBackendEventSyncService(),
            privateEvidenceCloudSyncConsentService: LocalMockPrivateEvidenceCloudSyncConsentService(),
            privateEvidenceBackupCleanupService: LocalMockPrivateEvidenceBackupCleanupService(),
            accountDeletionService: LocalMockAccountDeletionService(),
            backendSessionProvider: LocalMockBackendSessionProvider(),
            subscriptionService: MockOpenLARPSubscriptionService(),
            releaseConfiguration: configuration,
            now: now
        )
    }

    #if OPENLARP_INTERNAL_SERVICES
    private static func makeFirebaseBetaStore(
        configuration: OpenLARPReleaseConfiguration
    ) -> OpenLARPStore {
        let localDataStore = OpenLARPLocalDataStore.live
        let authenticationService = FirebaseOpenLARPAuthenticationService()
        let aiWorkflowService = FallbackV0AIWorkflowService(
            primary: FirebaseCallableV0AIWorkflowService(),
            fallback: LocalMockV0AIWorkflowService()
        )

        return OpenLARPStore(
            localDataStore: localDataStore,
            aiWorkflowService: aiWorkflowService,
            careerGraphSyncService: FirebaseReadyCareerGraphSyncService(
                firebaseService: FirebaseFirestoreCareerGraphSyncService(
                    attachmentDataProvider: localDataStore,
                    proofAttachmentReceiptPromoter: FirebaseCallableProofAttachmentReceiptPromoter()
                )
            ),
            careerStateSyncService: FirebaseCallableCareerStateSyncService(),
            authenticationService: authenticationService,
            backendEventSyncService: FirebaseReadyBackendEventSyncService(),
            privateEvidenceCloudSyncConsentService: FirebaseCallablePrivateEvidenceCloudSyncConsentService(),
            privateEvidenceBackupCleanupService: FirebaseCallablePrivateEvidenceBackupCleanupService(),
            accountDeletionService: FirebaseCallableAccountDeletionService(),
            subscriptionService: OpenLARPRevenueCatSubscriptionService.live(),
            releaseConfiguration: configuration
        )
    }
    #endif
}
