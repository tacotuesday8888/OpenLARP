import XCTest
@testable import OpenLARP

final class QuestReminderTests: XCTestCase {
    func testDisabledPreferencesNeverProduceReminderRequests() {
        let schedule = QuestReminderPolicy.schedule(
            for: .off,
            hasActiveCareerStep: true
        )

        XCTAssertNil(schedule)
    }

    func testEveryDayScheduleUsesOneGenericPrivacySafeReminder() throws {
        let preferences = QuestReminderPreferences(
            isEnabled: true,
            hour: 19,
            minute: 30,
            cadence: .everyDay
        )

        let schedule = try XCTUnwrap(
            QuestReminderPolicy.schedule(for: preferences, hasActiveCareerStep: true)
        )

        XCTAssertEqual(schedule.requests.count, 1)
        let request = try XCTUnwrap(schedule.requests.first)
        XCTAssertNil(request.weekday)
        XCTAssertEqual(request.hour, 19)
        XCTAssertEqual(request.minute, 30)
        XCTAssertEqual(request.title, "Your career step is ready")
        XCTAssertEqual(request.body, "Open OpenLARP when you’re ready to make one honest step forward.")
        XCTAssertFalse(request.title.localizedCaseInsensitiveContains("iOS"))
        XCTAssertFalse(request.body.localizedCaseInsensitiveContains("job"))
    }

    func testWeekdayScheduleCreatesMondayThroughFridayRequestsOnly() throws {
        let preferences = QuestReminderPreferences(
            isEnabled: true,
            hour: 8,
            minute: 5,
            cadence: .weekdays
        )

        let schedule = try XCTUnwrap(
            QuestReminderPolicy.schedule(for: preferences, hasActiveCareerStep: true)
        )

        XCTAssertEqual(schedule.requests.map(\.weekday), [2, 3, 4, 5, 6])
        XCTAssertEqual(Set(schedule.requests.map(\.identifier)).count, 5)
        XCTAssertTrue(schedule.requests.allSatisfy { $0.hour == 8 && $0.minute == 5 })
    }

    func testNoActiveCareerStepProducesNoSchedule() {
        let preferences = QuestReminderPreferences(
            isEnabled: true,
            hour: 18,
            minute: 0,
            cadence: .everyDay
        )

        XCTAssertNil(
            QuestReminderPolicy.schedule(for: preferences, hasActiveCareerStep: false)
        )
    }

    func testLegacyStateMigratesToRemindersOff() throws {
        let encoder = JSONEncoder.openLARPPersistence
        let decoder = JSONDecoder.openLARPPersistence
        let encoded = try encoder.encode(OpenLARPEngine.confirmGoal(goal))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 14
        object.removeValue(forKey: "questReminders")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try decoder.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, OpenLARPState.currentSchemaVersion)
        XCTAssertEqual(decoded.questReminders, .off)
    }

    @MainActor
    func testEnablingRequestsPermissionInContextSchedulesAndPersists() async throws {
        let directory = temporaryDirectory()
        let persistence = OpenLARPPersistence(directory: directory)
        try persistence.save(OpenLARPEngine.confirmGoal(goal))
        let scheduler = RecordingQuestReminderScheduler(
            authorizationStatus: .notDetermined,
            requestedAuthorizationStatus: .authorized
        )
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            questReminderScheduler: scheduler
        )

        await store.setQuestRemindersEnabled(true)

        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertEqual(scheduler.schedules.count, 1)
        XCTAssertEqual(store.state.questReminders.isEnabled, true)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .questRemindersEnabled)
        XCTAssertEqual(try persistence.load().questReminders, store.state.questReminders)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testDeniedPermissionKeepsRemindersDisabledAndDoesNotSchedule() async throws {
        let directory = temporaryDirectory()
        let persistence = OpenLARPPersistence(directory: directory)
        try persistence.save(OpenLARPEngine.confirmGoal(goal))
        let scheduler = RecordingQuestReminderScheduler(
            authorizationStatus: .denied,
            requestedAuthorizationStatus: .denied
        )
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            questReminderScheduler: scheduler
        )

        await store.setQuestRemindersEnabled(true)

        XCTAssertEqual(scheduler.authorizationRequestCount, 0)
        XCTAssertTrue(scheduler.schedules.isEmpty)
        XCTAssertFalse(store.state.questReminders.isEnabled)
        XCTAssertEqual(store.questReminderAuthorizationStatus, .denied)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .questReminderPermissionDenied)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testSchedulingFailureRestoresPreviousOffScheduleAndDoesNotPersistOptIn() async throws {
        let directory = temporaryDirectory()
        let persistence = OpenLARPPersistence(directory: directory)
        try persistence.save(OpenLARPEngine.confirmGoal(goal))
        let scheduler = RecordingQuestReminderScheduler(
            authorizationStatus: .authorized,
            shouldFailNextSchedule: true
        )
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            questReminderScheduler: scheduler
        )

        await store.setQuestRemindersEnabled(true)

        XCTAssertFalse(store.state.questReminders.isEnabled)
        XCTAssertFalse(try persistence.load().questReminders.isEnabled)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testChangingTimeAndCadenceReplacesExistingSchedule() async throws {
        let directory = temporaryDirectory()
        let persistence = OpenLARPPersistence(directory: directory)
        var state = OpenLARPEngine.confirmGoal(goal)
        state.questReminders = QuestReminderPreferences(
            isEnabled: true,
            hour: 18,
            minute: 0,
            cadence: .everyDay
        )
        try persistence.save(state)
        let scheduler = RecordingQuestReminderScheduler(authorizationStatus: .authorized)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            questReminderScheduler: scheduler
        )

        await store.updateQuestReminderTime(hour: 20, minute: 15)
        await store.updateQuestReminderCadence(.weekdays)

        XCTAssertEqual(scheduler.schedules.count, 2)
        XCTAssertEqual(store.state.questReminders.hour, 20)
        XCTAssertEqual(store.state.questReminders.minute, 15)
        XCTAssertEqual(store.state.questReminders.cadence, .weekdays)
        XCTAssertEqual(scheduler.schedules.last?.requests.map(\.weekday), [2, 3, 4, 5, 6])
    }

    @MainActor
    func testDisablingPersistsBeforeCancellingPendingReminders() async throws {
        let directory = temporaryDirectory()
        let persistence = OpenLARPPersistence(directory: directory)
        var state = OpenLARPEngine.confirmGoal(goal)
        state.questReminders.isEnabled = true
        try persistence.save(state)
        let scheduler = RecordingQuestReminderScheduler(authorizationStatus: .authorized)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            questReminderScheduler: scheduler
        )

        await store.setQuestRemindersEnabled(false)

        XCTAssertFalse(store.state.questReminders.isEnabled)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(store.state.betaEvents.last?.kind, .questRemindersDisabled)
        XCTAssertFalse(try persistence.load().questReminders.isEnabled)
    }

    @MainActor
    func testEraseAllOnDeviceDataCancelsReminderRequests() async throws {
        let directory = temporaryDirectory()
        let localDataStore = OpenLARPLocalDataStore(
            applicationSupportDirectory: directory.appendingPathComponent("ApplicationSupport"),
            cachesDirectory: directory.appendingPathComponent("Caches"),
            legacyDocumentsDirectory: directory.appendingPathComponent("Documents")
        )
        let scheduler = RecordingQuestReminderScheduler(authorizationStatus: .authorized)
        let store = OpenLARPStore(
            localDataStore: localDataStore,
            questReminderScheduler: scheduler
        )

        let erased = await store.eraseAllOnDeviceData()

        XCTAssertTrue(erased)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testActivationReconcilesRemindersAfterAccountRestoration() {
        let operations = AppLifecyclePolicy.activationOperations(for: .internalBeta)

        XCTAssertEqual(operations.last, .reconcileQuestReminders)
        XCTAssertGreaterThan(
            try! XCTUnwrap(operations.firstIndex(of: .reconcileQuestReminders)),
            try! XCTUnwrap(operations.firstIndex(of: .restoreAuthentication))
        )
    }

    private let goal = CareerGoal(
        currentStatus: .student,
        targetRole: "iOS engineering internship",
        timeline: "30 days",
        background: "Second-year CS student with one class project.",
        existingProof: "A SwiftUI class project",
        confidence: 3,
        biggestBlocker: "Thin proof"
    )

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

@MainActor
private final class RecordingQuestReminderScheduler: QuestReminderScheduling {
    var currentAuthorizationStatus: QuestReminderAuthorizationStatus
    let requestedAuthorizationStatus: QuestReminderAuthorizationStatus
    private(set) var authorizationRequestCount = 0
    private(set) var schedules: [QuestReminderSchedule] = []
    private(set) var cancelCount = 0
    private var shouldFailNextSchedule: Bool

    init(
        authorizationStatus: QuestReminderAuthorizationStatus,
        requestedAuthorizationStatus: QuestReminderAuthorizationStatus? = nil,
        shouldFailNextSchedule: Bool = false
    ) {
        currentAuthorizationStatus = authorizationStatus
        self.requestedAuthorizationStatus = requestedAuthorizationStatus ?? authorizationStatus
        self.shouldFailNextSchedule = shouldFailNextSchedule
    }

    func authorizationStatus() async -> QuestReminderAuthorizationStatus {
        currentAuthorizationStatus
    }

    func requestAuthorization() async throws -> QuestReminderAuthorizationStatus {
        authorizationRequestCount += 1
        currentAuthorizationStatus = requestedAuthorizationStatus
        return requestedAuthorizationStatus
    }

    func replacePendingReminders(with schedule: QuestReminderSchedule) async throws {
        if shouldFailNextSchedule {
            shouldFailNextSchedule = false
            throw RecordingQuestReminderError.schedulingFailed
        }
        schedules.append(schedule)
    }

    func cancelPendingReminders() async {
        cancelCount += 1
    }
}

private enum RecordingQuestReminderError: Error {
    case schedulingFailed
}
