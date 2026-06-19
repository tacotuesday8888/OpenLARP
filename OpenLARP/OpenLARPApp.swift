import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        OpenLARPFirebaseBootstrap.configureIfAvailable()
        let attachmentStore = OpenLARPAttachmentStore.live
        let authenticationService = FirebaseOpenLARPAuthenticationService()
        let aiWorkflowService = FallbackV0AIWorkflowService(
            primary: FirebaseCallableV0AIWorkflowService(),
            fallback: LocalMockV0AIWorkflowService()
        )
        _store = State(
            initialValue: OpenLARPStore(
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
                subscriptionService: OpenLARPRevenueCatSubscriptionService.live()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
