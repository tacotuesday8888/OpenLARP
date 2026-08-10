import SwiftUI

struct GuidedCareerOnboardingView: View {
    private enum FocusedField: Hashable {
        case targetOutcome
        case timeline
        case experience
        case existingProof
        case constraints
        case biggestBlocker
    }

    let store: OpenLARPStore
    let onGoalConfirmed: (CookedDiagnosticResultContent) -> Void

    @State private var draft = CareerIntakeDraft.empty
    @State private var flow = CareerOnboardingFlow()
    @State private var reviewUnderstanding: CareerUnderstanding?
    @State private var validationMessage: String?
    @State private var didChooseLocalEntry = false
    @State private var ownerScope = ""
    @State private var hypothesisEdits: [UUID: String] = [:]
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        Group {
            if !store.didFinishInitialAuthenticationResolution || store.isRestoringAuthenticationSession {
                authenticationResolutionView
            } else if shouldOfferAccountEntry {
                OnboardingAccountEntryView(store: store) {
                    didChooseLocalEntry = true
                }
            } else {
                careerQuestions
            }
        }
        .onAppear {
            ownerScope = store.onboardingOwnerScope
            if store.didFinishInitialAuthenticationResolution {
                store.recordOnboardingStarted()
            }
        }
        .onChange(of: store.didFinishInitialAuthenticationResolution) { _, didFinish in
            guard didFinish else { return }
            resetDraftForCurrentOwner()
            store.recordOnboardingStarted()
        }
        .onChange(of: store.onboardingOwnerScope) { _, newScope in
            guard newScope != ownerScope else { return }
            resetDraftForCurrentOwner()
            if store.didFinishInitialAuthenticationResolution {
                store.recordOnboardingStarted()
            }
        }
    }

    private var authenticationResolutionView: some View {
        Card {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opening your private workspace")
                        .font(.headline)
                    Text("OpenLARP is checking which protected on-device workspace belongs to you before accepting career answers.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var careerQuestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            OpenLARPHeroCard(
                feature: .path,
                eyebrow: "Career understanding",
                title: flow.step.title,
                subtitle: stepSubtitle,
                stat: flow.progressText
            )

            stepContent

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.openLARPCoral)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Button(action: performPrimaryAction) {
                if store.isGoalSetupRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Building Your Readiness Check")
                    }
                } else {
                    Label(flow.step.primaryActionTitle, systemImage: primaryActionSystemImage)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canUsePrimaryAction || store.isGoalSetupRunning)
            .opacity(canUsePrimaryAction && !store.isGoalSetupRunning ? 1 : 0.5)

            if flow.step != .outcome {
                Button {
                    validationMessage = nil
                    flow.goBack()
                } label: {
                    Label("Back to \(previousStepTitle)", systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.isGoalSetupRunning)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flow.step)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private var shouldOfferAccountEntry: Bool {
        guard !didChooseLocalEntry else { return false }
        return OnboardingAccountEntryPolicy.mode(
            configuration: store.releaseConfiguration,
            session: store.currentBackendSessionSnapshot()
        ) == .offerAccountOrLocal
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .outcome:
            outcomeStep
        case .currentReality:
            currentRealityStep
        case .commitment:
            commitmentStep
        case .review:
            reviewStep
        }
    }

    private var outcomeStep: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                onboardingPrompt(
                    "What are you working toward?",
                    detail: "Choose the closest outcome. You can change it later without inventing a cleaner story."
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                    ForEach(CareerOutcomeType.allCases) { outcomeType in
                        choiceButton(
                            title: outcomeType.title,
                            isSelected: draft.outcomeType == outcomeType
                        ) {
                            draft.outcomeType = outcomeType
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target role or outcome")
                        .font(.subheadline.weight(.semibold))
                    TextField("Entry-level iOS engineer", text: $draft.targetOutcome)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .targetOutcome)
                        .accessibilityLabel("Target role or career outcome")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Current stage")
                        .font(.subheadline.weight(.semibold))
                    Picker("Current stage", selection: $draft.currentStatus) {
                        ForEach(CurrentStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("OpenLARP uses this only as a user-confirmed career fact.")
                }
            }
        }
    }

    private var currentRealityStep: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                onboardingPrompt(
                    "What is true today?",
                    detail: "Specific beats impressive. Leave optional fields blank when the answer is unknown."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Timeline")
                        .font(.subheadline.weight(.semibold))
                    TextField("Within 90 days", text: $draft.timeline)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .timeline)
                        .accessibilityLabel("Career goal timeline")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Urgency")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(CareerUrgency.allCases) { urgency in
                            choiceButton(
                                title: urgency.title,
                                isSelected: draft.urgency == urgency
                            ) {
                                draft.urgency = urgency
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Relevant experience")
                        .font(.subheadline.weight(.semibold))
                    TextField("Coursework, projects, current work…", text: $draft.experience, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .experience)
                        .accessibilityLabel("Relevant experience")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Proof you already have")
                        .font(.subheadline.weight(.semibold))
                    TextField("Shipped work, links, screenshots, results…", text: $draft.existingProof, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .existingProof)
                        .accessibilityLabel("Existing career proof")
                    Text("Blank means unknown—not zero experience.")
                        .font(.caption)
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Confidence: \(draft.confidence) of 5")
                        .font(.subheadline.weight(.semibold))
                    Slider(
                        value: Binding(
                            get: { Double(draft.confidence) },
                            set: { draft.confidence = Int($0) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                    .tint(.openLARPGreen)
                    .accessibilityLabel("Current confidence")
                    .accessibilityValue("\(draft.confidence) out of 5")
                }
            }
        }
    }

    private var commitmentStep: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                onboardingPrompt(
                    "Make the plan fit your life",
                    detail: "A smaller honest commitment is more useful than a heroic plan you cannot sustain."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily time")
                        .font(.subheadline.weight(.semibold))
                    Picker("Daily time", selection: $draft.dailyCommitmentMinutes) {
                        Text("10 min").tag(10)
                        Text("20 min").tag(20)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Constraints")
                        .font(.subheadline.weight(.semibold))
                    TextField("Budget, schedule, location, access…", text: $draft.constraints, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .constraints)
                        .accessibilityLabel("Career plan constraints")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Biggest blocker")
                        .font(.subheadline.weight(.semibold))
                    TextField("What makes this outcome feel risky?", text: $draft.biggestBlocker, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .biggestBlocker)
                        .accessibilityLabel("Biggest career blocker")
                }
            }
        }
    }

    private var reviewStep: some View {
        let understanding = reviewUnderstanding ?? draft.makeUnderstanding(reviewedAt: Date())
        return VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    onboardingPrompt(
                        "Approve the facts, not a flattering guess",
                        detail: "Only the information below will shape your readiness check. Future AI suggestions will appear separately for confirmation."
                    )

                    reviewSection(
                        title: "You told us",
                        systemImage: "person.crop.circle.badge.checkmark",
                        facts: understanding.facts.filter {
                            $0.provenance.source == .userEntry || $0.provenance.source == .userEdit
                        }
                    )

                    if !understanding.pendingHypotheses.isEmpty {
                        hypothesisReviewSection(understanding.pendingHypotheses)
                    }

                    let confirmedHypotheses = understanding.facts.filter {
                        $0.provenance.source == .aiHypothesis && $0.confirmationState == .confirmed
                    }
                    if !confirmedHypotheses.isEmpty {
                        reviewSection(
                            title: "Suggestions you confirmed",
                            systemImage: "checkmark.bubble.fill",
                            facts: confirmedHypotheses
                        )
                    }

                    if !understanding.rejectedFacts.isEmpty {
                        reviewSection(
                            title: "Suggestions you rejected",
                            systemImage: "xmark.circle",
                            facts: understanding.rejectedFacts
                        )
                    }

                    if !understanding.unknowns.isEmpty {
                        Divider()
                        Label("Still unknown", systemImage: "questionmark.circle")
                            .font(.headline)
                        ForEach(understanding.unknowns) { unknown in
                            Text(unknown.prompt)
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Edit outcome") {
                    flow.goTo(.outcome)
                }
                Button("Edit reality") {
                    flow.goTo(.currentReality)
                }
                Button("Edit commitment") {
                    flow.goTo(.commitment)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
        }
    }

    private func hypothesisReviewSection(_ facts: [CareerFactRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label("Needs your confirmation", systemImage: "sparkles")
                .font(.headline)
            Text("Confirm only what is true. Correct the wording or reject the suggestion before approval.")
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 8) {
                    Text(fact.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                    Text(fact.value)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(
                        "Correct this suggestion",
                        text: Binding(
                            get: { hypothesisEdits[fact.id] ?? fact.value },
                            set: { hypothesisEdits[fact.id] = $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Edited value for \(fact.kind.title)")

                    HStack(spacing: 12) {
                        Button("Confirm") {
                            resolveHypothesis(fact, action: .confirm)
                        }
                        Button("Use edit") {
                            resolveHypothesis(fact, action: .edit)
                        }
                        Button("Reject", role: .destructive) {
                            resolveHypothesis(fact, action: .reject)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func reviewSection(
        title: String,
        systemImage: String,
        facts: [CareerFactRecord]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label(title, systemImage: systemImage)
                .font(.headline)
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                    Text(fact.value)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func onboardingPrompt(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choiceButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.openLARPBlue.opacity(0.14) : Color.openLARPBackground)
            .foregroundStyle(isSelected ? Color.openLARPBlue : Color.openLARPInk)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.openLARPBlue : Color.openLARPSoftInk.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var canUsePrimaryAction: Bool {
        switch flow.step {
        case .outcome:
            !draft.targetOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .currentReality:
            !draft.timeline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .commitment:
            true
        case .review:
            reviewUnderstanding?.pendingHypotheses.isEmpty == true
        }
    }

    private var stepSubtitle: String {
        switch flow.step {
        case .outcome: "Start with one honest target. This should feel like getting help, not filling out paperwork."
        case .currentReality: "OpenLARP separates what you know from what is still missing."
        case .commitment: "Your plan will respect the limits you name here."
        case .review: "Nothing becomes durable until you approve this understanding."
        }
    }

    private var primaryActionSystemImage: String {
        flow.step == .review ? "checkmark.seal.fill" : "arrow.right.circle.fill"
    }

    private var previousStepTitle: String {
        CareerOnboardingStep(rawValue: max(0, flow.step.rawValue - 1))?.title ?? "previous step"
    }

    private func performPrimaryAction() {
        validationMessage = nil
        if flow.step == .review {
            guard let reviewUnderstanding else {
                validationMessage = "Return to the previous step and review the current answers again."
                return
            }
            let goal = draft.makeGoal()
            let expectedOwnerScope = ownerScope
            Task {
                let succeeded = await store.approveCareerUnderstanding(
                    reviewUnderstanding,
                    goal: goal,
                    expectedOwnerScope: expectedOwnerScope
                )
                if succeeded, let content = CookedDiagnosticResultContent(state: store.state) {
                    onGoalConfirmed(content)
                } else if validationMessage == nil {
                    validationMessage = store.errorMessage ?? "OpenLARP could not save this understanding yet. Your answers remain available to review."
                }
            }
            return
        }

        do {
            try flow.advance(using: draft)
            if flow.step == .review {
                reviewUnderstanding = draft.makeUnderstanding(reviewedAt: Date())
                store.recordCareerUnderstandingReviewed()
            }
        } catch CareerOnboardingFlowError.targetOutcomeRequired {
            validationMessage = "Name the job, internship, promotion, or career outcome you want."
        } catch CareerOnboardingFlowError.timelineRequired {
            validationMessage = "Add a timeline so OpenLARP can size the first sprint honestly."
        } catch {
            validationMessage = "Review the current step before moving on."
        }
    }

    private enum HypothesisAction {
        case confirm
        case edit
        case reject
    }

    private func resolveHypothesis(_ fact: CareerFactRecord, action: HypothesisAction) {
        guard var understanding = reviewUnderstanding else { return }
        do {
            switch action {
            case .confirm:
                try understanding.confirmHypothesis(id: fact.id, at: Date())
            case .edit:
                try understanding.editAndConfirmFact(
                    id: fact.id,
                    value: hypothesisEdits[fact.id] ?? fact.value,
                    at: Date()
                )
            case .reject:
                try understanding.rejectFact(id: fact.id, at: Date())
            }
            hypothesisEdits.removeValue(forKey: fact.id)
            reviewUnderstanding = understanding
            validationMessage = nil
        } catch {
            validationMessage = "Use a specific, non-empty correction or choose reject."
        }
    }

    private func resetDraftForCurrentOwner() {
        ownerScope = store.onboardingOwnerScope
        draft = .empty
        flow = CareerOnboardingFlow()
        reviewUnderstanding = nil
        validationMessage = nil
        didChooseLocalEntry = false
        hypothesisEdits = [:]
        focusedField = nil
    }
}
