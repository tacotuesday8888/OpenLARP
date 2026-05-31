import SwiftUI

struct QuestMapView: View {
    let quests: [QuestDay]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next 7 days")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text("A short path keeps the goal visible without making the whole career feel impossible.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                VStack(spacing: 12) {
                    ForEach(quests) { quest in
                        QuestDayRow(quest: quest)
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
    let quest: QuestDay

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

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(quest.title)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        Spacer()

                        Text(quest.status.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(quest.status.color)
                    }

                    Text(quest.focus)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)

                    Text("+\(quest.xpReward) XP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.openLARPGreen)
                }
            }
        }
        .opacity(quest.status == .locked ? 0.72 : 1)
    }
}
