import Foundation

enum V0AIWorkflowKind: String, Codable, CaseIterable, Identifiable {
    case adaptiveCareerIntake
    case cookedDiagnostic
    case missionBrief
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

enum V0AdaptiveCareerResponseType: String, Codable, Equatable, Sendable {
    case freeText
    case singleChoice
    case duration
    case confidence
}

struct V0AdaptiveCareerQuestion: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var factKind: CareerFactKind
    var question: String
    var rationale: String
    var responseType: V0AdaptiveCareerResponseType
    var options: [String]
}

struct V0AdaptiveCareerHypothesis: Codable, Equatable, Sendable {
    var kind: CareerFactKind
    var value: String
    var confirmationState: CareerFactConfirmationState

    init(
        kind: CareerFactKind,
        value: String,
        confirmationState: CareerFactConfirmationState = .awaitingConfirmation
    ) {
        self.kind = kind
        self.value = value
        self.confirmationState = confirmationState
    }
}

struct V0AdaptiveCareerQuestionAnswer: Codable, Equatable, Sendable {
    var factKind: CareerFactKind
    var question: String
    var answer: String
}

struct V0AdaptiveCareerIntakeRequest: Equatable, Sendable {
    private static let questionPriority: [CareerFactKind] = [
        .existingProof,
        .experience,
        .constraints,
        .biggestBlocker,
        .timeline,
        .currentStage,
        .confidence,
        .dailyCommitment,
        .urgency,
        .outcomeType,
        .targetOutcome
    ]

    var confirmedFacts: [CareerFactRecord]
    var pendingHypotheses: [CareerFactRecord]
    var rejectedHypothesisIDs: [UUID]
    var unknownKinds: [CareerFactKind]
    var questionHistory: [V0AdaptiveCareerQuestionAnswer]
    var maxQuestions: Int
    var requestedAt: Date
    var requestID: UUID

    init(
        understanding: CareerUnderstanding,
        questionHistory: [V0AdaptiveCareerQuestionAnswer] = [],
        maxQuestions: Int = 1,
        requestedAt: Date,
        requestID: UUID = UUID()
    ) {
        confirmedFacts = Array(understanding.confirmedFacts.prefix(24))
        pendingHypotheses = Array(understanding.pendingHypotheses.prefix(12))
        rejectedHypothesisIDs = Array(understanding.rejectedFacts
            .filter { $0.provenance.source == .aiHypothesis }
            .map(\.id)
            .prefix(24))
        let unknownSet = Set(understanding.unknowns.map(\.kind))
        unknownKinds = Self.questionPriority.filter(unknownSet.contains)
        self.questionHistory = questionHistory.prefix(8).compactMap { item in
            guard let question = Self.bounded(item.question, limit: 240),
                  let answer = Self.bounded(item.answer, limit: 4_000) else {
                return nil
            }
            return V0AdaptiveCareerQuestionAnswer(
                factKind: item.factKind,
                question: question,
                answer: answer
            )
        }
        self.maxQuestions = max(0, min(maxQuestions, 3))
        self.requestedAt = requestedAt
        self.requestID = requestID
    }

    private static func bounded(_ value: String, limit: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}

enum V0AdaptiveCareerIntakeContractError: Error, Equatable {
    case requestIDMismatch
    case unexpectedWorkflowKind
    case tooManyQuestions
    case duplicateQuestion
    case questionForKnownFact
    case invalidQuestion
    case invalidHypothesis
}

struct V0AdaptiveCareerIntakeResponse: Equatable, Sendable {
    var requestID: UUID
    var run: V0AIWorkflowRun
    var questions: [V0AdaptiveCareerQuestion]
    var hypotheses: [V0AdaptiveCareerHypothesis]

    func validate(for request: V0AdaptiveCareerIntakeRequest) throws {
        guard requestID == request.requestID else {
            throw V0AdaptiveCareerIntakeContractError.requestIDMismatch
        }
        guard run.kind == .adaptiveCareerIntake else {
            throw V0AdaptiveCareerIntakeContractError.unexpectedWorkflowKind
        }
        guard questions.count <= request.maxQuestions else {
            throw V0AdaptiveCareerIntakeContractError.tooManyQuestions
        }
        let questionIDs = questions.map(\.id)
        let questionKinds = questions.map(\.factKind)
        guard questions.allSatisfy({ question in
            (1...64).contains(question.id.count) &&
                !question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (1...240).contains(question.question.count) &&
                !question.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (1...240).contains(question.rationale.count) &&
                !question.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                question.options.count <= 6 &&
                question.options.allSatisfy {
                    (1...120).contains($0.count) &&
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        }) else {
            throw V0AdaptiveCareerIntakeContractError.invalidQuestion
        }
        guard Set(questionIDs).count == questionIDs.count,
              Set(questionKinds).count == questionKinds.count else {
            throw V0AdaptiveCareerIntakeContractError.duplicateQuestion
        }
        let unknownKinds = Set(request.unknownKinds)
        guard questionKinds.allSatisfy(unknownKinds.contains) else {
            throw V0AdaptiveCareerIntakeContractError.questionForKnownFact
        }
        let pendingHypothesisKinds = Set(request.pendingHypotheses.map(\.kind))
        let hypothesisKinds = hypotheses.map(\.kind)
        guard hypotheses.count + request.pendingHypotheses.count <= 2,
              Set(hypothesisKinds).count == hypothesisKinds.count,
              hypotheses.allSatisfy({
                  $0.confirmationState == .awaitingConfirmation &&
                      unknownKinds.contains($0.kind) &&
                      !pendingHypothesisKinds.contains($0.kind) &&
                      (1...4_000).contains($0.value.count) &&
                      !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw V0AdaptiveCareerIntakeContractError.invalidHypothesis
        }
    }
}

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
    var allowsPrivateEvidenceCloudSync: Bool

    init(
        privacy: CareerUserPrivacySettings,
        allowsLongTermMemoryWrite: Bool? = nil
    ) {
        self.memoryMode = privacy.memoryMode
        self.allowsLongTermMemoryWrite = allowsLongTermMemoryWrite ?? V0AIWorkflowContext
            .allowsLongTermMemoryWrite(for: privacy)
        self.requiresUserApprovalForExternalActions = privacy.requireApprovalForExternalActions
        self.shareWins = privacy.shareWins
        self.allowsPrivateEvidenceCloudSync = privacy.allowsPrivateEvidenceCloudSync
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

struct V0MissionBriefRequest: Codable, Equatable {
    var schemaVersion: Int
    var goal: CareerGoal
    var confirmedFacts: [CareerFactRecord]
    var diagnostic: CookedDiagnostic
    var requiredEthicalBoundaries: [String]
    var requestedAt: Date
    var safetyRules: V0AISafetyRules

    init(
        goal: CareerGoal,
        understanding: CareerUnderstanding,
        diagnostic: CookedDiagnostic,
        requestedAt: Date,
        schemaVersion: Int = 1,
        safetyRules: V0AISafetyRules = .v0Default
    ) throws {
        guard understanding.reviewState == .approved,
              understanding.pendingHypotheses.isEmpty else {
            throw OpenLARPError.careerUnderstandingNeedsReview
        }
        self.schemaVersion = schemaVersion
        self.goal = goal
        confirmedFacts = understanding.confirmedFacts
        self.diagnostic = diagnostic
        requiredEthicalBoundaries = CareerMissionBrief.requiredEthicalBoundaries
        self.requestedAt = requestedAt
        self.safetyRules = safetyRules
    }
}

struct V0MissionBriefResponse: Codable, Equatable {
    var run: V0AIWorkflowRun
    var mission: CareerMissionBrief

    func validate(for request: V0MissionBriefRequest) throws {
        try mission.validate()
        guard run.kind == .missionBrief,
              mission.reviewState == .awaitingApproval,
              mission.targetOutcome == request.goal.targetRole,
              mission.constraints == request.goal.constraints.trimmingCharacters(in: .whitespacesAndNewlines),
              mission.confirmedCurrentState == request.confirmedFacts,
              mission.ethicalBoundaries == request.requiredEthicalBoundaries,
              mission.dailyCommitmentMinutes == request.goal.dailyCommitmentMinutes,
              mission.providerRoute == run.providerRoute,
              mission.usedFallback == run.usedFallback else {
            throw OpenLARPError.invalidMissionBrief
        }
    }
}

struct V0QuestPlanRequest: Codable, Equatable {
    var schemaVersion: Int
    var goal: CareerGoal
    var diagnostic: CookedDiagnostic
    var mission: CareerMissionBrief?
    var chapterTwoContext: V0ChapterTwoPlanContext?
    var requestedAt: Date
    var safetyRules: V0AISafetyRules

    init(
        goal: CareerGoal,
        diagnostic: CookedDiagnostic,
        mission: CareerMissionBrief? = nil,
        chapterTwoContext: V0ChapterTwoPlanContext? = nil,
        requestedAt: Date,
        schemaVersion: Int = 1,
        safetyRules: V0AISafetyRules = .v0Default
    ) {
        self.schemaVersion = schemaVersion
        self.goal = goal
        self.diagnostic = diagnostic
        self.mission = mission
        self.chapterTwoContext = chapterTwoContext
        self.requestedAt = requestedAt
        self.safetyRules = safetyRules
    }
}

struct V0ChapterTwoQuestEvidence: Codable, Equatable {
    var questTitle: String
    var gap: CareerGap
    var qualityScore: Int
}

struct V0ChapterTwoPlanContext: Codable, Equatable {
    var sprintID: UUID
    var checkpointSummary: String
    var nextFocus: String
    var readiness: ReadinessMetrics
    var completedQuestCount: Int
    var proofCount: Int
    var outcomeCount: Int
    var completedQuestEvidence: [V0ChapterTwoQuestEvidence]

    init(state: OpenLARPState, report: CareerSprintCheckpointReport) throws {
        guard let sprint = state.activeSprint,
              sprint.id == report.sprintID,
              sprint.phase == .chapterOneReview,
              report.checkpointDay == 7 else {
            throw OpenLARPError.invalidSprintLifecycle
        }
        let proofsByQuestID = Dictionary(
            grouping: state.progress.recentProof,
            by: \.questID
        )
        sprintID = sprint.id
        checkpointSummary = report.summary
        nextFocus = report.nextFocus
        readiness = report.endReadiness
        completedQuestCount = report.completedQuestCount
        proofCount = report.proofCount
        outcomeCount = report.outcomeCount
        completedQuestEvidence = state.plan.prefix(7).map { quest in
            V0ChapterTwoQuestEvidence(
                questTitle: quest.title,
                gap: quest.gap,
                qualityScore: proofsByQuestID[quest.id]?.compactMap { $0.quality?.qualityScore }.max() ?? 0
            )
        }
    }
}

extension V0ChapterTwoPlanContext: @unchecked Sendable {}

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
    func generateAdaptiveCareerIntake(
        _ request: V0AdaptiveCareerIntakeRequest
    ) async throws -> V0AdaptiveCareerIntakeResponse
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse
    func generateMissionBrief(_ request: V0MissionBriefRequest) async throws -> V0MissionBriefResponse
    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse
    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse
    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse
}

struct LocalMockV0AIWorkflowService: V0AIWorkflowServicing {
    func generateAdaptiveCareerIntake(
        _ request: V0AdaptiveCareerIntakeRequest
    ) async throws -> V0AdaptiveCareerIntakeResponse {
        let questions = request.unknownKinds.prefix(request.maxQuestions).map { kind in
            V0AdaptiveCareerQuestion(
                id: "adaptive-\(kind.rawValue)",
                factKind: kind,
                question: kind.unknownPrompt,
                rationale: "This missing detail changes which first action is realistic and useful.",
                responseType: .freeText,
                options: []
            )
        }
        let response = V0AdaptiveCareerIntakeResponse(
            requestID: request.requestID,
            run: run(kind: .adaptiveCareerIntake, requestedAt: request.requestedAt),
            questions: Array(questions),
            hypotheses: []
        )
        try response.validate(for: request)
        return response
    }

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        V0DiagnosticResponse(
            run: run(kind: .cookedDiagnostic, requestedAt: request.requestedAt),
            diagnostic: V0LocalAIWorkflowFallback.makeDiagnostic(for: request.goal)
        )
    }

    func generateMissionBrief(_ request: V0MissionBriefRequest) async throws -> V0MissionBriefResponse {
        let run = run(kind: .missionBrief, requestedAt: request.requestedAt)
        let mission = try CareerMissionBrief.proposal(
            targetOutcome: request.goal.targetRole,
            confirmedCurrentState: request.confirmedFacts,
            constraints: request.goal.constraints,
            mainReadinessGaps: request.diagnostic.readinessGaps ?? [request.diagnostic.mainGap],
            ethicalBoundaries: request.requiredEthicalBoundaries,
            firstMilestone: request.diagnostic.firstAction ?? request.diagnostic.fastestFix,
            dailyCommitmentMinutes: request.goal.dailyCommitmentMinutes,
            sprint: .richV0,
            providerRoute: run.providerRoute,
            usedFallback: run.usedFallback,
            generatedAt: request.requestedAt
        )
        let response = V0MissionBriefResponse(run: run, mission: mission)
        try response.validate(for: request)
        return response
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        V0QuestPlanResponse(
            run: run(kind: .questPlan, requestedAt: request.requestedAt),
            quests: request.chapterTwoContext == nil
                ? V0LocalAIWorkflowFallback.makeSevenDayPlan(for: request.goal)
                : V0LocalAIWorkflowFallback.makeChapterTwoPlan(for: request.goal)
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
        fallback: any V0AIWorkflowServicing
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func generateAdaptiveCareerIntake(
        _ request: V0AdaptiveCareerIntakeRequest
    ) async throws -> V0AdaptiveCareerIntakeResponse {
        do {
            return try await primary.generateAdaptiveCareerIntake(request)
        } catch {
            guard shouldUseLocalFallback(for: error) else { throw error }
            var response = try await fallback.generateAdaptiveCareerIntake(request)
            response.run = response.run.markedAsFallback(failureMessage: String(describing: error))
            return response
        }
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

    func generateMissionBrief(_ request: V0MissionBriefRequest) async throws -> V0MissionBriefResponse {
        do {
            return try await primary.generateMissionBrief(request)
        } catch {
            guard shouldUseLocalFallback(for: error) else { throw error }
            var response = try await fallback.generateMissionBrief(request)
            response.run = response.run.markedAsFallback(failureMessage: String(describing: error))
            response.mission.providerRoute = response.run.providerRoute
            response.mission.usedFallback = true
            try response.validate(for: request)
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
        let duration: (Int) -> Int = { suggestedMinutes in
            max(5, min(suggestedMinutes, goal.dailyCommitmentMinutes))
        }
        return [
            Quest(
                id: questIDs[0],
                day: 1,
                title: "Map 3 real requirements for \(goal.targetRole)",
                purpose: "You need proof that matches what the role actually asks for, not a vague interest list.",
                timeEstimateMinutes: duration(25),
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
                timeEstimateMinutes: duration(30),
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
                timeEstimateMinutes: duration(20),
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
                timeEstimateMinutes: duration(25),
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
                timeEstimateMinutes: duration(20),
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
                timeEstimateMinutes: duration(20),
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
                timeEstimateMinutes: duration(15),
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

    static func makeChapterTwoPlan(for goal: CareerGoal) -> [Quest] {
        let duration: (Int) -> Int = { suggestedMinutes in
            max(5, min(suggestedMinutes, goal.dailyCommitmentMinutes))
        }
        let quests: [(String, String, CareerGap, String, [String])] = [
            (
                "Choose the strongest proof from Chapter One",
                "Chapter Two should invest in evidence that already survived a real review.",
                .proofStrength,
                "Name the proof, the requirement it supports, and one honest limitation.",
                ["Review the seven proof receipts.", "Choose the strongest one.", "Write what it proves and what it does not prove."]
            ),
            (
                "Turn the proof into a concise portfolio story",
                "A clear, defensible story makes real work useful in applications and interviews.",
                .confidence,
                "Save the problem, action, tradeoff, result, and next-improvement story.",
                ["State the real problem.", "Describe only your own actions.", "Add the result and one limitation."]
            ),
            (
                "Match the proof to one current role requirement",
                "Focused evidence is more credible than a generic claim of fit.",
                .proofStrength,
                "Save the requirement and the exact proof connection.",
                ["Choose one role description.", "Select one requirement.", "Explain the evidence match without exaggeration."]
            ),
            (
                "Improve one weak edge in the proof",
                "A small targeted revision can raise credibility without expanding the project.",
                .proofStrength,
                "Document the before, the focused revision, and the after.",
                ["Choose one limitation.", "Make one bounded improvement.", "Record what changed."]
            ),
            (
                "Use the proof in one honest outreach draft",
                "Specific work gives a networking message a real reason to exist.",
                .networking,
                "Save or send a concise message that references the real artifact.",
                ["Choose one relevant person.", "Reference the proof briefly.", "Ask one low-pressure question."]
            ),
            (
                "Use the proof in one focused application action",
                "The sprint should connect evidence to a real opportunity, not stop at preparation.",
                .proofStrength,
                "Save the tailored bullet, application receipt, or final application-ready draft.",
                ["Choose one relevant opportunity.", "Tailor one truthful section.", "Submit or save the final ready-to-send version."]
            ),
            (
                "Run the 14-day evidence review",
                "A final review should show what changed and choose the next honest focus.",
                .consistency,
                "Write the strongest result, readiness change, outcome signal, and next focus.",
                ["Review all fourteen quests.", "Name the strongest evidence and outcome.", "Choose the next sprint focus."]
            )
        ]
        return quests.enumerated().map { offset, template in
            Quest(
                day: offset + 8,
                title: template.0,
                purpose: template.1,
                timeEstimateMinutes: duration(offset == 6 ? 15 : 25),
                difficulty: offset == 6 ? "Review" : "Adaptive",
                gap: template.2,
                proofRequired: template.3,
                xpReward: offset == 6 ? 160 : 130,
                steps: template.4,
                status: .locked
            )
        }
    }

    private static func strongestSignal(for goal: CareerGoal) -> String {
        if goal.existingProof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "You have a clear target, but not much evidence yet."
        }
        return "You already have a starting signal. Now it needs to become defensible proof."
    }
}
