import SwiftUI

typealias OutcomeLogSaveAction = (CareerOutcomeKind, String, String, String, Date, Bool) -> Void
typealias OutcomeLogUpdateAction = (UUID, CareerOutcomeKind, String, String, String, Date, Bool) -> Void
typealias OutcomeLogDeleteAction = (UUID) -> Void

enum OutcomeLogAvailability {
    case available
    case readOnly(String)
}

enum OutcomeSheetDestination: Identifiable {
    case log
    case detail(CareerOutcomeRecord)
    case edit(CareerOutcomeRecord)

    var id: String {
        switch self {
        case .log:
            "log"
        case .detail(let outcome):
            "detail-\(outcome.id.uuidString)"
        case .edit(let outcome):
            "edit-\(outcome.id.uuidString)"
        }
    }
}

struct ProgressTabView: View {
    let state: OpenLARPState
    let attachmentURL: (ProofAttachment) -> URL
    let improveWeakestArea: () -> Void
    let logOutcome: OutcomeLogSaveAction
    let updateOutcome: OutcomeLogUpdateAction
    let deleteOutcome: OutcomeLogDeleteAction
    @State private var selectedProof: ProofRecord?
    @State private var showingProofArchive = false
    @State private var outcomeSheetDestination: OutcomeSheetDestination?

    init(
        state: OpenLARPState,
        attachmentURL: @escaping (ProofAttachment) -> URL,
        improveWeakestArea: @escaping () -> Void,
        logOutcome: @escaping OutcomeLogSaveAction = { _, _, _, _, _, _ in },
        updateOutcome: @escaping OutcomeLogUpdateAction = { _, _, _, _, _, _, _ in },
        deleteOutcome: @escaping OutcomeLogDeleteAction = { _ in }
    ) {
        self.state = state
        self.attachmentURL = attachmentURL
        self.improveWeakestArea = improveWeakestArea
        self.logOutcome = logOutcome
        self.updateOutcome = updateOutcome
        self.deleteOutcome = deleteOutcome
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .stats,
                    eyebrow: "Stats",
                    title: "Less cooked",
                    subtitle: "The serious layer under the joke: proof, consistency, and readiness.",
                    stat: "\(state.progress.readiness.overall)%"
                )

                if state.needsGoalSetup {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No baseline yet")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                            Text("Set a goal and run the diagnostic to create the first readiness baseline.")
                                .font(.body)
                                .foregroundStyle(Color.openLARPSoftInk)
                            Button("Set Goal", action: improveWeakestArea)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                } else {
                    readinessCard
                    readinessHistoryCard
                    xpCard
                    outcomeLogCard
                    proofCard
                    badgeCard
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProof) { proof in
            ProofDetailView(proof: proof, attachmentURL: attachmentURL)
        }
        .sheet(isPresented: $showingProofArchive) {
            ProofArchiveView(
                proofs: state.progress.recentProof,
                attachmentURL: attachmentURL
            )
        }
        .sheet(item: $outcomeSheetDestination) { destination in
            outcomeSheet(for: destination)
        }
    }

    @ViewBuilder
    private func outcomeSheet(for destination: OutcomeSheetDestination) -> some View {
        switch destination {
        case .log:
            OutcomeLogSheet(save: logOutcome)
        case .detail(let outcome):
            OutcomeDetailView(
                outcome: outcome,
                isEditable: !state.needsGoalSetup,
                edit: {
                    outcomeSheetDestination = .edit(outcome)
                },
                delete: {
                    deleteOutcome(outcome.id)
                }
            )
        case .edit(let outcome):
            OutcomeLogSheet(outcome: outcome) { kind, title, organizationName, note, occurredAt, isPrivate in
                updateOutcome(
                    outcome.id,
                    kind,
                    title,
                    organizationName,
                    note,
                    occurredAt,
                    isPrivate
                )
            }
        }
    }

    private var readinessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .stats, eyebrow: "Signal radar", title: "Goal readiness")

                HStack(alignment: .center, spacing: 14) {
                    ReadinessRings(value: state.progress.readiness.overall)

                    VStack(spacing: 8) {
                        SummaryTile(value: label(for: state.progress.readiness.proofStrength), label: "Proof", color: .openLARPCoral)
                        SummaryTile(value: label(for: state.progress.readiness.confidence), label: "Confidence", color: .openLARPYellow)
                        SummaryTile(value: label(for: state.progress.readiness.consistency), label: "Consistency", color: .openLARPGreen)
                    }
                    .frame(maxWidth: 142)
                }

                ReadinessRow(title: "Proof strength", value: state.progress.readiness.proofStrength, color: .openLARPCoral)
                ReadinessRow(title: "Skill proof", value: state.progress.readiness.skillProof, color: .openLARPBlue)
                ReadinessRow(title: "Network strength", value: state.progress.readiness.networkStrength, color: .openLARPPurple)
                ReadinessRow(title: "Confidence", value: state.progress.readiness.confidence, color: .openLARPYellow)
                ReadinessRow(title: "Consistency", value: state.progress.readiness.consistency, color: .openLARPGreen)

                Button {
                    improveWeakestArea()
                } label: {
                    Label("Improve Weakest Area", systemImage: "target")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var readinessHistoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .stats, eyebrow: "History", title: "Readiness timeline")

                if state.progress.readinessHistory.isEmpty {
                    Text("The first readiness baseline appears after goal setup. Proof claims add snapshots over time.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(state.progress.readinessHistory.reversed()) { snapshot in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(snapshot.overall)")
                                .font(.headline.weight(.black))
                                .foregroundStyle(Color.openLARPBlue)
                                .frame(width: 44, height: 36)
                                .background(Color.openLARPBlue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(snapshot.reason)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.openLARPInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("\(label(for: snapshot.proofStrength)) proof, \(label(for: snapshot.skillProof)) skill proof, \(label(for: snapshot.networkStrength)) network")
                                    .font(.caption)
                                    .foregroundStyle(Color.openLARPSoftInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color.openLARPBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func label(for value: Int) -> String {
        switch value {
        case ..<35: "Weak"
        case 35..<55: "Building"
        case 55..<75: "Credible"
        default: "Strong"
        }
    }

    private var xpCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .quest, eyebrow: "Sprint momentum", title: "Sprint XP")

                ProgressView(value: Double(state.progress.xp), total: Double(state.progress.xpGoal))
                    .tint(.openLARPGreen)

                HStack(spacing: 8) {
                    SummaryTile(value: "\(state.progress.completedQuestCount)", label: "Quests", color: .openLARPPurple)
                    SummaryTile(value: "\(state.progress.proofCount)", label: "Proof", color: .openLARPGreen)
                    SummaryTile(value: "\(state.progress.streakCount)", label: "Streak", color: .openLARPCoral)
                }

                if let recovery = MissedDayRecoveryContent(state: state) {
                    Label("\(recovery.previousStreakText). Active streak reset after \(recovery.missedDaysText.lowercased())", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let skipped = SkippedTodayContent(state: state) {
                    Label("\(skipped.previousStreakText). \(skipped.unlockMessage)", systemImage: "forward.end")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Evidence bank", title: "Recent proof")

                Button {
                    showingProofArchive = true
                } label: {
                    Label("All proof receipts", systemImage: "archivebox")
                }
                .buttonStyle(SecondaryButtonStyle())

                if state.progress.recentProof.isEmpty {
                    Text("No proof yet. Today’s quest is where the first receipt comes from.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(state.progress.recentProof.prefix(4)) { proof in
                        Button {
                            selectedProof = proof
                        } label: {
                            ProofReceiptRow(
                                proof: proof,
                                attachmentURL: attachmentURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var outcomeLogCard: some View {
        OutcomeLogCard(
            content: OutcomeLogContent(outcomes: state.outcomeLog),
            feature: .stats,
            eyebrow: "Career history",
            title: "Outcome log",
            recentLimit: 3
        ) { outcome in
            outcomeSheetDestination = .detail(outcome)
        } logOutcome: {
            outcomeSheetDestination = .log
        }
    }

    private var badgeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Proof wins", title: "Badges")

                if state.progress.badges.isEmpty {
                    Text("Badges unlock from real progress, not from opening the app.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(state.progress.badges) { badge in
                            Label(badge.rawValue, systemImage: "seal.fill")
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
        }
    }
}

struct OutcomeLogCard: View {
    let content: OutcomeLogContent
    let feature: OpenLARPFeature
    let eyebrow: String
    let title: String
    let recentLimit: Int
    var availability: OutcomeLogAvailability = .available
    let openOutcome: (CareerOutcomeRecord) -> Void
    let logOutcome: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: feature, eyebrow: eyebrow, title: title)

                HStack(spacing: 8) {
                    Pill(title: content.countText, systemImage: "flag.fill", color: .openLARPPurple)

                    if let latestSummary = content.latestSummary {
                        Text(latestSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.openLARPSoftInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                }

                switch availability {
                case .available:
                    Button {
                        logOutcome()
                    } label: {
                        Label("Log Outcome", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                case .readOnly(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if content.outcomes.isEmpty {
                    Text(content.emptyMessage)
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(content.outcomes.prefix(recentLimit)) { outcome in
                        Button {
                            openOutcome(outcome)
                        } label: {
                            OutcomeRecordRow(outcome: outcome)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens outcome details")
                    }
                }
            }
        }
    }
}

struct OutcomeRecordRow: View {
    let outcome: CareerOutcomeRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: outcome.kind.systemImage)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.openLARPPurple)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(outcome.displayTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(outcome.occurredAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .lineLimit(1)
                }

                Text(metadataText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !trimmedNote.isEmpty {
                    Text(trimmedNote)
                        .font(.caption)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(outcome.kind.recoveryPrompt)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPPurple)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPSoftInk)
                .padding(.top, 3)
        }
        .padding(12)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var metadataText: String {
        var parts = [outcome.kind.label]
        if let organizationText = outcome.organizationText {
            parts.append(organizationText)
        }
        parts.append(outcome.isPrivate ? "Private" : "Marked safe to share later")
        return parts.joined(separator: " - ")
    }

    private var trimmedNote: String {
        outcome.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OutcomeLogSheet: View {
    let outcome: CareerOutcomeRecord?
    let save: OutcomeLogSaveAction
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CareerOutcomeKind = .applied
    @State private var title = ""
    @State private var organizationName = ""
    @State private var note = ""
    @State private var occurredAt = Date()
    @State private var isPrivate = true

    init(outcome: CareerOutcomeRecord? = nil, save: @escaping OutcomeLogSaveAction) {
        self.outcome = outcome
        self.save = save
        _kind = State(initialValue: outcome?.kind ?? .applied)
        _title = State(initialValue: outcome?.title ?? "")
        _organizationName = State(initialValue: outcome?.organizationName ?? "")
        _note = State(initialValue: outcome?.note ?? "")
        _occurredAt = State(initialValue: outcome?.occurredAt ?? Date())
        _isPrivate = State(initialValue: outcome?.isPrivate ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(CareerOutcomeKind.allCases) { outcomeKind in
                            Label(outcomeKind.label, systemImage: outcomeKind.systemImage)
                                .tag(outcomeKind)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Outcome title", text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextField("Organization optional", text: $organizationName)
                        .textInputAutocapitalization(.words)

                    TextField("Note optional", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)

                    DatePicker(
                        "Occurred",
                        selection: $occurredAt,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                } header: {
                    Text("Outcome")
                } footer: {
                    Text(kind.recoveryPrompt)
                }

                Section {
                    Toggle(isOn: $isPrivate) {
                        Label("Keep Private", systemImage: "lock.fill")
                    }
                    .tint(.openLARPBlue)
                } footer: {
                    Text("This saves to local career history on this device. It is not uploaded, posted, or shown on a public profile.")
                }
            }
            .navigationTitle(outcome == nil ? "Log Outcome" : "Edit Outcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(
                            kind,
                            title,
                            organizationName,
                            note,
                            occurredAt,
                            isPrivate
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct OutcomeDetailView: View {
    let outcome: CareerOutcomeRecord
    let isEditable: Bool
    let edit: () -> Void
    let delete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    detailsCard
                    noteCard
                    provenanceCard
                    actionCard
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Outcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete outcome?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Outcome", role: .destructive) {
                    delete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the outcome from active history. Past readiness snapshots stay intact.")
            }
        }
    }

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label(outcome.kind.label, systemImage: outcome.kind.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.openLARPPurple)
                    .textCase(.uppercase)

                Text(outcome.displayTitle)
                    .font(.title3.weight(.black))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    OutcomeDetailMetric(
                        title: "Occurred",
                        value: outcome.occurredAt.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                    OutcomeDetailMetric(
                        title: "Privacy",
                        value: outcome.isPrivate ? "Private" : "Share-safe",
                        systemImage: outcome.isPrivate ? "lock.fill" : "checkmark.seal"
                    )
                }
            }
        }
    }

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .stats, eyebrow: "Evidence graph", title: "Career signal")

                OutcomeDetailTextRow(title: "Organization", value: outcome.organizationText ?? "Not linked")
                OutcomeDetailTextRow(title: "Target role", value: outcome.targetRoleTitle)
                OutcomeDetailTextRow(title: "Saved", value: outcome.createdAt.formatted(date: .abbreviated, time: .shortened))

                if outcome.updatedAt > outcome.createdAt {
                    OutcomeDetailTextRow(title: "Last edited", value: outcome.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                Text(outcome.kind.recoveryPrompt)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var noteCard: some View {
        let trimmedNote = outcome.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            Card {
                OutcomeDetailTextBlock(title: "Private note", bodyText: trimmedNote)
            }
        }
    }

    private var provenanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Links", title: "Related evidence")

                OutcomeDetailTextRow(
                    title: "Quest",
                    value: outcome.relatedQuestID?.uuidString.prefix(8).description ?? "Not linked"
                )
                OutcomeDetailTextRow(
                    title: "Proof",
                    value: outcome.relatedProofID?.uuidString.prefix(8).description ?? "Not linked"
                )

                Text("These IDs keep the local record ready for future sync without exposing private proof by default.")
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        if isEditable {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        edit()
                    } label: {
                        Label("Edit Outcome", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Outcome", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        } else {
            Card {
                Label("Saved as private history. Set a new goal before editing or logging more outcomes.", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OutcomeDetailMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OutcomeDetailTextRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OutcomeDetailTextBlock: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.openLARPInk)

            Text(bodyText)
                .font(.body)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReadinessRow: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(label(for: value))
                    .foregroundStyle(color)
            }
            .font(.subheadline.weight(.semibold))

            ProgressView(value: Double(value), total: 100)
                .tint(color)
        }
    }

    private func label(for value: Int) -> String {
        switch value {
        case ..<35: "Weak"
        case 35..<55: "Developing"
        case 55..<75: "Credible"
        default: "Strong"
        }
    }
}
