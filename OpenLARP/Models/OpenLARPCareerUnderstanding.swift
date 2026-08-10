import Foundation

enum CareerOutcomeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case job
    case internship
    case promotion
    case careerChange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .job: "Job"
        case .internship: "Internship"
        case .promotion: "Promotion"
        case .careerChange: "Career change"
        }
    }
}

enum CareerUrgency: String, Codable, CaseIterable, Identifiable, Sendable {
    case exploring
    case steady
    case urgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exploring: "Exploring"
        case .steady: "Steady"
        case .urgent: "Urgent"
        }
    }
}

enum CareerFactKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case outcomeType
    case targetOutcome
    case currentStage
    case timeline
    case urgency
    case experience
    case existingProof
    case constraints
    case confidence
    case dailyCommitment
    case biggestBlocker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outcomeType: "Outcome type"
        case .targetOutcome: "Target outcome"
        case .currentStage: "Current stage"
        case .timeline: "Timeline"
        case .urgency: "Urgency"
        case .experience: "Experience"
        case .existingProof: "Existing proof"
        case .constraints: "Constraints"
        case .confidence: "Confidence"
        case .dailyCommitment: "Daily commitment"
        case .biggestBlocker: "Biggest blocker"
        }
    }

    var unknownPrompt: String {
        switch self {
        case .outcomeType: "What kind of outcome are you pursuing?"
        case .targetOutcome: "What outcome do you want?"
        case .currentStage: "What is your current career stage?"
        case .timeline: "When do you want this outcome?"
        case .urgency: "How urgent is this goal?"
        case .experience: "What relevant experience do you already have?"
        case .existingProof: "What work can you already show or explain?"
        case .constraints: "What limits should the plan respect?"
        case .confidence: "How confident do you feel right now?"
        case .dailyCommitment: "How much time can you spend each day?"
        case .biggestBlocker: "What is the biggest blocker?"
        }
    }

    var maxValueLength: Int {
        switch self {
        case .targetOutcome, .timeline:
            120
        case .biggestBlocker:
            1_000
        default:
            4_000
        }
    }
}

enum CareerFactSource: String, Codable, Sendable {
    case userEntry
    case userEdit
    case aiHypothesis
    case legacyMigration
}

enum CareerFactConfirmationState: String, Codable, Sendable {
    case awaitingConfirmation
    case confirmed
    case rejected
}

enum CareerFactError: Error, Equatable {
    case aiHypothesisRequiresExplicitUserConfirmation
    case emptyValue
    case missingSourceIdentifier
    case factNotFound
    case factIsNotAwaitingAIConfirmation
    case unresolvedHypotheses
}

struct CareerFactProvenance: Codable, Equatable, Sendable {
    var source: CareerFactSource
    var sourceIdentifier: String?
    var recordedAt: Date
}

struct CareerFactRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: CareerFactKind
    var value: String
    var provenance: CareerFactProvenance
    var confirmationState: CareerFactConfirmationState
    var lastUpdatedAt: Date

    static func userEntry(
        kind: CareerFactKind,
        value: String,
        createdAt: Date
    ) -> CareerFactRecord? {
        guard let value = CareerUnderstandingText.sanitized(value, limit: kind.maxValueLength) else { return nil }
        return CareerFactRecord(
            id: UUID(),
            kind: kind,
            value: value,
            provenance: CareerFactProvenance(
                source: .userEntry,
                sourceIdentifier: nil,
                recordedAt: createdAt
            ),
            confirmationState: .awaitingConfirmation,
            lastUpdatedAt: createdAt
        )
    }

    static func aiHypothesis(
        kind: CareerFactKind,
        value: String,
        workflowRequestID: String,
        createdAt: Date
    ) throws -> CareerFactRecord {
        guard let value = CareerUnderstandingText.sanitized(value, limit: kind.maxValueLength) else {
            throw CareerFactError.emptyValue
        }
        guard let workflowRequestID = CareerUnderstandingText.sanitized(workflowRequestID) else {
            throw CareerFactError.missingSourceIdentifier
        }
        return CareerFactRecord(
            id: UUID(),
            kind: kind,
            value: value,
            provenance: CareerFactProvenance(
                source: .aiHypothesis,
                sourceIdentifier: workflowRequestID,
                recordedAt: createdAt
            ),
            confirmationState: .awaitingConfirmation,
            lastUpdatedAt: createdAt
        )
    }

    func confirmed(at date: Date) throws -> CareerFactRecord {
        guard provenance.source != .aiHypothesis else {
            throw CareerFactError.aiHypothesisRequiresExplicitUserConfirmation
        }
        var result = self
        result.confirmationState = .confirmed
        result.lastUpdatedAt = date
        return result
    }

    func userConfirmed(at date: Date) -> CareerFactRecord {
        var result = self
        result.confirmationState = .confirmed
        result.lastUpdatedAt = date
        return result
    }

    func editedAndConfirmed(value: String, at date: Date) throws -> CareerFactRecord {
        guard let value = CareerUnderstandingText.sanitized(value, limit: kind.maxValueLength) else {
            throw CareerFactError.emptyValue
        }
        var result = self
        result.value = value
        result.provenance = CareerFactProvenance(
            source: .userEdit,
            sourceIdentifier: id.uuidString,
            recordedAt: date
        )
        result.confirmationState = .confirmed
        result.lastUpdatedAt = date
        return result
    }

    func rejected(at date: Date) -> CareerFactRecord {
        var result = self
        result.confirmationState = .rejected
        result.lastUpdatedAt = date
        return result
    }
}

struct CareerUnknown: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: CareerFactKind
    var prompt: String
    var lastUpdatedAt: Date

    init(
        id: UUID = UUID(),
        kind: CareerFactKind,
        prompt: String? = nil,
        lastUpdatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt ?? kind.unknownPrompt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

enum CareerUnderstandingReviewState: String, Codable, Sendable {
    case collecting
    case reviewing
    case approved
}

struct CareerUnderstanding: Codable, Equatable, Sendable {
    var facts: [CareerFactRecord]
    var unknowns: [CareerUnknown]
    var reviewState: CareerUnderstandingReviewState
    var reviewedAt: Date?
    var approvedAt: Date?

    static let empty = CareerUnderstanding(
        facts: [],
        unknowns: [],
        reviewState: .collecting,
        reviewedAt: nil,
        approvedAt: nil
    )

    static func reviewing(
        facts: [CareerFactRecord],
        unknowns: [CareerUnknown],
        reviewedAt: Date
    ) -> CareerUnderstanding {
        CareerUnderstanding(
            facts: facts,
            unknowns: unknowns,
            reviewState: .reviewing,
            reviewedAt: reviewedAt,
            approvedAt: nil
        )
    }

    static func migratingLegacyGoal(
        _ goal: CareerGoal,
        updatedAt: Date
    ) -> CareerUnderstanding {
        let entries: [(CareerFactKind, String)] = [
            (.targetOutcome, goal.targetRole),
            (.currentStage, goal.currentStatus.rawValue),
            (.timeline, goal.timeline),
            (.experience, goal.background),
            (.existingProof, goal.existingProof),
            (.constraints, goal.constraints),
            (.confidence, "\(max(1, min(goal.confidence, 5))) out of 5"),
            (.biggestBlocker, goal.biggestBlocker)
        ]
        let facts = entries.compactMap { kind, value -> CareerFactRecord? in
            guard let value = CareerUnderstandingText.sanitized(value, limit: kind.maxValueLength) else { return nil }
            return CareerFactRecord(
                id: UUID(),
                kind: kind,
                value: value,
                provenance: CareerFactProvenance(
                    source: .legacyMigration,
                    sourceIdentifier: "openlarp-state-schema-10",
                    recordedAt: updatedAt
                ),
                confirmationState: .confirmed,
                lastUpdatedAt: updatedAt
            )
        }
        let presentKinds = Set(facts.map(\.kind))
        let unknowns = CareerFactKind.allCases
            .filter { !presentKinds.contains($0) }
            .map { CareerUnknown(kind: $0, lastUpdatedAt: updatedAt) }
        return CareerUnderstanding(
            facts: facts,
            unknowns: unknowns,
            reviewState: .approved,
            reviewedAt: updatedAt,
            approvedAt: updatedAt
        )
    }

    var confirmedFacts: [CareerFactRecord] {
        facts.filter { $0.confirmationState == .confirmed }
    }

    var rejectedFacts: [CareerFactRecord] {
        facts.filter { $0.confirmationState == .rejected }
    }

    var pendingHypotheses: [CareerFactRecord] {
        facts.filter {
            $0.provenance.source == .aiHypothesis &&
                $0.confirmationState == .awaitingConfirmation
        }
    }

    mutating func rejectFact(id: UUID, at date: Date) throws {
        guard let index = facts.firstIndex(where: { $0.id == id }) else {
            throw CareerFactError.factNotFound
        }
        facts[index] = facts[index].rejected(at: date)
    }

    mutating func confirmHypothesis(id: UUID, at date: Date) throws {
        guard let index = facts.firstIndex(where: { $0.id == id }) else {
            throw CareerFactError.factNotFound
        }
        guard facts[index].provenance.source == .aiHypothesis,
              facts[index].confirmationState == .awaitingConfirmation else {
            throw CareerFactError.factIsNotAwaitingAIConfirmation
        }
        facts[index] = facts[index].userConfirmed(at: date)
    }

    mutating func editAndConfirmFact(id: UUID, value: String, at date: Date) throws {
        guard let index = facts.firstIndex(where: { $0.id == id }) else {
            throw CareerFactError.factNotFound
        }
        facts[index] = try facts[index].editedAndConfirmed(value: value, at: date)
    }

    mutating func approve(at date: Date) throws {
        guard pendingHypotheses.isEmpty else {
            throw CareerFactError.unresolvedHypotheses
        }
        facts = try facts.map { fact in
            guard fact.confirmationState == .awaitingConfirmation else { return fact }
            return try fact.confirmed(at: date)
        }
        reviewState = .approved
        reviewedAt = reviewedAt ?? date
        approvedAt = date
    }
}

struct CareerIntakeDraft: Codable, Equatable, Sendable {
    var outcomeType: CareerOutcomeType
    var targetOutcome: String
    var currentStatus: CurrentStatus
    var timeline: String
    var urgency: CareerUrgency
    var experience: String
    var existingProof: String
    var constraints: String
    var confidence: Int
    var dailyCommitmentMinutes: Int
    var biggestBlocker: String

    init(
        outcomeType: CareerOutcomeType,
        targetOutcome: String,
        currentStatus: CurrentStatus,
        timeline: String,
        urgency: CareerUrgency,
        experience: String,
        existingProof: String,
        constraints: String,
        confidence: Int,
        dailyCommitmentMinutes: Int,
        biggestBlocker: String
    ) {
        self.outcomeType = outcomeType
        self.targetOutcome = targetOutcome
        self.currentStatus = currentStatus
        self.timeline = timeline
        self.urgency = urgency
        self.experience = experience
        self.existingProof = existingProof
        self.constraints = constraints
        self.confidence = confidence
        self.dailyCommitmentMinutes = dailyCommitmentMinutes
        self.biggestBlocker = biggestBlocker
    }

    static let empty = CareerIntakeDraft(
        outcomeType: .job,
        targetOutcome: "",
        currentStatus: .student,
        timeline: "30 days",
        urgency: .steady,
        experience: "",
        existingProof: "",
        constraints: "",
        confidence: 3,
        dailyCommitmentMinutes: 20,
        biggestBlocker: ""
    )

    init(goal: CareerGoal) {
        outcomeType = goal.outcomeType
        targetOutcome = goal.targetRole
        currentStatus = goal.currentStatus
        timeline = goal.timeline
        urgency = goal.urgency
        experience = goal.background
        existingProof = goal.existingProof
        constraints = goal.constraints
        confidence = goal.confidence
        dailyCommitmentMinutes = goal.dailyCommitmentMinutes
        biggestBlocker = goal.biggestBlocker
    }

    func makeGoal() -> CareerGoal {
        CareerGoal(
            currentStatus: currentStatus,
            targetRole: CareerUnderstandingText.sanitized(
                targetOutcome,
                limit: CareerFactKind.targetOutcome.maxValueLength
            ) ?? "",
            timeline: CareerUnderstandingText.sanitized(
                timeline,
                limit: CareerFactKind.timeline.maxValueLength
            ) ?? "30 days",
            background: CareerUnderstandingText.sanitized(
                experience,
                limit: CareerFactKind.experience.maxValueLength
            ) ?? "",
            existingProof: CareerUnderstandingText.sanitized(
                existingProof,
                limit: CareerFactKind.existingProof.maxValueLength
            ) ?? "",
            confidence: max(1, min(confidence, 5)),
            biggestBlocker: CareerUnderstandingText.sanitized(
                biggestBlocker,
                limit: CareerFactKind.biggestBlocker.maxValueLength
            ) ?? "",
            outcomeType: outcomeType,
            urgency: urgency,
            constraints: CareerUnderstandingText.sanitized(
                constraints,
                limit: CareerFactKind.constraints.maxValueLength
            ) ?? "",
            dailyCommitmentMinutes: Self.normalizedDailyMinutes(dailyCommitmentMinutes)
        )
    }

    func makeApprovedUnderstanding(approvedAt: Date) -> CareerUnderstanding {
        var understanding = makeUnderstanding(reviewedAt: approvedAt)
        understanding.facts = understanding.facts.map { $0.userConfirmed(at: approvedAt) }
        understanding.reviewState = .approved
        understanding.approvedAt = approvedAt
        return understanding
    }

    func makeUnderstanding(reviewedAt: Date) -> CareerUnderstanding {
        let entries: [(CareerFactKind, String)] = [
            (.outcomeType, outcomeType.title),
            (.targetOutcome, targetOutcome),
            (.currentStage, currentStatus.rawValue),
            (.timeline, timeline),
            (.urgency, urgency.title),
            (.experience, experience),
            (.existingProof, existingProof),
            (.constraints, constraints),
            (.confidence, "\(max(1, min(confidence, 5))) out of 5"),
            (.dailyCommitment, "\(Self.normalizedDailyMinutes(dailyCommitmentMinutes)) minutes per day"),
            (.biggestBlocker, biggestBlocker)
        ]
        let facts = entries.compactMap { kind, value in
            CareerFactRecord.userEntry(kind: kind, value: value, createdAt: reviewedAt)
        }
        let presentKinds = Set(facts.map(\.kind))
        let unknowns = CareerFactKind.allCases
            .filter { !presentKinds.contains($0) }
            .map { CareerUnknown(kind: $0, lastUpdatedAt: reviewedAt) }
        return .reviewing(facts: facts, unknowns: unknowns, reviewedAt: reviewedAt)
    }

    private static func normalizedDailyMinutes(_ value: Int) -> Int {
        [10, 20, 30, 45].min(by: { abs($0 - value) < abs($1 - value) }) ?? 20
    }
}

enum CareerOnboardingStep: Int, Codable, CaseIterable, Identifiable, Sendable {
    case outcome
    case currentReality
    case commitment
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .outcome: "Name the outcome"
        case .currentReality: "Show where you stand"
        case .commitment: "Set a realistic pace"
        case .review: "Review our understanding"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .outcome: "Describe My Current Reality"
        case .currentReality: "Set My Daily Commitment"
        case .commitment: "Review OpenLARP's Understanding"
        case .review: "Approve Understanding & Check My Readiness"
        }
    }
}

enum CareerOnboardingFlowError: Error, Equatable {
    case targetOutcomeRequired
    case timelineRequired
    case approvalRequired
}

struct CareerOnboardingFlow: Equatable, Sendable {
    private(set) var step: CareerOnboardingStep

    init(step: CareerOnboardingStep = .outcome) {
        self.step = step
    }

    var progressText: String {
        "\(step.rawValue + 1) of \(CareerOnboardingStep.allCases.count)"
    }

    mutating func advance(using draft: CareerIntakeDraft) throws {
        switch step {
        case .outcome:
            guard !draft.targetOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CareerOnboardingFlowError.targetOutcomeRequired
            }
            step = .currentReality
        case .currentReality:
            guard !draft.timeline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CareerOnboardingFlowError.timelineRequired
            }
            step = .commitment
        case .commitment:
            step = .review
        case .review:
            throw CareerOnboardingFlowError.approvalRequired
        }
    }

    mutating func goBack() {
        guard let previous = CareerOnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    mutating func goTo(_ step: CareerOnboardingStep) {
        self.step = step
    }
}

private enum CareerUnderstandingText {
    static func sanitized(_ value: String, limit: Int = 4_000) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}
