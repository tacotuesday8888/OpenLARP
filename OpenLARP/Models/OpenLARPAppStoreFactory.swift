import Foundation

@MainActor
struct OpenLARPAppStoreFactory {
    typealias FirebaseBootstrap = @MainActor () -> Void
    typealias InternalStoreBuilder = @MainActor (OpenLARPReleaseConfiguration) -> OpenLARPStore

    private let localPersistence: OpenLARPPersistence
    private let localAttachmentStore: OpenLARPAttachmentStore
    private let firebaseBootstrap: FirebaseBootstrap
    private let internalStoreBuilder: InternalStoreBuilder

    init(
        localPersistence: OpenLARPPersistence = .live,
        localAttachmentStore: OpenLARPAttachmentStore = .live,
        firebaseBootstrap: @escaping FirebaseBootstrap = {
            _ = OpenLARPFirebaseBootstrap.configureIfAvailable()
        },
        internalStoreBuilder: @escaping InternalStoreBuilder = OpenLARPAppStoreFactory.makeFirebaseBetaStore
    ) {
        self.localPersistence = localPersistence
        self.localAttachmentStore = localAttachmentStore
        self.firebaseBootstrap = firebaseBootstrap
        self.internalStoreBuilder = internalStoreBuilder
    }

    func makeStore(for configuration: OpenLARPReleaseConfiguration) -> OpenLARPStore {
        switch configuration.serviceMode {
        case .localOnly:
            return OpenLARPStore(
                persistence: localPersistence,
                attachmentStore: localAttachmentStore,
                aiWorkflowService: LocalMockV0AIWorkflowService(),
                agentService: MockCareerAgentService(),
                careerGraphSyncService: LocalMockCareerGraphSyncService(),
                authenticationService: MockOpenLARPAuthenticationService(),
                backendEventSyncService: LocalMockBackendEventSyncService(),
                privateEvidenceCloudSyncConsentService: LocalMockPrivateEvidenceCloudSyncConsentService(),
                privateEvidenceBackupCleanupService: LocalMockPrivateEvidenceBackupCleanupService(),
                accountDeletionService: LocalMockAccountDeletionService(),
                backendSessionProvider: LocalMockBackendSessionProvider(),
                subscriptionService: MockOpenLARPSubscriptionService(),
                releaseConfiguration: configuration
            )
        case .firebaseBeta:
            firebaseBootstrap()
            return internalStoreBuilder(configuration)
        }
    }

    private static func makeFirebaseBetaStore(
        configuration: OpenLARPReleaseConfiguration
    ) -> OpenLARPStore {
        let attachmentStore = OpenLARPAttachmentStore.live
        let authenticationService = FirebaseOpenLARPAuthenticationService()
        let aiWorkflowService = FallbackV0AIWorkflowService(
            primary: FirebaseCallableV0AIWorkflowService(),
            fallback: LocalMockV0AIWorkflowService()
        )

        return OpenLARPStore(
            attachmentStore: attachmentStore,
            aiWorkflowService: aiWorkflowService,
            careerGraphSyncService: FirebaseReadyCareerGraphSyncService(
                firebaseService: FirebaseFirestoreCareerGraphSyncService(
                    attachmentDataProvider: attachmentStore,
                    proofAttachmentReceiptPromoter: FirebaseCallableProofAttachmentReceiptPromoter()
                )
            ),
            authenticationService: authenticationService,
            backendEventSyncService: FirebaseReadyBackendEventSyncService(),
            privateEvidenceCloudSyncConsentService: FirebaseCallablePrivateEvidenceCloudSyncConsentService(),
            privateEvidenceBackupCleanupService: FirebaseCallablePrivateEvidenceBackupCleanupService(),
            accountDeletionService: FirebaseCallableAccountDeletionService(),
            subscriptionService: OpenLARPRevenueCatSubscriptionService.live(),
            releaseConfiguration: configuration
        )
    }
}
