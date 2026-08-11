import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseFunctions)
@preconcurrency
import FirebaseFunctions
#endif

#if canImport(FirebaseSharedSwift)
import FirebaseSharedSwift
#endif

enum FirebaseCallableAIWorkflowServiceError: LocalAIWorkflowFallbackEligibleError, LocalizedError, Equatable {
    case sdkUnavailable
    case configurationMissing
    case authenticationRequired
    case serviceUnavailable
    case payloadEncodingFailed
    case responseDecodingFailed
    case contractMismatch(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            "Firebase Functions is not linked in this build."
        case .configurationMissing:
            "Firebase is linked but not configured for this build."
        case .authenticationRequired:
            "Sign in before running Firebase callable AI workflows."
        case .serviceUnavailable:
            "The Firebase callable AI service is temporarily unavailable."
        case .payloadEncodingFailed:
            "The OpenLARP AI workflow request could not be encoded for Firebase Functions."
        case .responseDecodingFailed:
            "The Firebase callable AI workflow response did not match the app contract."
        case .contractMismatch(let detail):
            detail
        }
    }

    var allowsLocalWorkflowFallback: Bool {
        switch self {
        case .sdkUnavailable, .configurationMissing, .authenticationRequired, .serviceUnavailable:
            true
        case .payloadEncodingFailed, .responseDecodingFailed, .contractMismatch:
            false
        }
    }

    static func recoverableCallableError(from error: Error) -> FirebaseCallableAIWorkflowServiceError? {
        let nsError = error as NSError

        #if canImport(FirebaseFunctions)
        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .deadlineExceeded, .resourceExhausted, .unavailable:
                return .serviceUnavailable
            case .unauthenticated:
                return .authenticationRequired
            default:
                return nil
            }
        }
        #endif

        guard nsError.domain == NSURLErrorDomain else { return nil }
        let recoverableCodes: Set<URLError.Code> = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed
        ]
        guard recoverableCodes.contains(URLError.Code(rawValue: nsError.code)) else { return nil }
        return .serviceUnavailable
    }
}

struct OpenLARPFirebaseCallableAIConfiguration: Equatable {
    var functionName: String
    var usesEmulator: Bool
    var emulatorHost: String
    var emulatorPort: Int

    static let production = OpenLARPFirebaseCallableAIConfiguration()
    static let localEmulator = OpenLARPFirebaseCallableAIConfiguration(usesEmulator: true)

    init(
        functionName: String = "runOpenLARPWorkflow",
        usesEmulator: Bool = false,
        emulatorHost: String = "localhost",
        emulatorPort: Int = 5001
    ) {
        self.functionName = functionName
        self.usesEmulator = usesEmulator
        self.emulatorHost = emulatorHost
        self.emulatorPort = emulatorPort
    }
}

@MainActor
protocol FirebaseCallableInvoking {
    func call<Payload: Codable & Equatable & Sendable, Result: Decodable>(
        _ functionName: String,
        envelope: V0AIBackendRequestEnvelope<Payload>,
        responseType: FirebaseCallableAIWorkflowResponse<Result>.Type
    ) async throws -> FirebaseCallableAIWorkflowResponse<Result>
}

struct FirebaseFunctionsCallableInvoker: FirebaseCallableInvoking {
    private let configuration: OpenLARPFirebaseCallableAIConfiguration

    init(configuration: OpenLARPFirebaseCallableAIConfiguration = .production) {
        self.configuration = configuration
    }

    func call<Payload: Codable & Equatable & Sendable, Result: Decodable>(
        _ functionName: String,
        envelope: V0AIBackendRequestEnvelope<Payload>,
        responseType: FirebaseCallableAIWorkflowResponse<Result>.Type
    ) async throws -> FirebaseCallableAIWorkflowResponse<Result> {
        #if canImport(FirebaseFunctions) && canImport(FirebaseCore) && canImport(FirebaseSharedSwift)
        guard FirebaseApp.app() != nil else {
            throw FirebaseCallableAIWorkflowServiceError.configurationMissing
        }

        let functions = Functions.functions()
        if configuration.usesEmulator {
            functions.useEmulator(withHost: configuration.emulatorHost, port: configuration.emulatorPort)
        }

        let callable: Callable<
            V0AIBackendRequestEnvelope<Payload>,
            FirebaseCallableAIWorkflowResponse<Result>
        > = functions.httpsCallable(
            functionName,
            requestAs: V0AIBackendRequestEnvelope<Payload>.self,
            responseAs: responseType,
            encoder: FirebaseCallableAIWorkflowJSON.firebaseDataEncoder(),
            decoder: FirebaseCallableAIWorkflowJSON.firebaseDataDecoder()
        )
        do {
            return try await callable.call(envelope)
        } catch {
            if let recoverable = FirebaseCallableAIWorkflowServiceError.recoverableCallableError(from: error) {
                throw recoverable
            }
            throw error
        }
        #else
        throw FirebaseCallableAIWorkflowServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseCallableV0AIWorkflowService: V0AIWorkflowServicing {
    private let configuration: OpenLARPFirebaseCallableAIConfiguration
    private let invoker: any FirebaseCallableInvoking
    private let preflight: @MainActor () throws -> String
    private let makeRequestID: @MainActor () -> UUID

    init(
        configuration: OpenLARPFirebaseCallableAIConfiguration = .production,
        invoker: (any FirebaseCallableInvoking)? = nil,
        requestID: @MainActor @escaping () -> UUID = { UUID() },
        preflight: @MainActor @escaping () throws -> String = FirebaseCallableV0AIWorkflowService.requireConfiguredAuthenticatedFirebase
    ) {
        self.configuration = configuration
        self.invoker = invoker ?? FirebaseFunctionsCallableInvoker(configuration: configuration)
        self.makeRequestID = requestID
        self.preflight = preflight
    }

    func generateAdaptiveCareerIntake(
        _ request: V0AdaptiveCareerIntakeRequest
    ) async throws -> V0AdaptiveCareerIntakeResponse {
        let response: FirebaseCallableAIWorkflowResponse<FirebaseCallableAdaptiveCareerIntakeResult> = try await callWorkflow(
            kind: .adaptiveCareerIntake,
            requestedAt: request.requestedAt,
            requestID: request.requestID,
            privacy: .localDefault,
            payload: FirebaseCallableAdaptiveCareerIntakePayload(request: request)
        )
        let result = V0AdaptiveCareerIntakeResponse(
            requestID: response.requestID,
            run: try response.workflowRun(
                expectedKind: .adaptiveCareerIntake,
                requestedAt: request.requestedAt
            ),
            questions: response.result.questions,
            hypotheses: response.result.hypotheses
        )
        do {
            try result.validate(for: request)
        } catch {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch(
                "Firebase callable adaptive intake response did not match the requested unknown facts."
            )
        }
        return result
    }

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        let response: FirebaseCallableAIWorkflowResponse<CookedDiagnostic> = try await callWorkflow(
            kind: .cookedDiagnostic,
            requestedAt: request.requestedAt,
            privacy: .localDefault,
            payload: FirebaseCallableDiagnosticPayload(request: request)
        )
        return V0DiagnosticResponse(
            run: try response.workflowRun(expectedKind: .cookedDiagnostic, requestedAt: request.requestedAt),
            diagnostic: response.result
        )
    }

    func generateMissionBrief(_ request: V0MissionBriefRequest) async throws -> V0MissionBriefResponse {
        let response: FirebaseCallableAIWorkflowResponse<FirebaseCallableMissionBriefResult> = try await callWorkflow(
            kind: .missionBrief,
            requestedAt: request.requestedAt,
            privacy: .localDefault,
            payload: FirebaseCallableMissionBriefPayload(request: request)
        )
        let run = try response.workflowRun(expectedKind: .missionBrief, requestedAt: request.requestedAt)
        let expectedFacts = request.confirmedFacts.map(FirebaseCallableMissionFactDTO.init)
        guard response.result.targetOutcome == request.goal.targetRole,
              response.result.confirmedCurrentState == expectedFacts,
              response.result.constraints == request.goal.constraints.trimmingCharacters(in: .whitespacesAndNewlines),
              response.result.ethicalBoundaries == request.requiredEthicalBoundaries,
              response.result.dailyCommitmentMinutes == request.goal.dailyCommitmentMinutes else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch(
                "Firebase callable mission response changed user-confirmed mission inputs."
            )
        }
        let mission = try CareerMissionBrief.proposal(
            targetOutcome: response.result.targetOutcome,
            confirmedCurrentState: request.confirmedFacts,
            constraints: response.result.constraints,
            mainReadinessGaps: response.result.mainReadinessGaps,
            ethicalBoundaries: response.result.ethicalBoundaries,
            firstMilestone: response.result.firstMilestone,
            dailyCommitmentMinutes: response.result.dailyCommitmentMinutes,
            sprint: response.result.sprint,
            providerRoute: run.providerRoute,
            usedFallback: run.usedFallback,
            generatedAt: run.completedAt
        )
        let result = V0MissionBriefResponse(run: run, mission: mission)
        do {
            try result.validate(for: request)
        } catch {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch(
                "Firebase callable mission response did not match the approved career understanding."
            )
        }
        return result
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        let response: FirebaseCallableAIWorkflowResponse<FirebaseCallableQuestPlanResult> = try await callWorkflow(
            kind: .questPlan,
            requestedAt: request.requestedAt,
            privacy: .localDefault,
            payload: FirebaseCallableQuestPlanPayload(request: request)
        )
        return V0QuestPlanResponse(
            run: try response.workflowRun(expectedKind: .questPlan, requestedAt: request.requestedAt),
            quests: response.result.quests.enumerated().map { index, quest in
                quest.appQuest(index: index, requestID: response.requestID)
            }
        )
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        let response: FirebaseCallableAIWorkflowResponse<QualityCheckResult> = try await callWorkflow(
            kind: .proofQualityCheck,
            requestedAt: request.requestedAt,
            privacy: request.privacy,
            payload: FirebaseCallableProofQualityPayload(request: request)
        )
        return V0ProofReviewResponse(
            run: try response.workflowRun(expectedKind: .proofQualityCheck, requestedAt: request.requestedAt),
            result: response.result
        )
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        let response: FirebaseCallableAIWorkflowResponse<FirebaseCallableProgressSummaryResult> = try await callWorkflow(
            kind: .progressSummary,
            requestedAt: request.requestedAt,
            privacy: request.privacy,
            payload: FirebaseCallableProgressSummaryPayload(request: request)
        )
        return V0ProgressSummaryResponse(
            run: try response.workflowRun(expectedKind: .progressSummary, requestedAt: request.requestedAt),
            summary: response.result.summary,
            progress: request.context.progress,
            readiness: response.result.readiness,
            nextQuestTitle: response.result.nextQuestTitle
        )
    }

    private func callWorkflow<Payload: Codable & Equatable & Sendable, Result: Decodable>(
        kind: V0AIWorkflowKind,
        requestedAt: Date,
        requestID requestedRequestID: UUID? = nil,
        privacy: CareerUserPrivacySettings,
        payload: Payload
    ) async throws -> FirebaseCallableAIWorkflowResponse<Result> {
        let expectedUserID = try preflight()
        let requestID = requestedRequestID ?? makeRequestID()
        let envelope = V0AIBackendRequestEnvelope(
            kind: kind,
            providerRoute: .firebaseCallableGenkit,
            requestedAt: requestedAt,
            requestID: requestID,
            privacy: privacy,
            payload: payload
        )
        let response = try await invoker.call(
            configuration.functionName,
            envelope: envelope,
            responseType: FirebaseCallableAIWorkflowResponse<Result>.self
        )
        try response.validateRequestID(requestID)
        try response.validateUserID(expectedUserID)
        return response
    }

    @MainActor
    private static func requireConfiguredAuthenticatedFirebase() throws -> String {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth)
        guard FirebaseApp.app() != nil else {
            throw FirebaseCallableAIWorkflowServiceError.configurationMissing
        }
        guard let currentUser = Auth.auth().currentUser else {
            throw FirebaseCallableAIWorkflowServiceError.authenticationRequired
        }
        return currentUser.uid
        #else
        throw FirebaseCallableAIWorkflowServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseCallableAIWorkflowResponse<Result: Decodable>: Decodable, @unchecked Sendable {
    var ok: Bool
    var schemaVersion: Int
    var requestID: UUID
    var kind: V0AIWorkflowKind
    var userID: String
    var evaluatedAt: Date
    var providerRoute: V0AIProviderRoute
    var liveModelCallsEnabled: Bool
    var liveModelUsed: Bool
    var usedFallback: Bool
    var fallbackReason: String?
    var promptVersion: String?
    var policyRevision: String?
    var externalActionTaken: Bool
    var result: Result

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion
        case requestID
        case kind
        case userID
        case evaluatedAt
        case providerRoute
        case liveModelCallsEnabled
        case liveModelUsed
        case usedFallback
        case fallbackReason
        case promptVersion
        case policyRevision
        case externalActionTaken
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        kind = try container.decode(V0AIWorkflowKind.self, forKey: .kind)
        userID = try container.decode(String.self, forKey: .userID)
        evaluatedAt = try container.decode(Date.self, forKey: .evaluatedAt)
        providerRoute = try container.decode(V0AIProviderRoute.self, forKey: .providerRoute)
        liveModelCallsEnabled = try container.decode(Bool.self, forKey: .liveModelCallsEnabled)
        liveModelUsed = try container.decodeIfPresent(Bool.self, forKey: .liveModelUsed) ?? false
        usedFallback = try container.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false
        fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
        promptVersion = try container.decodeIfPresent(String.self, forKey: .promptVersion)
        policyRevision = try container.decodeIfPresent(String.self, forKey: .policyRevision)
        externalActionTaken = try container.decode(Bool.self, forKey: .externalActionTaken)
        result = try container.decode(Result.self, forKey: .result)
    }

    func validateRequestID(_ expectedRequestID: UUID) throws {
        guard requestID == expectedRequestID else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow response did not match the request ID.")
        }
    }

    func validateUserID(_ expectedUserID: String) throws {
        guard userID == expectedUserID else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow response did not match the authenticated user.")
        }
    }

    func workflowRun(expectedKind: V0AIWorkflowKind, requestedAt: Date) throws -> V0AIWorkflowRun {
        guard ok else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow returned ok=false.")
        }
        guard schemaVersion == 1 else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow returned an unsupported schema version.")
        }
        guard kind == expectedKind else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow kind did not match the request.")
        }
        guard providerRoute == .firebaseCallableGenkit else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow returned an unexpected provider route.")
        }
        guard !externalActionTaken else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflows cannot take external actions.")
        }
        guard !liveModelUsed || (liveModelCallsEnabled && !usedFallback) else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow returned inconsistent live-model metadata.")
        }
        guard usedFallback == (fallbackReason != nil) else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow returned inconsistent fallback metadata.")
        }
        guard !liveModelUsed || (promptVersion != nil && policyRevision != nil) else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow omitted required live-model policy metadata.")
        }
        guard !liveModelCallsEnabled || liveModelUsed || usedFallback else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow did not explain why enabled live generation was not used.")
        }

        return V0AIWorkflowRun(
            kind: expectedKind,
            providerRoute: .firebaseCallableGenkit,
            requestedAt: requestedAt,
            completedAt: evaluatedAt,
            usedFallback: usedFallback,
            failureMessage: usedFallback ? AIWorkflowAuditRecord.fallbackFailureSummary : nil
        )
    }
}

private struct FirebaseCallableQuestPlanResult: Decodable {
    var quests: [FirebaseCallableQuestDTO]
}

private struct FirebaseCallableAdaptiveCareerIntakeResult: Decodable {
    var questions: [V0AdaptiveCareerQuestion]
    var hypotheses: [V0AdaptiveCareerHypothesis]
}

private struct FirebaseCallableMissionBriefResult: Decodable {
    var targetOutcome: String
    var confirmedCurrentState: [FirebaseCallableMissionFactDTO]
    var constraints: String
    var mainReadinessGaps: [String]
    var ethicalBoundaries: [String]
    var firstMilestone: String
    var dailyCommitmentMinutes: Int
    var sprint: CareerMissionSprint
}

private struct FirebaseCallableAdaptiveCareerIntakePayload: Codable, Equatable, Sendable {
    var confirmedFacts: [FirebaseCallableAdaptiveFactDTO]
    var pendingHypotheses: [FirebaseCallableAdaptiveHypothesisDTO]
    var rejectedHypothesisIDs: [UUID]
    var unknownKinds: [CareerFactKind]
    var questionHistory: [V0AdaptiveCareerQuestionAnswer]
    var maxQuestions: Int

    init(request: V0AdaptiveCareerIntakeRequest) {
        confirmedFacts = request.confirmedFacts.map(FirebaseCallableAdaptiveFactDTO.init)
        pendingHypotheses = request.pendingHypotheses.map(FirebaseCallableAdaptiveHypothesisDTO.init)
        rejectedHypothesisIDs = request.rejectedHypothesisIDs
        unknownKinds = request.unknownKinds
        questionHistory = request.questionHistory
        maxQuestions = request.maxQuestions
    }
}

private struct FirebaseCallableAdaptiveFactDTO: Codable, Equatable, Sendable {
    var id: UUID
    var kind: CareerFactKind
    var value: String
    var source: CareerFactSource
    var confirmationState: CareerFactConfirmationState?
    var lastUpdatedAt: Date

    init(fact: CareerFactRecord) {
        id = fact.id
        kind = fact.kind
        value = fact.value
        source = fact.provenance.source
        confirmationState = fact.provenance.source == .aiHypothesis ? .confirmed : nil
        lastUpdatedAt = fact.lastUpdatedAt
    }
}

private struct FirebaseCallableAdaptiveHypothesisDTO: Codable, Equatable, Sendable {
    var id: UUID
    var kind: CareerFactKind
    var value: String
    var source: CareerFactSource
    var confirmationState: CareerFactConfirmationState
    var lastUpdatedAt: Date

    init(fact: CareerFactRecord) {
        id = fact.id
        kind = fact.kind
        value = fact.value
        source = fact.provenance.source
        confirmationState = fact.confirmationState
        lastUpdatedAt = fact.lastUpdatedAt
    }
}

private struct FirebaseCallableDiagnosticPayload: Codable, Equatable, Sendable {
    var goal: FirebaseCallableCareerGoalDTO
    var requestedAt: Date

    init(request: V0DiagnosticRequest) {
        goal = FirebaseCallableCareerGoalDTO(goal: request.goal)
        requestedAt = request.requestedAt
    }
}

private struct FirebaseCallableMissionBriefPayload: Codable, Equatable, Sendable {
    var goal: FirebaseCallableCareerGoalDTO
    var confirmedFacts: [FirebaseCallableMissionFactDTO]
    var diagnostic: CookedDiagnostic
    var requiredEthicalBoundaries: [String]
    var requestedAt: Date

    init(request: V0MissionBriefRequest) {
        goal = FirebaseCallableCareerGoalDTO(goal: request.goal)
        confirmedFacts = request.confirmedFacts.map(FirebaseCallableMissionFactDTO.init)
        diagnostic = request.diagnostic
        requiredEthicalBoundaries = request.requiredEthicalBoundaries
        requestedAt = request.requestedAt
    }
}

private struct FirebaseCallableMissionFactDTO: Codable, Equatable, Sendable {
    var id: UUID
    var kind: CareerFactKind
    var value: String
    var source: CareerFactSource
    var confirmationState: CareerFactConfirmationState
    var lastUpdatedAt: Date

    init(fact: CareerFactRecord) {
        id = fact.id
        kind = fact.kind
        value = fact.value
        source = fact.provenance.source
        confirmationState = fact.confirmationState
        lastUpdatedAt = fact.lastUpdatedAt
    }
}

private struct FirebaseCallableQuestPlanPayload: Codable, Equatable, Sendable {
    var goal: FirebaseCallableCareerGoalDTO
    var diagnostic: CookedDiagnostic
    var mission: FirebaseCallableQuestMissionDTO?
    var chapterTwoContext: V0ChapterTwoPlanContext?
    var requestedAt: Date

    init(request: V0QuestPlanRequest) {
        goal = FirebaseCallableCareerGoalDTO(goal: request.goal)
        diagnostic = request.diagnostic
        mission = request.mission.map(FirebaseCallableQuestMissionDTO.init)
        chapterTwoContext = request.chapterTwoContext
        requestedAt = request.requestedAt
    }
}

private struct FirebaseCallableQuestMissionDTO: Codable, Equatable, Sendable {
    var targetOutcome: String
    var confirmedCurrentState: [FirebaseCallableMissionFactDTO]
    var constraints: String
    var mainReadinessGaps: [String]
    var ethicalBoundaries: [String]
    var firstMilestone: String
    var dailyCommitmentMinutes: Int
    var sprint: CareerMissionSprint

    init(mission: CareerMissionBrief) {
        targetOutcome = mission.targetOutcome
        confirmedCurrentState = mission.confirmedCurrentState.map(FirebaseCallableMissionFactDTO.init)
        constraints = mission.constraints
        mainReadinessGaps = mission.mainReadinessGaps
        ethicalBoundaries = mission.ethicalBoundaries
        firstMilestone = mission.firstMilestone
        dailyCommitmentMinutes = mission.dailyCommitmentMinutes
        sprint = mission.sprint
    }
}

private struct FirebaseCallableProofQualityPayload: Codable, Equatable, Sendable {
    var context: FirebaseCallableWorkflowContextDTO
    var proof: FirebaseCallableProofSubmissionDTO
    var requestedAt: Date
    var targetRoleTitle: String

    init(request: V0ProofReviewRequest) {
        context = FirebaseCallableWorkflowContextDTO(context: request.context)
        proof = FirebaseCallableProofSubmissionDTO(proof: request.proof)
        requestedAt = request.requestedAt
        targetRoleTitle = request.targetRoleTitle
    }
}

private struct FirebaseCallableProgressSummaryPayload: Codable, Equatable, Sendable {
    var context: FirebaseCallableWorkflowContextDTO
    var requestedAt: Date
    var targetRoleTitle: String

    init(request: V0ProgressSummaryRequest) {
        context = FirebaseCallableWorkflowContextDTO(context: request.context)
        requestedAt = request.requestedAt
        targetRoleTitle = request.targetRoleTitle
    }
}

private struct FirebaseCallableCareerGoalDTO: Codable, Equatable, Sendable {
    var currentStatus: String
    var targetRole: String
    var timeline: String
    var background: String
    var existingProof: String
    var confidence: Int
    var biggestBlocker: String
    var outcomeType: CareerOutcomeType
    var urgency: CareerUrgency
    var constraints: String
    var dailyCommitmentMinutes: Int

    init(goal: CareerGoal) {
        currentStatus = goal.currentStatus.rawValue
        targetRole = goal.targetRole
        timeline = goal.timeline
        background = goal.background
        existingProof = goal.existingProof
        confidence = goal.confidence
        biggestBlocker = goal.biggestBlocker
        outcomeType = goal.outcomeType
        urgency = goal.urgency
        constraints = goal.constraints
        dailyCommitmentMinutes = goal.dailyCommitmentMinutes
    }
}

private struct FirebaseCallableWorkflowContextDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var targetRoleTitle: String
    var currentQuest: FirebaseCallableQuestContextDTO?
    var progress: V0ProgressContext
    var privacy: V0AIBackendPrivacyMetadata
    var allowsLongTermMemoryWrite: Bool

    init(context: V0AIWorkflowContextSnapshot) {
        schemaVersion = context.schemaVersion
        targetRoleTitle = context.targetRoleTitle
        currentQuest = context.currentQuest.map(FirebaseCallableQuestContextDTO.init)
        progress = context.progress
        privacy = V0AIBackendPrivacyMetadata(privacy: context.privacy)
        allowsLongTermMemoryWrite = context.allowsLongTermMemoryWrite
    }
}

private struct FirebaseCallableQuestContextDTO: Codable, Equatable, Sendable {
    var id: UUID
    var day: Int
    var title: String
    var purpose: String
    var timeEstimateMinutes: Int
    var difficulty: String
    var gap: String
    var proofRequired: String
    var xpReward: Int
    var steps: [String]

    init(quest: Quest) {
        id = quest.id
        day = quest.day
        title = quest.title
        purpose = quest.purpose
        timeEstimateMinutes = quest.timeEstimateMinutes
        difficulty = quest.difficulty
        gap = quest.gap.rawValue
        proofRequired = quest.proofRequired
        xpReward = quest.xpReward
        steps = quest.steps
    }
}

private struct FirebaseCallableProofSubmissionDTO: Codable, Equatable, Sendable {
    var kind: String
    var text: String
    var link: String
    var submittedAt: Date
    var attachments: [FirebaseCallableProofAttachmentDTO]

    init(proof: ProofSubmission) {
        kind = proof.kind.rawValue
        text = proof.text
        link = proof.link
        submittedAt = proof.submittedAt
        attachments = proof.attachments.map(FirebaseCallableProofAttachmentDTO.init)
    }
}

private struct FirebaseCallableProofAttachmentDTO: Codable, Equatable, Sendable {
    var contentType: String
    var byteCount: Int

    init(attachment: ProofAttachment) {
        contentType = attachment.contentType
        byteCount = attachment.byteCount
    }
}

private struct FirebaseCallableQuestDTO: Decodable {
    var id: UUID?
    var day: Int
    var title: String
    var purpose: String
    var timeEstimateMinutes: Int
    var difficulty: String
    var gap: String
    var proofRequired: String
    var xpReward: Int
    var steps: [String]
    var status: QuestStatus?

    func appQuest(index: Int, requestID: UUID) -> Quest {
        Quest(
            id: id ?? Self.fallbackID(requestID: requestID, day: day, index: index),
            day: day,
            title: title,
            purpose: purpose,
            timeEstimateMinutes: timeEstimateMinutes,
            difficulty: difficulty,
            gap: CareerGap.backendAIValue(gap),
            proofRequired: proofRequired,
            xpReward: xpReward,
            steps: steps,
            status: status ?? (day == 1 ? .available : .locked)
        )
    }

    private static func fallbackID(requestID: UUID, day: Int, index: Int) -> UUID {
        let safeDay = max(0, min(day, 999_999))
        let safeIndex = max(0, min(index, 999_999))
        let prefix = String(requestID.uuidString.prefix(24))
        return UUID(uuidString: String(format: "\(prefix)%06d%06d", safeDay, safeIndex)) ?? UUID()
    }
}

private struct FirebaseCallableProgressSummaryResult: Decodable {
    var summary: String
    var readiness: ReadinessMetrics
    var nextQuestTitle: String?
}

private extension CareerGap {
    static func backendAIValue(_ value: String) -> CareerGap {
        if let gap = CareerGap(rawValue: value) {
            return gap
        }

        switch value {
        case "skillProof", "missingProof", "portfolio", "proof":
            return .proofStrength
        case "networkStrength", "network":
            return .networking
        case "target", "targetRole":
            return .targetClarity
        default:
            return .proofStrength
        }
    }
}

enum FirebaseCallableAIWorkflowJSON {
    static func dictionary<T: Encodable>(from value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseCallableAIWorkflowServiceError.payloadEncodingFailed
        }
        return object
    }

    static func decode<T: Decodable>(_ type: T.Type, fromJSONObject object: Any) throws -> T {
        try decode(type, fromData: data(fromJSONObject: object))
    }

    static func data(fromJSONObject object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw FirebaseCallableAIWorkflowServiceError.responseDecodingFailed
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func decode<T: Decodable>(_ type: T.Type, fromData data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                if let date = Self.date(from: value) {
                    return date
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Date is not a supported ISO 8601 string."
                )
            }
            return try decoder.decode(type, from: data)
        } catch {
            throw FirebaseCallableAIWorkflowServiceError.responseDecodingFailed
        }
    }

    private static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: value)
    }

    #if canImport(FirebaseSharedSwift)
    static func firebaseDataEncoder() -> FirebaseDataEncoder {
        let encoder = FirebaseDataEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func firebaseDataDecoder() -> FirebaseDataDecoder {
        let decoder = FirebaseDataDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date is not a supported ISO 8601 string."
            )
        }
        return decoder
    }
    #endif
}
