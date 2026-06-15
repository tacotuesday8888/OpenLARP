import SwiftUI

struct ProgressTabView: View {
    let state: OpenLARPState
    let attachmentURL: (ProofAttachment) -> URL
    let improveWeakestArea: () -> Void
    @State private var selectedProof: ProofRecord?
    @State private var showingProofArchive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .stats,
                    eyebrow: "Stats",
                    title: "Less cooked",
                    subtitle: "The serious layer under the joke: proof, consistency, and readiness.",
                    stat: "\(state.progress.readiness.overall)%"
                )

                if state.needsGoalSetup {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No baseline yet")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                            Text("Set a goal and run the diagnostic to create the first readiness baseline.")
                                .font(.body)
                                .foregroundStyle(Color.openLARPSoftInk)
                            Button("Set Goal", action: improveWeakestArea)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                } else {
                    readinessCard
                    readinessHistoryCard
                    xpCard
                    proofCard
                    badgeCard
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProof) { proof in
            ProofDetailView(proof: proof, attachmentURL: attachmentURL)
        }
        .sheet(isPresented: $showingProofArchive) {
            ProofArchiveView(
                proofs: state.progress.recentProof,
                attachmentURL: attachmentURL
            )
        }
    }

    private var readinessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .stats, eyebrow: "Signal radar", title: "Goal readiness")

                HStack(alignment: .center, spacing: 14) {
                    ReadinessRings(value: state.progress.readiness.overall)

                    VStack(spacing: 8) {
                        SummaryTile(value: label(for: state.progress.readiness.proofStrength), label: "Proof", color: .openLARPCoral)
                        SummaryTile(value: label(for: state.progress.readiness.confidence), label: "Confidence", color: .openLARPYellow)
                        SummaryTile(value: label(for: state.progress.readiness.consistency), label: "Consistency", color: .openLARPGreen)
                    }
                    .frame(maxWidth: 142)
                }

                ReadinessRow(title: "Proof strength", value: state.progress.readiness.proofStrength, color: .openLARPCoral)
                ReadinessRow(title: "Skill proof", value: state.progress.readiness.skillProof, color: .openLARPBlue)
                ReadinessRow(title: "Network strength", value: state.progress.readiness.networkStrength, color: .openLARPPurple)
                ReadinessRow(title: "Confidence", value: state.progress.readiness.confidence, color: .openLARPYellow)
                ReadinessRow(title: "Consistency", value: state.progress.readiness.consistency, color: .openLARPGreen)

                Button {
                    improveWeakestArea()
                } label: {
                    Label("Improve Weakest Area", systemImage: "target")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var readinessHistoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .stats, eyebrow: "History", title: "Readiness timeline")

                if state.progress.readinessHistory.isEmpty {
                    Text("The first readiness baseline appears after goal setup. Proof claims add snapshots over time.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(state.progress.readinessHistory.reversed()) { snapshot in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(snapshot.overall)")
                                .font(.headline.weight(.black))
                                .foregroundStyle(Color.openLARPBlue)
                                .frame(width: 44, height: 36)
                                .background(Color.openLARPBlue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(snapshot.reason)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.openLARPInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("\(label(for: snapshot.proofStrength)) proof, \(label(for: snapshot.skillProof)) skill proof, \(label(for: snapshot.networkStrength)) network")
                                    .font(.caption)
                                    .foregroundStyle(Color.openLARPSoftInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color.openLARPBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func label(for value: Int) -> String {
        switch value {
        case ..<35: "Weak"
        case 35..<55: "Building"
        case 55..<75: "Credible"
        default: "Strong"
        }
    }

    private var xpCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .quest, eyebrow: "Sprint momentum", title: "Sprint XP")

                ProgressView(value: Double(state.progress.xp), total: Double(state.progress.xpGoal))
                    .tint(.openLARPGreen)

                HStack(spacing: 8) {
                    SummaryTile(value: "\(state.progress.completedQuestCount)", label: "Quests", color: .openLARPPurple)
                    SummaryTile(value: "\(state.progress.proofCount)", label: "Proof", color: .openLARPGreen)
                    SummaryTile(value: "\(state.progress.streakCount)", label: "Streak", color: .openLARPCoral)
                }

                if let recovery = MissedDayRecoveryContent(state: state) {
                    Label("\(recovery.previousStreakText). Active streak reset after \(recovery.missedDaysText.lowercased())", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let skipped = SkippedTodayContent(state: state) {
                    Label("\(skipped.previousStreakText). \(skipped.unlockMessage)", systemImage: "forward.end")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Evidence bank", title: "Recent proof")

                Button {
                    showingProofArchive = true
                } label: {
                    Label("All proof receipts", systemImage: "archivebox")
                }
                .buttonStyle(SecondaryButtonStyle())

                if state.progress.recentProof.isEmpty {
                    Text("No proof yet. Today’s quest is where the first receipt comes from.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(state.progress.recentProof.prefix(4)) { proof in
                        Button {
                            selectedProof = proof
                        } label: {
                            ProofReceiptRow(
                                proof: proof,
                                attachmentURL: attachmentURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var badgeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Proof wins", title: "Badges")

                if state.progress.badges.isEmpty {
                    Text("Badges unlock from real progress, not from opening the app.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(state.progress.badges) { badge in
                            Label(badge.rawValue, systemImage: "seal.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.openLARPGreen)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(Color.openLARPGreen.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

private struct ReadinessRow: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(label(for: value))
                    .foregroundStyle(color)
            }
            .font(.subheadline.weight(.semibold))

            ProgressView(value: Double(value), total: 100)
                .tint(color)
        }
    }

    private func label(for value: Int) -> String {
        switch value {
        case ..<35: "Weak"
        case 35..<55: "Developing"
        case 55..<75: "Credible"
        default: "Strong"
        }
    }
}
