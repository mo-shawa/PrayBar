import AppKit
import SwiftUI
import ServiceManagement
import PrayBarCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store = PreferenceStore()
    private var preferences: Preferences?
    private var location: LocationProvider!
    private let cache = ScheduleCache()
    private let scheduler = UpdateScheduler()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var systemSleeping = false
    private var displaysSleeping = false
    private var locationRefreshPending = false
    private var paused: Bool { systemSleeping || displaysSleeping }
    private var snapshot: ScheduleSnapshot?
    private var activeInputs: ScheduleInputs?
    private var lastTitle = ""
    private var currentPrayer: PrayerEntry?
    private var notificationController: NotificationController?
    private var notificationConfiguration: NotificationConfiguration?
    private struct NotificationConfiguration: Equatable {
        let inputs: ScheduleInputs?
        let rollover: Date?
        let preferences: NotificationPreferences
    }
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short; formatter.timeStyle = .short
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = store.startupPreferences()
        location = LocationProvider(cache: store.loadFix())
        location.onChange = { [weak self] acquired in
            guard let self else { return }
            if acquired, let fix = self.location.state.cache { self.store.save(fix) }
            self.update()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        installObservers()
        update()
        menuWillOpen(menu)
        if let preferences, preferences.validationError == nil {
            if preferences.locationMode == .automatic { location.refresh() }
        } else {
            showSettings()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard location != nil else { return }
        update()
        // Rebuild the pending plan only if permission actually changed.
        notificationController?.refreshAuthorization { [weak self] in
            self?.update(refreshNotifications: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func installObservers() {
        observe(.NSSystemClockDidChange, center: .default) { [weak self] in self?.update(refreshNotifications: true) }
        observe(.NSSystemTimeZoneDidChange, center: .default) { [weak self] in
            guard let self else { return }
            NSTimeZone.resetSystemTimeZone()
            self.update(refreshNotifications: true)
            if self.preferences?.locationMode == .automatic {
                if self.paused { self.locationRefreshPending = true } else { self.location.refresh() }
            }
        }
        observe(NSLocale.currentLocaleDidChangeNotification, center: .default) { [weak self] in
            self?.stampFormatter.locale = .current
            self?.update()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, center: workspace) { [weak self] in
            self?.systemSleeping = true; self?.pause()
        }
        observe(NSWorkspace.screensDidSleepNotification, center: workspace) { [weak self] in
            self?.displaysSleeping = true; self?.pause()
        }
        observe(NSWorkspace.didWakeNotification, center: workspace) { [weak self] in
            self?.systemSleeping = false; self?.resume()
        }
        observe(NSWorkspace.screensDidWakeNotification, center: workspace) { [weak self] in
            self?.displaysSleeping = false; self?.resume()
        }
    }
    private func observe(_ name: Notification.Name, center: NotificationCenter, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }
    private func pause() { scheduler.cancel(); location.cancel() }
    private func resume() {
        guard !paused else { return }
        NSTimeZone.resetSystemTimeZone()
        update(refreshNotifications: true)
        if preferences?.locationMode == .automatic,
           locationRefreshPending || location.state.cache?.isStale(at: Date()) != false {
            locationRefreshPending = false
            location.refresh()
        }
    }

    private func update(now: Date = Date(), refreshNotifications: Bool = false, requestNotificationPermission: Bool = false) {
        scheduler.cancel()
        let priorInputs = activeInputs
        snapshot = nil; activeInputs = nil; currentPrayer = nil
        defer { updateNotifications(force: refreshNotifications, requestPermission: requestNotificationPermission) }
        guard let preferences, preferences.validationError == nil else { setTitle("Prayer · Check settings"); return }
        guard let inputs = preferences.inputs(cache: location.state.cache, systemTimeZone: .current) else {
            setTitle(location.state.activeID != nil ? "Prayer · Locating…" : "Prayer · Location needed")
            return
        }
        activeInputs = inputs
        if priorInputs?.timeZone != inputs.timeZone {
            timeFormatter.timeZone = inputs.timeZone
            stampFormatter.timeZone = inputs.timeZone
        }
        let snapshot = cache.snapshot(at: now, inputs: inputs)
        self.snapshot = snapshot
        if let next = snapshot.nextPrayer(at: now) {
            currentPrayer = next
            let detail = preferences.displayMode == .clock ? timeFormatter.string(from: next.time) : Indicator.countdown(to: next.time, now: now)
            setTitle("\(next.name.rawValue) · \(detail)")
            offerSettingsAfterFirstFix()
        } else { setTitle("Prayer · Unavailable") }
        scheduleDisplay(now: now, snapshot: snapshot)
    }

    private func scheduleDisplay(now: Date, snapshot: ScheduleSnapshot) {
        guard !paused, let preferences else { return }
        let date = Indicator.nextUpdate(now: now, snapshot: snapshot, mode: preferences.displayMode)
        let boundary = currentPrayer?.time
        let tolerance: TimeInterval = date == boundary || date == snapshot.rollover ? 0.5 : 3
        scheduler.schedule(at: date, tolerance: tolerance) { [weak self] in self?.displayTick() }
    }

    private func displayTick(now: Date = Date()) {
        // The ordinary minute tick needs only a Date subtraction, changed title,
        // and one timer. Inputs, formatters, location and notification IPC stay idle.
        guard let snapshot, let day = snapshot.today?.day, let next = currentPrayer,
              now >= day, now < snapshot.rollover, now < next.time,
              let preferences else { update(now: now); return }
        if preferences.displayMode == .countdown {
            setTitle("\(next.name.rawValue) · \(Indicator.countdown(to: next.time, now: now))")
        }
        scheduleDisplay(now: now, snapshot: snapshot)
    }

    private func updateNotifications(force: Bool = false, requestPermission: Bool = false) {
        let options = preferences?.notifications ?? NotificationPreferences()
        guard options.isEnabled || notificationController != nil else { return }
        let configuration = NotificationConfiguration(inputs: activeInputs, rollover: snapshot?.rollover, preferences: options)
        guard force || requestPermission || notificationConfiguration != configuration else { return }
        notificationConfiguration = configuration
        if notificationController == nil { notificationController = NotificationController() }
        notificationController?.update(snapshot: snapshot, preferences: options, timeZone: activeInputs?.timeZone, requestPermission: requestPermission)
    }

    private func offerSettingsAfterFirstFix() {
        guard !paused, store.shouldOfferSettings else { return }
        store.didOfferSettings()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.settingsWindow == nil, let preferences = self.preferences else { return }
            let alert = NSAlert()
            alert.messageText = "Prayer times are ready"
            alert.informativeText = "Using automatic location, \(preferences.method.label), and \(preferences.asr == .hanafi ? "Hanafi" : "Standard") Asr. You can change these choices in Settings at any time."
            let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login (recommended)", target: nil, action: nil)
            launchAtLogin.state = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) ? .on : .off
            launchAtLogin.toolTip = "Keep prayer times and reminders available whenever you log in to your Mac."
            launchAtLogin.sizeToFit()
            alert.accessoryView = launchAtLogin
            alert.addButton(withTitle: "Use defaults")
            alert.addButton(withTitle: "View all settings…")
            NSApplication.shared.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if let error = self.setLaunchAtLogin(launchAtLogin.state == .on) {
                let failure = NSAlert()
                failure.messageText = "Launch at login could not be changed"
                failure.informativeText = error
                failure.addButton(withTitle: "View all settings…")
                failure.runModal()
                self.showSettings()
                return
            }
            if response == .alertSecondButtonReturn { self.showSettings() }
            if launchAtLogin.state == .on, SMAppService.mainApp.status == .requiresApproval {
                let approval = NSAlert()
                approval.messageText = "Allow PrayBar to launch at login"
                approval.informativeText = "macOS needs your approval in Login Items. Prayer times will keep working while PrayBar is open."
                approval.addButton(withTitle: "Open Login Items…")
                approval.addButton(withTitle: "Later")
                if approval.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
            }
        }
    }
    private func setTitle(_ title: String) {
        guard title != lastTitle else { return }
        lastTitle = title
        statusItem.button?.title = title
        statusItem.button?.setAccessibilityLabel("Next prayer: \(title)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        update()
        menu.removeAllItems()
        let now = Date()
        row("Today’s prayers", heading: true)
        let next = snapshot?.nextPrayer(at: now)
        if let today = snapshot?.today {
            for prayer in today.prayers {
                row("\(prayer.name.rawValue)\(prayer == next ? " →" : "")    \(timeFormatter.string(from: prayer.time))")
            }
            if let next, snapshot?.tomorrow?.prayers.contains(next) == true {
                row("Next: tomorrow’s \(next.name.rawValue) · \(timeFormatter.string(from: next.time))")
            } else if let next, snapshot?.previous?.prayers.contains(next) == true {
                row("Next: \(next.name.rawValue) · \(timeFormatter.string(from: next.time)) (previous evening)")
            } else if next == nil { row("Next prayer unavailable for these inputs.") }
        } else {
            for name in PrayerName.allCases { row("\(name.rawValue)    —") }
            row(preferences == nil ? "Choose a location and calculation in Settings." : "Prayer times unavailable for these inputs.")
        }
        menu.addItem(.separator())
        if let preferences {
            if let inputs = activeInputs {
                let source = preferences.locationMode == .automatic ? "Automatic" : (preferences.locationLabel.isEmpty ? "Manual" : preferences.locationLabel)
                row(String(format: "%@: %.4f, %.4f", source, inputs.point.latitude, inputs.point.longitude))
                row("Time zone: \(inputs.timeZone.identifier) (\(preferences.locationMode == .automatic ? "system" : "manual"))")
            } else if let zone = preferences.activeTimeZone(system: .current) {
                row("Location unavailable · \(zone.identifier) (\(preferences.locationMode.rawValue))")
            }
            if preferences.locationMode == .automatic {
                row(location.state.status)
                if let fix = location.state.cache {
                    row("Fix: \(stampFormatter.string(from: fix.acquiredAt))\(fix.isStale(at: now) ? " · stale" : "")")
                }
            }
            row("\(preferences.method.label) · \(preferences.asr == .hanafi ? "Hanafi Asr" : "Standard Asr")")
            if preferences.notifications.isEnabled { row(notificationController?.status ?? "Notifications pending.") }
        } else { row("Location not configured.") }
        menu.addItem(.separator())
        let refresh = action("Refresh Location", selector: #selector(refreshLocation))
        refresh.isEnabled = preferences?.locationMode == .automatic && location.state.activeID == nil
        action("Settings…", selector: #selector(showSettings), key: ",")
        action("Quit", selector: #selector(quit), key: "q")
    }
    private func row(_ title: String, heading: Bool = false) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if heading { item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]) }
        menu.addItem(item)
    }
    @discardableResult private func action(_ title: String, selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }
    @objc private func refreshLocation() { if preferences?.locationMode == .automatic { location.refresh() } }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func showSettings() {
        if store.shouldOfferSettings { store.didOfferSettings() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "PrayBar Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences ?? Preferences(), notificationStatus: notificationController?.status, save: { [weak self] draft, login in
            self?.save(draft, launchAtLogin: login)
        }, close: { [weak self] in self?.settingsWindow?.close() }))
        settingsWindow = window
        window.center(); window.makeKeyAndOrderFront(nil)
    }

    private func setLaunchAtLogin(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled, service.status != .requiresApproval { try service.register() }
            if !enabled, [.enabled, .requiresApproval].contains(service.status) { try service.unregister() }
        } catch { return "Could not change launch at login: \(error.localizedDescription)" }
        return nil
    }

    private func save(_ draft: Preferences, launchAtLogin: Bool) -> String? {
        if let error = draft.validationError { return error }
        if let error = setLaunchAtLogin(launchAtLogin) { return error }
        location.cancel()
        locationRefreshPending = false
        preferences = draft
        store.save(draft)
        settingsWindow?.close()
        update(refreshNotifications: true, requestNotificationPermission: draft.notifications.isEnabled)
        if draft.locationMode == .automatic, !paused { location.refresh() }
        return nil
    }
    func windowWillClose(_ notification: Notification) {
        // Destroy the hosted form, including all SwiftUI state. No hidden settings tree.
        settingsWindow?.contentView = nil
        settingsWindow?.delegate = nil
        settingsWindow = nil
    }
    func applicationWillTerminate(_ notification: Notification) {
        scheduler.cancel(); location.cancel()
        notificationController?.stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
