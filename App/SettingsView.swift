import SwiftUI
import ServiceManagement
import PrayBarCore
import Adhan

struct SettingsView: View {
    @State private var draft: Preferences
    @State private var latitude: String
    @State private var longitude: String
    @State private var launchAtLogin: Bool
    @State private var error: String?
    private let save: (Preferences, Bool) -> String?
    private let close: () -> Void
    private let notificationStatus: String?

    init(preferences: Preferences, notificationStatus: String?, save: @escaping (Preferences, Bool) -> String?, close: @escaping () -> Void) {
        _draft = State(initialValue: preferences)
        _latitude = State(initialValue: preferences.manualPoint.map { String($0.latitude) } ?? "")
        _longitude = State(initialValue: preferences.manualPoint.map { String($0.longitude) } ?? "")
        _launchAtLogin = State(initialValue: [.enabled, .requiresApproval].contains(SMAppService.mainApp.status))
        self.save = save; self.close = close
        self.notificationStatus = notificationStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Location") {
                    Picker("Location source", selection: $draft.locationMode) {
                        Text("Automatic (Core Location)").tag(LocationMode.automatic)
                        Text("Manual coordinates").tag(LocationMode.manual)
                    }
                    if draft.locationMode == .manual {
                        TextField("Latitude", text: $latitude)
                        TextField("Longitude", text: $longitude)
                        TextField("Time zone", text: $draft.manualTimeZone)
                        TextField("Location label (optional)", text: $draft.locationLabel)
                        Text("Decimal degrees, using a dot. Time zone example: Asia/Amman or America/Toronto.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Uses the Mac’s system time zone. A one-time location lookup asks for permission; a valid cached fix remains usable if a refresh fails.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Prayer calculation") {
                    Picker("Calculation method", selection: $draft.method) {
                        ForEach(CalculationMethod.selectable, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(draft.method.defaultsDescription).font(.caption).foregroundStyle(.secondary)
                    if draft.method == .ummAlQura {
                        Text("Isha is 120 min in Ramadan, using the Umm al-Qura calendar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Asr convention", selection: $draft.asr) {
                        Text("Standard — earlier Asr (Shafi, Maliki, Hanbali)").tag(AsrConvention.standard)
                        Text("Hanafi — later Asr").tag(AsrConvention.hanafi)
                    }
                    Text("These choices are yours; location does not select them. Adhan’s method offsets and rounding apply. High latitudes use Adhan’s recommended night rule; polar calculations can be unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Notifications") {
                    Toggle("At the start of each prayer", isOn: $draft.notifications.atPrayer)
                    Toggle("Reminder before each prayer", isOn: $draft.notifications.beforePrayer)
                    if draft.notifications.beforePrayer {
                        Stepper("\(draft.notifications.reminderMinutes) \(draft.notifications.reminderMinutes == 1 ? "minute" : "minutes") before", value: $draft.notifications.reminderMinutes, in: 1...120)
                    }
                    Text("Save to allow notifications. Choose banners or persistent alerts, and sound, in System Settings → Notifications → PrayBar.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let notificationStatus { Text(notificationStatus).font(.caption).foregroundStyle(.secondary) }
                    Button("Open System Settings…") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }
                }
                Section("Menu bar") {
                    Picker("Display", selection: $draft.displayMode) {
                        Text("Next prayer and clock time").tag(DisplayMode.clock)
                        Text("Next prayer and countdown").tag(DisplayMode.countdown)
                    }
                    Toggle("Launch at login", isOn: $launchAtLogin)
                    if SMAppService.mainApp.status == .requiresApproval {
                        Text("Login launch needs approval in System Settings.").font(.caption)
                        Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save") { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 660)
    }

    private func apply() {
        var preferences = draft
        if draft.locationMode == .manual {
            guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                error = "Enter numeric latitude and longitude in decimal degrees."; return
            }
            preferences.manualPoint = GeoPoint(latitude: lat, longitude: lon)
            preferences.manualTimeZone = draft.manualTimeZone.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.locationLabel = draft.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let validation = preferences.validationError { error = validation; return }
        error = save(preferences, launchAtLogin)
    }
}
