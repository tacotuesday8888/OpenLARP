import Foundation
import UserNotifications

enum QuestReminderCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyDay
    case weekdays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyDay: "Every day"
        case .weekdays: "Weekdays"
        }
    }
}

struct QuestReminderPreferences: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var cadence: QuestReminderCadence

    static let off = QuestReminderPreferences(
        isEnabled: false,
        hour: 19,
        minute: 0,
        cadence: .everyDay
    )

    init(
        isEnabled: Bool,
        hour: Int,
        minute: Int,
        cadence: QuestReminderCadence
    ) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.cadence = cadence
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case hour
        case minute
        case cadence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            hour: try container.decodeIfPresent(Int.self, forKey: .hour) ?? Self.off.hour,
            minute: try container.decodeIfPresent(Int.self, forKey: .minute) ?? Self.off.minute,
            cadence: try container.decodeIfPresent(QuestReminderCadence.self, forKey: .cadence) ?? .everyDay
        )
    }
}

enum QuestReminderAuthorizationStatus: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

struct QuestReminderRequest: Equatable, Sendable {
    var identifier: String
    var weekday: Int?
    var hour: Int
    var minute: Int
    var title: String
    var body: String
}

struct QuestReminderSchedule: Equatable, Sendable {
    var requests: [QuestReminderRequest]
}

enum QuestReminderPolicy {
    static let identifierPrefix = "openlarp.quest-reminder"

    static func schedule(
        for preferences: QuestReminderPreferences,
        hasActiveCareerStep: Bool
    ) -> QuestReminderSchedule? {
        guard preferences.isEnabled, hasActiveCareerStep else { return nil }

        let weekdays: [Int?]
        switch preferences.cadence {
        case .everyDay:
            weekdays = [nil]
        case .weekdays:
            weekdays = [2, 3, 4, 5, 6]
        }

        return QuestReminderSchedule(
            requests: weekdays.map { weekday in
                QuestReminderRequest(
                    identifier: identifier(for: weekday),
                    weekday: weekday,
                    hour: preferences.hour,
                    minute: preferences.minute,
                    title: "Your career step is ready",
                    body: "Open OpenLARP when you’re ready to make one honest step forward."
                )
            }
        )
    }

    static var allIdentifiers: [String] {
        [identifier(for: nil)] + (1...7).map { identifier(for: $0) }
    }

    private static func identifier(for weekday: Int?) -> String {
        weekday.map { "\(identifierPrefix).weekday-\($0)" } ?? "\(identifierPrefix).daily"
    }
}

@MainActor
protocol QuestReminderScheduling: AnyObject {
    func authorizationStatus() async -> QuestReminderAuthorizationStatus
    func requestAuthorization() async throws -> QuestReminderAuthorizationStatus
    func replacePendingReminders(with schedule: QuestReminderSchedule) async throws
    func cancelPendingReminders() async
}

@MainActor
final class UserNotificationQuestReminderScheduler: QuestReminderScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> QuestReminderAuthorizationStatus {
        Self.authorizationStatus(from: await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async throws -> QuestReminderAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func replacePendingReminders(with schedule: QuestReminderSchedule) async throws {
        center.removePendingNotificationRequests(withIdentifiers: QuestReminderPolicy.allIdentifiers)

        do {
            for request in schedule.requests {
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .default

                var components = DateComponents()
                components.weekday = request.weekday
                components.hour = request.hour
                components.minute = request.minute

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: true
                )
                try await center.add(
                    UNNotificationRequest(
                        identifier: request.identifier,
                        content: content,
                        trigger: trigger
                    )
                )
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: QuestReminderPolicy.allIdentifiers)
            throw error
        }
    }

    func cancelPendingReminders() async {
        center.removePendingNotificationRequests(withIdentifiers: QuestReminderPolicy.allIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: QuestReminderPolicy.allIdentifiers)
    }

    private static func authorizationStatus(
        from status: UNAuthorizationStatus
    ) -> QuestReminderAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .unknown
        }
    }
}
