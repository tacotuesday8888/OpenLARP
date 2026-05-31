import SwiftUI

struct ProfileView: View {
    let profile: ProfileSummary
    @State private var memoryEnabled = true
    @State private var shareWins = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name)
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text(profile.status)
                        .font(.headline)
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active goal")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        Text(profile.goal)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.openLARPInk)

                        HStack {
                            Pill(title: profile.timeline, systemImage: "calendar", color: .openLARPCoral)
                            Pill(title: "\(profile.proofItems) proof items", systemImage: "checkmark.seal", color: .openLARPGreen)
                        }

                        Button {
                            // Goal rebuild/adapt flow comes after onboarding is wired.
                        } label: {
                            Label("Change goal", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Privacy")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        Toggle("Long-term memory", isOn: $memoryEnabled)
                        Toggle("Allow shareable wins", isOn: $shareWins)

                        Text(memoryEnabled ? profile.memoryMode : "Memory off for future sensitive chats")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Badges")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        FlowLayout(items: profile.badges)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Product rules")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        Label("Package real experience aggressively.", systemImage: "sparkles")
                        Label("Never invent employers, certificates, titles, dates, projects, or ownership.", systemImage: "checkmark.shield")
                        Label("The agent drafts. You approve external actions.", systemImage: "hand.tap")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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
