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
        let service = FirebaseFirestoreCareerGraphSyncService(writer: writer)

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
        let service = FirebaseFirestoreCareerGraphSyncService(writer: writer)

        let result = try await service.prepareSync(request)

        XCTAssertEqual(result.status, .synced)
        XCTAssertFalse(writer.writes.map(\.documentType).contains(.proofRecord))
        XCTAssertFalse(writer.writes.map(\.documentType).contains(.proofAttachment))
        XCTAssertTrue(result.uploadIntents.isEmpty)
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
