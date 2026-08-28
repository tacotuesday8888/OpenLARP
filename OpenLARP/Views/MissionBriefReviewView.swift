import SwiftUI

struct MissionBriefReviewView: View {
    let store: OpenLARPStore
    let mission: CareerMissionBrief

    @State private var constraints: String
    @State private var readinessGapsText: String
    @State private var firstMilestone: String
    @State private var dailyCommitmentMinutes: Int
    @State private var sprintSummary: String
    @State private var validationMessage: String?
    @State private var showingGoalResetConfirmation = false

    init(store: OpenLARPStore, mission: CareerMissionBrief) {
        self.store = store
        self.mission = mission
        _constraints = State(initialValue: mission.constraints)
        _readinessGapsText = State(initialValue: mission.mainReadinessGaps.joined(separator: "\n"))
        _firstMilestone = State(initialValue: mission.firstMilestone)
        _dailyCommitmentMinutes = State(initialValue: mission.dailyCommitmentMinutes)
        _sprintSummary = State(initialValue: mission.sprint.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OpenLARPHeroCard(
                feature: .path,
                eyebrow: "Mission review",
                title: "Turn the roast into a real plan",
                subtitle: "Edit the advice. Confirm the mission. OpenLARP will not create your sprint until you approve it.",
                stat: "14 days · 2 chapters"
            )

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(feature: .cooked, eyebrow: "Target outcome", title: mission.targetOutcome)

                    DisclosureGroup("Confirmed current state") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(mission.confirmedCurrentState) { fact in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.kind.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.openLARPSoftInk)
                                    Text(fact.value)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.top, 8)
                    }

                    missionEditor(
                        title: "Constraints",
                        detail: "Keep this honest so the daily plan fits your real life. Blank is allowed.",
                        text: $constraints,
                        accessibilityLabel: "Mission constraints"
                    )

                    missionEditor(
                        title: "Main readiness gaps",
                        detail: "Use one gap per line, up to four. These are directional priorities, not verified deficiencies.",
                        text: $readinessGapsText,
                        accessibilityLabel: "Mission readiness gaps"
                    )

                    missionEditor(
                        title: "First milestone",
                        detail: "The smallest meaningful result this sprint should create.",
                        text: $firstMilestone,
                        accessibilityLabel: "Mission first milestone"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily commitment")
                            .font(.subheadline.weight(.semibold))
                        Stepper(
                            "\(dailyCommitmentMinutes) minutes per day",
                            value: $dailyCommitmentMinutes,
                            in: 5...180,
                            step: 5
                        )
                        .accessibilityLabel("Daily mission commitment")
                        .accessibilityValue("\(dailyCommitmentMinutes) minutes")
                    }

                    missionEditor(
                        title: "Two-chapter sprint",
                        detail: "The sprint stays 14 days. Edit how the two chapters should work together.",
                        text: $sprintSummary,
                        accessibilityLabel: "Mission sprint structure"
                    )
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Non-negotiable boundaries", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPSuccessText)
                    ForEach(mission.ethicalBoundaries, id: \.self) { boundary in
                        Label(boundary, systemImage: "checkmark")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.openLARPAttentionText)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Button(action: approveMission) {
                if store.isMissionApprovalRunning {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Building Your Sprint")
                    }
                } else {
                    Label("Approve Mission & Build My Sprint", systemImage: "checkmark.seal.fill")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isMissionApprovalRunning)
            .accessibilityIdentifier("mission.approve")

            AskOpenLARPButton(
                store: store,
                surface: .missionBrief,
                title: "Ask OpenLARP about this mission"
            )
            .disabled(store.isMissionApprovalRunning)

            Button {
                showingGoalResetConfirmation = true
            } label: {
                Label("Adjust Career Goal", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(store.isMissionApprovalRunning)
        }
        .confirmationDialog(
            "Adjust this career goal?",
            isPresented: $showingGoalResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Return to Goal Setup", role: .destructive) {
                store.resetGoal()
            }
            Button("Keep This Mission", role: .cancel) {}
        } message: {
            Text("Your existing proof and outcome history stay saved, but this unapproved mission and readiness baseline will be replaced.")
        }
    }

    private func missionEditor(
        title: String,
        detail: String,
        text: Binding<String>,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: text)
                .frame(minHeight: 88)
                .padding(8)
                .background(Color.openLARPBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.openLARPSoftInk.opacity(0.22))
                }
                .accessibilityLabel(accessibilityLabel)
                .disabled(store.isMissionApprovalRunning)
        }
    }

    private func approveMission() {
        validationMessage = nil
        let gaps = readinessGapsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let edited: CareerMissionBrief
        do {
            edited = try mission.applyingUserEdits(
                constraints: constraints,
                mainReadinessGaps: gaps,
                firstMilestone: firstMilestone,
                dailyCommitmentMinutes: dailyCommitmentMinutes,
                sprintSummary: sprintSummary,
                editedAt: store.currentDate
            )
        } catch {
            validationMessage = "Keep one to four specific gaps, a concrete first milestone, and a short two-chapter sprint description."
            return
        }

        let expectedOwnerScope = store.onboardingOwnerScope
        Task {
            let succeeded = await store.approveMissionBrief(
                edited,
                expectedOwnerScope: expectedOwnerScope
            )
            if !succeeded, expectedOwnerScope == store.onboardingOwnerScope {
                validationMessage = store.errorMessage ?? "OpenLARP could not save this mission yet. Your edits are still here."
            }
        }
    }
}
