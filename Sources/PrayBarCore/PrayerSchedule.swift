import Foundation
import Adhan

public enum PrayerName: String, CaseIterable { case fajr = "Fajr", dhuhr = "Dhuhr", asr = "Asr", maghrib = "Maghrib", isha = "Isha" }
public struct PrayerEntry: Equatable {
    public let name: PrayerName
    public let time: Date
    public init(name: PrayerName, time: Date) { self.name = name; self.time = time }
}

public struct ScheduleInputs: Equatable {
    public let point: GeoPoint
    public let timeZone: TimeZone
    public let method: CalculationMethod
    public let asr: AsrConvention
    public init(point: GeoPoint, timeZone: TimeZone, method: CalculationMethod, asr: AsrConvention) {
        self.point = point; self.timeZone = timeZone; self.method = method; self.asr = asr
    }
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

public struct DaySchedule: Equatable {
    public let day: Date
    public let prayers: [PrayerEntry]
    public init?(day: Date, prayers: [PrayerEntry]) {
        guard prayers.map(\.name) == PrayerName.allCases,
              prayers.allSatisfy({ $0.time.timeIntervalSince1970.isFinite }),
              zip(prayers, prayers.dropFirst()).allSatisfy({ $0.time < $1.time }) else { return nil }
        self.day = day; self.prayers = prayers
    }
}

public enum PrayerCalculator {
    public static func calculate(day: Date, inputs: ScheduleInputs) -> DaySchedule? {
        guard inputs.point.isValid, inputs.method != .other else { return nil }
        // Pass ONLY local Gregorian Y/M/D. Adhan interprets the result as UTC instants.
        let date = inputs.calendar.dateComponents([.year, .month, .day], from: day)
        var params = inputs.method.params
        params.madhab = inputs.asr == .hanafi ? .hanafi : .shafi
        params.highLatitudeRule = HighLatitudeRule.recommended(for: inputs.point.adhan)
        // Umm al-Qura's documented Ramadan Isha interval is 120 minutes, otherwise 90.
        // Use Saudi Arabia's Umm al-Qura calendar, never the user's calendar preference.
        if inputs.method == .ummAlQura {
            var islamic = Calendar(identifier: .islamicUmmAlQura)
            islamic.timeZone = inputs.timeZone
            if islamic.component(.month, from: day) == 9 { params.adjustments.isha = 30 }
        }
        guard let times = PrayerTimes(coordinates: inputs.point.adhan, date: date, calculationParameters: params) else { return nil }
        return DaySchedule(day: inputs.calendar.startOfDay(for: day), prayers: [
            PrayerEntry(name: .fajr, time: times.fajr), PrayerEntry(name: .dhuhr, time: times.dhuhr),
            PrayerEntry(name: .asr, time: times.asr), PrayerEntry(name: .maghrib, time: times.maghrib),
            PrayerEntry(name: .isha, time: times.isha)
        ])
    }
}

public struct ScheduleSnapshot {
    public let previous: DaySchedule?
    public let today: DaySchedule?
    public let tomorrow: DaySchedule?
    public let rollover: Date
    public func nextPrayer(at now: Date) -> PrayerEntry? {
        // A missing current timetable is an unavailable state, not a guessed timetable.
        guard let today else { return nil }
        // At high latitudes Isha can fall after midnight. Do not skip the previous
        // evening's Isha simply because the civil date has rolled over.
        var next = today.prayers.first { $0.time > now }
        if let prior = previous?.prayers.first(where: { $0.time > now }), next == nil || prior.time < next!.time { next = prior }
        if let following = tomorrow?.prayers.first(where: { $0.time > now }), next == nil || following.time < next!.time { next = following }
        return next
    }
}

// Three bounded entries, including failures: previous evening, today, and tomorrow.
// The previous evening is needed only for prayers crossing civil midnight.
public final class ScheduleCache {
    private var inputs: ScheduleInputs?
    private var entries: [Date: DaySchedule] = [:]
    private var attempted: Set<Date> = []
    private var windowStart: Date?
    private var currentSnapshot: ScheduleSnapshot?
    private let calculate: (Date, ScheduleInputs) -> DaySchedule?
    public init(calculate: @escaping (Date, ScheduleInputs) -> DaySchedule? = PrayerCalculator.calculate) { self.calculate = calculate }
    public func snapshot(at now: Date, inputs newInputs: ScheduleInputs) -> ScheduleSnapshot {
        if inputs == newInputs, let start = windowStart, let snapshot = currentSnapshot,
           now >= start && now < snapshot.rollover { return snapshot }
        if inputs != newInputs { entries.removeAll(); attempted.removeAll(); inputs = newInputs }
        let calendar = newInputs.calendar
        let today = calendar.startOfDay(for: now)
        // Calendar arithmetic handles 23/25-hour days.
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: today)!)
        let previous = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: today)!)
        let days: Set<Date> = [previous, today, tomorrow]
        entries = entries.filter { days.contains($0.key) }
        attempted.formIntersection(days)
        for day in [previous, today, tomorrow] where !attempted.contains(day) {
            entries[day] = calculate(day, newInputs)
            attempted.insert(day)
        }
        let snapshot = ScheduleSnapshot(previous: entries[previous], today: entries[today], tomorrow: entries[tomorrow], rollover: tomorrow)
        windowStart = today; currentSnapshot = snapshot
        return snapshot
    }
}

public enum Indicator {
    public static func countdown(to prayer: Date, now: Date) -> String {
        let minutes = max(0, Int(floor(prayer.timeIntervalSince(now) / 60)))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    public static func nextUpdate(now: Date, snapshot: ScheduleSnapshot, mode: DisplayMode) -> Date {
        let next = snapshot.nextPrayer(at: now)
        let boundary = min(next?.time ?? snapshot.rollover, snapshot.rollover)
        guard mode == .countdown, next != nil else { return boundary }
        let minute = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
        return min(boundary, minute)
    }
}
