import Foundation
import Adhan

public enum LocationMode: String, Codable, CaseIterable { case automatic, manual }
public enum DisplayMode: String, Codable, CaseIterable { case clock, countdown }
public enum AsrConvention: String, Codable, CaseIterable { case standard, hanafi }

public struct GeoPoint: Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    var adhan: Coordinates { Coordinates(latitude: latitude, longitude: longitude) }
}

public struct Preferences: Codable, Equatable {
    public var locationMode: LocationMode = .automatic
    public var manualPoint: GeoPoint?
    public var manualTimeZone = TimeZone.current.identifier
    public var locationLabel = ""
    public var method: CalculationMethod = .muslimWorldLeague
    public var asr: AsrConvention = .standard
    public var displayMode: DisplayMode = .countdown
    public var notifications = NotificationPreferences()
    public init() {}

    // New preferences must not invalidate a user's existing v1 configuration.
    private enum CodingKeys: String, CodingKey {
        case locationMode, manualPoint, manualTimeZone, locationLabel, method, asr, displayMode, notifications
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        locationMode = try values.decode(LocationMode.self, forKey: .locationMode)
        manualPoint = try values.decodeIfPresent(GeoPoint.self, forKey: .manualPoint)
        manualTimeZone = try values.decode(String.self, forKey: .manualTimeZone)
        locationLabel = try values.decode(String.self, forKey: .locationLabel)
        method = try values.decode(CalculationMethod.self, forKey: .method)
        asr = try values.decode(AsrConvention.self, forKey: .asr)
        displayMode = try values.decode(DisplayMode.self, forKey: .displayMode)
        notifications = try values.decodeIfPresent(NotificationPreferences.self, forKey: .notifications) ?? NotificationPreferences()
    }

    public var validationError: String? {
        guard method != .other else { return "Choose a supported calculation method." }
        guard (1...120).contains(notifications.reminderMinutes) else { return "The reminder must be 1…120 minutes before prayer." }
        if locationMode == .manual {
            guard let point = manualPoint, point.isValid else {
                return "Latitude must be −90…90 and longitude −180…180, using decimal degrees."
            }
            guard TimeZone(identifier: manualTimeZone) != nil else {
                return "Enter a valid time zone identifier, such as Asia/Amman or America/Toronto."
            }
        }
        return nil
    }

    public func activeTimeZone(system: TimeZone) -> TimeZone? {
        locationMode == .automatic ? system : TimeZone(identifier: manualTimeZone)
    }

    public func inputs(cache: LocationFix?, systemTimeZone: TimeZone) -> ScheduleInputs? {
        guard validationError == nil,
              let point = locationMode == .manual ? manualPoint : cache?.point,
              point.isValid, let zone = activeTimeZone(system: systemTimeZone) else { return nil }
        return ScheduleInputs(point: point, timeZone: zone, method: method, asr: asr)
    }
}

// Writes happen on Save or a successful location acquisition, never on a display tick.
public final class PreferenceStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func loadPreferences() -> Preferences? { load(Preferences.self, key: "preferences.v1") }
    public func loadFix() -> LocationFix? {
        guard let fix = load(LocationFix.self, key: "location.v1"), fix.isValid else { return nil }
        return fix
    }
    // Only new installations get an offer, once usable times have arrived.
    public func startupPreferences() -> Preferences {
        if let saved = loadPreferences() { return saved }
        let initial = Preferences()
        save(initial)
        defaults.set(true, forKey: "offerSettingsAfterFix.v1")
        return initial
    }
    public var shouldOfferSettings: Bool { defaults.bool(forKey: "offerSettingsAfterFix.v1") }
    public func didOfferSettings() { defaults.set(false, forKey: "offerSettingsAfterFix.v1") }
    public func save(_ preferences: Preferences) { save(preferences, key: "preferences.v1") }
    public func save(_ fix: LocationFix) { save(fix, key: "location.v1") }
    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value), defaults.data(forKey: key) != data {
            defaults.set(data, forKey: key)
        }
    }
}

public extension CalculationMethod {
    static var selectable: [CalculationMethod] { allCases.filter { $0 != .other } }
    var label: String {
        switch self {
        case .muslimWorldLeague: return "Muslim World League"
        case .egyptian: return "Egyptian General Authority of Survey"
        case .karachi: return "University of Islamic Sciences, Karachi"
        case .ummAlQura: return "Umm al-Qura, Makkah"
        case .dubai: return "Dubai / UAE"
        case .moonsightingCommittee: return "Moonsighting Committee"
        case .northAmerica: return "ISNA / North America"
        case .kuwait: return "Kuwait"
        case .qatar: return "Qatar"
        case .singapore: return "Singapore"
        case .tehran: return "University of Tehran"
        case .turkey: return "Turkey (Diyanet approximation)"
        case .other: return "Other"
        }
    }
    var defaultsDescription: String {
        let p = params
        var text = "Fajr \(p.fajrAngle)° · "
        text += p.ishaInterval > 0 ? "Isha \(p.ishaInterval) min after Maghrib" : "Isha \(p.ishaAngle)°"
        if let angle = p.maghribAngle { text += " · Maghrib \(angle)°" }
        if self == .moonsightingCommittee { text += " · seasonal twilight adjustments" }
        if self == .turkey { text += " · intended for Turkey" }
        switch self {
        case .muslimWorldLeague, .egyptian, .karachi, .northAmerica, .singapore:
            text += " · Dhuhr +1 min"
        case .dubai: text += " · Dhuhr, Asr, Maghrib +3 min"
        case .moonsightingCommittee: text += " · Dhuhr +5, Maghrib +3 min"
        case .turkey: text += " · Dhuhr +5, Asr +4, Maghrib +7 min"
        default: text += " · no additional prayer offsets"
        }
        text += self == .singapore ? " · rounded up to a minute" : " · rounded to nearest minute"
        return text
    }
}
