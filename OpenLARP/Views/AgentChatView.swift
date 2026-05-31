import SwiftUI

struct AgentChatView: View {
    let prompts: [AgentPrompt]
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Career agent")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(Color.openLARPInk)

                        Text("Ask for help when you need to change goals, understand a quest, or get unstuck. The app still starts with action.")
                            .font(.body)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Memory")
                                .font(.headline)
                            Text("Memory is on for useful career context. Sensitive chats can be kept out of long-term memory.")
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                            Pill(title: "Drafts only. You approve external actions.", systemImage: "hand.raised", color: .openLARPCoral)
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
                TextField("Ask the agent", text: $draft)
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
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
