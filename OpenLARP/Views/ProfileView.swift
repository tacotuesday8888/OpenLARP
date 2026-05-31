import SwiftUI

struct ProfileView: View {
    let store: OpenLARPStore
    @State private var memoryEnabled = true
    @State private var shareWins = true
    @State private var showingResetConfirmation = false
    @State private var selectedProof: ProofRecord?
    @State private var showingProofArchive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text(store.state.goal?.currentStatus.rawValue ?? "Goal setup pending")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                activeGoalCard
                streakCard
                privacyCard
                badgeCard
                proofCard
                rulesCard
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProof) { proof in
            ProofDetailView(proof: proof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .sheet(isPresented: $showingProofArchive) {
            ProofArchiveView(proofs: store.state.progress.recentProof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .confirmationDialog(
            "Change goal?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Goal And Local Plan", role: .destructive) {
                store.resetGoal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local diagnostic and questline so you can set a new target.")
        }
    }

    private var activeGoalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active goal")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

                if let goal = store.state.goal {
                    Text(goal.targetRole)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Pill(title: goal.timeline, systemImage: "calendar", color: .openLARPCoral)
                        Pill(title: "\(store.state.progress.proofCount) proof items", systemImage: "checkmark.seal", color: .openLARPGreen)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ProfileDetailRow(title: "Background", value: goal.background.isEmpty ? "Not provided yet" : goal.background)
                        ProfileDetailRow(title: "Existing proof", value: goal.existingProof.isEmpty ? "Thin or not provided yet" : goal.existingProof)
                        ProfileDetailRow(title: "Biggest blocker", value: goal.biggestBlocker.isEmpty ? "Not provided yet" : goal.biggestBlocker)
                    }

                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Change goal", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Text("Set a career target from Today to unlock the diagnostic, quest map, and progress baseline.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                }
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

                Toggle("Long-term memory", isOn: $memoryEnabled)
                Toggle("Allow shareable wins", isOn: $shareWins)

                Text(memoryEnabled ? "Local memory is on for this device. Real cloud memory is not built yet." : "Memory is off for future sensitive chats on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var streakCard: some View {
        if !store.state.needsGoalSetup {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active streak")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(store.state.progress.streakCount)")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(Color.openLARPCoral)

                        Text(store.state.progress.streakCount == 1 ? "day" : "days")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }

                    if let recovery = MissedDayRecoveryContent(state: store.state) {
                        Text("\(recovery.previousStreakText). \(recovery.missedDaysText) Continue from Today to rebuild the active streak.")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let skipped = SkippedTodayContent(state: store.state) {
                        Text("\(skipped.previousStreakText). \(skipped.unlockMessage)")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("This is the current live streak for the local quest track.")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
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

                if store.state.progress.badges.isEmpty {
                    Text("Lock a goal and submit proof to earn the first badges.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    FlowLayout(items: store.state.progress.badges.map(\.rawValue))
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Proof receipts")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

                Button {
                    showingProofArchive = true
                } label: {
                    Label("Proof archive", systemImage: "archivebox")
                }
                .buttonStyle(SecondaryButtonStyle())

                if store.state.progress.recentProof.isEmpty {
                    Text("Recent proof will show up here after you complete a quest.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(store.state.progress.recentProof.prefix(3)) { proof in
                        Button {
                            selectedProof = proof
                        } label: {
                            ProofReceiptRow(proof: proof) { attachment in
                                store.localURL(for: attachment)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Product rules")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

                Label("Package real experience aggressively.", systemImage: "sparkles")
                Label("Never invent employers, schools, certificates, titles, dates, projects, or ownership.", systemImage: "checkmark.shield")
                Label("The agent drafts. You approve external actions.", systemImage: "hand.tap")
            }
            .font(.subheadline)
            .foregroundStyle(Color.openLARPSoftInk)
        }
    }
}

private struct ProfileDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
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
