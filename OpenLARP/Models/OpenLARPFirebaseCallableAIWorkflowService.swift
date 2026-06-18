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

enum FirebaseCallableAIWorkflowServiceError: Error, LocalizedError, Equatable {
    case sdkUnavailable
    case configurationMissing
    case authenticationRequired
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
        case .payloadEncodingFailed:
            "The OpenLARP AI workflow request could not be encoded for Firebase Functions."
        case .responseDecodingFailed:
            "The Firebase callable AI workflow response did not match the app contract."
        case .contractMismatch(let detail):
            detail
        }
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
        return try await callable.call(envelope)
        #else
        throw FirebaseCallableAIWorkflowServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseCallableV0AIWorkflowService: V0AIWorkflowServicing {
    private let configuration: OpenLARPFirebaseCallableAIConfiguration
    private let invoker: any FirebaseCallableInvoking
    private let preflight: @MainActor () throws -> Void
    private let makeRequestID: @MainActor () -> UUID

    init(
        configuration: OpenLARPFirebaseCallableAIConfiguration = .production,
        invoker: (any FirebaseCallableInvoking)? = nil,
        requestID: @MainActor @escaping () -> UUID = { UUID() },
        preflight: @MainActor @escaping () throws -> Void = FirebaseCallableV0AIWorkflowService.requireConfiguredAuthenticatedFirebase
    ) {
        self.configuration = configuration
        self.invoker = invoker ?? FirebaseFunctionsCallableInvoker(configuration: configuration)
        self.makeRequestID = requestID
        self.preflight = preflight
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
        privacy: CareerUserPrivacySettings,
        payload: Payload
    ) async throws -> FirebaseCallableAIWorkflowResponse<Result> {
        try preflight()
        let requestID = makeRequestID()
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
        return response
    }

    @MainActor
    private static func requireConfiguredAuthenticatedFirebase() throws {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth)
        guard FirebaseApp.app() != nil else {
            throw FirebaseCallableAIWorkflowServiceError.configurationMissing
        }
        guard Auth.auth().currentUser != nil else {
            throw FirebaseCallableAIWorkflowServiceError.authenticationRequired
        }
        #else
        throw FirebaseCallableAIWorkflowServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseCallableAIWorkflowResponse<Result: Decodable>: Decodable {
    var ok: Bool
    var schemaVersion: Int
    var requestID: UUID
    var kind: V0AIWorkflowKind
    var userID: String
    var evaluatedAt: Date
    var providerRoute: V0AIProviderRoute
    var liveModelCallsEnabled: Bool
    var externalActionTaken: Bool
    var result: Result

    func validateRequestID(_ expectedRequestID: UUID) throws {
        guard requestID == expectedRequestID else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow response did not match the request ID.")
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
        guard !liveModelCallsEnabled, !externalActionTaken else {
            throw FirebaseCallableAIWorkflowServiceError.contractMismatch("Firebase callable AI workflow returned a live-model or external-action response before production gates are enabled.")
        }

        return V0AIWorkflowRun(
            kind: expectedKind,
            providerRoute: .firebaseCallableGenkit,
            requestedAt: requestedAt,
            completedAt: evaluatedAt
        )
    }
}

private struct FirebaseCallableQuestPlanResult: Decodable {
    var quests: [FirebaseCallableQuestDTO]
}

private struct FirebaseCallableDiagnosticPayload: Codable, Equatable, Sendable {
    var goal: FirebaseCallableCareerGoalDTO
    var requestedAt: Date

    init(request: V0DiagnosticRequest) {
        goal = FirebaseCallableCareerGoalDTO(goal: request.goal)
        requestedAt = request.requestedAt
    }
}

private struct FirebaseCallableQuestPlanPayload: Codable, Equatable, Sendable {
    var goal: FirebaseCallableCareerGoalDTO
    var diagnostic: CookedDiagnostic
    var requestedAt: Date

    init(request: V0QuestPlanRequest) {
        goal = FirebaseCallableCareerGoalDTO(goal: request.goal)
        diagnostic = request.diagnostic
        requestedAt = request.requestedAt
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

    init(goal: CareerGoal) {
        currentStatus = goal.currentStatus.rawValue
        targetRole = goal.targetRole
        timeline = goal.timeline
        background = goal.background
        existingProof = goal.existingProof
        confidence = goal.confidence
        biggestBlocker = goal.biggestBlocker
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
