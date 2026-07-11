import Foundation

enum OpenLARPEngine {
    static func confirmGoal(_ goal: CareerGoal, now: Date = Date()) -> OpenLARPState {
        let diagnostic = makeDiagnostic(for: goal)
        let plan = makeSevenDayPlan(for: goal)
        return confirmGoal(goal, diagnostic: diagnostic, plan: plan, now: now)
    }

    static func confirmGoal(
        _ goal: CareerGoal,
        diagnostic: CookedDiagnostic,
        plan: [Quest],
        now: Date = Date()
    ) -> OpenLARPState {
        let profile = AgentBriefFactory.makeProfile(for: goal, now: now)
        let targetRole = AgentBriefFactory.makeTargetRole(for: goal, now: now)
        var progress = ProgressState.empty
        progress.readiness = initialReadiness(from: diagnostic)
        progress.badges = [.firstGoal]
        progress.readinessHistory = [
            ReadinessSnapshot(
                source: .initialBaseline,
                reason: "Initial Am I Cooked baseline",
                metrics: progress.readiness,
                createdAt: now
            )
        ]

        var state = OpenLARPState(
            userProfile: profile,
            goal: goal,
            targetRoles: [targetRole],
            diagnostic: diagnostic,
            plan: validatedInitialPlan(plan) ?? makeSevenDayPlan(for: goal),
            progress: progress,
            updatedAt: now
        )
        state.agentBrief = AgentBriefFactory.makeBrief(for: state, generatedAt: now)
        return state
    }

    static func startCurrentQuest(in state: OpenLARPState, now: Date = Date()) throws -> OpenLARPState {
        guard let currentQuest = state.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }
        guard currentQuest.status == .available || currentQuest.status == .inProgress else {
            throw OpenLARPError.questNotAvailable
        }

        var next = state
        setQuestStatus(currentQuest.id, to: .inProgress, in: &next)
        next.missedDayRecovery = .empty
        next.updatedAt = now
        return next
    }

    static func skipCurrentQuest(
        in state: OpenLARPState,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> OpenLARPState {
        guard let currentQuest = state.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }
        guard currentQuest.status == .available || currentQuest.status == .inProgress else {
            throw OpenLARPError.questNotAvailable
        }

        var next = state
        let previousStreakCount = next.progress.streakCount
        let nextQuestID = nextQuestID(after: currentQuest.id, in: next)

        setQuestStatus(currentQuest.id, to: .skipped, in: &next)
        lockFutureAvailableQuests(after: currentQuest.id, in: &next)
        if let nextQuestID {
            setQuestStatus(nextQuestID, to: .locked, in: &next)
        }

        next.progress.streakCount = 0
        next.dailyCadence = .empty
        next.missedDayRecovery = .empty
        next.skippedToday = SkippedTodayState(
            skippedQuestID: currentQuest.id,
            skippedQuestTitle: currentQuest.title,
            skippedAt: now,
            previousStreakCount: previousStreakCount,
            nextQuestID: nextQuestID,
            nextUnlockDate: nextQuestID == nil ? nil : nextLocalDay(after: now, calendar: calendar)
        )
        next.updatedAt = now
        return next
    }

    static func checkProof(_ proof: ProofSubmission, in state: OpenLARPState) throws -> QualityCheckResult {
        guard let quest = state.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }

        return try checkProof(proof, for: quest)
    }

    static func checkProof(_ proof: ProofSubmission, for quest: Quest) throws -> QualityCheckResult {
        let trimmedText = proof.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = proof.link.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachment = !proof.attachments.isEmpty
        guard !trimmedText.isEmpty else {
            throw OpenLARPError.emptyProof
        }

        let inspectionScope = ProofInspectionScope(
            didInspectWrittenText: !trimmedText.isEmpty,
            didInspectLinkFormat: !trimmedLink.isEmpty,
            didInspectLinkedDestination: false,
            didInspectAttachmentMetadata: hasAttachment,
            didInspectAttachmentContents: false
        )

        if proof.kind == .selfReport {
            return QualityCheckResult(
                isAccepted: false,
                qualityScore: 48,
                label: "Needs more context",
                reason: "Your written reflection records progress, but it is a self-report rather than inspected evidence.",
                improvement: "Describe what changed and connect it to a concrete result or role requirement.",
                xpEarned: max(25, Int(Double(quest.xpReward) * 0.375)),
                readinessDelta: 2,
                inspectionScope: inspectionScope
            )
        }

        let wordCount = trimmedText.split { $0.isWhitespace || $0.isNewline }.count
        let accepted = wordCount >= 18

        if accepted {
            return QualityCheckResult(
                isAccepted: true,
                qualityScore: 78,
                label: "Well-documented submission",
                reason: "Your written description includes enough specific context to document meaningful progress.",
                improvement: "Connect the written account to one target-role requirement so it becomes easier to reuse.",
                xpEarned: quest.xpReward,
                readinessDelta: 7,
                inspectionScope: inspectionScope
            )
        }

        return QualityCheckResult(
            isAccepted: false,
            qualityScore: 55,
            label: "Needs more context",
            reason: "The written description does not yet include enough detail to document meaningful progress.",
            improvement: "Add what you did, what changed, and how it connects to the quest.",
            xpEarned: max(30, quest.xpReward / 2),
            readinessDelta: 3,
            inspectionScope: inspectionScope
        )
    }

    static func claim(
        _ result: QualityCheckResult,
        proof: ProofSubmission,
        in state: OpenLARPState,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> OpenLARPState {
        guard let quest = state.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }

        var next = state
        setQuestStatus(quest.id, to: .completed, in: &next)

        next.progress.xp += result.xpEarned
        next.progress.streakCount = max(1, next.progress.streakCount + 1)
        next.progress.completedQuestCount += 1
        next.progress.proofCount += 1
        next.progress.readiness = updatedReadiness(next.progress.readiness, delta: result.readinessDelta)
        addBadges(for: result, progress: &next.progress)

        let record = ProofRecord(
            id: proof.id,
            questID: quest.id,
            questTitle: quest.title,
            kind: proof.kind,
            text: proof.text,
            link: proof.link,
            attachments: proof.attachments,
            submittedAt: proof.submittedAt,
            quality: result
        )
        next.progress.recentProof.insert(record, at: 0)
        next.progress.readinessHistory.append(
            ReadinessSnapshot(
                source: .proofClaim,
                reason: "\(result.label): \(quest.gap.title)",
                metrics: next.progress.readiness,
                relatedQuestID: quest.id,
                relatedProofID: proof.id,
                createdAt: now
            )
        )
        recordDailyCompletion(
            quest: quest,
            result: result,
            now: now,
            calendar: calendar,
            in: &next
        )
        next.agentBrief = AgentBriefFactory.makeBrief(for: next, generatedAt: now)
        next.updatedAt = now
        return next
    }

    static func logOutcome(
        _ outcome: CareerOutcomeRecord,
        in state: OpenLARPState,
        now: Date = Date()
    ) -> OpenLARPState {
        var next = state
        var savedOutcome = outcome
        savedOutcome.deletedAt = nil
        let isExistingOutcome = next.outcomeLog.contains { $0.id == outcome.id }
        next.outcomeLog.removeAll { $0.id == savedOutcome.id }
        next.outcomeLog.insert(savedOutcome, at: 0)
        sortOutcomeLog(in: &next)

        if isExistingOutcome {
            next.agentBrief = AgentBriefFactory.makeBrief(for: next, generatedAt: now)
            next.updatedAt = now
            return next
        }

        let previousReadiness = next.progress.readiness
        let impact = outcomeImpact(for: outcome.kind)
        next.progress.xp += impact.xp
        next.progress.readiness = updatedReadiness(next.progress.readiness, for: outcome.kind)
        addOutcomeBadges(for: outcome.kind, progress: &next.progress)

        if next.progress.readiness != previousReadiness {
            next.progress.readinessHistory.append(
                ReadinessSnapshot(
                    source: .outcomeLog,
                    reason: "\(outcome.kind.label): \(impact.reason)",
                    metrics: next.progress.readiness,
                    relatedQuestID: outcome.relatedQuestID,
                    relatedProofID: outcome.relatedProofID,
                    relatedOutcomeID: outcome.id,
                    createdAt: now
                )
            )
        }

        next.agentBrief = AgentBriefFactory.makeBrief(for: next, generatedAt: now)
        next.updatedAt = now
        return next
    }

    static func updateOutcome(
        _ outcome: CareerOutcomeRecord,
        in state: OpenLARPState,
        now: Date = Date()
    ) -> OpenLARPState {
        var next = state
        guard next.outcomeLog.contains(where: { $0.id == outcome.id }) else {
            return state
        }

        var updatedOutcome = outcome
        updatedOutcome.updatedAt = now
        next.outcomeLog.removeAll { $0.id == outcome.id }
        next.outcomeLog.insert(updatedOutcome, at: 0)
        sortOutcomeLog(in: &next)
        next.agentBrief = AgentBriefFactory.makeBrief(for: next, generatedAt: now)
        next.updatedAt = now
        return next
    }

    static func deleteOutcome(
        id: UUID,
        in state: OpenLARPState,
        now: Date = Date()
    ) -> OpenLARPState {
        var next = state
        guard let index = next.outcomeLog.firstIndex(where: { $0.id == id }) else {
            return state
        }

        next.outcomeLog[index].deletedAt = now
        next.outcomeLog[index].updatedAt = now
        sortOutcomeLog(in: &next)
        next.agentBrief = AgentBriefFactory.makeBrief(for: next, generatedAt: now)
        next.updatedAt = now
        return next
    }

    static func refreshDailyAvailability(
        in state: OpenLARPState,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> OpenLARPState {
        if let skippedAt = state.skippedToday.skippedAt {
            var next = state

            if calendar.isDate(skippedAt, inSameDayAs: now) {
                if let nextQuestID = next.skippedToday.nextQuestID {
                    setQuestStatus(nextQuestID, to: .locked, in: &next)
                }
                return next
            }

            if let nextQuestID = next.skippedToday.nextQuestID {
                setQuestStatus(nextQuestID, to: .available, in: &next)
            }
            next.skippedToday = .empty
            next.updatedAt = now
            return next
        }

        guard let completedAt = state.dailyCadence.completedAt else {
            return state
        }

        var next = state

        if calendar.isDate(completedAt, inSameDayAs: now) {
            if let nextQuestID = next.dailyCadence.nextQuestID {
                setQuestStatus(nextQuestID, to: .locked, in: &next)
            }
            return next
        }

        if let nextQuestID = next.dailyCadence.nextQuestID {
            setQuestStatus(nextQuestID, to: .available, in: &next)

            let unlockDate = next.dailyCadence.nextUnlockDate ?? nextLocalDay(after: completedAt, calendar: calendar)
            let missedDayCount = missedQuestDayCount(unlockDate: unlockDate, returnDate: now, calendar: calendar)
            if missedDayCount > 0 {
                let previousStreakCount = next.dailyCadence.streakCountAfterCompletion ?? next.progress.streakCount
                next.progress.streakCount = 0
                next.missedDayRecovery = MissedDayRecoveryState(
                    startedAt: now,
                    missedDayCount: missedDayCount,
                    lastCompletedQuestID: next.dailyCadence.lastCompletedQuestID,
                    nextQuestID: nextQuestID,
                    previousStreakCount: previousStreakCount
                )
            } else {
                next.missedDayRecovery = .empty
            }
        }
        next.dailyCadence = .empty
        next.updatedAt = now
        return next
    }

    static func resetGoal(now: Date = Date()) -> OpenLARPState {
        var state = OpenLARPState.empty
        state.updatedAt = now
        return state
    }

    static func validatedInitialPlan(_ plan: [Quest]) -> [Quest]? {
        guard !plan.isEmpty else { return nil }

        var seenIDs = Set<UUID>()
        var sanitized: [Quest] = []

        for (index, quest) in plan.enumerated() {
            guard seenIDs.insert(quest.id).inserted else { return nil }
            guard !quest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard !quest.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard !quest.proofRequired.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            var next = quest
            next.day = index + 1
            next.timeEstimateMinutes = max(5, min(next.timeEstimateMinutes, 90))
            next.xpReward = max(25, min(next.xpReward, 180))
            next.status = index == 0 ? .available : .locked
            sanitized.append(next)
        }

        return sanitized
    }

    static func swappedCurrentQuest(in state: OpenLARPState, now: Date = Date()) throws -> OpenLARPState {
        guard let currentQuest = state.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }

        var next = state
        guard let index = next.plan.firstIndex(where: { $0.id == currentQuest.id }) else {
            throw OpenLARPError.noCurrentQuest
        }

        next.plan[index].title = "Build one tiny proof artifact"
        next.plan[index].purpose = "A smaller quest still has to create something real you can point to later."
        next.plan[index].proofRequired = "Paste a short note, link, or screenshot of the artifact."
        next.plan[index].steps = [
            "Pick one tiny artifact related to your target role.",
            "Spend 20 minutes making the first usable version.",
            "Write what it proves and where it falls short."
        ]
        next.plan[index].status = .available
        next.agentBrief = AgentBriefFactory.makeBrief(for: next, generatedAt: now)
        next.updatedAt = now
        return next
    }

    private static func makeDiagnostic(for goal: CareerGoal) -> CookedDiagnostic {
        CookedDiagnostic(
            score: 58,
            label: "Medium Cooked",
            mainGap: "Your target is realistic, but your proof is still too thin for \(goal.targetRole).",
            strongestSignal: strongestSignal(for: goal),
            fastestFix: "Turn one target-role requirement into a small artifact you can show or explain.",
            readinessBaseline: ReadinessMetrics.baseline.overall
        )
    }

    private static func initialReadiness(from diagnostic: CookedDiagnostic) -> ReadinessMetrics {
        let baseline = ReadinessMetrics.baseline
        let overall = clampedReadinessScore(diagnostic.readinessBaseline)
        let offset = overall - baseline.overall

        return ReadinessMetrics(
            overall: overall,
            targetClarity: clampedReadinessScore(baseline.targetClarity + offset / 2),
            proofStrength: clampedReadinessScore(baseline.proofStrength + offset),
            confidence: clampedReadinessScore(baseline.confidence + offset / 2),
            consistency: clampedReadinessScore(baseline.consistency + offset / 3),
            skillProof: clampedReadinessScore(baseline.skillProof + offset),
            experienceProof: clampedReadinessScore(baseline.experienceProof + offset),
            profileCredibility: clampedReadinessScore(baseline.profileCredibility + offset / 2),
            networkStrength: clampedReadinessScore(baseline.networkStrength + offset / 3),
            interviewReadiness: clampedReadinessScore(baseline.interviewReadiness + offset / 3),
            applicationExecution: clampedReadinessScore(baseline.applicationExecution + offset / 3)
        )
    }

    private static func clampedReadinessScore(_ score: Int) -> Int {
        max(0, min(score, 100))
    }

    private static func strongestSignal(for goal: CareerGoal) -> String {
        if goal.existingProof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "You have a clear target, but not much evidence yet."
        }
        return "You already have a starting signal. Now it needs to become defensible proof."
    }

    private static func makeSevenDayPlan(for goal: CareerGoal) -> [Quest] {
        [
            Quest(
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

    private static func setQuestStatus(_ id: UUID, to status: QuestStatus, in state: inout OpenLARPState) {
        guard let index = state.plan.firstIndex(where: { $0.id == id }) else { return }
        state.plan[index].status = status
    }

    private static func nextQuestID(after id: UUID, in state: OpenLARPState) -> UUID? {
        guard let completedIndex = state.plan.firstIndex(where: { $0.id == id }) else { return nil }
        let nextIndex = completedIndex + 1
        guard state.plan.indices.contains(nextIndex) else { return nil }
        return state.plan[nextIndex].id
    }

    private static func sortOutcomeLog(in state: inout OpenLARPState) {
        state.outcomeLog.sort { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.occurredAt > rhs.occurredAt
        }
    }

    private static func lockFutureAvailableQuests(after id: UUID, in state: inout OpenLARPState) {
        guard let completedIndex = state.plan.firstIndex(where: { $0.id == id }) else { return }
        let firstFutureIndex = completedIndex + 1
        guard state.plan.indices.contains(firstFutureIndex) else { return }

        for index in firstFutureIndex..<state.plan.endIndex where state.plan[index].status == .available {
            state.plan[index].status = .locked
        }
    }

    private static func recordDailyCompletion(
        quest: Quest,
        result: QualityCheckResult,
        now: Date,
        calendar: Calendar,
        in state: inout OpenLARPState
    ) {
        let nextQuestID = nextQuestID(after: quest.id, in: state)
        lockFutureAvailableQuests(after: quest.id, in: &state)

        state.dailyCadence = DailyCadenceState(
            lastCompletedQuestID: quest.id,
            completedQuestTitle: quest.title,
            completedAt: now,
            resultLabel: result.label,
            xpEarned: result.xpEarned,
            streakCountAfterCompletion: state.progress.streakCount,
            nextQuestID: nextQuestID,
            nextUnlockDate: nextQuestID == nil ? nil : nextLocalDay(after: now, calendar: calendar)
        )
        state.missedDayRecovery = .empty
        state.skippedToday = .empty
    }

    private static func nextLocalDay(after date: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86_400)
    }

    private static func missedQuestDayCount(unlockDate: Date, returnDate: Date, calendar: Calendar) -> Int {
        let unlockDay = calendar.startOfDay(for: unlockDate)
        let returnDay = calendar.startOfDay(for: returnDate)
        let dayDifference = calendar.dateComponents([.day], from: unlockDay, to: returnDay).day ?? 0
        return max(0, dayDifference)
    }

    private static func updatedReadiness(_ readiness: ReadinessMetrics, delta: Int) -> ReadinessMetrics {
        ReadinessMetrics(
            overall: min(100, readiness.overall + max(1, delta / 2)),
            targetClarity: min(100, readiness.targetClarity + max(1, delta / 3)),
            proofStrength: min(100, readiness.proofStrength + delta),
            confidence: min(100, readiness.confidence + max(1, delta / 2)),
            consistency: min(100, readiness.consistency + max(1, delta)),
            skillProof: min(100, readiness.skillProof + max(1, delta - 1)),
            experienceProof: min(100, readiness.experienceProof + max(1, delta / 2)),
            profileCredibility: min(100, readiness.profileCredibility + max(1, delta / 2)),
            networkStrength: min(100, readiness.networkStrength + (delta > 5 ? 2 : 1)),
            interviewReadiness: min(100, readiness.interviewReadiness + max(1, delta / 3)),
            applicationExecution: min(100, readiness.applicationExecution + max(1, delta / 3))
        )
    }

    private static func updatedReadiness(_ readiness: ReadinessMetrics, for outcomeKind: CareerOutcomeKind) -> ReadinessMetrics {
        switch outcomeKind {
        case .applied:
            ReadinessMetrics(
                overall: clampedReadinessScore(readiness.overall + 1),
                targetClarity: readiness.targetClarity,
                proofStrength: readiness.proofStrength,
                confidence: clampedReadinessScore(readiness.confidence + 1),
                consistency: clampedReadinessScore(readiness.consistency + 1),
                skillProof: readiness.skillProof,
                experienceProof: readiness.experienceProof,
                profileCredibility: readiness.profileCredibility,
                networkStrength: readiness.networkStrength,
                interviewReadiness: readiness.interviewReadiness,
                applicationExecution: clampedReadinessScore(readiness.applicationExecution + 4)
            )
        case .interview:
            ReadinessMetrics(
                overall: clampedReadinessScore(readiness.overall + 2),
                targetClarity: readiness.targetClarity,
                proofStrength: readiness.proofStrength,
                confidence: clampedReadinessScore(readiness.confidence + 2),
                consistency: clampedReadinessScore(readiness.consistency + 1),
                skillProof: readiness.skillProof,
                experienceProof: readiness.experienceProof,
                profileCredibility: readiness.profileCredibility,
                networkStrength: readiness.networkStrength,
                interviewReadiness: clampedReadinessScore(readiness.interviewReadiness + 5),
                applicationExecution: clampedReadinessScore(readiness.applicationExecution + 2)
            )
        case .rejection:
            readiness
        case .offer:
            ReadinessMetrics(
                overall: clampedReadinessScore(readiness.overall + 4),
                targetClarity: readiness.targetClarity,
                proofStrength: clampedReadinessScore(readiness.proofStrength + 3),
                confidence: clampedReadinessScore(readiness.confidence + 4),
                consistency: clampedReadinessScore(readiness.consistency + 2),
                skillProof: clampedReadinessScore(readiness.skillProof + 2),
                experienceProof: clampedReadinessScore(readiness.experienceProof + 3),
                profileCredibility: readiness.profileCredibility,
                networkStrength: readiness.networkStrength,
                interviewReadiness: clampedReadinessScore(readiness.interviewReadiness + 5),
                applicationExecution: clampedReadinessScore(readiness.applicationExecution + 5)
            )
        case .changedGoal:
            readiness
        case .other:
            ReadinessMetrics(
                overall: clampedReadinessScore(readiness.overall + 1),
                targetClarity: readiness.targetClarity,
                proofStrength: readiness.proofStrength,
                confidence: clampedReadinessScore(readiness.confidence + 1),
                consistency: readiness.consistency,
                skillProof: readiness.skillProof,
                experienceProof: readiness.experienceProof,
                profileCredibility: readiness.profileCredibility,
                networkStrength: readiness.networkStrength,
                interviewReadiness: readiness.interviewReadiness,
                applicationExecution: readiness.applicationExecution
            )
        }
    }

    private static func outcomeImpact(for kind: CareerOutcomeKind) -> (xp: Int, reason: String) {
        switch kind {
        case .applied:
            (25, "Application activity logged without counting it as proof.")
        case .interview:
            (45, "Interview signal logged for follow-up practice.")
        case .rejection:
            (0, "Rejection logged as recovery context, not as proof of readiness.")
        case .offer:
            (80, "Major outcome logged for future proof and progress context.")
        case .changedGoal:
            (0, "Goal change logged as context only; a fresh diagnostic should create the new baseline.")
        case .other:
            (10, "Career event logged for future context.")
        }
    }

    private static func addBadges(for result: QualityCheckResult, progress: inout ProgressState) {
        if !progress.badges.contains(.firstProof) {
            progress.badges.append(.firstProof)
        }
        if result.isAccepted,
           result.inspectionScope.didInspectSubmittedEvidence,
           !progress.badges.contains(.strongProof) {
            progress.badges.append(.strongProof)
        }
        if progress.streakCount >= 3, !progress.badges.contains(.threeDayStreak) {
            progress.badges.append(.threeDayStreak)
        }
        if progress.streakCount >= 7, !progress.badges.contains(.weeklyStreak) {
            progress.badges.append(.weeklyStreak)
        }
    }

    private static func addOutcomeBadges(for kind: CareerOutcomeKind, progress: inout ProgressState) {
        guard kind != .rejection, kind != .changedGoal else { return }

        if !progress.badges.contains(.firstOutcome) {
            progress.badges.append(.firstOutcome)
        }
        if kind == .interview, !progress.badges.contains(.firstInterview) {
            progress.badges.append(.firstInterview)
        }
        if kind == .offer, !progress.badges.contains(.firstOffer) {
            progress.badges.append(.firstOffer)
        }
    }
}
