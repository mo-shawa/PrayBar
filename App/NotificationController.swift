import AppKit
import UserNotifications
import PrayBarCore

// macOS owns delivery. No notification timer or wakeup loop in the app.
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var work: Task<Void, Never>?
    private var authorizationCheck: Task<Void, Never>?
    private var authorizationStatus: UNAuthorizationStatus?
    private var retryScheduling = false
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private(set) var status = "Notifications off."

    override init() { super.init(); center.delegate = self }

    func update(snapshot: ScheduleSnapshot?, preferences: NotificationPreferences, timeZone: TimeZone?, requestPermission: Bool) {
        authorizationCheck?.cancel()
        authorizationCheck = nil
        let previous = work
        previous?.cancel()
        // Cancel obsolete times immediately. Serialize additions so an in-flight
        // old add cannot repopulate the queue after the new plan clears it.
        center.removeAllPendingNotificationRequests()
        work = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            self.center.removeAllPendingNotificationRequests()
            self.retryScheduling = false
            guard preferences.isEnabled else {
                self.authorizationStatus = nil
                self.status = "Notifications off."
                return
            }
            var settings = await self.center.notificationSettings()
            guard !Task.isCancelled else { return }
            do {
                if settings.authorizationStatus == .notDetermined, requestPermission {
                    _ = try await self.center.requestAuthorization(options: [.alert, .sound])
                    settings = await self.center.notificationSettings()
                }
                guard !Task.isCancelled else { return }
                self.authorizationStatus = settings.authorizationStatus
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    self.status = "Allow PrayBar in System Settings → Notifications."
                    return
                }
                guard let timeZone else { self.status = "Notifications need a valid location and timetable."; return }
                self.formatter.timeZone = timeZone
                // Use current time after any permission dialog; never schedule
                // reminders which elapsed while the user was deciding.
                let events = PrayerNotifications.plan(snapshot: snapshot, preferences: preferences, now: Date())
                for event in events {
                    guard !Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    let name = event.prayer.name.rawValue
                    let unit = event.reminderMinutes == 1 ? "minute" : "minutes"
                    content.title = event.kind == .prayer ? "Time for \(name)" : "\(name) in \(event.reminderMinutes) \(unit)"
                    content.body = "\(name) begins at \(self.formatter.string(from: event.prayer.time)) (\(timeZone.identifier))."
                    content.sound = .default
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
                    components.calendar = calendar
                    components.timeZone = calendar.timeZone
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await self.center.add(UNNotificationRequest(identifier: event.identifier, content: content, trigger: trigger))
                }
                guard !Task.isCancelled else { return }
                self.status = events.isEmpty ? "Notifications need an available timetable." : "Notifications enabled."
            } catch {
                guard !Task.isCancelled else { return }
                // A partial plan must not masquerade as a fully scheduled one.
                self.center.removeAllPendingNotificationRequests()
                self.retryScheduling = true
                self.status = "Could not schedule notifications: \(error.localizedDescription)"
            }
        }
    }

    // Activation can reveal a permission change, but does not invalidate the
    // timetable. Read authorization once; leave unchanged system requests alone.
    func refreshAuthorization(onChange: @escaping () -> Void) {
        guard authorizationStatus != nil || retryScheduling else { return }
        authorizationCheck?.cancel()
        authorizationCheck = Task { [weak self] in
            guard let self else { return }
            let settings = await self.center.notificationSettings()
            guard !Task.isCancelled,
                  self.retryScheduling || self.authorizationStatus != settings.authorizationStatus else { return }
            onChange()
        }
    }

    func stop() { work?.cancel(); authorizationCheck?.cancel() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
