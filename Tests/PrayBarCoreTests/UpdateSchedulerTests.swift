import XCTest
@testable import PrayBarCore

final class UpdateSchedulerTests: XCTestCase {
    func testCancellationReplacementAndStaleCallbackCannotCreateDuplicates() {
        var timers: [Timer] = []
        var callbacks: [() -> Void] = []
        let scheduler = UpdateScheduler { date, tolerance, callback in
            let timer = Timer(fire: date, interval: 0, repeats: false) { _ in callback() }
            timer.tolerance = tolerance
            timers.append(timer); callbacks.append(callback)
            return timer
        }
        var updates = 0
        let now = Date(timeIntervalSince1970: 1000)
        scheduler.schedule(at: now) { updates += 1 }
        scheduler.schedule(at: now.addingTimeInterval(60)) { updates += 1 }
        XCTAssertFalse(timers[0].isValid)
        XCTAssertEqual(timers.filter(\.isValid).count, 1)
        callbacks[0]() // Force a previously queued obsolete callback.
        XCTAssertEqual(updates, 0)
        callbacks[1]()
        XCTAssertEqual(updates, 1)
        XCTAssertFalse(scheduler.hasActiveTimer)
        callbacks[1]()
        XCTAssertEqual(updates, 1)
        scheduler.schedule(at: now.addingTimeInterval(120)) { updates += 1 }
        scheduler.cancel() // Display/system sleep.
        callbacks[2]()
        XCTAssertEqual(updates, 1)
        XCTAssertNil(scheduler.scheduledDate)
        XCTAssertEqual(timers.filter(\.isValid).count, 0)
        scheduler.schedule(at: nil) { updates += 1 } // Unconfigured.
        XCTAssertEqual(timers.count, 3)
    }

    func testCallbackCanRescheduleAndOnlyOneTimerSurvives() {
        var timers: [Timer] = []
        var callbacks: [() -> Void] = []
        let scheduler = UpdateScheduler { date, _, callback in
            let timer = Timer(fire: date, interval: 0, repeats: false) { _ in callback() }
            timers.append(timer); callbacks.append(callback); return timer
        }
        scheduler.schedule(at: Date(timeIntervalSince1970: 100)) {
            scheduler.schedule(at: Date(timeIntervalSince1970: 200)) {}
        }
        callbacks[0]()
        XCTAssertFalse(timers[0].isValid)
        XCTAssertTrue(timers[1].isValid)
        XCTAssertEqual(timers.filter(\.isValid).count, 1)
        XCTAssertEqual(scheduler.scheduledDate, Date(timeIntervalSince1970: 200))
        scheduler.cancel()
    }

    func testDeinitializationCancelsTimer() {
        var timer: Timer?
        var scheduler: UpdateScheduler? = UpdateScheduler { date, _, callback in
            let value = Timer(fire: date, interval: 0, repeats: false) { _ in callback() }
            timer = value; return value
        }
        scheduler?.schedule(at: Date(timeIntervalSince1970: 100)) {}
        XCTAssertTrue(timer!.isValid)
        scheduler = nil
        XCTAssertFalse(timer!.isValid)
    }
}
