import Foundation

/// Only pointer intent. Automatic opening/closing and response authority keep
/// their existing owners; leaving a preview cannot resolve a request.
struct NotchHoverPolicy {
    enum Action { case expand, collapse }
    private var opening: TimeInterval?
    private var closing: TimeInterval?
    private var suppressedUntilExit = false
    var nextDeadline: TimeInterval? { opening ?? closing }
    mutating func dismissed() {
        opening = nil; closing = nil; suppressedUntilExit = true
    }
    mutating func update(inside: Bool, expanded: Bool, mayCollapse: Bool, now: TimeInterval) -> Action? {
        if inside {
            closing = nil
            guard !expanded, !suppressedUntilExit else { opening = nil; return nil }
            if let opening, now >= opening { self.opening = nil; return .expand }
            if opening == nil { opening = now + 0.14 }
        } else {
            suppressedUntilExit = false; opening = nil
            guard expanded, mayCollapse else { closing = nil; return nil }
            if let closing, now >= closing { self.closing = nil; return .collapse }
            if closing == nil { closing = now + 0.32 }
        }
        return nil
    }
}
