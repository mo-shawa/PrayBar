import Foundation

public struct NotificationPreferences: Codable, Equatable {
    public var atPrayer = false
    public var beforePrayer = false
    public var reminderMinutes = 10
    public var isEnabled: Bool { atPrayer || beforePrayer }
    public init(atPrayer: Bool = false, beforePrayer: Bool = false, reminderMinutes: Int = 10) {
        self.atPrayer = atPrayer; self.beforePrayer = beforePrayer; self.reminderMinutes = reminderMinutes
    }
}

public struct PrayerNotification: Equatable {
    public enum Kind: String { case prayer, reminder }
    public let prayer: PrayerEntry
    public let kind: Kind
    public let date: Date
    public let reminderMinutes: Int
    public var identifier: String { "PrayBar.\(kind.rawValue).\(prayer.name.rawValue).\(Int64(prayer.time.timeIntervalSince1970))" }
}

public enum PrayerNotifications {
    // A bounded rolling window, scheduled by macOS rather than an app timer.
    // Old reminders are skipped on wake/relaunch; they are never replayed.
    public static func plan(snapshot: ScheduleSnapshot?, preferences: NotificationPreferences, now: Date) -> [PrayerNotification] {
        guard let snapshot, snapshot.today != nil, preferences.isEnabled,
              (1...120).contains(preferences.reminderMinutes) else { return [] }
        var events: [String: PrayerNotification] = [:]
        for day in [snapshot.previous, snapshot.today, snapshot.tomorrow].compactMap({ $0 }) {
            for prayer in day.prayers where prayer.time > now {
                if preferences.atPrayer {
                    let event = PrayerNotification(prayer: prayer, kind: .prayer, date: prayer.time, reminderMinutes: preferences.reminderMinutes)
                    events[event.identifier] = event
                }
                let reminder = prayer.time.addingTimeInterval(-Double(preferences.reminderMinutes) * 60)
                if preferences.beforePrayer, reminder > now {
                    let event = PrayerNotification(prayer: prayer, kind: .reminder, date: reminder, reminderMinutes: preferences.reminderMinutes)
                    events[event.identifier] = event
                }
            }
        }
        return events.values.sorted { $0.date == $1.date ? $0.identifier < $1.identifier : $0.date < $1.date }
    }
}
