import SwiftUI

struct AgentChatView: View {
    let store: OpenLARPStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private var prompts: [AgentPrompt] {
        [
            AgentPrompt(title: "Why this quest?", description: store.state.currentQuest?.purpose ?? "Set a goal first so the agent has context."),
            AgentPrompt(title: "Make this easier", description: "Shrink the action without turning it into fake progress."),
            AgentPrompt(title: "Improve my proof", description: "Turn a self-report into something more defensible."),
            AgentPrompt(title: "Change my goal", description: "Rebuild the questline when the target is wrong.")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Agent helper")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(Color.openLARPInk)

                        Text("Use this to unblock today’s quest. OpenLARP still starts with action, not chat.")
                            .font(.body)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let quest = store.state.currentQuest {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Current context")
                                    .font(.headline)
                                    .foregroundStyle(Color.openLARPInk)
                                Text(quest.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.openLARPInk)
                                Text(quest.proofRequired)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.openLARPSoftInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Boundaries")
                                .font(.headline)
                                .foregroundStyle(Color.openLARPInk)
                            Text("Local helper only. No real AI call, no backend memory, and no external action without user approval.")
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Pill(title: "Drafts only", systemImage: "hand.raised", color: .openLARPCoral)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Try asking")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        ForEach(prompts) { prompt in
                            Button {
                                draft = prompt.title
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(prompt.title)
                                            .font(.headline)
                                            .foregroundStyle(Color.openLARPInk)
                                        Text(prompt.description)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.openLARPSoftInk)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(Color.openLARPGreen)
                                }
                                .padding(14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
                .padding(20)
            }

            HStack(spacing: 10) {
                TextField("Ask about today's quest", text: $draft)
                    .textFieldStyle(.roundedBorder)

                Button {
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.openLARPGreen)
                }
                .accessibilityLabel("Send message")
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Helper")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Back to Quest") {
                    dismiss()
                }
            }
        }
    }
}
