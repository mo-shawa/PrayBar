import XCTest
import Adhan
@testable import PrayBarCore

private func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int = 30, _ hour: Int = 0, _ minute: Int = 0, zone: String = "Asia/Amman") -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
private func inputs(zone: String = "Asia/Amman", point: GeoPoint = GeoPoint(latitude: 31.95, longitude: 35.93), method: CalculationMethod = .muslimWorldLeague, asr: AsrConvention = .standard) -> ScheduleInputs {
    ScheduleInputs(point: point, timeZone: TimeZone(identifier: zone)!, method: method, asr: asr)
}
private func fixture(day: Date, inputs: ScheduleInputs) -> DaySchedule? {
    let calendar = inputs.calendar
    let prayers = zip(PrayerName.allCases, [5, 12, 16, 18, 20]).map { name, hour in
        PrayerEntry(name: name, time: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!)
    }
    return DaySchedule(day: day, prayers: prayers)
}

final class PrayerScheduleTests: XCTestCase {
    func testPublishedAdhanReferenceTimetable() throws {
        // Adhan 1.5.0 Tests/AdhanTests.swift, Raleigh 2015-07-12, ISNA/Hanafi.
        let config = inputs(zone: "America/New_York", point: GeoPoint(latitude: 35.7750, longitude: -78.6336), method: .northAmerica, asr: .hanafi)
        let actual = try XCTUnwrap(PrayerCalculator.calculate(day: date(2015, 7, 12, zone: "America/New_York"), inputs: config))
        let expected = [(4, 42), (13, 21), (18, 22), (20, 32), (21, 57)].map {
            date(2015, 7, 12, $0.0, $0.1, zone: "America/New_York")
        }
        XCTAssertEqual(actual.prayers.map(\.time), expected)
    }

    func testTomorrowFailureBecomesUnavailableAfterIsha() throws {
        let config = inputs()
        let today = try XCTUnwrap(fixture(day: date(), inputs: config))
        let snapshot = ScheduleSnapshot(previous: nil, today: today, tomorrow: nil, rollover: date(2026, 10, 1))
        XCTAssertEqual(snapshot.nextPrayer(at: date(2026, 9, 30, 19))?.name, .isha)
        XCTAssertNil(snapshot.nextPrayer(at: date(2026, 9, 30, 21)))
    }

    func testBeforeFajrAndEveryTransitionIncludingExactBoundary() throws {
        let snapshot = ScheduleCache(calculate: fixture).snapshot(at: date(), inputs: inputs())
        let prayers = try XCTUnwrap(snapshot.today).prayers
        XCTAssertEqual(snapshot.nextPrayer(at: date())?.name, .fajr)
        for (index, prayer) in prayers.enumerated() {
            XCTAssertEqual(snapshot.nextPrayer(at: prayer.time.addingTimeInterval(-1)), prayer)
            let expected = index < 4 ? prayers[index + 1] : snapshot.tomorrow!.prayers[0]
            XCTAssertEqual(snapshot.nextPrayer(at: prayer.time), expected)
            XCTAssertEqual(snapshot.nextPrayer(at: prayer.time.addingTimeInterval(1)), expected)
        }
    }

    func testAfterIshaTomorrowFajrAndMidnightRollover() {
        let cache = ScheduleCache(calculate: fixture)
        let evening = cache.snapshot(at: date(2026, 9, 30, 23, 59), inputs: inputs())
        XCTAssertEqual(evening.nextPrayer(at: date(2026, 9, 30, 23, 59))?.time, date(2026, 10, 1, 5))
        let midnight = cache.snapshot(at: date(2026, 10, 1), inputs: inputs())
        XCTAssertEqual(midnight.today?.day, date(2026, 10, 1))
        XCTAssertEqual(midnight.nextPrayer(at: date(2026, 10, 1))?.time, date(2026, 10, 1, 5))
    }

    func testSunriseIsExcludedFromRealCalculationAndNextPrayer() throws {
        let config = inputs()
        let snapshot = ScheduleCache().snapshot(at: date(), inputs: config)
        let today = try XCTUnwrap(snapshot.today)
        let params = config.method.params
        let raw = try XCTUnwrap(PrayerTimes(coordinates: Coordinates(latitude: 31.95, longitude: 35.93), date: DateComponents(year: 2026, month: 9, day: 30), calculationParameters: params))
        XCTAssertEqual(today.prayers.map(\.name), PrayerName.allCases)
        XCTAssertFalse(today.prayers.contains { $0.time == raw.sunrise })
        XCTAssertEqual(snapshot.nextPrayer(at: raw.fajr)?.name, .dhuhr)
        XCTAssertEqual(snapshot.nextPrayer(at: raw.sunrise)?.name, .dhuhr)
    }

    func testTorontoDSTUsesCalendarDaysAndAbsoluteInstants() throws {
        let config = inputs(zone: "America/Toronto", point: GeoPoint(latitude: 43.65, longitude: -79.38))
        for (month, day, hours) in [(3, 8, 23.0), (11, 1, 25.0)] {
            let now = date(2026, month, day, zone: "America/Toronto")
            let snapshot = ScheduleCache().snapshot(at: now, inputs: config)
            XCTAssertEqual(snapshot.rollover.timeIntervalSince(now), hours * 3600)
            let today = try XCTUnwrap(snapshot.today)
            let tomorrow = try XCTUnwrap(snapshot.tomorrow)
            XCTAssertEqual(today.day, now)
            XCTAssertEqual(config.calendar.component(.day, from: tomorrow.day), day + 1)
            XCTAssertLessThan(today.prayers.last!.time, tomorrow.prayers.first!.time)
            XCTAssertEqual(snapshot.nextPrayer(at: today.prayers.last!.time), tomorrow.prayers.first)
        }
    }

    func testAmmanCurrentAndHistoricalDST() throws {
        let config = inputs()
        let current = date()
        let snapshot = ScheduleCache().snapshot(at: current, inputs: config)
        XCTAssertEqual(snapshot.rollover.timeIntervalSince(current), 24 * 3600)
        XCTAssertEqual(config.timeZone.secondsFromGMT(for: current), 3 * 3600)
        // That day's midnight did not exist. Use a real noon instant to find its start.
        let historical = config.calendar.startOfDay(for: date(2021, 3, 26, 12))
        let historicalSnapshot = ScheduleCache().snapshot(at: historical, inputs: config)
        XCTAssertEqual(historicalSnapshot.rollover.timeIntervalSince(historical), 23 * 3600)
        XCTAssertEqual(config.calendar.component(.hour, from: historicalSnapshot.rollover), 0)
        XCTAssertNotNil(try XCTUnwrap(historicalSnapshot.today).prayers.first)
    }

    func testTimeZoneChangeInvalidatesCacheAndSelectsLocalGregorianDate() {
        var calls = 0
        let cache = ScheduleCache { day, input in calls += 1; return fixture(day: day, inputs: input) }
        let instant = date(2026, 10, 1, 1)
        _ = cache.snapshot(at: instant, inputs: inputs())
        let toronto = inputs(zone: "America/Toronto")
        let changed = cache.snapshot(at: instant, inputs: toronto)
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(toronto.calendar.component(.day, from: changed.today!.day), 30)
        XCTAssertEqual(changed.nextPrayer(at: instant)?.name, .isha)
    }

    func testWakeAfterMultipleBoundariesAndMultipleDaysDoesNotReplayTicks() {
        let cache = ScheduleCache(calculate: fixture)
        _ = cache.snapshot(at: date(2026, 9, 30, 4), inputs: inputs())
        let awake = date(2026, 9, 30, 19)
        XCTAssertEqual(cache.snapshot(at: awake, inputs: inputs()).nextPrayer(at: awake)?.name, .isha)
        let daysLater = date(2026, 10, 3, 13)
        XCTAssertEqual(cache.snapshot(at: daysLater, inputs: inputs()).nextPrayer(at: daysLater)?.time, date(2026, 10, 3, 16))
    }

    func testCacheReusesDaysButInvalidatesForMethodAsrAndCoordinates() {
        var calls = 0
        let cache = ScheduleCache { day, input in calls += 1; return fixture(day: day, inputs: input) }
        _ = cache.snapshot(at: date(), inputs: inputs())
        for hour in 1...23 { _ = cache.snapshot(at: date(2026, 9, 30, hour), inputs: inputs()) }
        XCTAssertEqual(calls, 3)
        _ = cache.snapshot(at: date(2026, 10, 1), inputs: inputs())
        XCTAssertEqual(calls, 4)
        _ = cache.snapshot(at: date(2026, 10, 1), inputs: inputs(method: .egyptian))
        XCTAssertEqual(calls, 7)
        _ = cache.snapshot(at: date(2026, 10, 1), inputs: inputs(method: .egyptian, asr: .hanafi))
        XCTAssertEqual(calls, 10)
        _ = cache.snapshot(at: date(2026, 10, 1), inputs: inputs(point: GeoPoint(latitude: 32, longitude: 36)))
        XCTAssertEqual(calls, 13)
    }

    func testCalculationMethodAndAsrChangeActualTimes() throws {
        let standard = try XCTUnwrap(PrayerCalculator.calculate(day: date(), inputs: inputs()))
        let hanafi = try XCTUnwrap(PrayerCalculator.calculate(day: date(), inputs: inputs(asr: .hanafi)))
        let egyptian = try XCTUnwrap(PrayerCalculator.calculate(day: date(), inputs: inputs(method: .egyptian)))
        XCTAssertGreaterThan(hanafi.prayers[2].time, standard.prayers[2].time)
        XCTAssertEqual(hanafi.prayers[0], standard.prayers[0])
        XCTAssertLessThan(egyptian.prayers[0].time, standard.prayers[0].time)
        XCTAssertNotEqual(egyptian.prayers[4], standard.prayers[4])
    }

    func testHighLatitudeRecommendedRuleAndPolarUnavailability() throws {
        let config = inputs(zone: "Europe/London", point: GeoPoint(latitude: 51.5, longitude: -0.12))
        let day = date(2026, 6, 21, zone: "Europe/London")
        let actual = try XCTUnwrap(PrayerCalculator.calculate(day: day, inputs: config))
        var params = config.method.params
        params.highLatitudeRule = .seventhOfTheNight
        let expected = try XCTUnwrap(PrayerTimes(coordinates: Coordinates(latitude: 51.5, longitude: -0.12), date: DateComponents(year: 2026, month: 6, day: 21), calculationParameters: params))
        XCTAssertEqual(actual.prayers[0].time, expected.fajr)
        XCTAssertEqual(actual.prayers[4].time, expected.isha)
        XCTAssertNil(PrayerCalculator.calculate(day: day, inputs: inputs(point: GeoPoint(latitude: 89, longitude: 0))))
    }

    func testInvalidCoordinatesAndUnavailableCalculationNeverCreateFallback() {
        for point in [GeoPoint(latitude: 91, longitude: 0), GeoPoint(latitude: 0, longitude: -181), GeoPoint(latitude: .nan, longitude: 0), GeoPoint(latitude: 0, longitude: .infinity)] {
            XCTAssertFalse(point.isValid)
            XCTAssertNil(PrayerCalculator.calculate(day: date(), inputs: inputs(point: point)))
        }
        var calls = 0
        let cache = ScheduleCache { _, _ in calls += 1; return nil }
        let unavailable = cache.snapshot(at: date(), inputs: inputs())
        XCTAssertNil(unavailable.today)
        XCTAssertNil(unavailable.nextPrayer(at: date()))
        for hour in 1...23 { _ = cache.snapshot(at: date(2026, 9, 30, hour), inputs: inputs()) }
        XCTAssertEqual(calls, 3, "Failed calculations must also be cached.")
        XCTAssertEqual(Indicator.nextUpdate(now: date(), snapshot: unavailable, mode: .countdown), unavailable.rollover)
    }

    func testCountdownWholeMinutesIsDerivedFromNow() {
        let prayer = date(2026, 9, 30, 16, 10)
        XCTAssertEqual(Indicator.countdown(to: prayer, now: prayer.addingTimeInterval(-42 * 60 - 59)), "42m")
        XCTAssertEqual(Indicator.countdown(to: prayer, now: prayer.addingTimeInterval(-372 * 60)), "6h 12m")
        XCTAssertEqual(Indicator.countdown(to: prayer, now: prayer.addingTimeInterval(-59)), "0m")
        XCTAssertEqual(Indicator.countdown(to: prayer, now: prayer.addingTimeInterval(60)), "0m")
    }

    func testClockOnlySchedulesBoundaryAndCountdownSchedulesMinuteOrBoundary() {
        let now = date(2026, 9, 30, 13, 10).addingTimeInterval(17)
        let snapshot = ScheduleCache(calculate: fixture).snapshot(at: now, inputs: inputs())
        XCTAssertEqual(Indicator.nextUpdate(now: now, snapshot: snapshot, mode: .clock), date(2026, 9, 30, 16))
        XCTAssertEqual(Indicator.nextUpdate(now: now, snapshot: snapshot, mode: .countdown), date(2026, 9, 30, 13, 11))
        let near = date(2026, 9, 30, 16).addingTimeInterval(-2)
        XCTAssertEqual(Indicator.nextUpdate(now: near, snapshot: snapshot, mode: .countdown), date(2026, 9, 30, 16))
        let late = date(2026, 9, 30, 23)
        XCTAssertEqual(Indicator.nextUpdate(now: late, snapshot: snapshot, mode: .clock), date(2026, 10, 1))
    }

    func testUmmAlQuraRamadanAdjustment() throws {
        let config = inputs(zone: "Asia/Riyadh", point: GeoPoint(latitude: 21.42, longitude: 39.83), method: .ummAlQura)
        for (day, interval) in [(date(2026, 2, 25, zone: "Asia/Riyadh"), 120.0), (date(2026, 9, 30, zone: "Asia/Riyadh"), 90.0)] {
            let schedule = try XCTUnwrap(PrayerCalculator.calculate(day: day, inputs: config))
            XCTAssertEqual(schedule.prayers[4].time.timeIntervalSince(schedule.prayers[3].time), interval * 60)
        }
    }

    func testLatePrayersCrossingMidnightAreNotSkippedOnLaunchOrRollover() throws {
        let config = inputs(zone: "Atlantic/Reykjavik", point: GeoPoint(latitude: 64.15, longitude: -21.94))
        let noon = date(2026, 6, 21, 12, zone: "Atlantic/Reykjavik")
        let cache = ScheduleCache()
        let snapshot = cache.snapshot(at: noon, inputs: config)
        let today = try XCTUnwrap(snapshot.today)
        let maghrib = today.prayers[3]
        let isha = today.prayers[4]
        XCTAssertGreaterThan(maghrib.time, snapshot.rollover)
        XCTAssertGreaterThan(isha.time, snapshot.rollover)
        let midnight = snapshot.rollover
        let rolled = cache.snapshot(at: midnight, inputs: config)
        XCTAssertEqual(rolled.nextPrayer(at: midnight), maghrib)
        XCTAssertEqual(rolled.nextPrayer(at: maghrib.time), isha)
        XCTAssertEqual(rolled.nextPrayer(at: isha.time)?.name, .fajr)
        XCTAssertEqual(ScheduleCache().snapshot(at: midnight, inputs: config).nextPrayer(at: midnight), maghrib)
    }
}
