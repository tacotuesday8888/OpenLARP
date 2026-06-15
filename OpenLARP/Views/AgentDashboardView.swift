import SwiftUI

struct AgentDashboardView: View {
    let store: OpenLARPStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .agent,
                    eyebrow: "Private agent",
                    title: "Career Brief",
                    subtitle: store.state.needsGoalSetup ? "Set a goal first so the agent has real context." : store.state.agentBrief.summary,
                    stat: store.state.agentBrief.providerRoute.label
                )

                if store.state.needsGoalSetup {
                    emptyStateCard
                } else {
                    trustBoundaryCard
                    scanCard
                    topOpportunityCard
                    opportunitiesCard
                    nextStepsCard
                    activityCard
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyStateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .agent, eyebrow: "No context", title: "Agent waiting")

                Text("OpenLARP needs a target role, baseline readiness, and the first proof sprint before the agent can rank useful next moves.")
                    .font(.body)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trustBoundaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .privacy, eyebrow: "Trust", title: "Agent boundaries")

                Label("Uses your goal, proof receipts, readiness history, and approved preferences.", systemImage: "person.text.rectangle")
                Label("Future cloud scans watch approved sources for jobs, projects, courses, deadlines, and networking leads.", systemImage: "server.rack")
                Label("External applications, messages, and publishing stay drafts until you approve them.", systemImage: "hand.raised.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.openLARPSoftInk)
        }
    }

    private var scanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeader(feature: .agent, eyebrow: "Scan", title: "Approved source monitor")
                    Spacer()
                    if store.isAgentScanning {
                        ProgressView()
                            .tint(.openLARPBlue)
                    }
                }

                Text(store.isAgentScanning ? "Ranking opportunities against target fit, urgency, missing proof, and expected impact." : "The local mock scan simulates future cloud agents that watch approved sources while the user is away.")
                    .font(.body)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        await store.runAgentScan()
                    }
                } label: {
                    Label(store.isAgentScanning ? "Agent Scan Running" : "Run Agent Scan", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isAgentScanning)
                .opacity(store.isAgentScanning ? 0.65 : 1)
            }
        }
    }

    @ViewBuilder
    private var topOpportunityCard: some View {
        if let opportunity = store.state.agentBrief.opportunities.first {
            OpportunityBriefCard(opportunity: opportunity, isFeatured: true)
        }
    }

    private var opportunitiesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .agent, eyebrow: "Ranked brief", title: "Opportunity queue")

                if store.state.agentBrief.opportunities.isEmpty {
                    Text("Ranked opportunities appear after the first agent scan.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(store.state.agentBrief.opportunities) { opportunity in
                        OpportunityBriefRow(opportunity: opportunity)
                    }
                }
            }
        }
    }

    private var nextStepsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .quest, eyebrow: "Drafted", title: "Next steps")

                ForEach(store.state.agentBrief.nextSteps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.openLARPGreen)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)

                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .stats, eyebrow: "Audit trail", title: "Agent activity")

                if store.state.agentBrief.activities.isEmpty {
                    Text("Agent activity appears here after a goal is created.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(store.state.agentBrief.activities) { activity in
                        AgentActivityRow(activity: activity)
                    }
                }
            }
        }
    }
}

struct OpportunityBriefCard: View {
    let opportunity: OpportunityCard
    var isFeatured = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FeatureMark(feature: .agent, size: 38)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(isFeatured ? "Top ranked brief" : "Opportunity")
                            .font(.caption.weight(.black))
                            .foregroundStyle(Color.openLARPBlue)
                            .textCase(.uppercase)

                        Text(opportunity.title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(Color.openLARPInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("#\(opportunity.rank == 0 ? 1 : opportunity.rank)")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color.openLARPBlue)
                        .frame(width: 44, height: 36)
                        .background(Color.openLARPBlue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack(spacing: 8) {
                    Pill(title: opportunity.type.rawValue, systemImage: opportunity.type.systemImage, color: .openLARPBlue)
                    Pill(title: "\(opportunity.compositeScore)% fit", systemImage: "chart.bar.fill", color: .openLARPGreen)
                }

                Text(opportunity.whyItMatters)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Missing proof: \(opportunity.missingProof)", systemImage: "scope")
                    Label(opportunity.recommendedAction, systemImage: "arrow.right.circle.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPInk)
            }
        }
    }
}

private struct OpportunityBriefRow: View {
    let opportunity: OpportunityCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("#\(opportunity.rank)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 26)
                    .background(Color.openLARPBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(opportunity.title)
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }

            HStack(spacing: 6) {
                MiniScore(label: "Fit", value: opportunity.fitScore, color: .openLARPBlue)
                MiniScore(label: "Urgency", value: opportunity.urgencyScore, color: .openLARPCoral)
                MiniScore(label: "Impact", value: opportunity.impactScore, color: .openLARPGreen)
            }

            Text(opportunity.recommendedAction)
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AgentActivityRow: View {
    let activity: AgentActivity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                    Spacer()
                    Text(activity.status.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }

                Text(activity.summary)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                if activity.approvalRequired {
                    Label("Approval required before external action", systemImage: "hand.raised.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.openLARPCoral)
                }
            }
        }
        .padding(12)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var icon: String {
        switch activity.type {
        case .profileAnalysis: "person.text.rectangle"
        case .questGeneration: "bolt.fill"
        case .proofEvaluation: "checkmark.seal.fill"
        case .readinessUpdate: "chart.line.uptrend.xyaxis"
        case .opportunityScan: "magnifyingglass"
        case .briefGeneration: "doc.text.fill"
        }
    }

    private var color: Color {
        switch activity.status {
        case .completed: .openLARPGreen
        case .running: .openLARPBlue
        case .queued: .openLARPYellow
        case .needsApproval: .openLARPCoral
        case .failed: .openLARPRed
        }
    }
}

private struct MiniScore: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.openLARPSoftInk)
            ProgressView(value: Double(value), total: 100)
                .tint(color)
        }
        .frame(maxWidth: .infinity)
    }
}
