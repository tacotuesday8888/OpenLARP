import XCTest
import FirebaseFunctions
@testable import OpenLARP

final class AIBackendContractTests: XCTestCase {
    @MainActor
    func testFirebaseCallableAIWorkflowServiceSendsAdaptiveIntakeAndPreservesRequestProvenance() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "adaptiveCareerIntake",
            result: [
                "questions": [[
                    "id": "adaptive-existingProof",
                    "factKind": "existingProof",
                    "question": "What work can you already show or explain?",
                    "rationale": "This changes the first useful action.",
                    "responseType": "freeText",
                    "options": []
                ]],
                "hypotheses": [[
                    "kind": "constraints",
                    "value": "Your plan may need to fit around evening availability.",
                    "confirmationState": "awaitingConfirmation"
                ]]
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )
        var understanding = CareerIntakeDraft(
            outcomeType: .careerChange,
            targetOutcome: "AI product engineer",
            currentStatus: .newGrad,
            timeline: "12 weeks",
            urgency: .urgent,
            experience: "One class project",
            existingProof: "",
            constraints: "",
            confidence: 3,
            dailyCommitmentMinutes: 30,
            biggestBlocker: ""
        ).makeUnderstanding(reviewedAt: sampleDate)
        let confirmedAIHypothesis = try CareerFactRecord.aiHypothesis(
            kind: .biggestBlocker,
            value: "Needs role-specific proof",
            workflowRequestID: "prior-adaptive-request",
            createdAt: sampleDate
        )
        understanding.facts.append(confirmedAIHypothesis)
        try understanding.confirmHypothesis(id: confirmedAIHypothesis.id, at: sampleDate)
        try understanding.confirmUserEntriesForAdaptiveIntake(at: sampleDate)
        let request = V0AdaptiveCareerIntakeRequest(
            understanding: understanding,
            requestedAt: sampleDate,
            requestID: sampleRequestID
        )

        let response = try await service.generateAdaptiveCareerIntake(request)

        XCTAssertEqual(response.requestID, sampleRequestID)
        XCTAssertEqual(response.run.kind, .adaptiveCareerIntake)
        XCTAssertEqual(response.questions.map(\.factKind), [.existingProof])
        XCTAssertEqual(response.hypotheses.map(\.kind), [.constraints])
        let payloadJSON = try encodedJSONObjectString(invoker.calls[0].payload)
        XCTAssertTrue(payloadJSON.contains(#""kind" : "adaptiveCareerIntake""#))
        XCTAssertTrue(payloadJSON.contains(#""unknownKinds" : ["#))
        XCTAssertTrue(payloadJSON.contains(#""existingProof""#))
        XCTAssertTrue(payloadJSON.contains(#""maxQuestions" : 1"#))
        XCTAssertTrue(payloadJSON.contains(#""source" : "aiHypothesis""#))
        XCTAssertTrue(payloadJSON.contains(#""confirmationState" : "confirmed""#))
    }

    @MainActor
    func testLocalAdaptiveIntakeAsksOnlyTheHighestValueMissingQuestion() async throws {
        var understanding = CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: "iOS Engineer",
            currentStatus: .student,
            timeline: "90 days",
            urgency: .steady,
            experience: "",
            existingProof: "",
            constraints: "",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: ""
        ).makeUnderstanding(reviewedAt: sampleDate)
        try understanding.confirmUserEntriesForAdaptiveIntake(at: sampleDate)
        let request = V0AdaptiveCareerIntakeRequest(
            understanding: understanding,
            requestedAt: sampleDate,
            requestID: sampleRequestID
        )

        let response = try await LocalMockV0AIWorkflowService().generateAdaptiveCareerIntake(request)

        XCTAssertEqual(response.questions.map(\.factKind), [.existingProof])
        XCTAssertTrue(response.hypotheses.isEmpty)
    }

    @MainActor
    func testAdaptiveIntakeUsesDeterministicFallbackWhenFirebaseIsUnavailable() async throws {
        let invoker = MockFirebaseCallableInvoker(
            error: FirebaseCallableAIWorkflowServiceError.authenticationRequired
        )
        let service = FallbackV0AIWorkflowService(
            primary: FirebaseCallableV0AIWorkflowService(
                invoker: invoker,
                requestID: { sampleRequestID },
                preflight: { "user_123" }
            ),
            fallback: LocalMockV0AIWorkflowService()
        )
        var understanding = CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: "iOS Engineer",
            currentStatus: .student,
            timeline: "90 days",
            urgency: .steady,
            experience: "One class app",
            existingProof: "",
            constraints: "Evenings only",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: "Interview confidence"
        ).makeUnderstanding(reviewedAt: sampleDate)
        try understanding.confirmUserEntriesForAdaptiveIntake(at: sampleDate)
        let request = V0AdaptiveCareerIntakeRequest(
            understanding: understanding,
            requestedAt: sampleDate,
            requestID: sampleRequestID
        )

        let response = try await service.generateAdaptiveCareerIntake(request)

        XCTAssertEqual(invoker.calls.count, 1)
        XCTAssertEqual(response.questions.map(\.factKind), [.existingProof])
        XCTAssertEqual(response.run.providerRoute, .localMock)
        XCTAssertTrue(response.run.usedFallback)
    }

    func testCallableTransportErrorsAreMappedOnlyWhenLocalFallbackIsSafe() {
        let offline = NSError(
            domain: NSURLErrorDomain,
            code: URLError.notConnectedToInternet.rawValue
        )
        let invalidRequest = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.invalidArgument.rawValue
        )
        let unavailable = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.unavailable.rawValue
        )

        XCTAssertEqual(
            FirebaseCallableAIWorkflowServiceError.recoverableCallableError(from: offline),
            .serviceUnavailable
        )
        XCTAssertEqual(
            FirebaseCallableAIWorkflowServiceError.recoverableCallableError(from: unavailable),
            .serviceUnavailable
        )
        XCTAssertNil(
            FirebaseCallableAIWorkflowServiceError.recoverableCallableError(from: invalidRequest)
        )
    }

    func testAdaptiveIntakeRejectsAnOverwhelmingHypothesisSet() throws {
        var understanding = CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: "iOS Engineer",
            currentStatus: .student,
            timeline: "90 days",
            urgency: .steady,
            experience: "One class app",
            existingProof: "",
            constraints: "",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: ""
        ).makeUnderstanding(reviewedAt: sampleDate)
        try understanding.confirmUserEntriesForAdaptiveIntake(at: sampleDate)
        understanding.facts.append(try CareerFactRecord.aiHypothesis(
            kind: .existingProof,
            value: "Possible proof",
            workflowRequestID: "prior-request",
            createdAt: sampleDate
        ))
        let request = V0AdaptiveCareerIntakeRequest(
            understanding: understanding,
            requestedAt: sampleDate,
            requestID: sampleRequestID
        )
        let response = V0AdaptiveCareerIntakeResponse(
            requestID: sampleRequestID,
            run: V0AIWorkflowRun(
                kind: .adaptiveCareerIntake,
                providerRoute: .firebaseCallableGenkit,
                requestedAt: sampleDate
            ),
            questions: [],
            hypotheses: [
                V0AdaptiveCareerHypothesis(kind: .constraints, value: "Possible constraint"),
                V0AdaptiveCareerHypothesis(kind: .biggestBlocker, value: "Possible blocker")
            ]
        )

        XCTAssertThrowsError(try response.validate(for: request)) { error in
            XCTAssertEqual(
                error as? V0AdaptiveCareerIntakeContractError,
                .invalidHypothesis
            )
        }
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceSendsDiagnosticEnvelopeAndDecodesResponse() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            result: [
                "score": 62,
                "label": "Some proof, not enough signal",
                "mainGap": "Your AI product engineer goal needs stronger evidence.",
                "strongestSignal": "You already have starting proof.",
                "fastestFix": "Create one small artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        let response = try await service.generateDiagnostic(
            V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
        )

        XCTAssertEqual(invoker.calls.map(\.functionName), ["runOpenLARPWorkflow"])
        XCTAssertEqual(response.run.kind, .cookedDiagnostic)
        XCTAssertEqual(response.run.providerRoute, .firebaseCallableGenkit)
        XCTAssertEqual(response.run.requestedAt, sampleDate)
        XCTAssertEqual(response.run.completedAt, Date(timeIntervalSince1970: 1_813_312_800.123))
        XCTAssertFalse(response.run.usedFallback)
        XCTAssertEqual(response.diagnostic.label, "Some proof, not enough signal")

        let payloadJSON = try encodedJSONObjectString(invoker.calls[0].payload)
        XCTAssertTrue(payloadJSON.contains(#""providerRoute" : "firebaseCallableGenkit""#))
        XCTAssertTrue(payloadJSON.contains(#""kind" : "cookedDiagnostic""#))
        XCTAssertTrue(payloadJSON.contains(#""targetRole" : "AI product engineer""#))
        XCTAssertTrue(payloadJSON.contains(#""outcomeType" : "careerChange""#))
        XCTAssertTrue(payloadJSON.contains(#""urgency" : "urgent""#))
        XCTAssertTrue(payloadJSON.contains(#""constraints" : "Weeknights only""#))
        XCTAssertTrue(payloadJSON.contains(#""dailyCommitmentMinutes" : 30"#))
        XCTAssertTrue(payloadJSON.contains("hardBannedClaims"))
        XCTAssertFalse(payloadJSON.localizedCaseInsensitiveContains("gemini"))
        XCTAssertFalse(payloadJSON.localizedCaseInsensitiveContains("modelID"))
        XCTAssertFalse(payloadJSON.localizedCaseInsensitiveContains("owner-user-secret"))
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceMapsBackendQuestDTOsIntoAppQuests() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "questPlan",
            result: [
                "quests": [
                    [
                        "day": 1,
                        "title": "Map 3 requirements for AI product engineer",
                        "purpose": "Turn vague anxiety into a concrete proof target.",
                        "timeEstimateMinutes": 25,
                        "difficulty": "Starter",
                        "gap": "proofStrength",
                        "proofRequired": "Requirement notes",
                        "xpReward": 120,
                        "steps": ["Find two role descriptions", "List repeated requirements"]
                    ],
                    [
                        "day": 2,
                        "title": "Create one tiny proof artifact",
                        "purpose": "Build real evidence.",
                        "timeEstimateMinutes": 30,
                        "difficulty": "Starter",
                        "gap": "skillProof",
                        "proofRequired": "Artifact link or screenshot",
                        "xpReward": 130,
                        "steps": ["Choose one requirement", "Create a first version"]
                    ]
                ]
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        let response = try await service.generateQuestPlan(
            V0QuestPlanRequest(
                goal: sampleGoal,
                diagnostic: sampleDiagnostic,
                requestedAt: sampleDate
            )
        )

        XCTAssertEqual(response.run.kind, .questPlan)
        XCTAssertEqual(response.run.providerRoute, .firebaseCallableGenkit)
        XCTAssertEqual(response.quests.map(\.status), [.available, .locked])
        XCTAssertEqual(response.quests.map(\.gap), [.proofStrength, .proofStrength])
        XCTAssertEqual(response.quests[0].id.uuidString, "11111111-1111-4111-8111-000001000000")
        XCTAssertEqual(response.quests[1].id.uuidString, "11111111-1111-4111-8111-000002000001")
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceDecodesProofQualityAndProgressSummary() async throws {
        let proofInvoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "proofQualityCheck",
            result: [
                "isAccepted": true,
                "qualityScore": 84,
                "label": "Credible proof",
                "reason": "The proof describes a concrete action.",
                "improvement": "Add one measurable detail next.",
                "xpEarned": 120,
                "readinessDelta": 6
            ]
        ))
        let proofService = FirebaseCallableV0AIWorkflowService(
            invoker: proofInvoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )
        let state = sampleState
        let proofResponse = try await proofService.reviewProof(
            V0ProofReviewRequest(
                state: state,
                proof: sampleProof,
                requestedAt: sampleDate
            )
        )

        XCTAssertEqual(proofResponse.run.kind, .proofQualityCheck)
        XCTAssertEqual(proofResponse.run.providerRoute, .firebaseCallableGenkit)
        XCTAssertTrue(proofResponse.result.isAccepted)
        XCTAssertEqual(proofResponse.result.qualityScore, 84)
        let proofPayloadJSON = try encodedJSONObjectString(proofInvoker.calls[0].payload)
        XCTAssertTrue(proofPayloadJSON.contains(#""kind" : "proofQualityCheck""#))
        XCTAssertTrue(proofPayloadJSON.contains(#""contentType" : "image\/png""#))
        XCTAssertTrue(proofPayloadJSON.contains(#""byteCount" : 32000"#))
        XCTAssertFalse(proofPayloadJSON.contains("localRelativePath"))
        XCTAssertFalse(proofPayloadJSON.contains("ProofAttachments/private-proof.png"))
        XCTAssertFalse(proofPayloadJSON.contains("private-proof.png"))
        XCTAssertFalse(proofPayloadJSON.contains("originalFileName"))
        XCTAssertFalse(proofPayloadJSON.contains(sampleProof.id.uuidString))

        let progressInvoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "progressSummary",
            result: [
                "summary": "Readiness is 48% with three proof receipts.",
                "readiness": [
                    "overall": 51,
                    "proofStrength": 50,
                    "confidence": 52,
                    "consistency": 44,
                    "skillProof": 49,
                    "networkStrength": 37
                ],
                "nextQuestTitle": "Map 3 requirements for AI product engineer"
            ]
        ))
        let progressService = FirebaseCallableV0AIWorkflowService(
            invoker: progressInvoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )
        let progressResponse = try await progressService.summarizeProgress(
            V0ProgressSummaryRequest(state: state, requestedAt: sampleDate)
        )

        XCTAssertEqual(progressResponse.run.kind, .progressSummary)
        XCTAssertEqual(progressResponse.summary, "Readiness is 48% with three proof receipts.")
        XCTAssertEqual(progressResponse.readiness.overall, 51)
        XCTAssertEqual(progressResponse.progress.completedQuestCount, state.progress.completedQuestCount)
        XCTAssertEqual(progressResponse.nextQuestTitle, "Map 3 requirements for AI product engineer")
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceAcceptsValidatedLiveModelResponse() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            liveModelCallsEnabled: true,
            liveModelUsed: true,
            promptVersion: "openlarp.cooked.v1",
            policyRevision: "beta-2026-08-10",
            result: [
                "score": 62,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        let response = try await service.generateDiagnostic(
            V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
        )

        XCTAssertFalse(response.run.usedFallback)
        XCTAssertEqual(response.run.providerRoute, .firebaseCallableGenkit)
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceAcceptsExplicitServerFallbackResponse() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            liveModelCallsEnabled: true,
            usedFallback: true,
            fallbackReason: "budget",
            policyRevision: "beta-2026-08-10",
            result: [
                "score": 48,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        let response = try await service.generateDiagnostic(
            V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
        )

        XCTAssertTrue(response.run.usedFallback)
        XCTAssertEqual(response.run.providerRoute, .firebaseCallableGenkit)
        XCTAssertEqual(response.run.failureMessage, AIWorkflowAuditRecord.fallbackFailureSummary)
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceRejectsUnexpectedProviderRoute() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            providerRoute: "cloudRunGenkit",
            result: [
                "score": 48,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
        }
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceRejectsFallbackWithoutReason() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            liveModelCallsEnabled: true,
            usedFallback: true,
            result: [
                "score": 48,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
        }
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceRejectsUnsupportedResponseVersion() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            schemaVersion: 2,
            kind: "cookedDiagnostic",
            result: [
                "score": 48,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
        }
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceRejectsUnsafeCallableResponseFlags() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            liveModelCallsEnabled: true,
            liveModelUsed: true,
            promptVersion: "openlarp.cooked.v1",
            policyRevision: "beta-2026-08-10",
            externalActionTaken: true,
            result: [
                "score": 62,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        do {
            _ = try await service.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
            XCTFail("Expected callable response with live model flag to be rejected.")
        } catch FirebaseCallableAIWorkflowServiceError.contractMismatch {
            XCTAssertEqual(invoker.calls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceRejectsMismatchedRequestID() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            requestID: "99999999-9999-4999-8999-999999999999",
            kind: "cookedDiagnostic",
            result: [
                "score": 62,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        do {
            _ = try await service.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
            XCTFail("Expected mismatched callable requestID to be rejected.")
        } catch FirebaseCallableAIWorkflowServiceError.contractMismatch {
            XCTAssertEqual(invoker.calls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFirebaseCallableAIWorkflowServiceRejectsMismatchedUserID() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            userID: "different_user",
            result: [
                "score": 62,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let service = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )

        do {
            _ = try await service.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
            XCTFail("Expected mismatched callable userID to be rejected.")
        } catch FirebaseCallableAIWorkflowServiceError.contractMismatch {
            XCTAssertEqual(invoker.calls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFallbackAIWorkflowDoesNotHideFirebaseContractMismatch() async throws {
        let invoker = MockFirebaseCallableInvoker(response: callableResponse(
            kind: "cookedDiagnostic",
            liveModelCallsEnabled: true,
            result: [
                "score": 62,
                "label": "Some proof, not enough signal",
                "mainGap": "Needs stronger evidence.",
                "strongestSignal": "Has proof.",
                "fastestFix": "Create an artifact.",
                "readinessBaseline": 48
            ]
        ))
        let primary = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )
        let fallback = FallbackV0AIWorkflowService(
            primary: primary,
            fallback: LocalMockV0AIWorkflowService()
        )

        do {
            _ = try await fallback.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
            XCTFail("Expected callable contract mismatch to stay visible instead of falling back.")
        } catch FirebaseCallableAIWorkflowServiceError.contractMismatch {
            XCTAssertEqual(invoker.calls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFallbackAIWorkflowDoesNotHideRawCallableFailure() async throws {
        let invoker = MockFirebaseCallableInvoker(error: RawCallableFailure())
        let primary = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )
        let fallback = FallbackV0AIWorkflowService(
            primary: primary,
            fallback: LocalMockV0AIWorkflowService()
        )

        do {
            _ = try await fallback.generateDiagnostic(
                V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
            )
            XCTFail("Expected raw callable failures to stay visible instead of falling back.")
        } catch is RawCallableFailure {
            XCTAssertEqual(invoker.calls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFallbackAIWorkflowUsesLocalMockForRecoverableFirebaseSetupState() async throws {
        let invoker = MockFirebaseCallableInvoker(error: FirebaseCallableAIWorkflowServiceError.authenticationRequired)
        let primary = FirebaseCallableV0AIWorkflowService(
            invoker: invoker,
            requestID: { sampleRequestID },
            preflight: { "user_123" }
        )
        let fallback = FallbackV0AIWorkflowService(
            primary: primary,
            fallback: LocalMockV0AIWorkflowService()
        )

        let response = try await fallback.generateDiagnostic(
            V0DiagnosticRequest(goal: sampleGoal, requestedAt: sampleDate)
        )

        XCTAssertEqual(invoker.calls.count, 1)
        XCTAssertEqual(response.run.providerRoute, .localMock)
        XCTAssertTrue(response.run.usedFallback)
    }

    func testRequestEnvelopeRedactsPrivateAndSessionIdentifiers() throws {
        let privateIdentifiers = V0AIBackendPrivateIdentifiers(
            ownerUserID: "owner-user-secret-123",
            accountID: "account-private-456",
            sessionID: "session-private-789",
            email: "langqi@example.com"
        )
        let envelope = makeEnvelope(privateIdentifiers: privateIdentifiers)

        let json = try encodedJSONString(envelope)

        XCTAssertFalse(json.contains("owner-user-secret-123"))
        XCTAssertFalse(json.contains("account-private-456"))
        XCTAssertFalse(json.contains("session-private-789"))
        XCTAssertFalse(json.contains("langqi@example.com"))
        XCTAssertFalse(json.contains("ownerUserID"))
        XCTAssertFalse(json.contains("accountID"))
        XCTAssertFalse(json.contains("sessionID"))
        XCTAssertFalse(json.contains("email"))
    }

    func testRequestEnvelopeCarriesProviderRouteOnlyWithoutDirectModelIDs() throws {
        let envelope = makeEnvelope(providerRoute: .cloudRunGenkit)

        let json = try encodedJSONString(envelope)

        XCTAssertTrue(json.contains(#""providerRoute" : "cloudRunGenkit""#))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("gemini"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("modelID"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("modelName"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("llm"))
    }

    func testRequestEnvelopeIncludesSafetyRules() throws {
        let envelope = makeEnvelope()

        XCTAssertEqual(envelope.safetyRules, .v0Default)
        XCTAssertTrue(envelope.safetyRules.hardBannedClaims.contains("fake employers"))
        XCTAssertTrue(envelope.safetyRules.hardBannedClaims.contains("fake certificates"))
        XCTAssertTrue(envelope.safetyRules.requiredBehaviors.contains("frame real experience honestly"))
        XCTAssertTrue(envelope.safetyRules.privacyRequirements.contains("do not take external actions without approval"))

        let json = try encodedJSONString(envelope)

        XCTAssertTrue(json.contains("hardBannedClaims"))
        XCTAssertTrue(json.contains("fake ownership claims"))
        XCTAssertTrue(json.contains("privacyRequirements"))
    }

    func testRequestEnvelopeEncodesAndDecodesStableJSON() throws {
        let envelope = makeEnvelope()
        let encoded = try encodedJSONString(envelope)

        XCTAssertEqual(encoded, stableEnvelopeJSON)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            V0AIBackendRequestEnvelope<SampleAIBackendPayload>.self,
            from: Data(encoded.utf8)
        )

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(try encodedJSONString(decoded), stableEnvelopeJSON)
    }

    private func makeEnvelope(
        providerRoute: V0AIProviderRoute = .cloudRunGenkit,
        privateIdentifiers: V0AIBackendPrivateIdentifiers = .none
    ) -> V0AIBackendRequestEnvelope<SampleAIBackendPayload> {
        V0AIBackendRequestEnvelope(
            kind: .cookedDiagnostic,
            providerRoute: providerRoute,
            requestedAt: Date(timeIntervalSince1970: 0),
            requestID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            privacy: .localDefault,
            privateIdentifiers: privateIdentifiers,
            payload: SampleAIBackendPayload(promptPurpose: "diagnose", revision: 1)
        )
    }

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func encodedJSONObjectString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private var stableEnvelopeJSON: String {
        """
        {
          "payload" : {
            "promptPurpose" : "diagnose",
            "revision" : 1
          },
          "run" : {
            "kind" : "cookedDiagnostic",
            "privacy" : {
              "allowsLongTermMemoryWrite" : false,
              "allowsPrivateEvidenceCloudSync" : false,
              "memoryMode" : "localOnly",
              "requiresUserApprovalForExternalActions" : true,
              "shareWins" : false
            },
            "providerRoute" : "cloudRunGenkit",
            "requestID" : "11111111-1111-1111-1111-111111111111",
            "requestedAt" : "1970-01-01T00:00:00Z",
            "schemaVersion" : 1
          },
          "safetyRules" : {
            "hardBannedClaims" : [
              "fake employers",
              "fake schools",
              "fake certificates",
              "fake job titles",
              "fake dates",
              "fake projects",
              "fake ownership claims"
            ],
            "privacyRequirements" : [
              "do not request provider credentials",
              "do not write long-term memory unless the user enabled it",
              "do not take external actions without approval"
            ],
            "requiredBehaviors" : [
              "frame real experience honestly",
              "separate proof from self-report",
              "recommend small truthful next steps"
            ]
          },
          "schemaVersion" : 1
        }
        """
    }
}

private struct SampleAIBackendPayload: Codable, Equatable {
    var promptPurpose: String
    var revision: Int
}

private final class MockFirebaseCallableInvoker: FirebaseCallableInvoking {
    struct Call {
        var functionName: String
        var payload: [String: Any]
    }

    var calls: [Call] = []
    var response: [String: Any]?
    var error: Error?

    init(response: [String: Any]) {
        self.response = response
    }

    init(error: Error) {
        self.error = error
    }

    func call<Payload: Codable & Equatable & Sendable, Result: Decodable>(
        _ functionName: String,
        envelope: V0AIBackendRequestEnvelope<Payload>,
        responseType: FirebaseCallableAIWorkflowResponse<Result>.Type
    ) async throws -> FirebaseCallableAIWorkflowResponse<Result> {
        calls.append(Call(functionName: functionName, payload: try FirebaseCallableAIWorkflowJSON.dictionary(from: envelope)))
        if let error {
            throw error
        }
        guard let response else {
            throw RawCallableFailure()
        }
        let responseData = try JSONSerialization.data(withJSONObject: response)
        return try FirebaseCallableAIWorkflowJSON.decode(responseType, fromData: responseData)
    }
}

private struct RawCallableFailure: Error {}

private let sampleRequestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let sampleDate = Date(timeIntervalSince1970: 1_781_776_800)

private let sampleGoal = CareerGoal(
    currentStatus: .newGrad,
    targetRole: "AI product engineer",
    timeline: "12 weeks",
    background: "CS student with one shipped class project.",
    existingProof: "GitHub project and internship notes.",
    confidence: 3,
    biggestBlocker: "Not enough role-specific proof.",
    outcomeType: .careerChange,
    urgency: .urgent,
    constraints: "Weeknights only",
    dailyCommitmentMinutes: 30
)

private let sampleDiagnostic = CookedDiagnostic(
    score: 62,
    label: "Some proof, not enough signal",
    mainGap: "Needs more evidence",
    strongestSignal: "Has project proof",
    fastestFix: "Create one artifact",
    readinessBaseline: 48
)

private let sampleQuest = Quest(
    id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
    day: 1,
    title: "Map 3 requirements for AI product engineer",
    purpose: "Identify proof gaps.",
    timeEstimateMinutes: 25,
    difficulty: "Starter",
    gap: .proofStrength,
    proofRequired: "Requirement notes",
    xpReward: 120,
    steps: ["Read two role descriptions", "List repeated requirements"],
    status: .available
)

private let sampleProof = ProofSubmission(
    id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
    kind: .proof,
    text: "I mapped requirements from three AI product engineer postings and tied them to my existing project evidence.",
    link: "https://example.com/proof",
    attachments: [
        ProofAttachment(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            fileName: "private-proof.png",
            originalFileName: "private-proof.png",
            contentType: "image/png",
            byteCount: 32_000,
            createdAt: sampleDate,
            localRelativePath: "ProofAttachments/private-proof.png"
        )
    ],
    submittedAt: sampleDate
)

private var sampleState: OpenLARPState {
    OpenLARPState(
        userProfile: nil,
        goal: sampleGoal,
        diagnostic: sampleDiagnostic,
        plan: [sampleQuest],
        progress: ProgressState(
            xp: 420,
            xpGoal: 1000,
            streakCount: 2,
            completedQuestCount: 2,
            proofCount: 3,
            badges: [],
            readiness: ReadinessMetrics(
                overall: 48,
                proofStrength: 42,
                confidence: 51,
                consistency: 39,
                skillProof: 44,
                networkStrength: 30
            ),
            recentProof: []
        ),
        updatedAt: sampleDate
    )
}

private func callableResponse(
    schemaVersion: Int = 1,
    requestID: String = "11111111-1111-4111-8111-111111111111",
    kind: String,
    userID: String = "user_123",
    providerRoute: String = "firebaseCallableGenkit",
    liveModelCallsEnabled: Bool = false,
    liveModelUsed: Bool = false,
    usedFallback: Bool = false,
    fallbackReason: String? = nil,
    promptVersion: String? = nil,
    policyRevision: String? = nil,
    externalActionTaken: Bool = false,
    result: [String: Any]
) -> [String: Any] {
    var response: [String: Any] = [
        "ok": true,
        "schemaVersion": schemaVersion,
        "requestID": requestID,
        "kind": kind,
        "userID": userID,
        "evaluatedAt": "2027-06-18T10:00:00.123Z",
        "providerRoute": providerRoute,
        "liveModelCallsEnabled": liveModelCallsEnabled,
        "liveModelUsed": liveModelUsed,
        "usedFallback": usedFallback,
        "externalActionTaken": externalActionTaken,
        "result": result
    ]
    if let fallbackReason {
        response["fallbackReason"] = fallbackReason
    }
    if let promptVersion {
        response["promptVersion"] = promptVersion
    }
    if let policyRevision {
        response["policyRevision"] = policyRevision
    }
    return response
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected operation to throw.", file: file, line: line)
    } catch FirebaseCallableAIWorkflowServiceError.contractMismatch {
        return
    } catch {
        XCTFail("Expected a callable contract mismatch, received \(error).", file: file, line: line)
    }
}
