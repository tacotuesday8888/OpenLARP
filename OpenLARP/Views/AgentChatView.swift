import SwiftUI

struct AskOpenLARPButton: View {
    let store: OpenLARPStore
    let surface: V0ContextualAssistantSurface
    var title = "Ask OpenLARP"
    var onUseDraft: ((String) -> Void)?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(title, systemImage: "sparkles")
        }
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                AgentChatView(
                    store: store,
                    surface: surface,
                    onUseDraft: onUseDraft
                )
            }
        }
    }
}

struct AgentChatView: View {
    let store: OpenLARPStore
    let surface: V0ContextualAssistantSurface
    var onUseDraft: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var response: V0ContextualAssistantResponse?

    init(
        store: OpenLARPStore,
        surface: V0ContextualAssistantSurface = .questDetail,
        onUseDraft: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.surface = surface
        self.onUseDraft = onUseDraft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .agent,
                    eyebrow: surface.eyebrow,
                    title: "Ask OpenLARP",
                    subtitle: "Get one grounded explanation and a concrete next move without leaving this step.",
                    stat: "No memory write"
                )

                contextCard

                if let response {
                    responseCards(response)
                } else {
                    suggestedQuestions
                }

                composer

                Label(
                    "This exchange is not saved as memory. OpenLARP cannot inspect linked pages or attachment contents, and it never acts outside the app.",
                    systemImage: "hand.raised.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Contextual Help")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(surface.backTitle) { dismiss() }
            }
        }
    }

    private var contextCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(feature: .agent, eyebrow: "Current context", title: surface.contextTitle)
                if let quest = store.state.currentQuest,
                   [.questDetail, .proofPreparation, .proofFeedback].contains(surface) {
                    Text(quest.title)
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)
                    Text(quest.purpose)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else if let mission = store.state.mission, surface == .missionBrief {
                    Text(mission.firstMilestone)
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)
                    Text("\(mission.dailyCommitmentMinutes) minutes per day")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else if let diagnostic = store.state.diagnostic, surface == .cookedEvaluation {
                    Text(diagnostic.mainGap)
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)
                    Text("Directional baseline: \(diagnostic.readinessBaseline)/100")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    Text(store.state.goal?.targetRole ?? "Confirmed career goal")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)
                }
            }
        }
    }

    private var suggestedQuestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking")
                .font(.headline)
                .foregroundStyle(Color.openLARPInk)

            ForEach(surface.suggestedQuestions, id: \.self) { suggestion in
                Button {
                    question = suggestion
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.openLARPInk)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.down.left")
                            .foregroundStyle(Color.openLARPSuccessText)
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func responseCards(_ response: V0ContextualAssistantResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .agent, eyebrow: "Grounded answer", title: "What to do next")
                Text(response.answer)
                    .font(.body)
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !response.factIDsUsed.isEmpty {
                    DisclosureGroup("Confirmed facts used") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(response.factIDsUsed, id: \.self) { factID in
                                if let fact = store.state.careerUnderstanding.confirmedFacts.first(where: { $0.id == factID }) {
                                    Label(fact.value, systemImage: "checkmark.seal.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.openLARPSuccessText)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                ForEach(response.inferences, id: \.self) { inference in
                    labeledText("Inference", inference, systemImage: "questionmark.diamond.fill", color: .openLARPYellow)
                }
                ForEach(response.advice, id: \.self) { advice in
                    labeledText("Advice", advice, systemImage: "lightbulb.fill", color: .openLARPBlue)
                }
            }
        }

        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(feature: .quest, eyebrow: "Your move", title: response.nextAction.title)
                Text(response.nextAction.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestedDraft = response.suggestedDraft {
                    Text(suggestedDraft)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Color.openLARPInk)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color.openLARPBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if let onUseDraft {
                        Button {
                            onUseDraft(suggestedDraft)
                            dismiss()
                        } label: {
                            Label("Use This Draft", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private func labeledText(_ label: String, _ text: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .textCase(.uppercase)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composer: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(response == nil ? "Your question" : "Ask a follow-up")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

                TextEditor(text: $question)
                    .frame(minHeight: 92)
                    .padding(8)
                    .background(Color.openLARPBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.openLARPSoftInk.opacity(0.22))
                    }
                    .accessibilityLabel("Question for OpenLARP")
                    .disabled(store.isContextualAssistantRunning)

                Button {
                    let submittedQuestion = question
                    Task {
                        if let answer = await store.askOpenLARP(surface: surface, question: submittedQuestion) {
                            response = answer
                            question = ""
                        }
                    }
                } label: {
                    if store.isContextualAssistantRunning {
                        HStack {
                            ProgressView().tint(.white)
                            Text("Thinking")
                        }
                    } else {
                        Label("Get Grounded Help", systemImage: "sparkles")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isContextualAssistantRunning)
            }
        }
    }
}

private extension V0ContextualAssistantSurface {
    var eyebrow: String {
        switch self {
        case .cookedEvaluation: "Cooked evaluation"
        case .missionBrief: "Mission brief"
        case .questDetail: "Quest detail"
        case .proofPreparation: "Proof preparation"
        case .proofFeedback: "Proof feedback"
        case .weeklyReport: "Sprint report"
        }
    }

    var contextTitle: String {
        switch self {
        case .cookedEvaluation: "Your directional readiness baseline"
        case .missionBrief: "Your editable mission"
        case .questDetail: "Today’s quest"
        case .proofPreparation: "The proof you are preparing"
        case .proofFeedback: "The review you just received"
        case .weeklyReport: "Your checkpoint progress"
        }
    }

    var backTitle: String {
        switch self {
        case .cookedEvaluation: "Back to Cooked"
        case .missionBrief: "Back to Mission"
        case .questDetail, .proofPreparation, .proofFeedback: "Back to Quest"
        case .weeklyReport: "Back to Report"
        }
    }

    var suggestedQuestions: [String] {
        switch self {
        case .cookedEvaluation:
            ["What does this score actually mean?", "Which gap should I address first?", "What is uncertain here?"]
        case .missionBrief:
            ["Is this milestone realistic?", "How should I adjust this for my constraints?", "Why are these gaps prioritized?"]
        case .questDetail:
            ["Why this quest?", "Make this action smaller without making it fake progress.", "What counts as done?"]
        case .proofPreparation:
            ["What should this proof include?", "Help me describe this honestly.", "What would make this more defensible?"]
        case .proofFeedback:
            ["How do I improve this review?", "What is the smallest useful revision?", "What did OpenLARP actually inspect?"]
        case .weeklyReport:
            ["What changed this week?", "What should chapter two focus on?", "Which result is most meaningful?"]
        }
    }
}
