import AppKit

@main
enum PrayBarApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let controller = AppController()
        application.setActivationPolicy(.accessory)
        application.delegate = controller
        // NSApplication's delegate is weak. Retain it through the run loop.
        withExtendedLifetime(controller) { application.run() }
    }
}
