import SwiftUI

struct QuestMapView: View {
    let state: OpenLARPState
    let viewToday: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next 7 days")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text(state.goal == nil ? "Set a goal first. The quest map appears after the cooked diagnostic." : "A short path keeps the goal visible without making the whole career feel impossible.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state.plan.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No questline yet")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                            Text("The map is generated locally after goal setup and the Am I Cooked diagnostic.")
                                .font(.body)
                                .foregroundStyle(Color.openLARPSoftInk)
                            Button("View Today", action: viewToday)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("\(state.progress.streakCount)", systemImage: "flame.fill")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color.openLARPCoral)
                                Text("day streak")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.openLARPSoftInk)
                                Spacer()
                                Text("\(state.progress.completedQuestCount)/7 complete")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.openLARPInk)
                            }

                            ProgressView(value: Double(state.progress.completedQuestCount), total: 7)
                                .tint(.openLARPGreen)
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(state.plan) { quest in
                            QuestDayRow(quest: quest, viewToday: viewToday)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuestDayRow: View {
    let quest: Quest
    let viewToday: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(quest.status.color.opacity(0.18))
                    Text("\(quest.day)")
                        .font(.headline.weight(.black))
                        .foregroundStyle(quest.status.color)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(quest.title)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Text(quest.status.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(quest.status.color)
                    }

                    Text(quest.gap.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)

                    HStack {
                        Text("+\(quest.xpReward) XP")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPGreen)

                        Spacer()

                        if quest.status == .available || quest.status == .inProgress {
                            Button("View Today", action: viewToday)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.openLARPGreen)
                        }
                    }
                }
            }
        }
        .opacity(quest.status == .locked ? 0.72 : 1)
    }
}
