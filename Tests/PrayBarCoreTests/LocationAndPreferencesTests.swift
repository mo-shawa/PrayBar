import XCTest
@testable import PrayBarCore

final class LocationAndPreferencesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func fix(at date: Date) -> LocationFix { LocationFix(point: GeoPoint(latitude: 31.95, longitude: 35.93), acquiredAt: date) }

    func testLocationFailureKeepsValidCacheAndExplainsManualOptionWithoutCache() {
        let cached = fix(at: now)
        var state = LocationRequestState(cache: cached)
        let id = state.begin()!
        XCTAssertTrue(state.finish(id: id, fix: nil, failure: "Permission denied."))
        XCTAssertEqual(state.cache, cached)
        XCTAssertTrue(state.status.contains("Using cached location"))
        XCTAssertNil(state.activeID)
        var empty = LocationRequestState()
        XCTAssertTrue(empty.finish(id: empty.begin()!, fix: nil, failure: "Timed out."))
        XCTAssertNil(empty.cache)
        XCTAssertTrue(empty.status.contains("manual location"))
    }

    func testOverlappingRequestsDeduplicateAndCancelledResultsAreIgnored() {
        var state = LocationRequestState()
        let old = state.begin()!
        XCTAssertNil(state.begin())
        state.cancel() // Manual-mode switch or any configuration change.
        let current = state.begin()!
        XCTAssertNotEqual(old, current)
        XCTAssertFalse(state.finish(id: old, fix: fix(at: now)))
        XCTAssertNil(state.cache)
        XCTAssertEqual(state.activeID, current)
        XCTAssertTrue(state.finish(id: current, fix: fix(at: now)))
        XCTAssertEqual(state.cache, fix(at: now))
        XCTAssertFalse(state.finish(id: current, fix: fix(at: now.addingTimeInterval(10))))
    }

    func testCacheStalenessHasDocumentedBoundAndHandlesClockGoingBackwards() {
        XCTAssertFalse(fix(at: now).isStale(at: now.addingTimeInterval(24 * 3600 - 1)))
        XCTAssertTrue(fix(at: now).isStale(at: now.addingTimeInterval(24 * 3600)))
        XCTAssertTrue(fix(at: now).isStale(at: now.addingTimeInterval(-120)))
        let invalid = LocationFix(point: GeoPoint(latitude: 200, longitude: 0), acquiredAt: now)
        XCTAssertNil(LocationRequestState(cache: invalid).cache)
        var state = LocationRequestState(cache: fix(at: now))
        XCTAssertTrue(state.finish(id: state.begin()!, fix: invalid))
        XCTAssertEqual(state.cache, fix(at: now))
    }

    func testManualValidationAndExplicitTimeZoneSelection() {
        var preferences = Preferences()
        XCTAssertNil(preferences.inputs(cache: nil, systemTimeZone: TimeZone(identifier: "America/Toronto")!))
        XCTAssertEqual(preferences.activeTimeZone(system: TimeZone(identifier: "America/Toronto")!)?.identifier, "America/Toronto")
        preferences.locationMode = .manual
        XCTAssertNotNil(preferences.validationError)
        preferences.manualPoint = GeoPoint(latitude: 31.95, longitude: 35.93)
        preferences.manualTimeZone = "not/a-zone"
        XCTAssertNotNil(preferences.validationError)
        preferences.manualTimeZone = "Asia/Amman"
        XCTAssertNil(preferences.validationError)
        XCTAssertEqual(preferences.inputs(cache: nil, systemTimeZone: TimeZone(identifier: "America/Toronto")!)?.timeZone.identifier, "Asia/Amman")
    }

    func testPreferenceAndLocationPersistenceRoundTripAndMissingConfiguration() {
        let name = "PrayBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PreferenceStore(defaults: defaults)
        XCTAssertNil(store.loadPreferences())
        XCTAssertNil(store.loadFix())
        var preferences = Preferences()
        preferences.locationMode = .manual
        preferences.manualPoint = GeoPoint(latitude: 31.95, longitude: 35.93)
        preferences.asr = .hanafi
        preferences.displayMode = .countdown
        store.save(preferences); store.save(fix(at: now))
        XCTAssertEqual(store.loadPreferences(), preferences)
        XCTAssertEqual(store.loadFix(), fix(at: now))
        defaults.set(Data("broken".utf8), forKey: "preferences.v1")
        XCTAssertNil(store.loadPreferences())
    }

    func testFreshLaunchWorksWithExplicitDefaultsAndOffersSettingsAfterFixOnlyOnce() {
        let name = "PrayBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PreferenceStore(defaults: defaults)
        let preferences = store.startupPreferences()
        XCTAssertEqual(preferences.locationMode, .automatic)
        XCTAssertEqual(preferences.displayMode, .countdown)
        XCTAssertEqual(preferences.asr, .standard)
        XCTAssertEqual(preferences.method, .muslimWorldLeague)
        XCTAssertNil(preferences.validationError)
        XCTAssertFalse(preferences.notifications.isEnabled)
        XCTAssertEqual(preferences.notifications.reminderMinutes, 10)
        XCTAssertTrue(store.shouldOfferSettings)
        XCTAssertEqual(store.startupPreferences(), preferences)
        store.didOfferSettings()
        XCTAssertFalse(store.shouldOfferSettings)
        XCTAssertEqual(store.startupPreferences(), preferences)
        XCTAssertFalse(store.shouldOfferSettings)
    }

    func testOldSavedConfigurationDecodesWithoutNotificationKeysOrChangingChoices() throws {
        var original = Preferences()
        original.displayMode = .clock
        original.asr = .hanafi
        original.locationMode = .manual
        original.manualPoint = GeoPoint(latitude: 43.65, longitude: -79.38)
        original.manualTimeZone = "America/Toronto"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "notifications")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertFalse(decoded.notifications.isEnabled)
    }
}
