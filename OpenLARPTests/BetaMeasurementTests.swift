import Foundation
import XCTest
@testable import OpenLARP

@MainActor
final class BetaMeasurementTests: XCTestCase {
    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let privateGoal = CareerGoal(
        currentStatus: .student,
        targetRole: "AI product internship",
        timeline: "30 days",
        background: "Private background with langqi@example.com, visa concern, and campus office.",
        existingProof: "Secret Project Falcon, private repo, and https://private.example.com/proof.",
        confidence: 2,
        biggestBlocker: "Confidential blocker with family money stress."
    )

    func testStoreRecordsCoreBetaEventsAndPersistsThem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let timestamp = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { timestamp },
            calendar: testCalendar
        )

        await store.confirmGoal(privateGoal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I mapped repeated AI product internship requirements, built a small role-fit rubric, and saved a reusable artifact for my search.",
            link: "https://example.com/ai-product-rubric"
        )
        store.claimPendingQualityResult()
        store.recordCookedCardPrepared()
        store.logOutcome(
            kind: .interview,
            title: "Recruiter screen scheduled",
            organizationName: "Example Labs",
            note: "Private recruiter note should never be exported.",
            occurredAt: timestamp
        )
        await store.prepareCareerGraphSyncPreview()

        let eventKinds = store.state.betaEvents.map(\.kind)

        XCTAssertEqual(eventKinds.prefix(4), [.goalConfirmed, .diagnosticShown, .freeSprintStarted, .firstQuestStarted])
        XCTAssertTrue(eventKinds.contains(.proofSubmitted))
        XCTAssertTrue(eventKinds.contains(.proofAccepted))
        XCTAssertTrue(eventKinds.contains(.xpClaimed))
        XCTAssertTrue(eventKinds.contains(.cookedCardPrepared))
        XCTAssertTrue(eventKinds.contains(.outcomeLogged))
        XCTAssertTrue(eventKinds.contains(.syncPreviewPrepared))

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.betaEvents.map(\.kind), eventKinds)
        XCTAssertEqual(reloaded.betaEvents.first?.occurredAt, timestamp)
    }

    func testNextDayReturnEventIsRecordedAfterDailyRefreshUnlocksQuest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayOne = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let dayTwo = localDate(year: 2026, month: 6, day: 2, hour: 9)
        var currentDate = dayOne
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { currentDate },
            calendar: testCalendar
        )

        await store.confirmGoal(privateGoal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I created a requirement map, matched it to my portfolio gaps, and saved a reusable proof artifact for applications.",
            link: "https://example.com/requirement-map"
        )
        store.claimPendingQualityResult()

        currentDate = dayTwo
        store.refreshDailyAvailability()

        XCTAssertTrue(store.state.betaEvents.map(\.kind).contains(.nextDayReturn))
        XCTAssertEqual(store.state.betaEvents.filter { $0.kind == .nextDayReturn }.count, 1)

        store.refreshDailyAvailability()

        XCTAssertEqual(store.state.betaEvents.filter { $0.kind == .nextDayReturn }.count, 1)
    }

    func testLateReturnDoesNotRecordNextDayReturn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayOne = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let dayFour = localDate(year: 2026, month: 6, day: 4, hour: 9)
        var currentDate = dayOne
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { currentDate },
            calendar: testCalendar
        )

        await store.confirmGoal(privateGoal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I created a requirement map, matched it to my portfolio gaps, and saved a reusable proof artifact for applications.",
            link: "https://example.com/requirement-map"
        )
        store.claimPendingQualityResult()

        currentDate = dayFour
        store.refreshDailyAvailability()

        XCTAssertFalse(store.state.betaEvents.map(\.kind).contains(.nextDayReturn))
        XCTAssertEqual(store.state.missedDayRecovery.missedDayCount, 2)
    }

    func testMeasurementOnlyEventDoesNotRewriteMainStateTimestamp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let goalSetupTime = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let preparedTime = localDate(year: 2026, month: 6, day: 1, hour: 12)
        var currentDate = goalSetupTime
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { currentDate },
            calendar: testCalendar
        )
        await store.confirmGoal(privateGoal)
        let stateUpdatedAt = store.state.updatedAt

        currentDate = preparedTime
        store.recordCookedCardPrepared()

        XCTAssertEqual(store.state.updatedAt, stateUpdatedAt)
        XCTAssertEqual(store.state.betaEvents.last?.occurredAt, preparedTime)
    }

    func testBetaSummaryExportContainsOnlyAggregatedSafeData() throws {
        var state = OpenLARPEngine.confirmGoal(privateGoal, now: localDate(year: 2026, month: 6, day: 1, hour: 9))
        state.progress.recentProof = [privateProof()]
        state.progress.proofCount = 1
        state.progress.completedQuestCount = 1
        state.outcomeLog = [
            CareerOutcomeRecord(
                kind: .interview,
                title: "Private recruiter screen",
                organizationName: "Example Labs",
                note: "Sensitive recruiter note should stay private.",
                occurredAt: localDate(year: 2026, month: 6, day: 2, hour: 10),
                targetRoleTitle: privateGoal.targetRole,
                isPrivate: true
            )
        ]
        state.betaEvents = [
            BetaEventRecord(kind: .goalConfirmed, occurredAt: localDate(year: 2026, month: 6, day: 1, hour: 9)),
            BetaEventRecord(kind: .firstQuestStarted, occurredAt: localDate(year: 2026, month: 6, day: 1, hour: 9), day: 1),
            BetaEventRecord(kind: .proofSubmitted, occurredAt: localDate(year: 2026, month: 6, day: 1, hour: 10), day: 1),
            BetaEventRecord(kind: .proofAccepted, occurredAt: localDate(year: 2026, month: 6, day: 1, hour: 10), day: 1),
            BetaEventRecord(kind: .cookedCardPrepared, occurredAt: localDate(year: 2026, month: 6, day: 1, hour: 11)),
            BetaEventRecord(kind: .outcomeLogged, occurredAt: localDate(year: 2026, month: 6, day: 2, hour: 10))
        ]

        let content = BetaMeasurementSummaryContent(state: state)
        let exportedText = content.searchableText
        let exportedJSON = try String(
            decoding: JSONEncoder.openLARPBetaExport.encode(content),
            as: UTF8.self
        )

        XCTAssertEqual(content.totalEvents, 6)
        XCTAssertTrue(exportedText.contains("Proof submitted: 1"))
        XCTAssertTrue(exportedText.contains("Proof accepted: 1"))
        XCTAssertTrue(exportedText.contains("Private proof text, links, attachment paths, local file paths, and private notes are not included."))
        XCTAssertFalse(exportedText.contains("langqi@example.com"))
        XCTAssertFalse(exportedText.contains("visa"))
        XCTAssertFalse(exportedText.contains("Secret Project Falcon"))
        XCTAssertFalse(exportedText.contains("private.example.com"))
        XCTAssertFalse(exportedText.contains("Sensitive recruiter note"))
        XCTAssertFalse(exportedText.contains("ProofAttachments"))
        XCTAssertFalse(exportedText.contains("sk-test-secret"))
        XCTAssertFalse(exportedJSON.contains("langqi@example.com"))
        XCTAssertFalse(exportedJSON.contains("Secret Project Falcon"))
        XCTAssertFalse(exportedJSON.contains("Sensitive recruiter note"))
        XCTAssertFalse(exportedJSON.contains("ProofAttachments"))
    }

    func testBetaSummaryExportIncludesAIWorkflowAggregatesWithoutPrivateData() throws {
        var state = OpenLARPEngine.confirmGoal(privateGoal, now: localDate(year: 2026, month: 6, day: 1, hour: 9))
        state.aiWorkflowRuns = [
            AIWorkflowAuditRecord(
                kind: .cookedDiagnostic,
                providerRoute: .firebaseCallableGenkit,
                requestedAt: localDate(year: 2026, month: 6, day: 1, hour: 9),
                completedAt: localDate(year: 2026, month: 6, day: 1, hour: 9),
                usedFallback: false
            ),
            AIWorkflowAuditRecord(
                kind: .proofQualityCheck,
                providerRoute: .localMock,
                requestedAt: localDate(year: 2026, month: 6, day: 1, hour: 10),
                completedAt: localDate(year: 2026, month: 6, day: 1, hour: 10),
                usedFallback: true,
                failureSummary: "Primary workflow failed; local fallback handled this run."
            )
        ]
        state.progress.recentProof = [privateProof()]
        state.progress.proofCount = 1

        let content = BetaMeasurementSummaryContent(state: state)
        let exportedText = content.searchableText
        let exportedJSON = try String(
            decoding: JSONEncoder.openLARPBetaExport.encode(content),
            as: UTF8.self
        )

        XCTAssertEqual(content.aiWorkflowRunCount, 2)
        XCTAssertEqual(content.aiWorkflowFallbackCount, 1)
        XCTAssertEqual(content.aiWorkflowKindCounts, [
            AIWorkflowRunCount(kind: .cookedDiagnostic, count: 1),
            AIWorkflowRunCount(kind: .proofQualityCheck, count: 1)
        ])
        XCTAssertEqual(content.aiWorkflowProviderCounts, [
            AIWorkflowProviderCount(providerRoute: .localMock, count: 1),
            AIWorkflowProviderCount(providerRoute: .firebaseCallableGenkit, count: 1)
        ])
        XCTAssertTrue(exportedText.contains("AI workflow runs: 2"))
        XCTAssertTrue(exportedText.contains("AI fallbacks: 1"))
        XCTAssertTrue(exportedText.contains("cookedDiagnostic: 1"))
        XCTAssertTrue(exportedText.contains("firebaseCallableGenkit: 1"))
        XCTAssertFalse(exportedText.contains("langqi@example.com"))
        XCTAssertFalse(exportedText.contains("Secret Project Falcon"))
        XCTAssertFalse(exportedText.contains("private.example.com"))
        XCTAssertFalse(exportedText.contains("sk-test-secret"))
        XCTAssertFalse(exportedText.contains("ProofAttachments"))
        XCTAssertFalse(exportedJSON.contains("langqi@example.com"))
        XCTAssertFalse(exportedJSON.contains("Secret Project Falcon"))
        XCTAssertFalse(exportedJSON.contains("private.example.com"))
        XCTAssertFalse(exportedJSON.contains("sk-test-secret"))
        XCTAssertFalse(exportedJSON.contains("ProofAttachments"))
    }

    func testLegacyStateWithoutBetaEventsDecodesWithEmptyLog() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = OpenLARPEngine.confirmGoal(privateGoal, now: localDate(year: 2026, month: 6, day: 1, hour: 9))
        let encoded = try encoder.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "betaEvents")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.betaEvents, [])
    }

    func testMalformedBetaEventsAreDroppedWithoutLosingState() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = OpenLARPEngine.confirmGoal(privateGoal, now: localDate(year: 2026, month: 6, day: 1, hour: 9))
        let encoded = try encoder.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["betaEvents"] = [
            [
                "kind": "goalConfirmed",
                "occurredAt": "2026-06-01T09:00:00Z",
                "day": 1
            ],
            [
                "kind": "futureEventKind",
                "occurredAt": "2026-06-01T10:00:00Z",
                "day": 1
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OpenLARPState.self, from: data)

        XCTAssertEqual(decoded.goal, original.goal)
        XCTAssertEqual(decoded.betaEvents, [
            BetaEventRecord(
                kind: .goalConfirmed,
                occurredAt: localDate(year: 2026, month: 6, day: 1, hour: 9),
                day: 1
            )
        ])
    }

    func testResetGoalPreservesBetaEventLog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { self.localDate(year: 2026, month: 6, day: 1, hour: 9) },
            calendar: testCalendar
        )

        await store.confirmGoal(privateGoal)
        store.startCurrentQuest()
        let beforeReset = store.state.betaEvents

        store.resetGoal()

        XCTAssertTrue(store.state.needsGoalSetup)
        XCTAssertEqual(store.state.betaEvents, beforeReset)
    }

    func testPaywallViewedEventDoesNotRewriteMainStateTimestamp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let goalSetupTime = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let paywallTime = localDate(year: 2026, month: 6, day: 2, hour: 11)
        var currentDate = goalSetupTime
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { currentDate },
            calendar: testCalendar
        )
        await store.confirmGoal(privateGoal)
        let stateUpdatedAt = store.state.updatedAt

        currentDate = paywallTime
        store.recordSubscriptionPaywallViewed()

        XCTAssertEqual(store.state.updatedAt, stateUpdatedAt)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .subscriptionPaywallViewed)
        XCTAssertEqual(store.state.betaEvents.last?.occurredAt, paywallTime)
    }

    private func privateProof() -> ProofRecord {
        let now = localDate(year: 2026, month: 6, day: 1, hour: 10)
        let attachment = ProofAttachment(
            id: UUID(uuidString: "F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1")!,
            fileName: "local-private-proof.png",
            originalFileName: "private-screenshot.png",
            contentType: "image/png",
            byteCount: 40_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        return ProofRecord(
            id: UUID(uuidString: "F2F2F2F2-F2F2-F2F2-F2F2-F2F2F2F2F2F2")!,
            questID: UUID(uuidString: "F3F3F3F3-F3F3-F3F3-F3F3-F3F3F3F3F3F3")!,
            questTitle: "Private proof quest",
            kind: .proof,
            text: "Sensitive proof text with sk-test-secret and internal recruiter notes.",
            link: "https://private.example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Concrete enough to count.",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
    }

    private func localDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        testCalendar.date(from: DateComponents(
            timeZone: testCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
