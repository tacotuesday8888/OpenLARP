import Foundation

enum TargetSeniority: String, Codable, CaseIterable, Identifiable {
    case internship = "Internship"
    case entryLevel = "Entry level"
    case earlyCareer = "Early career"
    case careerSwitch = "Career switch"

    var id: String { rawValue }
}

enum RoleFamily: String, Codable, CaseIterable, Identifiable {
    case software = "Software"
    case product = "Product"
    case ai = "AI"
    case design = "Design"
    case business = "Business"
    case other = "Other"

    var id: String { rawValue }
}

enum TargetRoleStatus: String, Codable {
    case active
    case backup
    case paused
}

struct TargetRole: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var seniority: TargetSeniority
    var roleFamily: RoleFamily
    var timeline: String
    var keywords: [String]
    var preferredLocations: [String]
    var status: TargetRoleStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        seniority: TargetSeniority,
        roleFamily: RoleFamily,
        timeline: String,
        keywords: [String] = [],
        preferredLocations: [String] = [],
        status: TargetRoleStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.seniority = seniority
        self.roleFamily = roleFamily
        self.timeline = timeline
        self.keywords = keywords
        self.preferredLocations = preferredLocations
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum CareerMemoryMode: String, Codable {
    case localOnly
    case cloudReady
    case off

    var label: String {
        switch self {
        case .localOnly: "Local only"
        case .cloudReady: "Cloud-ready"
        case .off: "Off"
        }
    }
}

struct CareerUserPrivacySettings: Codable, Equatable {
    var memoryMode: CareerMemoryMode
    var shareWins: Bool
    var requireApprovalForExternalActions: Bool

    static let localDefault = CareerUserPrivacySettings(
        memoryMode: .localOnly,
        shareWins: true,
        requireApprovalForExternalActions: true
    )
}

struct CareerUserProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var accountID: String?
    var email: String?
    var displayName: String
    var segment: CurrentStatus
    var backgroundSummary: String
    var minutesPerDay: Int
    var networkingComfort: Int
    var privacy: CareerUserPrivacySettings
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        accountID: String? = nil,
        email: String? = nil,
        displayName: String = "Early-career candidate",
        segment: CurrentStatus,
        backgroundSummary: String,
        minutesPerDay: Int = 25,
        networkingComfort: Int = 3,
        privacy: CareerUserPrivacySettings = .localDefault,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.email = email
        self.displayName = displayName
        self.segment = segment
        self.backgroundSummary = backgroundSummary
        self.minutesPerDay = minutesPerDay
        self.networkingComfort = networkingComfort
        self.privacy = privacy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ReadinessSnapshotSource: String, Codable {
    case initialBaseline
    case proofClaim
    case agentScan
}

struct ReadinessSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var source: ReadinessSnapshotSource
    var reason: String
    var overall: Int
    var proofStrength: Int
    var confidence: Int
    var consistency: Int
    var skillProof: Int
    var networkStrength: Int
    var relatedQuestID: UUID?
    var relatedProofID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        source: ReadinessSnapshotSource,
        reason: String,
        metrics: ReadinessMetrics,
        relatedQuestID: UUID? = nil,
        relatedProofID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.reason = reason
        self.overall = metrics.overall
        self.proofStrength = metrics.proofStrength
        self.confidence = metrics.confidence
        self.consistency = metrics.consistency
        self.skillProof = metrics.skillProof
        self.networkStrength = metrics.networkStrength
        self.relatedQuestID = relatedQuestID
        self.relatedProofID = relatedProofID
        self.createdAt = createdAt
    }
}

enum OpportunityType: String, Codable, CaseIterable, Identifiable {
    case job = "Job"
    case internship = "Internship"
    case project = "Project"
    case course = "Course"
    case certificate = "Certificate"
    case networking = "Networking"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .job, .internship: "briefcase.fill"
        case .project: "hammer.fill"
        case .course: "book.closed.fill"
        case .certificate: "seal.fill"
        case .networking: "person.2.fill"
        }
    }
}

struct OpportunityCard: Codable, Equatable, Identifiable {
    var id: UUID
    var type: OpportunityType
    var title: String
    var sourceName: String
    var sourceURL: URL?
    var fitScore: Int
    var urgencyScore: Int
    var missingProofScore: Int
    var impactScore: Int
    var compositeScore: Int
    var rank: Int
    var whyItMatters: String
    var missingProof: String
    var recommendedAction: String
    var deadline: Date?
    var approvalRequired: Bool

    init(
        id: UUID = UUID(),
        type: OpportunityType,
        title: String,
        sourceName: String,
        sourceURL: URL? = nil,
        fitScore: Int,
        urgencyScore: Int,
        missingProofScore: Int,
        impactScore: Int,
        compositeScore: Int = 0,
        rank: Int = 0,
        whyItMatters: String,
        missingProof: String,
        recommendedAction: String,
        deadline: Date? = nil,
        approvalRequired: Bool = true
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.fitScore = fitScore
        self.urgencyScore = urgencyScore
        self.missingProofScore = missingProofScore
        self.impactScore = impactScore
        self.compositeScore = compositeScore
        self.rank = rank
        self.whyItMatters = whyItMatters
        self.missingProof = missingProof
        self.recommendedAction = recommendedAction
        self.deadline = deadline
        self.approvalRequired = approvalRequired
    }
}

struct AgentNextStep: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var detail: String
    var relatedQuestID: UUID?
    var relatedOpportunityID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        relatedQuestID: UUID? = nil,
        relatedOpportunityID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.relatedQuestID = relatedQuestID
        self.relatedOpportunityID = relatedOpportunityID
    }
}

enum AgentProviderRoute: String, Codable {
    case localMock
    case genkitBackend

    var label: String {
        switch self {
        case .localMock: "Local mock"
        case .genkitBackend: "Genkit backend-ready"
        }
    }
}

enum AgentActivityType: String, Codable {
    case profileAnalysis
    case questGeneration
    case proofEvaluation
    case readinessUpdate
    case opportunityScan
    case briefGeneration
}

enum AgentActivityStatus: String, Codable {
    case queued
    case running
    case completed
    case needsApproval
    case failed

    var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .completed: "Complete"
        case .needsApproval: "Needs approval"
        case .failed: "Failed"
        }
    }
}

struct AgentActivity: Codable, Equatable, Identifiable {
    var id: UUID
    var type: AgentActivityType
    var status: AgentActivityStatus
    var title: String
    var summary: String
    var relatedEntityIDs: [UUID]
    var externalActionTaken: Bool
    var approvalRequired: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        type: AgentActivityType,
        status: AgentActivityStatus,
        title: String,
        summary: String,
        relatedEntityIDs: [UUID] = [],
        externalActionTaken: Bool = false,
        approvalRequired: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.title = title
        self.summary = summary
        self.relatedEntityIDs = relatedEntityIDs
        self.externalActionTaken = externalActionTaken
        self.approvalRequired = approvalRequired
        self.createdAt = createdAt
    }
}

struct AgentBrief: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var generatedAt: Date
    var providerRoute: AgentProviderRoute
    var targetRoleID: UUID?
    var opportunities: [OpportunityCard]
    var nextSteps: [AgentNextStep]
    var activities: [AgentActivity]

    static let empty = AgentBrief(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        title: "Career agent brief",
        summary: "Set a goal to unlock the local career agent brief.",
        generatedAt: Date(timeIntervalSince1970: 0),
        providerRoute: .localMock,
        targetRoleID: nil,
        opportunities: [],
        nextSteps: [],
        activities: []
    )
}

protocol OpportunityRankingServicing {
    func rank(_ opportunities: [OpportunityCard], for targetRole: TargetRole) -> [OpportunityCard]
}

struct LocalOpportunityRankingService: OpportunityRankingServicing {
    func rank(_ opportunities: [OpportunityCard], for targetRole: TargetRole) -> [OpportunityCard] {
        let targetKeywords = Set(targetRole.keywords.map { $0.lowercased() })
        let scored = opportunities.map { opportunity in
            let titleTokens = Set(opportunity.title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let keywordBoost = titleTokens.intersection(targetKeywords).isEmpty ? 0 : 4
            let typeBoost: Int
            switch opportunity.type {
            case .project:
                typeBoost = 5
            case .networking, .internship:
                typeBoost = 3
            case .course, .certificate:
                typeBoost = 1
            case .job:
                typeBoost = 2
            }

            var ranked = opportunity
            ranked.compositeScore = min(
                100,
                Int(Double(opportunity.fitScore) * 0.35) +
                    Int(Double(opportunity.urgencyScore) * 0.25) +
                    Int(Double(opportunity.missingProofScore) * 0.20) +
                    Int(Double(opportunity.impactScore) * 0.20) +
                    keywordBoost +
                    typeBoost
            )
            return ranked
        }
        .sorted { lhs, rhs in
            if lhs.compositeScore == rhs.compositeScore {
                return lhs.fitScore > rhs.fitScore
            }
            return lhs.compositeScore > rhs.compositeScore
        }

        return scored.enumerated().map { index, opportunity in
            var ranked = opportunity
            ranked.rank = index + 1
            return ranked
        }
    }
}

// TODO(Firebase/Genkit): Replace the mock implementation with a backend client
// that calls authenticated Cloud Functions callable Genkit flows or Cloud Run.
// The iOS app should never import provider SDKs or send prompts directly to LLMs.
@MainActor
protocol CareerAgentBriefServicing {
    func generateBrief(for state: OpenLARPState) async throws -> AgentBrief
}

struct MockCareerAgentService: CareerAgentBriefServicing {
    private let rankingService: OpportunityRankingServicing

    init(rankingService: OpportunityRankingServicing = LocalOpportunityRankingService()) {
        self.rankingService = rankingService
    }

    func generateBrief(for state: OpenLARPState) async throws -> AgentBrief {
        AgentBriefFactory.makeBrief(for: state, rankingService: rankingService)
    }
}

enum AgentBriefFactory {
    static func makeBrief(
        for state: OpenLARPState,
        rankingService: OpportunityRankingServicing = LocalOpportunityRankingService(),
        generatedAt: Date = Date()
    ) -> AgentBrief {
        guard let targetRole = state.targetRoles.first ?? state.goal.map({ makeTargetRole(for: $0) }) else {
            return .empty
        }

        let opportunities = rankingService.rank(sampleOpportunities(for: targetRole), for: targetRole)
        let proofCount = state.progress.proofCount
        let proofText = proofCount == 1 ? "1 proof receipt" : "\(proofCount) proof receipts"
        let currentQuest = state.currentQuest ?? state.plan.first { $0.status == .locked }

        var activities: [AgentActivity] = [
            AgentActivity(
                type: .opportunityScan,
                status: .completed,
                title: "Ranked approved sources",
                summary: "Scored projects, networking, and learning paths against fit, urgency, missing proof, and impact.",
                relatedEntityIDs: opportunities.map { $0.id },
                createdAt: generatedAt
            ),
            AgentActivity(
                type: .briefGeneration,
                status: .completed,
                title: "Updated career brief",
                summary: "Combined target role, readiness, current quest, and \(proofText).",
                relatedEntityIDs: currentQuest.map { [$0.id] } ?? [],
                createdAt: generatedAt
            )
        ]

        if let latestProof = state.progress.recentProof.first {
            activities.insert(
                AgentActivity(
                    type: .proofEvaluation,
                    status: .completed,
                    title: "Evaluated latest proof",
                    summary: latestProof.quality?.reason ?? "Saved proof into the local evidence graph.",
                    relatedEntityIDs: [latestProof.id, latestProof.questID],
                    createdAt: latestProof.submittedAt
                ),
                at: 0
            )
        } else {
            activities.insert(
                AgentActivity(
                    type: .profileAnalysis,
                    status: .completed,
                    title: "Built first profile model",
                    summary: "Mapped current status, target role, blocker, and proof baseline.",
                    relatedEntityIDs: [targetRole.id],
                    createdAt: generatedAt
                ),
                at: 0
            )
        }

        let nextSteps = [
            AgentNextStep(
                title: "Do today's proof quest",
                detail: currentQuest?.title ?? "Set a new target to generate the next quest.",
                relatedQuestID: currentQuest?.id
            ),
            AgentNextStep(
                title: "Save one stronger receipt",
                detail: "Add a link, screenshot, or artifact note so future resume and interview help has real evidence."
            ),
            AgentNextStep(
                title: "Review the top ranked brief",
                detail: opportunities.first?.recommendedAction ?? "Run a local agent scan after goal setup.",
                relatedOpportunityID: opportunities.first?.id
            )
        ]

        return AgentBrief(
            id: UUID(),
            title: "Career agent brief",
            summary: "For \(targetRole.title), readiness is \(state.progress.readiness.overall)%. The agent sees \(proofText) and \(opportunities.count) ranked next moves.",
            generatedAt: generatedAt,
            providerRoute: .genkitBackend,
            targetRoleID: targetRole.id,
            opportunities: opportunities,
            nextSteps: nextSteps,
            activities: activities
        )
    }

    static func makeProfile(for goal: CareerGoal, now: Date = Date()) -> CareerUserProfile {
        CareerUserProfile(
            segment: goal.currentStatus,
            backgroundSummary: goal.background.isEmpty ? "Background not provided yet." : goal.background,
            createdAt: now,
            updatedAt: now
        )
    }

    static func makeTargetRole(for goal: CareerGoal, now: Date = Date()) -> TargetRole {
        TargetRole(
            title: goal.targetRole,
            seniority: inferredSeniority(from: goal),
            roleFamily: inferredRoleFamily(from: goal.targetRole),
            timeline: goal.timeline,
            keywords: inferredKeywords(from: goal.targetRole),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func sampleOpportunities(for targetRole: TargetRole) -> [OpportunityCard] {
        let title = targetRole.title
        return [
            OpportunityCard(
                type: .project,
                title: "Ship a proof artifact for \(title)",
                sourceName: "OpenLARP Agent",
                fitScore: 92,
                urgencyScore: 74,
                missingProofScore: 90,
                impactScore: 91,
                whyItMatters: "This creates evidence tied directly to the target role instead of another unsupported claim.",
                missingProof: "Role-specific artifact",
                recommendedAction: "Turn the top job requirement into a small public or private artifact."
            ),
            OpportunityCard(
                type: .networking,
                title: "Ask one \(targetRole.roleFamily.rawValue.lowercased()) peer for a proof review",
                sourceName: "Approved network scan",
                fitScore: 84,
                urgencyScore: 82,
                missingProofScore: 64,
                impactScore: 78,
                whyItMatters: "A narrow review request is more credible than broad networking and can improve the next proof item.",
                missingProof: "Network signal",
                recommendedAction: "Send a short draft for approval before contacting anyone."
            ),
            OpportunityCard(
                type: .course,
                title: "Complete one focused skill sprint",
                sourceName: "Course scan",
                fitScore: 68,
                urgencyScore: 48,
                missingProofScore: 58,
                impactScore: 61,
                whyItMatters: "A short course only matters if it produces a portfolio receipt.",
                missingProof: "Skill proof",
                recommendedAction: "Pick a free module that ends with a concrete artifact."
            )
        ]
    }

    private static func inferredSeniority(from goal: CareerGoal) -> TargetSeniority {
        let role = goal.targetRole.lowercased()
        if role.contains("intern") {
            return .internship
        }
        if goal.currentStatus == .careerSwitcher {
            return .careerSwitch
        }
        if goal.currentStatus == .newGrad || role.contains("entry") || role.contains("junior") {
            return .entryLevel
        }
        return .earlyCareer
    }

    private static func inferredRoleFamily(from role: String) -> RoleFamily {
        let lowercased = role.lowercased()
        if lowercased.contains("product") || lowercased.contains("pm") {
            return .product
        }
        if lowercased.contains("ai") || lowercased.contains("machine learning") || lowercased.contains("ml") {
            return .ai
        }
        if lowercased.contains("design") {
            return .design
        }
        if lowercased.contains("software") || lowercased.contains("ios") || lowercased.contains("engineer") || lowercased.contains("developer") {
            return .software
        }
        return .other
    }

    private static func inferredKeywords(from role: String) -> [String] {
        let words = role
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
            .filter { $0.count > 1 }
        return Array(Set(words)).sorted()
    }
}
