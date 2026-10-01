import Foundation

// One one-shot timer, on the main run loop's common modes (including an open NSMenu).
// The factory is the only testing seam; no waiting or generic scheduling framework.
public final class UpdateScheduler {
    public typealias TimerFactory = (Date, TimeInterval, @escaping () -> Void) -> Timer
    private let makeTimer: TimerFactory
    private var timer: Timer?
    private var generation: UInt64 = 0
    public private(set) var scheduledDate: Date?
    public var hasActiveTimer: Bool { timer?.isValid == true }
    public init(makeTimer: @escaping TimerFactory = { date, tolerance, action in
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in action() }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }) { self.makeTimer = makeTimer }
    public func cancel() {
        generation &+= 1
        timer?.invalidate(); timer = nil; scheduledDate = nil
    }
    public func schedule(at date: Date?, tolerance: TimeInterval = 0.5, action: @escaping () -> Void) {
        cancel()
        guard let date else { return }
        let token = generation
        scheduledDate = date
        timer = makeTimer(date, tolerance) { [weak self] in
            guard let self, self.generation == token else { return }
            self.cancel()
            action()
        }
    }
    deinit { timer?.invalidate() }
}
