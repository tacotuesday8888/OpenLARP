import Foundation

enum CareerMissionReviewState: String, Codable, Equatable, Sendable {
    case awaitingApproval
    case approved
}

struct CareerMissionSprint: Codable, Equatable, Sendable {
    var dayCount: Int
    var chapterCount: Int
    var summary: String

    static let richV0 = CareerMissionSprint(
        dayCount: 14,
        chapterCount: 2,
        summary: "Chapter one builds honest career proof. " +
            "Chapter two adapts the next seven actions using what the first week actually produced."
    )
}

enum CareerMissionBriefError: Error, Equatable {
    case unsupportedSchemaVersion
    case invalidTargetOutcome
    case unconfirmedCurrentState
    case invalidConstraints
    case invalidReadinessGaps
    case invalidEthicalBoundaries
    case invalidFirstMilestone
    case invalidDailyCommitment
    case invalidSprint
    case invalidReviewState
    case alreadyApproved
}

struct CareerMissionBrief: Codable, Equatable, Identifiable, Sendable {
    static let requiredEthicalBoundaries = [
        "Use only truthful, defensible career claims.",
        "Never invent employers, schools, credentials, titles, dates, projects, ownership, experience, or results.",
        "The user approves every external action."
    ]

    var id: UUID
    var schemaVersion: Int
    var targetOutcome: String
    var confirmedCurrentState: [CareerFactRecord]
    var constraints: String
    var mainReadinessGaps: [String]
    var ethicalBoundaries: [String]
    var firstMilestone: String
    var dailyCommitmentMinutes: Int
    var sprint: CareerMissionSprint
    var reviewState: CareerMissionReviewState
    var providerRoute: V0AIProviderRoute
    var usedFallback: Bool
    var generatedAt: Date
    var lastUpdatedAt: Date
    var approvedAt: Date?

    static func localProposal(
        goal: CareerGoal,
        understanding: CareerUnderstanding,
        diagnostic: CookedDiagnostic,
        generatedAt: Date
    ) throws -> CareerMissionBrief {
        try proposal(
            targetOutcome: goal.targetRole,
            confirmedCurrentState: understanding.confirmedFacts,
            constraints: goal.constraints,
            mainReadinessGaps: diagnostic.readinessGaps.nonEmpty ?? [diagnostic.mainGap],
            ethicalBoundaries: requiredEthicalBoundaries,
            firstMilestone: diagnostic.firstAction.nonBlank ?? diagnostic.fastestFix,
            dailyCommitmentMinutes: goal.dailyCommitmentMinutes,
            sprint: .richV0,
            providerRoute: .localMock,
            usedFallback: false,
            generatedAt: generatedAt
        )
    }

    static func legacyApproved(
        goal: CareerGoal,
        understanding: CareerUnderstanding,
        diagnostic: CookedDiagnostic,
        approvedAt: Date
    ) -> CareerMissionBrief? {
        guard var mission = try? localProposal(
            goal: goal,
            understanding: understanding,
            diagnostic: diagnostic,
            generatedAt: approvedAt
        ) else {
            return nil
        }
        mission.usedFallback = true
        return try? mission.approved(at: approvedAt)
    }

    static func proposal(
        id: UUID = UUID(),
        targetOutcome: String,
        confirmedCurrentState: [CareerFactRecord],
        constraints: String,
        mainReadinessGaps: [String],
        ethicalBoundaries: [String],
        firstMilestone: String,
        dailyCommitmentMinutes: Int,
        sprint: CareerMissionSprint,
        providerRoute: V0AIProviderRoute,
        usedFallback: Bool,
        generatedAt: Date
    ) throws -> CareerMissionBrief {
        let mission = CareerMissionBrief(
            id: id,
            schemaVersion: 1,
            targetOutcome: targetOutcome.trimmed,
            confirmedCurrentState: confirmedCurrentState,
            constraints: constraints.trimmed,
            mainReadinessGaps: mainReadinessGaps.map(\.trimmed),
            ethicalBoundaries: ethicalBoundaries.map(\.trimmed),
            firstMilestone: firstMilestone.trimmed,
            dailyCommitmentMinutes: dailyCommitmentMinutes,
            sprint: CareerMissionSprint(
                dayCount: sprint.dayCount,
                chapterCount: sprint.chapterCount,
                summary: sprint.summary.trimmed
            ),
            reviewState: .awaitingApproval,
            providerRoute: providerRoute,
            usedFallback: usedFallback,
            generatedAt: generatedAt,
            lastUpdatedAt: generatedAt,
            approvedAt: nil
        )
        try mission.validate()
        return mission
    }

    func applyingUserEdits(
        constraints: String,
        mainReadinessGaps: [String],
        firstMilestone: String,
        dailyCommitmentMinutes: Int,
        sprintSummary: String,
        editedAt: Date
    ) throws -> CareerMissionBrief {
        guard reviewState == .awaitingApproval else {
            throw CareerMissionBriefError.alreadyApproved
        }
        guard editedAt >= lastUpdatedAt else {
            throw CareerMissionBriefError.invalidReviewState
        }
        var edited = self
        edited.constraints = constraints.trimmed
        edited.mainReadinessGaps = mainReadinessGaps.map(\.trimmed)
        edited.firstMilestone = firstMilestone.trimmed
        edited.dailyCommitmentMinutes = dailyCommitmentMinutes
        edited.sprint.summary = sprintSummary.trimmed
        edited.lastUpdatedAt = editedAt
        try edited.validate()
        return edited
    }

    func approved(at date: Date) throws -> CareerMissionBrief {
        guard reviewState == .awaitingApproval else {
            throw CareerMissionBriefError.alreadyApproved
        }
        guard date >= lastUpdatedAt else {
            throw CareerMissionBriefError.invalidReviewState
        }
        var approved = self
        approved.reviewState = .approved
        approved.lastUpdatedAt = date
        approved.approvedAt = date
        try approved.validate()
        return approved
    }

    func validate() throws {
        guard schemaVersion == 1 else {
            throw CareerMissionBriefError.unsupportedSchemaVersion
        }
        guard targetOutcome.hasLength(in: 1...120), targetOutcome == targetOutcome.trimmed else {
            throw CareerMissionBriefError.invalidTargetOutcome
        }
        guard confirmedCurrentState.allSatisfy({ $0.confirmationState == .confirmed }),
              Set(confirmedCurrentState.map(\.id)).count == confirmedCurrentState.count else {
            throw CareerMissionBriefError.unconfirmedCurrentState
        }
        guard constraints.count <= 4_000, constraints == constraints.trimmed else {
            throw CareerMissionBriefError.invalidConstraints
        }
        guard (1...4).contains(mainReadinessGaps.count),
              mainReadinessGaps.allSatisfy({ $0.hasLength(in: 1...500) && $0 == $0.trimmed }),
              Set(mainReadinessGaps).count == mainReadinessGaps.count else {
            throw CareerMissionBriefError.invalidReadinessGaps
        }
        guard ethicalBoundaries == Self.requiredEthicalBoundaries else {
            throw CareerMissionBriefError.invalidEthicalBoundaries
        }
        guard firstMilestone.hasLength(in: 1...500), firstMilestone == firstMilestone.trimmed else {
            throw CareerMissionBriefError.invalidFirstMilestone
        }
        guard (5...180).contains(dailyCommitmentMinutes) else {
            throw CareerMissionBriefError.invalidDailyCommitment
        }
        guard sprint.dayCount == 14,
              sprint.chapterCount == 2,
              sprint.summary.hasLength(in: 1...800),
              sprint.summary == sprint.summary.trimmed else {
            throw CareerMissionBriefError.invalidSprint
        }
        guard lastUpdatedAt >= generatedAt else {
            throw CareerMissionBriefError.invalidReviewState
        }
        switch reviewState {
        case .awaitingApproval:
            guard approvedAt == nil else {
                throw CareerMissionBriefError.invalidReviewState
            }
        case .approved:
            guard let approvedAt, approvedAt == lastUpdatedAt, approvedAt >= generatedAt else {
                throw CareerMissionBriefError.invalidReviewState
            }
        }
    }
}

extension CareerMissionBrief {
    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case targetOutcome
        case confirmedCurrentState
        case constraints
        case mainReadinessGaps
        case ethicalBoundaries
        case firstMilestone
        case dailyCommitmentMinutes
        case sprint
        case reviewState
        case providerRoute
        case usedFallback
        case generatedAt
        case lastUpdatedAt
        case approvedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        targetOutcome = try container.decode(String.self, forKey: .targetOutcome)
        confirmedCurrentState = try container.decode([CareerFactRecord].self, forKey: .confirmedCurrentState)
        constraints = try container.decode(String.self, forKey: .constraints)
        mainReadinessGaps = try container.decode([String].self, forKey: .mainReadinessGaps)
        ethicalBoundaries = try container.decode([String].self, forKey: .ethicalBoundaries)
        firstMilestone = try container.decode(String.self, forKey: .firstMilestone)
        dailyCommitmentMinutes = try container.decode(Int.self, forKey: .dailyCommitmentMinutes)
        sprint = try container.decode(CareerMissionSprint.self, forKey: .sprint)
        reviewState = try container.decode(CareerMissionReviewState.self, forKey: .reviewState)
        providerRoute = try container.decode(V0AIProviderRoute.self, forKey: .providerRoute)
        usedFallback = try container.decode(Bool.self, forKey: .usedFallback)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
        approvedAt = try container.decodeIfPresent(Date.self, forKey: .approvedAt)
        try validate()
    }
}

private extension Optional where Wrapped == [String] {
    var nonEmpty: [String]? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

private extension Optional where Wrapped == String {
    var nonBlank: String? {
        guard let self else { return nil }
        let trimmed = self.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasLength(in range: ClosedRange<Int>) -> Bool {
        range.contains(count) && !trimmed.isEmpty
    }
}
