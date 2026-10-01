import XCTest
import UserNotifications
@testable import PrayBarCore

final class PrayerNotificationsTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func inputs(_ zone: String, asr: AsrConvention = .standard) -> ScheduleInputs {
        ScheduleInputs(point: GeoPoint(latitude: 43.65, longitude: -79.38), timeZone: TimeZone(identifier: zone)!, method: .muslimWorldLeague, asr: asr)
    }

    func testFivePrayersBothTypesAndTenMinuteDefaultWithNoSunrise() {
        let now = date("2026-03-08T05:00:00Z")
        let snapshot = ScheduleCache().snapshot(at: now, inputs: inputs("America/Toronto"))
        let preferences = NotificationPreferences(atPrayer: true, beforePrayer: true)
        let events = PrayerNotifications.plan(snapshot: snapshot, preferences: preferences, now: now)
        XCTAssertEqual(events.count, 20)
        XCTAssertEqual(Set(events.map(\.identifier)).count, events.count)
        XCTAssertEqual(Set(events.map { $0.prayer.name }), Set(PrayerName.allCases))
        for event in events {
            XCTAssertEqual(event.date, event.kind == .prayer ? event.prayer.time : event.prayer.time.addingTimeInterval(-600))
            XCTAssertTrue(event.date > now)
        }
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted())
    }

    func testSleepRecoverySkipsElapsedRemindersWithoutSkippingFuturePrayer() {
        let start = date("2026-03-08T05:00:00Z")
        let snapshot = ScheduleCache().snapshot(at: start, inputs: inputs("America/Toronto"))
        let fajr = snapshot.today!.prayers[0]
        let now = fajr.time.addingTimeInterval(-60)
        let events = PrayerNotifications.plan(snapshot: snapshot, preferences: .init(atPrayer: true, beforePrayer: true), now: now)
        XCTAssertTrue(events.contains { $0.prayer == fajr && $0.kind == .prayer })
        XCTAssertFalse(events.contains { $0.prayer == fajr && $0.kind == .reminder })
        let later = PrayerNotifications.plan(snapshot: snapshot, preferences: .init(atPrayer: true, beforePrayer: true), now: snapshot.today!.prayers[3].time)
        XCTAssertFalse(later.contains { $0.prayer.time <= snapshot.today!.prayers[3].time })
    }

    func testAfterIshaIncludesTomorrowAndMidnightKeepsAbsoluteInstants() {
        let now = date("2026-09-30T21:00:00Z")
        let snapshot = ScheduleCache().snapshot(at: now, inputs: inputs("America/Toronto"))
        let afterIsha = snapshot.today!.prayers.last!.time.addingTimeInterval(1)
        let events = PrayerNotifications.plan(snapshot: snapshot, preferences: .init(atPrayer: true), now: afterIsha)
        XCTAssertEqual(events.map(\.prayer), snapshot.tomorrow!.prayers)
        XCTAssertEqual(events.first?.prayer.name, .fajr)
    }

    func testDSTAndTimeZoneChangesProduceUTCTriggersForExactlyTheCalculatedInstants() {
        for zone in ["America/Toronto", "Asia/Amman"] {
            for iso in ["2026-03-08T05:00:00Z", "2026-11-01T04:00:00Z"] {
                let now = date(iso)
                let snapshot = ScheduleCache().snapshot(at: now, inputs: inputs(zone))
                let events = PrayerNotifications.plan(snapshot: snapshot, preferences: .init(atPrayer: true, beforePrayer: true), now: now)
                XCTAssertFalse(events.isEmpty)
                for event in events {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
                    components.calendar = calendar; components.timeZone = calendar.timeZone
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    XCTAssertEqual(calendar.date(from: trigger.dateComponents), event.date)
                    XCTAssertFalse(trigger.repeats)
                }
            }
        }
    }

    func testSettingsChangesReplaceTimesAndDisabledUnavailablePlansAreEmpty() {
        let now = date("2026-09-30T04:00:00Z")
        let cache = ScheduleCache()
        let standard = cache.snapshot(at: now, inputs: inputs("America/Toronto"))
        let hanafi = cache.snapshot(at: now, inputs: inputs("America/Toronto", asr: .hanafi))
        let options = NotificationPreferences(atPrayer: true, beforePrayer: true, reminderMinutes: 20)
        let first = PrayerNotifications.plan(snapshot: standard, preferences: options, now: now)
        let second = PrayerNotifications.plan(snapshot: hanafi, preferences: options, now: now)
        XCTAssertNotEqual(first.first { $0.prayer.name == .asr }?.identifier, second.first { $0.prayer.name == .asr }?.identifier)
        XCTAssertTrue(second.allSatisfy { $0.reminderMinutes == 20 })
        XCTAssertTrue(PrayerNotifications.plan(snapshot: nil, preferences: options, now: now).isEmpty)
        XCTAssertTrue(PrayerNotifications.plan(snapshot: standard, preferences: .init(), now: now).isEmpty)
        XCTAssertTrue(PrayerNotifications.plan(snapshot: standard, preferences: .init(atPrayer: true, reminderMinutes: 0), now: now).isEmpty)
        let unavailable = ScheduleCache(calculate: { _, _ in nil }).snapshot(at: now, inputs: inputs("Asia/Amman"))
        XCTAssertTrue(PrayerNotifications.plan(snapshot: unavailable, preferences: options, now: now).isEmpty)
        XCTAssertLessThanOrEqual(second.count, 30)
    }
}
