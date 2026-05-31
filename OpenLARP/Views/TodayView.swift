import SwiftUI

struct TodayView: View {
    let snapshot: UserSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                cookedCard
                questCard
                readinessCard
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Duolingo for your career")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.openLARPGreen)
                        .textCase(.uppercase)

                    Text(snapshot.targetRole)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Label("\(snapshot.streakCount)", systemImage: "flame.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.openLARPCoral)

                    Text("day streak")
                        .font(.caption)
                        .foregroundStyle(Color.openLARPSoftInk)
                }
            }

            HStack {
                Pill(title: snapshot.targetTimeline, systemImage: "clock", color: .openLARPCoral)
                Pill(title: "\(snapshot.proofCount) proof items", systemImage: "checkmark.seal", color: .openLARPGreen)
            }
        }
    }

    private var cookedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Am I Cooked?")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.openLARPInk)

                        Text(snapshot.cookedLabel)
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(Color.openLARPCoral)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(Color.openLARPCoral.opacity(0.18), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.cookedScore) / 100)
                            .stroke(Color.openLARPCoral, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(snapshot.cookedScore)")
                            .font(.title2.weight(.black))
                    }
                    .frame(width: 82, height: 82)
                }

                Text(snapshot.mainGap)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    // Share-card generation comes after the visual direction is locked.
                } label: {
                    Label("Preview share card", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var questCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Pill(title: snapshot.todayQuest.timeEstimate, systemImage: "timer", color: .openLARPGreen)
                    Pill(title: "+\(snapshot.todayQuest.xpReward) XP", systemImage: "bolt.fill", color: .openLARPYellow)
                }

                Text(snapshot.todayQuest.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(snapshot.todayQuest.purpose)
                    .font(.body)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Label(snapshot.todayQuest.proofRequired, systemImage: "photo.on.rectangle")
                    Label("One main quest. Swap only if it is a bad fit.", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)

                HStack(spacing: 10) {
                    Button {
                        // Proof upload will connect to storage after the shell is validated.
                    } label: {
                        Label("Submit proof", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        // Quest swap rules come later.
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                            .frame(width: 48, height: 48)
                            .background(Color.openLARPYellow.opacity(0.24))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .accessibilityLabel("Swap quest")
                }
            }
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

                    Text("\(snapshot.xp) / \(snapshot.xpGoal) XP")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                ProgressView(value: Double(snapshot.xp), total: Double(snapshot.xpGoal))
                    .tint(.openLARPGreen)

                ForEach(snapshot.readiness) { gap in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(gap.title)
                            Spacer()
                            Text(gap.label)
                                .foregroundStyle(gap.color)
                        }
                        .font(.subheadline.weight(.semibold))

                        ProgressView(value: gap.value)
                            .tint(gap.color)
                    }
                }
            }
        }
    }
}
