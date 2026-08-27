import SwiftUI

struct GuidedCareerOnboardingView: View {
    private enum FocusedField: Hashable {
        case targetOutcome
        case timeline
        case experience
        case existingProof
        case constraints
        case biggestBlocker
        case adaptiveAnswer
    }

    let store: OpenLARPStore
    let onGoalConfirmed: (CookedDiagnosticResultContent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft = CareerIntakeDraft.empty
    @State private var flow = CareerOnboardingFlow()
    @State private var reviewUnderstanding: CareerUnderstanding?
    @State private var validationMessage: String?
    @State private var didChooseLocalEntry = false
    @State private var ownerScope = ""
    @State private var hypothesisEdits: [UUID: String] = [:]
    @State private var adaptiveQuestion: V0AdaptiveCareerQuestion?
    @State private var adaptiveAnswer = ""
    @State private var didFinishAdaptiveRequest = false
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
                if store.isAdaptiveIntakeRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Finding One Useful Follow-up")
                    }
                } else if store.isGoalSetupRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Building Your Readiness Check")
                    }
                } else {
                    Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canUsePrimaryAction || isOnboardingWorkRunning)
            .accessibilityIdentifier("onboarding.primaryAction")

            if flow.step != .outcome {
                Button {
                    validationMessage = nil
                    flow.goBack()
                } label: {
                    Label("Back to \(previousStepTitle)", systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isOnboardingWorkRunning)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: flow.step)
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

                LazyVGrid(columns: choiceColumns(minimumWidth: 130), spacing: 10) {
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
                        .accessibilityIdentifier("onboarding.targetOutcome")
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
                    LazyVGrid(columns: choiceColumns(minimumWidth: 100), spacing: 8) {
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
        let displayedUnknowns = understanding.unknowns.filter {
            $0.kind != adaptiveQuestion?.factKind
        }
        return VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    onboardingPrompt(
                        "Approve the facts, not a flattering guess",
                        detail: reviewPromptDetail
                    )

                    if let adaptiveQuestion {
                        adaptiveQuestionSection(adaptiveQuestion)
                    }

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

                    if !displayedUnknowns.isEmpty {
                        Divider()
                        Label("Still unknown", systemImage: "questionmark.circle")
                            .font(.headline)
                        ForEach(displayedUnknowns) { unknown in
                            Text(unknown.prompt)
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                        }
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    reviewEditButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    reviewEditButtons
                }
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .disabled(isOnboardingWorkRunning)
        }
    }

    private func adaptiveQuestionSection(_ question: V0AdaptiveCareerQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label("One detail would improve your first quest", systemImage: "questionmark.bubble.fill")
                .font(.headline)
            Text(question.question)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(question.rationale)
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)

            if !question.options.isEmpty {
                LazyVGrid(columns: choiceColumns(minimumWidth: 120), spacing: 8) {
                    ForEach(question.options, id: \.self) { option in
                        choiceButton(
                            title: option,
                            isSelected: adaptiveAnswer == option
                        ) {
                            adaptiveAnswer = option
                        }
                    }
                }
            }

            TextField("Answer only if you know", text: $adaptiveAnswer, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .adaptiveAnswer)
                .accessibilityLabel(question.question)
                .accessibilityHint("Leave this blank and choose keep unknown if you are not sure.")

            Button("Keep this unknown") {
                adaptiveQuestion = nil
                adaptiveAnswer = ""
                validationMessage = nil
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .accessibilityLabel("Keep \(question.factKind.title) unknown")
            .accessibilityIdentifier("onboarding.keepUnknown")
        }
    }

    private func hypothesisReviewSection(_ facts: [CareerFactRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label("AI suggestion — needs your confirmation", systemImage: "sparkles")
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

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            hypothesisActionButtons(for: fact)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            hypothesisActionButtons(for: fact)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var reviewEditButtons: some View {
        Button("Edit outcome") {
            returnToEditing(.outcome)
        }
        Button("Edit reality") {
            returnToEditing(.currentReality)
        }
        Button("Edit commitment") {
            returnToEditing(.commitment)
        }
    }

    @ViewBuilder
    private func hypothesisActionButtons(for fact: CareerFactRecord) -> some View {
        Button("Confirm") {
            resolveHypothesis(fact, action: .confirm)
        }
        .accessibilityLabel("Confirm \(fact.kind.title) AI suggestion")
        Button("Use edit") {
            resolveHypothesis(fact, action: .edit)
        }
        .accessibilityLabel("Use edited \(fact.kind.title) AI suggestion")
        Button("Reject", role: .destructive) {
            resolveHypothesis(fact, action: .reject)
        }
        .accessibilityLabel("Reject \(fact.kind.title) AI suggestion")
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
                    .imageScale(.medium)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("onboarding.scalableChoiceLabel")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.openLARPBlue.opacity(0.14) : Color.openLARPBackground)
            .foregroundStyle(isSelected ? Color.openLARPBlueDark : Color.openLARPInk)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.openLARPBlueDark : Color.openLARPSoftInk.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choiceColumns(minimumWidth: CGFloat) -> [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: minimumWidth))]
    }

    private var canUsePrimaryAction: Bool {
        switch flow.step {
        case .outcome:
            return !draft.targetOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .currentReality:
            return !draft.timeline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .commitment:
            return true
        case .review:
            if adaptiveQuestion != nil {
                return !adaptiveAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !didFinishAdaptiveRequest {
                return reviewUnderstanding != nil
            }
            return reviewUnderstanding?.pendingHypotheses.isEmpty == true
        }
    }

    private var primaryActionTitle: String {
        guard flow.step == .review else { return flow.step.primaryActionTitle }
        if adaptiveQuestion != nil {
            return "Use This Answer"
        }
        if !didFinishAdaptiveRequest {
            return "Confirm Facts & Personalize My Check"
        }
        return flow.step.primaryActionTitle
    }

    private var isOnboardingWorkRunning: Bool {
        store.isAdaptiveIntakeRunning || store.isGoalSetupRunning
    }

    private var stepSubtitle: String {
        switch flow.step {
        case .outcome: "Start with one honest target. This should feel like getting help, not filling out paperwork."
        case .currentReality: "OpenLARP separates what you know from what is still missing."
        case .commitment: "Your plan will respect the limits you name here."
        case .review: "Nothing becomes durable until you approve this understanding."
        }
    }

    private var reviewPromptDetail: String {
        if adaptiveQuestion != nil {
            return "Answer only if you know. You can keep this detail unknown, and no AI suggestion becomes fact without your decision."
        }
        if didFinishAdaptiveRequest {
            return "Only the facts and suggestions you explicitly accepted will shape your readiness check."
        }
        return "Confirm what you entered first. OpenLARP may ask one useful follow-up, and every AI suggestion stays separate until you decide."
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
            if let adaptiveQuestion {
                applyAdaptiveAnswer(to: adaptiveQuestion)
                return
            }
            if !didFinishAdaptiveRequest {
                requestAdaptiveIntake()
                return
            }
            approveCurrentUnderstanding()
            return
        }

        do {
            try flow.advance(using: draft)
            if flow.step == .review {
                let reviewedAt = Date()
                reviewUnderstanding = reviewUnderstanding?.rebuildingReview(
                    using: draft,
                    reviewedAt: reviewedAt
                ) ?? draft.makeUnderstanding(reviewedAt: reviewedAt)
                adaptiveQuestion = nil
                adaptiveAnswer = ""
                didFinishAdaptiveRequest = false
                hypothesisEdits = [:]
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

    private func requestAdaptiveIntake() {
        guard var understanding = reviewUnderstanding else {
            validationMessage = "Return to the previous step and review the current answers again."
            return
        }
        do {
            try understanding.confirmUserEntriesForAdaptiveIntake(at: Date())
            reviewUnderstanding = understanding
        } catch {
            validationMessage = "Review the facts again before OpenLARP asks a follow-up."
            return
        }

        let expectedOwnerScope = ownerScope
        Task {
            do {
                let response = try await store.generateAdaptiveCareerIntake(
                    for: understanding,
                    expectedOwnerScope: expectedOwnerScope
                )
                guard flow.step == .review,
                      expectedOwnerScope == ownerScope,
                      var updatedUnderstanding = reviewUnderstanding else { return }
                try updatedUnderstanding.addAdaptiveHypotheses(from: response, at: Date())
                reviewUnderstanding = updatedUnderstanding
                adaptiveQuestion = response.questions.first
                adaptiveAnswer = ""
                didFinishAdaptiveRequest = true
                validationMessage = nil

                if adaptiveQuestion == nil && updatedUnderstanding.pendingHypotheses.isEmpty {
                    await approveUnderstanding(updatedUnderstanding, expectedOwnerScope: expectedOwnerScope)
                }
            } catch {
                guard expectedOwnerScope == ownerScope else { return }
                didFinishAdaptiveRequest = true
                validationMessage = "OpenLARP could not load a personalized follow-up. Your confirmed answers are still ready for an honest local readiness check."
            }
        }
    }

    private func applyAdaptiveAnswer(to question: V0AdaptiveCareerQuestion) {
        guard var understanding = reviewUnderstanding else { return }
        var updatedDraft = draft
        let supersededHypothesisIDs = Set(understanding.pendingHypotheses
            .filter { $0.kind == question.factKind }
            .map(\.id))
        do {
            try updatedDraft.applyAdaptiveAnswer(adaptiveAnswer, for: question.factKind)
            try understanding.answerAdaptiveQuestion(
                question,
                answer: adaptiveAnswer,
                at: Date()
            )
            draft = updatedDraft
            reviewUnderstanding = understanding
            for id in supersededHypothesisIDs {
                hypothesisEdits.removeValue(forKey: id)
            }
            adaptiveQuestion = nil
            adaptiveAnswer = ""
            focusedField = nil
            validationMessage = nil
        } catch {
            validationMessage = "Use a specific answer, or keep this detail unknown."
        }
    }

    private func approveCurrentUnderstanding() {
        guard let reviewUnderstanding else {
            validationMessage = "Return to the previous step and review the current answers again."
            return
        }
        let expectedOwnerScope = ownerScope
        Task {
            await approveUnderstanding(reviewUnderstanding, expectedOwnerScope: expectedOwnerScope)
        }
    }

    private func approveUnderstanding(
        _ understanding: CareerUnderstanding,
        expectedOwnerScope: String
    ) async {
        let goal = draft.makeGoal()
        let succeeded = await store.approveCareerUnderstanding(
            understanding,
            goal: goal,
            expectedOwnerScope: expectedOwnerScope
        )
        if succeeded, let content = CookedDiagnosticResultContent(state: store.state) {
            onGoalConfirmed(content)
        } else if validationMessage == nil {
            validationMessage = store.errorMessage ?? "OpenLARP could not save this understanding yet. Your answers remain available to review."
        }
    }

    private func returnToEditing(_ step: CareerOnboardingStep) {
        flow.goTo(step)
        adaptiveQuestion = nil
        adaptiveAnswer = ""
        didFinishAdaptiveRequest = false
        hypothesisEdits = [:]
        validationMessage = nil
    }

    private enum HypothesisAction: Equatable {
        case confirm
        case edit
        case reject
    }

    private func resolveHypothesis(_ fact: CareerFactRecord, action: HypothesisAction) {
        guard var understanding = reviewUnderstanding else { return }
        var updatedDraft = draft
        do {
            switch action {
            case .confirm:
                try updatedDraft.applyAdaptiveAnswer(fact.value, for: fact.kind)
                try understanding.confirmHypothesis(id: fact.id, at: Date())
            case .edit:
                let editedValue = hypothesisEdits[fact.id] ?? fact.value
                try updatedDraft.applyAdaptiveAnswer(editedValue, for: fact.kind)
                try understanding.editAndConfirmFact(
                    id: fact.id,
                    value: editedValue,
                    at: Date()
                )
            case .reject:
                try understanding.rejectFact(id: fact.id, at: Date())
            }
            hypothesisEdits.removeValue(forKey: fact.id)
            if action != .reject, adaptiveQuestion?.factKind == fact.kind {
                adaptiveQuestion = nil
                adaptiveAnswer = ""
                focusedField = nil
            }
            draft = updatedDraft
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
        adaptiveQuestion = nil
        adaptiveAnswer = ""
        didFinishAdaptiveRequest = false
        focusedField = nil
    }
}
