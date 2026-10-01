import Foundation

public struct LocationFix: Codable, Equatable {
    public let point: GeoPoint
    public let acquiredAt: Date
    public init(point: GeoPoint, acquiredAt: Date) { self.point = point; self.acquiredAt = acquiredAt }
    public var isValid: Bool { point.isValid && acquiredAt.timeIntervalSince1970.isFinite }
    public func isStale(at now: Date) -> Bool {
        let age = now.timeIntervalSince(acquiredAt)
        return !isValid || age < -60 || age >= LocationRequestState.staleAfter
    }
}

// Small request gate shared by the real Core Location adapter and deterministic tests.
public struct LocationRequestState {
    public static let staleAfter: TimeInterval = 24 * 60 * 60
    public static let timeout: TimeInterval = 30
    public private(set) var activeID: UInt64?
    public private(set) var cache: LocationFix?
    public private(set) var status = "Location has not been requested."
    private var generation: UInt64 = 0
    public init(cache: LocationFix? = nil) { self.cache = cache?.isValid == true ? cache : nil }

    @discardableResult public mutating func begin() -> UInt64? {
        guard activeID == nil else { return nil }
        generation &+= 1
        activeID = generation
        status = "Finding location…"
        return generation
    }
    public mutating func cancel() {
        if activeID != nil {
            status = "Location lookup cancelled." + (cache == nil ? "" : " Using cached location.")
        }
        activeID = nil; generation &+= 1
    }

    // Old callbacks cannot replace the cache after settings have invalidated their request.
    @discardableResult public mutating func finish(id: UInt64, fix: LocationFix?, failure: String? = nil) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        if let fix, fix.isValid {
            cache = fix
            status = "Location updated."
        } else {
            status = (failure ?? "Location unavailable.") + (cache == nil ? " Enter a manual location in Settings." : " Using cached location.")
        }
        return true
    }
}
