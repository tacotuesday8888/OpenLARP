import Foundation

enum V0AIWorkflowKind: String, Codable, CaseIterable, Identifiable {
    case cookedDiagnostic
    case questPlan
    case proofQualityCheck
    case progressSummary

    var id: String { rawValue }
}

extension V0AIWorkflowKind: Sendable {}

enum V0AIProviderRoute: String, Codable, CaseIterable, Identifiable {
    case localMock
    case firebaseCallableGenkit
    case cloudRunGenkit

    var id: String { rawValue }
}

extension V0AIProviderRoute: Sendable {}

struct V0AISafetyRules: Codable, Equatable {
    var hardBannedClaims: [String]
    var requiredBehaviors: [String]
    var privacyRequirements: [String]

    static let v0Default = V0AISafetyRules()

    init(
        hardBannedClaims: [String] = [
            "fake employers",
            "fake schools",
            "fake certificates",
            "fake job titles",
            "fake dates",
            "fake projects",
            "fake ownership claims"
        ],
        requiredBehaviors: [String] = [
            "frame real experience honestly",
            "separate proof from self-report",
            "recommend small truthful next steps"
        ],
        privacyRequirements: [String] = [
            "do not request provider credentials",
            "do not write long-term memory unless the user enabled it",
            "do not take external actions without approval"
        ]
    ) {
        self.hardBannedClaims = hardBannedClaims
        self.requiredBehaviors = requiredBehaviors
        self.privacyRequirements = privacyRequirements
    }
}

extension V0AISafetyRules: Sendable {}

struct V0AIBackendPrivateIdentifiers: Equatable {
    static let none = V0AIBackendPrivateIdentifiers()

    var ownerUserID: String?
    var accountID: String?
    var sessionID: String?
    var email: String?

    init(
        ownerUserID: String? = nil,
        accountID: String? = nil,
        sessionID: String? = nil,
        email: String? = nil
    ) {
        self.ownerUserID = ownerUserID
        self.accountID = accountID
        self.sessionID = sessionID
        self.email = email
    }
}

struct V0AIBackendPrivacyMetadata: Codable, Equatable {
    var memoryMode: CareerMemoryMode
    var allowsLongTermMemoryWrite: Bool
    var requiresUserApprovalForExternalActions: Bool
    var shareWins: Bool

    init(
        privacy: CareerUserPrivacySettings,
        allowsLongTermMemoryWrite: Bool? = nil
    ) {
        self.memoryMode = privacy.memoryMode
        self.allowsLongTermMemoryWrite = allowsLongTermMemoryWrite ?? V0AIWorkflowContext
            .allowsLongTermMemoryWrite(for: privacy)
        self.requiresUserApprovalForExternalActions = privacy.requireApprovalForExternalActions
        self.shareWins = privacy.shareWins
    }
}

extension V0AIBackendPrivacyMetadata: Sendable {}

struct V0AIBackendRequestRunMetadata: Codable, Equatable {
    var schemaVersion: Int
    var kind: V0AIWorkflowKind
    var providerRoute: V0AIProviderRoute
    var requestedAt: Date
    var requestID: UUID
    var privacy: V0AIBackendPrivacyMetadata

    init(
        kind: V0AIWorkflowKind,
        providerRoute: V0AIProviderRoute,
        requestedAt: Date,
        requestID: UUID = UUID(),
        privacy: CareerUserPrivacySettings = .localDefault,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.providerRoute = providerRoute
        self.requestedAt = requestedAt
        self.requestID = requestID
        self.privacy = V0AIBackendPrivacyMetadata(privacy: privacy)
    }
}

extension V0AIBackendRequestRunMetadata: Sendable {}

struct V0AIBackendRequestEnvelope<Payload: Codable & Equatable>: Codable, Equatable {
    var schemaVersion: Int
    var run: V0AIBackendRequestRunMetadata
    var safetyRules: V0AISafetyRules
    var payload: Payload

    init(
        kind: V0AIWorkflowKind,
        providerRoute: V0AIProviderRoute,
        requestedAt: Date,
        requestID: UUID = UUID(),
        privacy: CareerUserPrivacySettings = .localDefault,
        privateIdentifiers: V0AIBackendPrivateIdentifiers = .none,
        payload: Payload,
        safetyRules: V0AISafetyRules = .v0Default,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        run = V0AIBackendRequestRunMetadata(
            kind: kind,
            providerRoute: providerRoute,
            requestedAt: requestedAt,
            requestID: requestID,
            privacy: privacy,
            schemaVersion: schemaVersion
        )
        self.safetyRules = safetyRules
        self.payload = payload

        _ = privateIdentifiers
    }
}

extension V0AIBackendRequestEnvelope: Sendable where Payload: Sendable {}

struct V0AIWorkflowRun: Codable, Equatable {
    var schemaVersion: Int
    var kind: V0AIWorkflowKind
    var providerRoute: V0AIProviderRoute
    var requestedAt: Date
    var completedAt: Date
    var usedFallback: Bool
    var failureMessage: String?

    init(
        kind: V0AIWorkflowKind,
        providerRoute: V0AIProviderRoute,
        requestedAt: Date,
        completedAt: Date? = nil,
        usedFallback: Bool = false,
        schemaVersion: Int = 1,
        failureMessage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.providerRoute = providerRoute
        self.requestedAt = requestedAt
        self.completedAt = completedAt ?? requestedAt
        self.usedFallback = usedFallback
        self.failureMessage = failureMessage
    }

    func markedAsFallback(failureMessage: String? = nil) -> V0AIWorkflowRun {
        var run = self
        run.usedFallback = true
        run.failureMessage = failureMessage
        return run
    }
}

struct AIWorkflowAuditRecord: Codable, Equatable, Identifiable {
    static let fallbackFailureSummary = "Primary workflow failed; local fallback handled this run."
    static let maxStoredCount = 100

    var id: UUID
    var schemaVersion: Int
    var kind: V0AIWorkflowKind
    var providerRoute: V0AIProviderRoute
    var requestedAt: Date
    var completedAt: Date
    var usedFallback: Bool
    var failureSummary: String?

    init(
        id: UUID = UUID(),
        kind: V0AIWorkflowKind,
        providerRoute: V0AIProviderRoute,
        requestedAt: Date,
        completedAt: Date,
        usedFallback: Bool = false,
        schemaVersion: Int = 1,
        failureSummary: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.providerRoute = providerRoute
        self.requestedAt = Self.persistenceStableDate(requestedAt)
        self.completedAt = Self.persistenceStableDate(completedAt)
        self.usedFallback = usedFallback
        self.failureSummary = Self.safeFailureSummary(from: failureSummary, usedFallback: usedFallback)
    }

    init(run: V0AIWorkflowRun) {
        self.init(
            kind: run.kind,
            providerRoute: run.providerRoute,
            requestedAt: run.requestedAt,
            completedAt: run.completedAt,
            usedFallback: run.usedFallback,
            schemaVersion: run.schemaVersion,
            failureSummary: run.failureMessage
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case kind
        case providerRoute
        case requestedAt
        case completedAt
        case usedFallback
        case failureSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: try container.decode(V0AIWorkflowKind.self, forKey: .kind),
            providerRoute: try container.decode(V0AIProviderRoute.self, forKey: .providerRoute),
            requestedAt: try container.decode(Date.self, forKey: .requestedAt),
            completedAt: try container.decode(Date.self, forKey: .completedAt),
            usedFallback: try container.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false,
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            failureSummary: try container.decodeIfPresent(String.self, forKey: .failureSummary)
        )
    }

    private static func safeFailureSummary(from summary: String?, usedFallback: Bool) -> String? {
        guard usedFallback else { return nil }
        guard summary == fallbackFailureSummary else { return fallbackFailureSummary }
        return summary
    }

    private static func persistenceStableDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }
}

struct LossyAIWorkflowAuditRecordList: Decodable {
    var records: [AIWorkflowAuditRecord]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodedRecords: [AIWorkflowAuditRecord] = []

        while !container.isAtEnd {
            if let record = try? container.decode(AIWorkflowAuditRecord.self) {
                decodedRecords.append(record)
            } else if (try? container.decode(DiscardedAIWorkflowAuditRecord.self)) == nil {
                break
            }
        }

        records = decodedRecords
    }
}

private struct DiscardedAIWorkflowAuditRecord: Decodable {}

struct V0DiagnosticRequest: Codable, Equatable {
    var schemaVersion: Int
    var goal: CareerGoal
    var requestedAt: Date
    var safetyRules: V0AISafetyRules

    init(
        goal: CareerGoal,
        requestedAt: Date,
        schemaVersion: Int = 1,
        safetyRules: V0AISafetyRules = .v0Default
    ) {
        self.schemaVersion = schemaVersion
        self.goal = goal
        self.requestedAt = requestedAt
        self.safetyRules = safetyRules
    }
}

struct V0DiagnosticResponse: Codable, Equatable {
    var run: V0AIWorkflowRun
    var diagnostic: CookedDiagnostic
}

struct V0QuestPlanRequest: Codable, Equatable {
    var schemaVersion: Int
    var goal: CareerGoal
    var diagnostic: CookedDiagnostic
    var requestedAt: Date
    var safetyRules: V0AISafetyRules

    init(
        goal: CareerGoal,
        diagnostic: CookedDiagnostic,
        requestedAt: Date,
        schemaVersion: Int = 1,
        safetyRules: V0AISafetyRules = .v0Default
    ) {
        self.schemaVersion = schemaVersion
        self.goal = goal
        self.diagnostic = diagnostic
        self.requestedAt = requestedAt
        self.safetyRules = safetyRules
    }
}

struct V0QuestPlanResponse: Codable, Equatable {
    var run: V0AIWorkflowRun
    var quests: [Quest]
}

struct V0ProgressContext: Codable, Equatable {
    var readiness: ReadinessMetrics
    var completedQuestCount: Int
    var proofCount: Int
    var streakCount: Int
    var xp: Int
    var xpGoal: Int

    init(progress: ProgressState) {
        readiness = progress.readiness
        completedQuestCount = progress.completedQuestCount
        proofCount = progress.proofCount
        streakCount = progress.streakCount
        xp = progress.xp
        xpGoal = progress.xpGoal
    }
}

struct V0OutcomeContext: Codable, Equatable {
    var activeOutcomeCount: Int
    var latestOutcomeKind: CareerOutcomeKind?
    var latestOutcomeOccurredAt: Date?
    var recentOutcomeKinds: [CareerOutcomeKind]

    init(outcomes: [CareerOutcomeRecord]) {
        let visibleOutcomes = OutcomeLogContent(outcomes: outcomes).outcomes
        activeOutcomeCount = visibleOutcomes.count
        latestOutcomeKind = visibleOutcomes.first?.kind
        latestOutcomeOccurredAt = visibleOutcomes.first?.occurredAt
        recentOutcomeKinds = visibleOutcomes.prefix(5).map(\.kind)
    }
}

struct V0AIWorkflowContextSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var targetRoleTitle: String
    var currentQuest: Quest?
    var progress: V0ProgressContext
    var outcomes: V0OutcomeContext
    var privacy: CareerUserPrivacySettings
    var allowsLongTermMemoryWrite: Bool

    init(
        state: OpenLARPState,
        schemaVersion: Int = 1,
        targetRoleTitle: String? = nil,
        currentQuest: Quest? = nil,
        progress: V0ProgressContext? = nil,
        outcomes: V0OutcomeContext? = nil,
        privacy: CareerUserPrivacySettings? = nil,
        allowsLongTermMemoryWrite: Bool? = nil
    ) {
        let resolvedPrivacy = privacy ?? state.userProfile?.privacy ?? .localDefault

        self.schemaVersion = schemaVersion
        self.targetRoleTitle = targetRoleTitle ?? V0AIWorkflowContext.targetRoleTitle(in: state)
        self.currentQuest = currentQuest ?? state.currentQuest
        self.progress = progress ?? V0ProgressContext(progress: state.progress)
        self.outcomes = outcomes ?? V0OutcomeContext(outcomes: state.outcomeLog)
        self.privacy = resolvedPrivacy
        self.allowsLongTermMemoryWrite = allowsLongTermMemoryWrite ?? V0AIWorkflowContext
            .allowsLongTermMemoryWrite(for: resolvedPrivacy)
    }
}

struct V0ProofReviewRequest: Codable, Equatable {
    var schemaVersion: Int
    var context: V0AIWorkflowContextSnapshot
    var proof: ProofSubmission
    var requestedAt: Date
    var questID: UUID?
    var targetRoleTitle: String
    var privacy: CareerUserPrivacySettings
    var allowsLongTermMemoryWrite: Bool
    var safetyRules: V0AISafetyRules

    init(
        state: OpenLARPState,
        proof: ProofSubmission,
        requestedAt: Date,
        schemaVersion: Int = 1,
        questID: UUID? = nil,
        targetRoleTitle: String? = nil,
        privacy: CareerUserPrivacySettings? = nil,
        allowsLongTermMemoryWrite: Bool? = nil,
        safetyRules: V0AISafetyRules = .v0Default
    ) {
        let resolvedContext = V0AIWorkflowContextSnapshot(
            state: state,
            targetRoleTitle: targetRoleTitle,
            currentQuest: questID.flatMap { id in state.plan.first { $0.id == id } },
            privacy: privacy,
            allowsLongTermMemoryWrite: allowsLongTermMemoryWrite
        )

        self.schemaVersion = schemaVersion
        self.context = resolvedContext
        self.proof = proof
        self.requestedAt = requestedAt
        self.questID = resolvedContext.currentQuest?.id
        self.targetRoleTitle = resolvedContext.targetRoleTitle
        self.privacy = resolvedContext.privacy
        self.allowsLongTermMemoryWrite = resolvedContext.allowsLongTermMemoryWrite
        self.safetyRules = safetyRules
    }
}

struct V0ProofReviewResponse: Codable, Equatable {
    var run: V0AIWorkflowRun
    var result: QualityCheckResult
}

struct V0ProgressSummaryRequest: Codable, Equatable {
    var schemaVersion: Int
    var context: V0AIWorkflowContextSnapshot
    var requestedAt: Date
    var targetRoleTitle: String
    var privacy: CareerUserPrivacySettings
    var allowsLongTermMemoryWrite: Bool
    var safetyRules: V0AISafetyRules

    init(
        state: OpenLARPState,
        requestedAt: Date,
        schemaVersion: Int = 1,
        targetRoleTitle: String? = nil,
        privacy: CareerUserPrivacySettings? = nil,
        allowsLongTermMemoryWrite: Bool? = nil,
        safetyRules: V0AISafetyRules = .v0Default
    ) {
        let resolvedContext = V0AIWorkflowContextSnapshot(
            state: state,
            targetRoleTitle: targetRoleTitle,
            privacy: privacy,
            allowsLongTermMemoryWrite: allowsLongTermMemoryWrite
        )

        self.schemaVersion = schemaVersion
        self.context = resolvedContext
        self.requestedAt = requestedAt
        self.targetRoleTitle = resolvedContext.targetRoleTitle
        self.privacy = resolvedContext.privacy
        self.allowsLongTermMemoryWrite = resolvedContext.allowsLongTermMemoryWrite
        self.safetyRules = safetyRules
    }
}

struct V0ProgressSummaryResponse: Codable, Equatable {
    var run: V0AIWorkflowRun
    var summary: String
    var progress: V0ProgressContext
    var readiness: ReadinessMetrics
    var completedQuestCount: Int
    var proofCount: Int
    var streakCount: Int
    var nextQuestTitle: String?

    init(
        run: V0AIWorkflowRun,
        summary: String,
        progress: V0ProgressContext,
        readiness: ReadinessMetrics? = nil,
        completedQuestCount: Int? = nil,
        proofCount: Int? = nil,
        streakCount: Int? = nil,
        nextQuestTitle: String? = nil
    ) {
        self.run = run
        self.summary = summary
        self.progress = progress
        self.readiness = readiness ?? progress.readiness
        self.completedQuestCount = completedQuestCount ?? progress.completedQuestCount
        self.proofCount = proofCount ?? progress.proofCount
        self.streakCount = streakCount ?? progress.streakCount
        self.nextQuestTitle = nextQuestTitle
    }
}

protocol LocalAIWorkflowFallbackEligibleError: Error {
    var allowsLocalWorkflowFallback: Bool { get }
}

// TODO: Future adapters should route to Firebase callable Genkit or Cloud Run,
// keeping provider SDKs, credentials, and direct LLM calls out of this app target.
@MainActor
protocol V0AIWorkflowServicing {
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse
    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse
    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse
    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse
}

struct LocalMockV0AIWorkflowService: V0AIWorkflowServicing {
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        V0DiagnosticResponse(
            run: run(kind: .cookedDiagnostic, requestedAt: request.requestedAt),
            diagnostic: V0LocalAIWorkflowFallback.makeDiagnostic(for: request.goal)
        )
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        V0QuestPlanResponse(
            run: run(kind: .questPlan, requestedAt: request.requestedAt),
            quests: V0LocalAIWorkflowFallback.makeSevenDayPlan(for: request.goal)
        )
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        guard let quest = request.context.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }

        return V0ProofReviewResponse(
            run: run(kind: .proofQualityCheck, requestedAt: request.requestedAt),
            result: try OpenLARPEngine.checkProof(request.proof, for: quest)
        )
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        V0ProgressSummaryResponse(
            run: run(kind: .progressSummary, requestedAt: request.requestedAt),
            summary: V0LocalAIWorkflowFallback.makeProgressSummary(for: request.context),
            progress: request.context.progress,
            nextQuestTitle: request.context.currentQuest?.title
        )
    }

    private func run(kind: V0AIWorkflowKind, requestedAt: Date) -> V0AIWorkflowRun {
        V0AIWorkflowRun(
            kind: kind,
            providerRoute: .localMock,
            requestedAt: requestedAt
        )
    }
}

struct FallbackV0AIWorkflowService: V0AIWorkflowServicing {
    private let primary: any V0AIWorkflowServicing
    private let fallback: any V0AIWorkflowServicing

    init(
        primary: any V0AIWorkflowServicing,
        fallback: any V0AIWorkflowServicing = LocalMockV0AIWorkflowService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        do {
            return try await primary.generateDiagnostic(request)
        } catch {
            guard shouldUseLocalFallback(for: error) else { throw error }
            var response = try await fallback.generateDiagnostic(request)
            response.run = response.run.markedAsFallback(failureMessage: String(describing: error))
            return response
        }
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        do {
            return try await primary.generateQuestPlan(request)
        } catch {
            guard shouldUseLocalFallback(for: error) else { throw error }
            var response = try await fallback.generateQuestPlan(request)
            response.run = response.run.markedAsFallback(failureMessage: String(describing: error))
            return response
        }
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        do {
            return try await primary.reviewProof(request)
        } catch {
            guard shouldUseLocalFallback(for: error) else { throw error }
            var response = try await fallback.reviewProof(request)
            response.run = response.run.markedAsFallback(failureMessage: String(describing: error))
            return response
        }
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        do {
            return try await primary.summarizeProgress(request)
        } catch {
            guard shouldUseLocalFallback(for: error) else { throw error }
            var response = try await fallback.summarizeProgress(request)
            response.run = response.run.markedAsFallback(failureMessage: String(describing: error))
            return response
        }
    }

    private func shouldUseLocalFallback(for error: Error) -> Bool {
        guard let eligibleError = error as? any LocalAIWorkflowFallbackEligibleError else { return false }
        return eligibleError.allowsLocalWorkflowFallback
    }
}

private enum V0AIWorkflowContext {
    static func targetRoleTitle(in state: OpenLARPState) -> String {
        if let goalTitle = state.goal?.targetRole, !goalTitle.isEmpty {
            return goalTitle
        }
        if let roleTitle = state.targetRoles.first?.title, !roleTitle.isEmpty {
            return roleTitle
        }
        return "Unknown target role"
    }

    static func allowsLongTermMemoryWrite(for privacy: CareerUserPrivacySettings) -> Bool {
        privacy.memoryMode == .cloudReady
    }
}

private enum V0LocalAIWorkflowFallback {
    private static let questIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    ]

    static func makeDiagnostic(for goal: CareerGoal) -> CookedDiagnostic {
        CookedDiagnostic(
            score: 58,
            label: "Medium Cooked",
            mainGap: "Your target is realistic, but your proof is still too thin for \(goal.targetRole).",
            strongestSignal: strongestSignal(for: goal),
            fastestFix: "Turn one target-role requirement into a small artifact you can show or explain.",
            readinessBaseline: ReadinessMetrics.baseline.overall
        )
    }

    static func makeSevenDayPlan(for goal: CareerGoal) -> [Quest] {
        [
            Quest(
                id: questIDs[0],
                day: 1,
                title: "Map 3 real requirements for \(goal.targetRole)",
                purpose: "You need proof that matches what the role actually asks for, not a vague interest list.",
                timeEstimateMinutes: 25,
                difficulty: "Starter",
                gap: .proofStrength,
                proofRequired: "Paste your requirement notes or link to the document.",
                xpReward: 120,
                steps: [
                    "Find two postings or descriptions for the target role.",
                    "Write down three repeated requirements.",
                    "Pick the one requirement you can prove fastest this week."
                ],
                status: .available
            ),
            Quest(
                id: questIDs[1],
                day: 2,
                title: "Create one tiny proof artifact",
                purpose: "A small real artifact beats a big unsupported claim.",
                timeEstimateMinutes: 30,
                difficulty: "Starter",
                gap: .proofStrength,
                proofRequired: "Add a link, screenshot, or notes showing what you made.",
                xpReward: 130,
                steps: [
                    "Choose the smallest artifact that proves one target requirement.",
                    "Make the first version.",
                    "Write what it proves honestly."
                ],
                status: .locked
            ),
            Quest(
                id: questIDs[2],
                day: 3,
                title: "Rewrite one profile bullet from real proof",
                purpose: "Better wording is allowed. Inventing facts is not.",
                timeEstimateMinutes: 20,
                difficulty: "Balanced",
                gap: .confidence,
                proofRequired: "Paste the before and after bullet.",
                xpReward: 100,
                steps: [
                    "Pick one true thing you have done.",
                    "Write the plain version.",
                    "Rewrite it to show impact without adding fake facts."
                ],
                status: .locked
            ),
            Quest(
                id: questIDs[3],
                day: 4,
                title: "Explain your proof in five bullets",
                purpose: "If you cannot explain the work, it will not help in interviews.",
                timeEstimateMinutes: 25,
                difficulty: "Balanced",
                gap: .confidence,
                proofRequired: "Paste the five bullets.",
                xpReward: 110,
                steps: [
                    "Describe the problem.",
                    "Describe your action.",
                    "Name the tradeoff.",
                    "Name the result.",
                    "Name what you would improve next."
                ],
                status: .locked
            ),
            Quest(
                id: questIDs[4],
                day: 5,
                title: "Find one low-friction networking target",
                purpose: "Networking gets easier when the ask is specific and tied to real work.",
                timeEstimateMinutes: 20,
                difficulty: "Spicy",
                gap: .networking,
                proofRequired: "Paste the person's role and why they are relevant.",
                xpReward: 120,
                steps: [
                    "Find one person with a role close to your target.",
                    "Write why their path is useful.",
                    "Draft one honest question."
                ],
                status: .locked
            ),
            Quest(
                id: questIDs[5],
                day: 6,
                title: "Send or save one honest outreach draft",
                purpose: "The goal is a real, low-pressure career action, not fake confidence.",
                timeEstimateMinutes: 20,
                difficulty: "Spicy",
                gap: .networking,
                proofRequired: "Paste the sent message or saved draft.",
                xpReward: 140,
                steps: [
                    "Use the networking target from yesterday.",
                    "Write a short message with one clear ask.",
                    "Send it or save the final draft."
                ],
                status: .locked
            ),
            Quest(
                id: questIDs[6],
                day: 7,
                title: "Run the weekly less-cooked check",
                purpose: "Progress is the point. The app should show what actually changed.",
                timeEstimateMinutes: 15,
                difficulty: "Review",
                gap: .consistency,
                proofRequired: "Write what proof improved and what still blocks you.",
                xpReward: 160,
                steps: [
                    "Review completed quests.",
                    "Name the strongest proof created.",
                    "Pick the next gap to shrink."
                ],
                status: .locked
            )
        ]
    }

    static func makeProgressSummary(for context: V0AIWorkflowContextSnapshot) -> String {
        let targetRole = context.targetRoleTitle
        let progress = context.progress
        let questText = progress.completedQuestCount == 1 ? "1 quest" : "\(progress.completedQuestCount) quests"
        let proofText = progress.proofCount == 1 ? "1 proof receipt" : "\(progress.proofCount) proof receipts"

        if let nextQuest = context.currentQuest {
            return "For \(targetRole), readiness is \(progress.readiness.overall)%. You have completed \(questText), saved \(proofText), and your next move is \(nextQuest.title)."
        }

        return "For \(targetRole), readiness is \(progress.readiness.overall)%. You have completed \(questText) and saved \(proofText)."
    }

    private static func strongestSignal(for goal: CareerGoal) -> String {
        if goal.existingProof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "You have a clear target, but not much evidence yet."
        }
        return "You already have a starting signal. Now it needs to become defensible proof."
    }
}
