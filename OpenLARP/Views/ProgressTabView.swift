import SwiftUI

struct ProgressTabView: View {
    let state: OpenLARPState
    let attachmentURL: (ProofAttachment) -> URL
    let improveWeakestArea: () -> Void
    @State private var selectedProof: ProofRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progress")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text("The serious layer under the cooked joke: proof, consistency, and readiness.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
    }

    private var readinessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Goal readiness")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)

                    Spacer()

                    Text("\(state.progress.readiness.overall)%")
                        .font(.title3.weight(.black))
                        .foregroundStyle(Color.openLARPGreen)
                }

                ReadinessRow(title: "Proof strength", value: state.progress.readiness.proofStrength, color: .openLARPCoral)
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

    private var xpCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sprint XP")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)
                    Spacer()
                    Text("\(state.progress.xp) / \(state.progress.xpGoal)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                ProgressView(value: Double(state.progress.xp), total: Double(state.progress.xpGoal))
                    .tint(.openLARPGreen)

                HStack {
                    ProgressStat(value: "\(state.progress.completedQuestCount)", label: "quests")
                    ProgressStat(value: "\(state.progress.proofCount)", label: "proof")
                    ProgressStat(value: "\(state.progress.streakCount)", label: "streak")
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent proof")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

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
                Text("Badges")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

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

private struct ProgressStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(Color.openLARPInk)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
