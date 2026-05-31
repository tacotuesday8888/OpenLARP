import SwiftUI

extension UserSnapshot {
    static let sample = UserSnapshot(
        name: "Langqi",
        targetRole: "Morgan Stanley summer analyst internship",
        targetTimeline: "AI-estimated: urgent, 30 days",
        cookedLabel: "Medium Cooked",
        cookedScore: 62,
        mainGap: "Your ambition is clear, but your proof is still too thin for finance roles.",
        streakCount: 6,
        xp: 740,
        xpGoal: 1_000,
        todayQuest: Quest(
            title: "Build a deal story from one public company",
            purpose: "Analyst roles need evidence that you can explain a business, not just say you are interested in finance.",
            timeEstimate: "25 min",
            difficulty: "Adaptive",
            proofRequired: "Paste 5 bullets or upload a screenshot of your notes.",
            xpReward: 120
        ),
        proofCount: 9,
        readiness: [
            ReadinessGap(title: "Proof", value: 0.42, label: "Developing", color: .openLARPCoral),
            ReadinessGap(title: "Story", value: 0.58, label: "Close", color: .openLARPYellow),
            ReadinessGap(title: "Interview", value: 0.35, label: "Weak", color: .openLARPRed),
            ReadinessGap(title: "Momentum", value: 0.74, label: "Strong", color: .openLARPGreen)
        ]
    )
}

extension QuestDay {
    static let sampleWeek: [QuestDay] = [
        QuestDay(day: 1, title: "Pick the target", focus: "Goal clarity", status: .complete, xpReward: 80),
        QuestDay(day: 2, title: "Find repeated requirements", focus: "Job pattern", status: .complete, xpReward: 90),
        QuestDay(day: 3, title: "Build a deal story", focus: "Proof", status: .current, xpReward: 120),
        QuestDay(day: 4, title: "Rewrite one bullet", focus: "Resume proof", status: .locked, xpReward: 100),
        QuestDay(day: 5, title: "Record your pitch", focus: "Interview story", status: .locked, xpReward: 120),
        QuestDay(day: 6, title: "Send one warm message", focus: "Network", status: .locked, xpReward: 140),
        QuestDay(day: 7, title: "Weekly cooked check", focus: "Progress", status: .locked, xpReward: 160)
    ]
}

extension AgentPrompt {
    static let samplePrompts: [AgentPrompt] = [
        AgentPrompt(title: "Change my goal", description: "Rebuild or adapt your quest path for a new target."),
        AgentPrompt(title: "Why this quest?", description: "See how today's task makes you less cooked."),
        AgentPrompt(title: "Make this more aggressive", description: "Package real experience more strongly without inventing facts."),
        AgentPrompt(title: "I missed a day", description: "Get a recovery quest and protect your momentum.")
    ]
}

extension ProfileSummary {
    static let sample = ProfileSummary(
        name: "Langqi",
        status: "College student",
        goal: "Summer analyst internship",
        timeline: "30 days",
        memoryMode: "Memory on, sensitive chats excluded",
        proofItems: 9,
        badges: ["6-day streak", "Proof builder", "First target locked"]
    )
}
