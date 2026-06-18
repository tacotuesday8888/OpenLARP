import XCTest
@testable import OpenLARP

@MainActor
final class FirebaseCareerGraphSyncReadinessTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .newGrad,
        targetRole: "AI product engineer",
        timeline: "30 days",
        background: "Recent graduate with one AI prototype.",
        existingProof: "Prototype demo and project notes.",
        confidence: 3,
        biggestBlocker: "Needs stronger product proof."
    )

    func testFirebaseCareerGraphSyncWritesAuthenticatedFirestoreMetadata() async throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let state = careerGraphStateWithProof(now: now)
        let session = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_graph",
            accountID: "private-account",
            email: "private@example.com"
        )
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let dataProvider = StaticProofAttachmentDataProvider()
        let uploader = CapturingProofAttachmentUploader()
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: dataProvider,
            proofAttachmentUploader: uploader
        )

        let result = try await service.prepareSync(request)

        XCTAssertEqual(result.status, .synced)
        XCTAssertTrue(result.didContactNetwork)
        XCTAssertFalse(result.requiresAuthenticationToSync)
        XCTAssertEqual(writer.writes.map(\.documentPath), result.firestoreDocumentPaths)
        XCTAssertTrue(writer.writes.contains {
            $0.documentType == .profile && $0.documentPath.hasPrefix("users/firebase_uid_graph/profiles/")
        })
        XCTAssertTrue(writer.writes.contains {
            $0.documentType == .goal && $0.documentPath == "users/firebase_uid_graph/goals/current"
        })
        XCTAssertTrue(writer.writes.contains {
            $0.documentType == .targetRole && $0.documentPath.hasPrefix("users/firebase_uid_graph/targetRoles/")
        })
        XCTAssertTrue(writer.writes.contains {
            $0.documentType == .proofRecord && $0.documentPath.hasPrefix("users/firebase_uid_graph/proofRecords/")
        })
        XCTAssertTrue(writer.writes.contains {
            $0.documentType == .proofAttachment && $0.documentPath.hasPrefix("users/firebase_uid_graph/proofAttachments/")
        })
        XCTAssertTrue(writer.writes.contains {
            $0.documentType == .readinessSnapshot && $0.documentPath.hasPrefix("users/firebase_uid_graph/readinessSnapshots/")
        })
        XCTAssertEqual(result.uploadIntents.map(\.storagePath), [
            "users/firebase_uid_graph/proofAttachments/E1E1E1E1-E1E1-E1E1-E1E1-E1E1E1E1E1E1"
        ])
        XCTAssertEqual(uploader.requests.map(\.uploadIntent.storagePath), result.uploadIntents.map(\.storagePath))
        XCTAssertEqual(uploader.requests.first?.data.count, 32_000)
        XCTAssertEqual(result.uploadReceipts.map(\.status), [.uploaded])
        XCTAssertEqual(result.uploadReceipts.first?.storageBucket, "openlarp-test.appspot.com")
        let proofRecordWrite = try XCTUnwrap(writer.writes.first { $0.documentType == .proofRecord })
        XCTAssertFalse(proofRecordWrite.merge)
        let attachmentWrite = try XCTUnwrap(writer.writes.first { $0.documentType == .proofAttachment })
        XCTAssertTrue(attachmentWrite.merge)
        XCTAssertEqual(attachmentWrite.data["uploadStatus"] as? String, CareerGraphSyncUploadStatus.uploaded.rawValue)
        XCTAssertNotNil(attachmentWrite.data["uploadReceipt"])
        XCTAssertNil(attachmentWrite.data["localRelativePath"])
        XCTAssertFalse(String(describing: writer.writes).contains("private@example.com"))
        XCTAssertFalse(String(describing: writer.writes).contains("private-account"))
    }

    func testFirebaseReadyCareerGraphSyncFallsBackToLocalPreviewWhenUnauthenticated() async throws {
        let now = Date(timeIntervalSince1970: 40_500)
        let state = careerGraphStateWithProof(now: now)
        let session = BackendUserSession.localOnly(for: state)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let firebaseService = FirebaseFirestoreCareerGraphSyncService(writer: writer)
        let readyService = FirebaseReadyCareerGraphSyncService(firebaseService: firebaseService)

        let result = try await readyService.prepareSync(request)

        XCTAssertEqual(result.status, .preparedLocally)
        XCTAssertFalse(result.didContactNetwork)
        XCTAssertTrue(result.requiresAuthenticationToSync)
        XCTAssertTrue(writer.writes.isEmpty)
        XCTAssertTrue(result.firestoreDocumentPaths.contains {
            $0.hasPrefix("users/\(session.ownerUserID)/proofRecords/")
        })
    }

    func testFirebaseCareerGraphSyncDoesNotWritePrivateProofByDefault() async throws {
        let now = Date(timeIntervalSince1970: 41_000)
        let state = careerGraphStateWithProof(now: now)
        let session = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_default")
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: false
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: StaticProofAttachmentDataProvider(),
            proofAttachmentUploader: CapturingProofAttachmentUploader()
        )

        let result = try await service.prepareSync(request)

        XCTAssertEqual(result.status, .synced)
        XCTAssertFalse(writer.writes.map(\.documentType).contains(.proofRecord))
        XCTAssertFalse(writer.writes.map(\.documentType).contains(.proofAttachment))
        XCTAssertTrue(result.uploadIntents.isEmpty)
        XCTAssertTrue(result.uploadReceipts.isEmpty)
    }

    func testDirectFirebaseCareerGraphSyncRequiresAuthentication() async {
        let now = Date(timeIntervalSince1970: 41_500)
        let state = careerGraphStateWithProof(now: now)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: BackendUserSession.localOnly(for: state),
            requestedAt: now,
            includePrivateEvidence: true
        )
        let service = FirebaseFirestoreCareerGraphSyncService(writer: CapturingCareerGraphDocumentWriter())

        do {
            _ = try await service.prepareSync(request)
            XCTFail("Unauthenticated Firebase sync should throw before writing metadata.")
        } catch let error as FirebaseBackendServiceError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirebaseCareerGraphSyncDoesNotWriteMetadataWhenAttachmentBytesAreMissing() async {
        let now = Date(timeIntervalSince1970: 42_000)
        let state = careerGraphStateWithProof(now: now)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_missing_file"),
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: ThrowingProofAttachmentDataProvider(error: .missingLocalAttachment),
            proofAttachmentUploader: FailingIfCalledProofAttachmentUploader()
        )

        do {
            _ = try await service.prepareSync(request)
            XCTFail("Missing local attachment bytes should stop Firebase sync before metadata writes.")
        } catch let error as FirebaseBackendServiceError {
            XCTAssertEqual(error, .attachmentBytesUnavailable)
            XCTAssertTrue(writer.writes.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirebaseCareerGraphSyncDoesNotWriteMetadataWhenAttachmentPathIsRejected() async {
        let now = Date(timeIntervalSince1970: 42_250)
        let state = careerGraphStateWithProof(now: now)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_bad_path"),
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: ThrowingProofAttachmentDataProvider(error: .unsafeLocalPath),
            proofAttachmentUploader: FailingIfCalledProofAttachmentUploader()
        )

        do {
            _ = try await service.prepareSync(request)
            XCTFail("Unsafe local attachment paths should stop Firebase sync before upload or metadata writes.")
        } catch let error as FirebaseBackendServiceError {
            XCTAssertEqual(error, .attachmentPathRejected)
            XCTAssertTrue(writer.writes.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirebaseCareerGraphSyncDoesNotWriteMetadataWhenUploadReceiptIsFailed() async {
        let now = Date(timeIntervalSince1970: 42_500)
        let state = careerGraphStateWithProof(now: now)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_failed_receipt"),
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let uploader = InvalidReceiptProofAttachmentUploader(status: .failed)
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: StaticProofAttachmentDataProvider(),
            proofAttachmentUploader: uploader
        )

        do {
            _ = try await service.prepareSync(request)
            XCTFail("A failed upload receipt should stop Firestore metadata writes.")
        } catch let error as FirebaseBackendServiceError {
            XCTAssertEqual(error, .invalidUploadReceipt)
            XCTAssertTrue(writer.writes.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirebaseCareerGraphSyncDoesNotWriteMetadataWhenUploadReceiptMismatchesIntent() async {
        let now = Date(timeIntervalSince1970: 42_750)
        let state = careerGraphStateWithProof(now: now)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_mismatch"),
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let uploader = InvalidReceiptProofAttachmentUploader(storagePathOverride: "users/firebase_uid_mismatch/proofAttachments/wrong")
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: StaticProofAttachmentDataProvider(),
            proofAttachmentUploader: uploader
        )

        do {
            _ = try await service.prepareSync(request)
            XCTFail("A mismatched upload receipt should stop Firestore metadata writes.")
        } catch let error as FirebaseBackendServiceError {
            XCTAssertEqual(error, .invalidUploadReceipt)
            XCTAssertTrue(writer.writes.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirebaseCareerGraphSyncRejectsEachMismatchedUploadReceiptField() async {
        let now = Date(timeIntervalSince1970: 42_900)
        let state = careerGraphStateWithProof(now: now)
        let cases: [(String, InvalidReceiptProofAttachmentUploader)] = [
            ("proof ID", InvalidReceiptProofAttachmentUploader(proofIDOverride: "wrong-proof")),
            ("attachment ID", InvalidReceiptProofAttachmentUploader(attachmentIDOverride: "wrong-attachment")),
            ("content type", InvalidReceiptProofAttachmentUploader(contentTypeOverride: "application/pdf")),
            ("byte count", InvalidReceiptProofAttachmentUploader(byteCountOverride: 12)),
            ("idempotency key", InvalidReceiptProofAttachmentUploader(idempotencyKeyOverride: "wrong-key"))
        ]

        for (label, uploader) in cases {
            let request = CareerGraphSyncPreparationRequest(
                state: state,
                session: BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_mismatch_\(label.replacingOccurrences(of: " ", with: "_"))"),
                requestedAt: now,
                includePrivateEvidence: true
            )
            let writer = CapturingCareerGraphDocumentWriter()
            let service = FirebaseFirestoreCareerGraphSyncService(
                writer: writer,
                attachmentDataProvider: StaticProofAttachmentDataProvider(),
                proofAttachmentUploader: uploader
            )

            do {
                _ = try await service.prepareSync(request)
                XCTFail("A mismatched upload receipt \(label) should stop Firestore metadata writes.")
            } catch let error as FirebaseBackendServiceError {
                XCTAssertEqual(error, .invalidUploadReceipt)
                XCTAssertTrue(writer.writes.isEmpty)
            } catch {
                XCTFail("Unexpected error for \(label): \(error)")
            }
        }
    }

    func testExistingStorageObjectReceiptRequiresExactOpenLARPMetadata() throws {
        let now = Date(timeIntervalSince1970: 43_000)
        let state = careerGraphStateWithProof(now: now)
        let session = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_existing")
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )
        let intent = try XCTUnwrap(CareerGraphSyncPlanner().plan(request).storageUploads.first)
        let metadata = CareerGraphStorageObjectMetadata(
            storagePath: intent.storagePath,
            contentType: intent.contentType,
            byteCount: intent.byteCount,
            customMetadata: CareerGraphStorageObjectMetadata.expectedCustomMetadata(
                ownerUserID: session.ownerUserID,
                intent: intent
            ),
            updatedAt: nil,
            storageBucket: "openlarp-test.appspot.com",
            storageGeneration: 101,
            metadataGeneration: 2,
            md5Hash: "mock-md5"
        )

        let receipt = try XCTUnwrap(CareerGraphSyncUploadReceipt(
            existingObject: metadata,
            intent: intent,
            session: session,
            uploadedAtFallback: now
        ))
        XCTAssertEqual(receipt.status, .uploaded)
        XCTAssertEqual(receipt.storagePath, intent.storagePath)
        XCTAssertEqual(receipt.storageBucket, "openlarp-test.appspot.com")
        XCTAssertEqual(receipt.uploadedAt, now)

        var extraMetadata = metadata
        extraMetadata.customMetadata["localRelativePath"] = "ProofAttachments/private-local-path.png"
        XCTAssertNil(CareerGraphSyncUploadReceipt(
            existingObject: extraMetadata,
            intent: intent,
            session: session
        ))

        var wrongOwner = metadata
        wrongOwner.customMetadata["ownerUserID"] = "other_uid"
        XCTAssertNil(CareerGraphSyncUploadReceipt(
            existingObject: wrongOwner,
            intent: intent,
            session: session
        ))

        var wrongProof = metadata
        wrongProof.customMetadata["proofID"] = "other-proof"
        XCTAssertNil(CareerGraphSyncUploadReceipt(
            existingObject: wrongProof,
            intent: intent,
            session: session
        ))

        var mismatchedSize = metadata
        mismatchedSize.byteCount += 1
        XCTAssertNil(CareerGraphSyncUploadReceipt(
            existingObject: mismatchedSize,
            intent: intent,
            session: session
        ))

        var wrongIdempotencyKey = metadata
        wrongIdempotencyKey.customMetadata["idempotencyKey"] = "wrong-key"
        XCTAssertNil(CareerGraphSyncUploadReceipt(
            existingObject: wrongIdempotencyKey,
            intent: intent,
            session: session
        ))
    }

    func testFirebaseCareerGraphSyncAcceptsExistingMatchingStorageObjectForRetry() async throws {
        let now = Date(timeIntervalSince1970: 43_500)
        let state = careerGraphStateWithProof(now: now)
        let session = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_retry")
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let uploader = ExistingObjectProofAttachmentUploader()
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: StaticProofAttachmentDataProvider(),
            proofAttachmentUploader: uploader
        )

        let firstResult = try await service.prepareSync(request)
        let retryResult = try await service.prepareSync(request)

        XCTAssertEqual(uploader.requests.count, 2)
        XCTAssertEqual(firstResult.uploadReceipts.map(\.status), [.uploaded])
        XCTAssertEqual(retryResult.uploadReceipts.map(\.status), [.uploaded])
        XCTAssertEqual(firstResult.uploadReceipts.first?.storagePath, retryResult.uploadReceipts.first?.storagePath)
        XCTAssertEqual(firstResult.uploadReceipts.first?.idempotencyKey, retryResult.uploadReceipts.first?.idempotencyKey)
        XCTAssertEqual(
            writer.writes.filter { $0.documentType == .proofAttachment }.count,
            2
        )
    }

    func testFirebaseCareerGraphSyncPromotesReceiptsServerSideAndSkipsClientAttachmentWrites() async throws {
        let now = Date(timeIntervalSince1970: 43_750)
        let state = careerGraphStateWithProof(now: now)
        let session = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_promote")
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let uploader = CapturingProofAttachmentUploader()
        let promoter = CapturingProofAttachmentReceiptPromoter(writesProofAttachmentDocuments: true)
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: StaticProofAttachmentDataProvider(),
            proofAttachmentUploader: uploader,
            proofAttachmentReceiptPromoter: promoter
        )

        let result = try await service.prepareSync(request)

        XCTAssertEqual(uploader.requests.count, 1)
        XCTAssertEqual(promoter.requests.count, 1)
        XCTAssertEqual(promoter.requests.first?.session.ownerUserID, "firebase_uid_promote")
        XCTAssertEqual(promoter.requests.first?.uploadIntent.storagePath, result.uploadIntents.first?.storagePath)
        XCTAssertEqual(promoter.requests.first?.uploadReceipt.storageBucket, "openlarp-test.appspot.com")
        XCTAssertEqual(result.uploadReceipts.first?.storageBucket, "openlarp-server-promoted.appspot.com")
        XCTAssertEqual(result.uploadReceipts.first?.storageGeneration, 202)
        XCTAssertTrue(result.firestoreDocumentPaths.contains {
            $0 == "users/firebase_uid_promote/proofAttachments/E1E1E1E1-E1E1-E1E1-E1E1-E1E1E1E1E1E1"
        })
        XCTAssertFalse(writer.writes.map(\.documentType).contains(.proofAttachment))
        XCTAssertTrue(writer.writes.contains { $0.documentType == .proofRecord })
        XCTAssertTrue(writer.writes.contains { $0.documentType == .readinessSnapshot })
    }

    func testFirebaseCareerGraphSyncDoesNotWriteMetadataWhenPromotionReceiptMismatchesIntent() async {
        let now = Date(timeIntervalSince1970: 43_900)
        let state = careerGraphStateWithProof(now: now)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_bad_promotion"),
            requestedAt: now,
            includePrivateEvidence: true
        )
        let writer = CapturingCareerGraphDocumentWriter()
        let service = FirebaseFirestoreCareerGraphSyncService(
            writer: writer,
            attachmentDataProvider: StaticProofAttachmentDataProvider(),
            proofAttachmentUploader: CapturingProofAttachmentUploader(),
            proofAttachmentReceiptPromoter: InvalidProofAttachmentReceiptPromoter(byteCountOverride: 12)
        )

        do {
            _ = try await service.prepareSync(request)
            XCTFail("A mismatched server promotion receipt should stop Firestore metadata writes.")
        } catch let error as FirebaseBackendServiceError {
            XCTAssertEqual(error, .invalidUploadReceipt)
            XCTAssertTrue(writer.writes.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func careerGraphStateWithProof(now: Date) -> OpenLARPState {
        let attachment = ProofAttachment(
            id: UUID(uuidString: "E1E1E1E1-E1E1-E1E1-E1E1-E1E1E1E1E1E1")!,
            fileName: "proof-upload.png",
            originalFileName: "proof-upload.png",
            contentType: "image/png",
            byteCount: 32_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/proof-upload.png"
        )
        let proof = ProofRecord(
            id: UUID(uuidString: "E2E2E2E2-E2E2-E2E2-E2E2-E2E2E2E2E2E2")!,
            questID: UUID(uuidString: "E3E3E3E3-E3E3-E3E3-E3E3-E3E3E3E3E3E3")!,
            questTitle: "Map role requirements",
            kind: .proof,
            text: "Compared three real AI product engineer postings and mapped them to shipped SwiftUI work.",
            link: "https://example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 91,
                label: "Strong proof",
                reason: "Specific, verifiable work sample.",
                improvement: "Attach the final walkthrough.",
                xpEarned: 120,
                readinessDelta: 8
            )
        )
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        state.userProfile?.privacy.shareWins = true
        state.userProfile?.privacy.memoryMode = .cloudReady
        return state
    }
}

private final class CapturingCareerGraphDocumentWriter: FirebaseCareerGraphDocumentWriting, @unchecked Sendable {
    private(set) var writes: [FirebaseCareerGraphDocumentWrite] = []

    func writeDocuments(_ documents: [FirebaseCareerGraphDocumentWrite]) async throws {
        writes.append(contentsOf: documents)
    }
}

private struct StaticProofAttachmentDataProvider: CareerGraphProofAttachmentDataProviding {
    func data(for uploadIntent: CareerGraphSyncUploadIntent) async throws -> Data {
        Data(repeating: 7, count: uploadIntent.byteCount)
    }
}

private struct ThrowingProofAttachmentDataProvider: CareerGraphProofAttachmentDataProviding {
    var error: CareerGraphProofAttachmentDataError

    func data(for uploadIntent: CareerGraphSyncUploadIntent) async throws -> Data {
        throw error
    }
}

private final class CapturingProofAttachmentUploader: CareerGraphProofAttachmentUploading, @unchecked Sendable {
    private(set) var requests: [CareerGraphProofAttachmentUploadRequest] = []

    func upload(_ request: CareerGraphProofAttachmentUploadRequest) async throws -> CareerGraphSyncUploadReceipt {
        requests.append(request)
        return CareerGraphSyncUploadReceipt(
            intent: request.uploadIntent,
            status: .uploaded,
            uploadedAt: request.requestedAt,
            storageBucket: "openlarp-test.appspot.com",
            storageGeneration: 101,
            metadataGeneration: 2,
            md5Hash: "mock-md5"
        )
    }
}

private struct FailingIfCalledProofAttachmentUploader: CareerGraphProofAttachmentUploading {
    func upload(_ request: CareerGraphProofAttachmentUploadRequest) async throws -> CareerGraphSyncUploadReceipt {
        XCTFail("Proof attachment uploader should not be called when local bytes are missing.")
        return CareerGraphSyncUploadReceipt(intent: request.uploadIntent, status: .failed)
    }
}

private final class ExistingObjectProofAttachmentUploader: CareerGraphProofAttachmentUploading, @unchecked Sendable {
    private(set) var requests: [CareerGraphProofAttachmentUploadRequest] = []

    func upload(_ request: CareerGraphProofAttachmentUploadRequest) async throws -> CareerGraphSyncUploadReceipt {
        requests.append(request)
        let metadata = CareerGraphStorageObjectMetadata(
            storagePath: request.uploadIntent.storagePath,
            contentType: request.uploadIntent.contentType,
            byteCount: request.uploadIntent.byteCount,
            customMetadata: CareerGraphStorageObjectMetadata.expectedCustomMetadata(
                ownerUserID: request.session.ownerUserID,
                intent: request.uploadIntent
            ),
            updatedAt: request.requestedAt,
            storageBucket: "openlarp-test.appspot.com",
            storageGeneration: 101,
            metadataGeneration: 2,
            md5Hash: "mock-md5"
        )
        guard let receipt = CareerGraphSyncUploadReceipt(
            existingObject: metadata,
            intent: request.uploadIntent,
            session: request.session
        ) else {
            throw FirebaseBackendServiceError.invalidUploadReceipt
        }
        return receipt
    }
}

private final class CapturingProofAttachmentReceiptPromoter: CareerGraphProofAttachmentReceiptPromoting, @unchecked Sendable {
    var writesProofAttachmentDocuments: Bool
    private(set) var requests: [CareerGraphProofAttachmentPromotionRequest] = []

    init(writesProofAttachmentDocuments: Bool = false) {
        self.writesProofAttachmentDocuments = writesProofAttachmentDocuments
    }

    func promote(_ request: CareerGraphProofAttachmentPromotionRequest) async throws -> CareerGraphSyncUploadReceipt {
        requests.append(request)
        return CareerGraphSyncUploadReceipt(
            intent: request.uploadIntent,
            status: .uploaded,
            uploadedAt: request.requestedAt,
            storageBucket: "openlarp-server-promoted.appspot.com",
            storageGeneration: 202,
            metadataGeneration: 3,
            md5Hash: "server-promoted-md5"
        )
    }
}

private struct InvalidProofAttachmentReceiptPromoter: CareerGraphProofAttachmentReceiptPromoting {
    var writesProofAttachmentDocuments: Bool = true
    var byteCountOverride: Int?

    func promote(_ request: CareerGraphProofAttachmentPromotionRequest) async throws -> CareerGraphSyncUploadReceipt {
        var receipt = request.uploadReceipt
        if let byteCountOverride {
            receipt.byteCount = byteCountOverride
        }
        return receipt
    }
}

private struct InvalidReceiptProofAttachmentUploader: CareerGraphProofAttachmentUploading {
    var status: CareerGraphSyncUploadStatus = .uploaded
    var proofIDOverride: String?
    var attachmentIDOverride: String?
    var storagePathOverride: String?
    var contentTypeOverride: String?
    var byteCountOverride: Int?
    var idempotencyKeyOverride: String?

    func upload(_ request: CareerGraphProofAttachmentUploadRequest) async throws -> CareerGraphSyncUploadReceipt {
        var receipt = CareerGraphSyncUploadReceipt(
            intent: request.uploadIntent,
            status: status,
            uploadedAt: request.requestedAt
        )
        if let storagePathOverride {
            receipt.storagePath = storagePathOverride
        }
        if let proofIDOverride {
            receipt.proofID = proofIDOverride
        }
        if let attachmentIDOverride {
            receipt.attachmentID = attachmentIDOverride
        }
        if let contentTypeOverride {
            receipt.contentType = contentTypeOverride
        }
        if let byteCountOverride {
            receipt.byteCount = byteCountOverride
        }
        if let idempotencyKeyOverride {
            receipt.idempotencyKey = idempotencyKeyOverride
        }
        return receipt
    }
}
