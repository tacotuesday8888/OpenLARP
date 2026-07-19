import Foundation
import XCTest
@testable import OpenLARP

final class LocalDataOwnershipTests: XCTestCase {
    func testGuestAndFirebaseOwnersHaveStableDistinctStorageKeys() {
        let firstAccount = OpenLARPLocalOwner.firebaseAccount(userID: "firebase-user-123")
        let sameAccount = OpenLARPLocalOwner.firebaseAccount(userID: "firebase-user-123")

        XCTAssertEqual(OpenLARPLocalOwner.guest.storageKey, "guest")
        XCTAssertEqual(firstAccount.storageKey, sameAccount.storageKey)
        XCTAssertNotEqual(firstAccount.storageKey, OpenLARPLocalOwner.guest.storageKey)
        XCTAssertTrue(firstAccount.storageKey.hasPrefix("account-"))
    }

    func testAccountContextUsesOnlyHashedDirectoryInsideOwnerRoot() throws {
        let fixture = localDataFixture()
        let rawUserID = "../../student@example.com/private"
        let owner = OpenLARPLocalOwner.firebaseAccount(userID: rawUserID)

        let context = try fixture.store.context(for: owner)

        XCTAssertEqual(context.directory.deletingLastPathComponent(), fixture.store.ownersDirectory)
        XCTAssertEqual(context.directory.lastPathComponent, owner.storageKey)
        XCTAssertFalse(context.directory.path.contains(rawUserID))
        XCTAssertFalse(context.directory.path.contains("student@example.com"))
        XCTAssertEqual(context.persistence.directory, context.directory)
        XCTAssertEqual(context.attachmentStore.directory, context.directory)
    }

    func testContextWritesAndValidatesOwnerMetadata() throws {
        let fixture = localDataFixture()
        let owner = OpenLARPLocalOwner.firebaseAccount(userID: "firebase-owner")

        let context = try fixture.store.context(for: owner)
        let metadataData = try Data(contentsOf: context.metadataURL)
        let metadata = try JSONDecoder().decode(OpenLARPLocalOwnerMetadata.self, from: metadataData)

        XCTAssertEqual(metadata.schemaVersion, OpenLARPLocalOwnerMetadata.currentSchemaVersion)
        XCTAssertEqual(metadata.storageKey, owner.storageKey)
        XCTAssertEqual(metadata.kind, .account)
        XCTAssertNoThrow(try fixture.store.context(for: owner))

        let mismatched = OpenLARPLocalOwnerMetadata(owner: .guest)
        try JSONEncoder().encode(mismatched).write(to: context.metadataURL, options: .atomic)

        XCTAssertThrowsError(try fixture.store.context(for: owner)) { error in
            XCTAssertEqual(error as? OpenLARPLocalDataError, .ownerMetadataMismatch)
        }
    }

    func testContextRejectsSymlinkedOwnerDirectory() throws {
        let fixture = localDataFixture()
        let outside = fixture.applicationSupport
            .appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture.store.ownersDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.store.ownersDirectory.appendingPathComponent("guest", isDirectory: true),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try fixture.store.context(for: .guest)) { error in
            XCTAssertEqual(error as? OpenLARPLocalDataError, .managedSymlink)
        }
    }

    func testContextRejectsSymlinkedManagedProductRoot() throws {
        let fixture = localDataFixture()
        let outside = fixture.applicationSupport.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture.applicationSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.store.productDirectory,
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try fixture.store.context(for: .guest)) { error in
            XCTAssertEqual(error as? OpenLARPLocalDataError, .managedSymlink)
        }
    }

    func testFilePolicyProtectsFilesAndControlsBackupEligibility() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let included = directory.appendingPathComponent("state.json")
        let excluded = directory.appendingPathComponent("draft.json")
        let policy = OpenLARPFilePolicy()

        try policy.write(Data("state".utf8), to: included, role: .state)
        try policy.write(Data("draft".utf8), to: excluded, role: .proofDraft)

        XCTAssertFalse(try isExcludedFromBackup(included))
        XCTAssertTrue(try isExcludedFromBackup(excluded))
        XCTAssertEqual(policy.fileProtectionType, .complete)
        if let protection = try protectionType(included) {
            XCTAssertEqual(protection, .complete)
        }
        if let protection = try protectionType(excluded) {
            XCTAssertEqual(protection, .complete)
        }
    }

    func testOwnerBoundPersistenceRejectsAStateOpenedWithAnotherOwnerKey() throws {
        let fixture = localDataFixture()
        let context = try fixture.store.context(
            for: .firebaseAccount(userID: "firebase-account-a")
        )
        var state = OpenLARPState.empty
        var goal = CareerGoal.empty
        goal.targetRole = "Account A Role"
        state.goal = goal
        try context.persistence.save(state)

        let wrongOwnerPersistence = OpenLARPPersistence(
            directory: context.directory,
            ownerKey: "account-wrong-owner"
        )

        XCTAssertThrowsError(try wrongOwnerPersistence.load()) { error in
            XCTAssertEqual(error as? OpenLARPPersistenceError, .ownerMismatch)
        }
        XCTAssertEqual(context.persistence.ownerKey, context.metadata.persistenceKey)
    }

    func testCorruptPrimaryRecoversPreviousValidatedOwnerState() throws {
        let fixture = localDataFixture()
        let context = try fixture.store.context(for: .guest)
        var first = OpenLARPState.empty
        var firstGoal = CareerGoal.empty
        firstGoal.targetRole = "Recoverable Role"
        first.goal = firstGoal
        var second = first
        second.goal?.targetRole = "Newest Role"

        try context.persistence.save(first)
        try context.persistence.save(second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.persistence.previousFileURL.path))
        try Data("corrupt-primary".utf8).write(to: context.persistence.fileURL, options: .atomic)

        let result = try context.persistence.loadWithRecovery()

        XCTAssertEqual(result.source, .recoveredPrevious)
        XCTAssertEqual(result.state.goal?.targetRole, "Recoverable Role")
        XCTAssertEqual(try context.persistence.load().goal?.targetRole, "Recoverable Role")
    }

    func testCorruptPrimaryAndPreviousArePreservedAndReported() throws {
        let fixture = localDataFixture()
        let context = try fixture.store.context(for: .guest)
        try OpenLARPFilePolicy().write(
            Data("bad-primary".utf8),
            to: context.persistence.fileURL,
            role: .state
        )
        try OpenLARPFilePolicy().write(
            Data("bad-previous".utf8),
            to: context.persistence.previousFileURL,
            role: .previousState
        )
        let primaryBefore = try Data(contentsOf: context.persistence.fileURL)
        let previousBefore = try Data(contentsOf: context.persistence.previousFileURL)

        XCTAssertThrowsError(try context.persistence.loadWithRecovery()) { error in
            XCTAssertEqual(error as? OpenLARPPersistenceError, .unrecoverableState)
        }
        XCTAssertEqual(try Data(contentsOf: context.persistence.fileURL), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: context.persistence.previousFileURL), previousBefore)
    }

    func testFutureStateSchemaIsRejectedWithoutRewritingIt() throws {
        let fixture = localDataFixture()
        let context = try fixture.store.context(for: .guest)
        try context.persistence.save(.empty)
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: context.persistence.fileURL))
                as? [String: Any]
        )
        var stateObject = try XCTUnwrap(envelope["state"] as? [String: Any])
        stateObject["schemaVersion"] = OpenLARPState.currentSchemaVersion + 1
        envelope["state"] = stateObject
        let futureData = try JSONSerialization.data(withJSONObject: envelope)
        try futureData.write(to: context.persistence.fileURL, options: .atomic)

        XCTAssertThrowsError(try context.persistence.load()) { error in
            XCTAssertEqual(
                error as? OpenLARPPersistenceError,
                .unsupportedStateSchema(OpenLARPState.currentSchemaVersion + 1)
            )
        }
        XCTAssertEqual(try Data(contentsOf: context.persistence.fileURL), futureData)
    }

    func testLegacyStateMigratesOnceAndAccountFieldsAreSanitized() throws {
        let fixture = localDataFixture()
        try FileManager.default.createDirectory(at: fixture.documents, withIntermediateDirectories: true)
        var legacy = OpenLARPState.empty
        var goal = CareerGoal.empty
        goal.targetRole = "Preserved legacy goal"
        legacy.goal = goal
        legacy.userProfile = CareerUserProfile(
            accountID: "old-account",
            email: "student@example.com",
            segment: .student,
            backgroundSummary: "Real experience"
        )
        legacy.userProfile?.privacy.allowsPrivateEvidenceCloudSync = true
        try OpenLARPPersistence(directory: fixture.documents).save(legacy)

        XCTAssertEqual(try fixture.store.migrateLegacyDataIfNeeded(), .migrated)
        let migrated = try fixture.store.context(for: .guest).persistence.load()
        XCTAssertEqual(migrated.goal?.targetRole, "Preserved legacy goal")
        XCTAssertNil(migrated.userProfile?.accountID)
        XCTAssertNil(migrated.userProfile?.email)
        XCTAssertFalse(try XCTUnwrap(migrated.userProfile).privacy.allowsPrivateEvidenceCloudSync)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.documents.appendingPathComponent("openlarp-state.json").path))
        XCTAssertEqual(try fixture.store.migrateLegacyDataIfNeeded(), .alreadyCompleted)
    }

    func testLegacyMigrationCopiesOnlyReferencedProofBytes() throws {
        let fixture = localDataFixture()
        try FileManager.default.createDirectory(at: fixture.documents, withIntermediateDirectories: true)
        let bytes = Data("referenced-proof".utf8)
        let attachment = ProofAttachment(
            fileName: "proof.png",
            contentType: "image/png",
            byteCount: bytes.count
        )
        var legacy = OpenLARPState.empty
        legacy.progress.recentProof = [
            ProofRecord(
                id: UUID(),
                questID: UUID(),
                questTitle: "Real work",
                kind: .proof,
                text: "Evidence",
                link: "",
                attachments: [attachment],
                submittedAt: .distantPast,
                quality: nil
            )
        ]
        try OpenLARPPersistence(directory: fixture.documents).save(legacy)
        try OpenLARPAttachmentStore(directory: fixture.documents).importAttachment(attachment, data: bytes)
        let unreferenced = fixture.documents.appendingPathComponent("ProofAttachments/unreferenced.png")
        try Data("do-not-copy".utf8).write(to: unreferenced)

        XCTAssertEqual(try fixture.store.migrateLegacyDataIfNeeded(), .migrated)
        let guest = try fixture.store.context(for: .guest)
        XCTAssertEqual(try guest.attachmentStore.data(for: attachment), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: guest.directory.appendingPathComponent("ProofAttachments/unreferenced.png").path))
    }

    func testUploadReadUsesIntentOwnerAndRejectsOwnerPathDisagreement() async throws {
        let fixture = localDataFixture()
        let ownerID = "firebase-account-a"
        let context = try fixture.store.context(for: .firebaseAccount(userID: ownerID))
        let bytes = Data("account-a-proof".utf8)
        let attachment = ProofAttachment(
            fileName: "account-a.png",
            contentType: "image/png",
            byteCount: bytes.count
        )
        try context.attachmentStore.importAttachment(attachment, data: bytes)
        _ = try fixture.store.context(for: .firebaseAccount(userID: "firebase-account-b"))
        let cloudAttachment = CloudProofAttachmentDocument(
            attachment: attachment,
            ownerUserID: ownerID,
            proofID: UUID()
        )
        var intent = CareerGraphSyncUploadIntent(
            proofID: cloudAttachment.proofID,
            attachment: cloudAttachment
        )

        let loadedBytes = try await fixture.store.data(for: intent)
        XCTAssertEqual(loadedBytes, bytes)
        intent.storagePath = "users/firebase-account-b/proofAttachments/\(attachment.id.uuidString)"
        do {
            _ = try await fixture.store.data(for: intent)
            XCTFail("Mismatched owner paths must fail closed.")
        } catch {
            XCTAssertEqual(error as? OpenLARPLocalDataError, .invalidUploadOwner)
        }
    }

    func testCorruptLegacyStateIsPreserved() throws {
        let fixture = localDataFixture()
        try FileManager.default.createDirectory(at: fixture.documents, withIntermediateDirectories: true)
        let legacyURL = fixture.documents.appendingPathComponent("openlarp-state.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: legacyURL)

        XCTAssertThrowsError(try fixture.store.migrateLegacyDataIfNeeded()) { error in
            XCTAssertEqual(error as? OpenLARPLocalDataError, .legacyMigrationFailed)
        }
        XCTAssertEqual(try Data(contentsOf: legacyURL), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.migrationMarkerURL.path))
    }

    func testEraseRemovesEveryOwnerAndCreatesNewGuestIdentity() throws {
        let fixture = localDataFixture()
        let oldGuest = try fixture.store.context(for: .guest)
        let account = try fixture.store.context(for: .firebaseAccount(userID: "account-a"))
        try oldGuest.persistence.save(stateWithGoal("Guest secret"))
        try account.persistence.save(stateWithGoal("Account secret"))
        let oldGuestID = oldGuest.metadata.guestID

        let freshGuest = try fixture.store.eraseAllOnDeviceData()

        XCTAssertNotEqual(freshGuest.metadata.guestID, oldGuestID)
        XCTAssertEqual(try freshGuest.persistence.load(), .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: account.directory.path))
        let ownerNames = try FileManager.default.contentsOfDirectory(atPath: fixture.store.ownersDirectory.path)
        XCTAssertEqual(ownerNames, ["guest"])
    }

    @MainActor
    func testStoreSwitchesBetweenGuestAndAccountWithoutAdoptingData() async throws {
        let fixture = localDataFixture()
        let guest = try fixture.store.context(for: .guest)
        try guest.persistence.save(stateWithGoal("Guest goal"))
        let accountSession = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase-account-a")
        let authentication = MockOpenLARPAuthenticationService(googleSignInSession: accountSession)
        let store = OpenLARPStore(
            localDataStore: fixture.store,
            authenticationService: authentication,
            backendSessionProvider: authentication,
            releaseConfiguration: .internalBeta
        )

        XCTAssertEqual(store.state.goal?.targetRole, "Guest goal")
        let exactGuestState = store.state
        await store.signInWithGoogle(presenting: nil)
        XCTAssertNil(store.state.goal)
        store.state = stateWithGoal("Account goal")
        await store.signOutOfAccount()
        XCTAssertEqual(store.state, exactGuestState)

        await store.signInWithGoogle(presenting: nil)
        XCTAssertEqual(store.state.goal?.targetRole, "Account goal")
    }

    @MainActor
    func testDelayedGuestWorkflowCannotMutateAccountAfterOwnerSwitch() async throws {
        let fixture = localDataFixture()
        let workflow = DelayedDiagnosticWorkflowService()
        let session = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase-account-a")
        let authentication = MockOpenLARPAuthenticationService(googleSignInSession: session)
        let store = OpenLARPStore(
            localDataStore: fixture.store,
            aiWorkflowService: workflow,
            authenticationService: authentication,
            backendSessionProvider: authentication,
            releaseConfiguration: .internalBeta
        )
        var goal = CareerGoal.empty
        goal.targetRole = "Guest-only delayed goal"

        let goalTask = Task { await store.confirmGoal(goal) }
        while !workflow.didStartDiagnostic { await Task.yield() }
        await store.signInWithGoogle(presenting: nil)
        workflow.resumeDiagnostic()
        await goalTask.value

        XCTAssertNil(store.state.goal)
        XCTAssertEqual(store.currentBackendSessionSnapshot().ownerUserID, session.ownerUserID)
        XCTAssertEqual(try fixture.store.context(for: .firebaseAccount(userID: session.ownerUserID)).persistence.load().goal, nil)
    }

    @MainActor
    func testStoreEraseCreatesNewStableGuestAndNeverCallsCloudDeletion() async throws {
        let fixture = localDataFixture()
        let deletion = CountingAccountDeletionService()
        let store = OpenLARPStore(
            localDataStore: fixture.store,
            accountDeletionService: deletion,
            releaseConfiguration: .internalBeta
        )
        let originalOwnerID = store.currentBackendSessionSnapshot().ownerUserID
        store.state = stateWithGoal("Erase me")

        let erased = await store.eraseAllOnDeviceData()
        XCTAssertTrue(erased)
        let replacementOwnerID = store.currentBackendSessionSnapshot().ownerUserID
        XCTAssertNotEqual(replacementOwnerID, originalOwnerID)
        XCTAssertTrue(replacementOwnerID.hasPrefix("local_"))
        XCTAssertEqual(store.state, .empty)
        XCTAssertEqual(deletion.callCount, 0)
    }

    private func localDataFixture() -> (
        store: OpenLARPLocalDataStore,
        applicationSupport: URL,
        caches: URL,
        documents: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (
            OpenLARPLocalDataStore(
                applicationSupportDirectory: root.appendingPathComponent("Application Support", isDirectory: true),
                cachesDirectory: root.appendingPathComponent("Caches", isDirectory: true),
                legacyDocumentsDirectory: root.appendingPathComponent("Documents", isDirectory: true)
            ),
            root.appendingPathComponent("Application Support", isDirectory: true),
            root.appendingPathComponent("Caches", isDirectory: true),
            root.appendingPathComponent("Documents", isDirectory: true)
        )
    }

    private func stateWithGoal(_ title: String) -> OpenLARPState {
        var state = OpenLARPState.empty
        var goal = CareerGoal.empty
        goal.targetRole = title
        state.goal = goal
        return state
    }

    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }

    private func protectionType(_ url: URL) throws -> FileProtectionType? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
    }
}

@MainActor
private final class DelayedDiagnosticWorkflowService: V0AIWorkflowServicing {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var didStartDiagnostic = false
    private let base = LocalMockV0AIWorkflowService()

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        didStartDiagnostic = true
        await withCheckedContinuation { continuation = $0 }
        return try await base.generateDiagnostic(request)
    }

    func resumeDiagnostic() {
        continuation?.resume()
        continuation = nil
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        try await base.generateQuestPlan(request)
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        try await base.reviewProof(request)
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        try await base.summarizeProgress(request)
    }
}

@MainActor
private final class CountingAccountDeletionService: AccountDeletionServicing {
    private(set) var callCount = 0

    func deleteAccount(_ request: AccountDeletionRequest) async throws -> AccountDeletionResult {
        callCount += 1
        return AccountDeletionResult(request: request)
    }
}
