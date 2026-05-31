import Foundation

enum OpenLARPEngine {
    static func confirmGoal(_ goal: CareerGoal, now: Date = Date()) -> OpenLARPState {
        let diagnostic = makeDiagnostic(for: goal)
        let plan = makeSevenDayPlan(for: goal)
        var progress = ProgressState.empty
        progress.badges = [.firstGoal]

        return OpenLARPState(
            goal: goal,
            diagnostic: diagnostic,
            plan: plan,
            progress: progress,
            updatedAt: now
        )
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
        next.updatedAt = now
        return next
    }

    static func checkProof(_ proof: ProofSubmission, in state: OpenLARPState) throws -> QualityCheckResult {
        guard let quest = state.currentQuest else {
            throw OpenLARPError.noCurrentQuest
        }

        let trimmedText = proof.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = proof.link.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachment = !proof.attachments.isEmpty
        guard !trimmedText.isEmpty || !trimmedLink.isEmpty || hasAttachment else {
            throw OpenLARPError.emptyProof
        }

        if proof.kind == .selfReport {
            return QualityCheckResult(
                isAccepted: false,
                qualityScore: 48,
                label: "Needs stronger proof",
                reason: "This keeps the streak alive, but it is still mostly your word. Useful, not definitive.",
                improvement: "Add a screenshot, link, notes, or artifact next time so this becomes evidence.",
                xpEarned: max(25, Int(Double(quest.xpReward) * 0.375)),
                readinessDelta: 2
            )
        }

        let wordCount = trimmedText.split { $0.isWhitespace || $0.isNewline }.count
        let hasUsefulLink = trimmedLink.hasPrefix("http://") || trimmedLink.hasPrefix("https://")
        let accepted = wordCount >= 18 || hasUsefulLink || hasAttachment

        if accepted {
            return QualityCheckResult(
                isAccepted: true,
                qualityScore: hasAttachment ? 88 : hasUsefulLink ? 86 : 78,
                label: "Strong proof",
                reason: hasAttachment ? "This includes a saved screenshot or photo, so it is more than a claim." : "This gives OpenLARP something concrete to count: a real artifact, action, or trace of work.",
                improvement: "Next time, connect the artifact to one target-role requirement so the proof becomes easier to reuse.",
                xpEarned: quest.xpReward,
                readinessDelta: 7
            )
        }

        return QualityCheckResult(
            isAccepted: false,
            qualityScore: 55,
            label: "Needs stronger proof",
            reason: "This is a start, but it does not yet show enough detail to prove meaningful progress.",
            improvement: "Add what you made, who it helps, or a link/screenshot that shows the work exists.",
            xpEarned: max(30, quest.xpReward / 2),
            readinessDelta: 3
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
        recordDailyCompletion(
            quest: quest,
            result: result,
            now: now,
            calendar: calendar,
            in: &next
        )
        next.updatedAt = now
        return next
    }

    static func refreshDailyAvailability(
        in state: OpenLARPState,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> OpenLARPState {
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
    }

    private static func nextLocalDay(after date: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86_400)
    }

    private static func updatedReadiness(_ readiness: ReadinessMetrics, delta: Int) -> ReadinessMetrics {
        ReadinessMetrics(
            overall: min(100, readiness.overall + max(1, delta / 2)),
            proofStrength: min(100, readiness.proofStrength + delta),
            confidence: min(100, readiness.confidence + max(1, delta / 2)),
            consistency: min(100, readiness.consistency + max(1, delta))
        )
    }

    private static func addBadges(for result: QualityCheckResult, progress: inout ProgressState) {
        if !progress.badges.contains(.firstProof) {
            progress.badges.append(.firstProof)
        }
        if result.isAccepted, !progress.badges.contains(.strongProof) {
            progress.badges.append(.strongProof)
        }
        if progress.streakCount >= 3, !progress.badges.contains(.threeDayStreak) {
            progress.badges.append(.threeDayStreak)
        }
        if progress.streakCount >= 7, !progress.badges.contains(.weeklyStreak) {
            progress.badges.append(.weeklyStreak)
        }
    }
}
