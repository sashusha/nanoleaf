/// Independent reasons must all clear before restoring the light.
public struct IdlePolicy {
    public enum Reason: Hashable { case screensaver, displaySleep, systemSleep }
    private var reasons: Set<Reason> = []
    public init() {}
    public var isSuppressed: Bool { !reasons.isEmpty }
    public var statusReasons: String {
        [(Reason.screensaver, "screensaver active"), (Reason.displaySleep, "display asleep"), (Reason.systemSleep, "system asleep")]
            .filter { reasons.contains($0.0) }.map { $0.1 }.joined(separator: ", ")
    }
    public mutating func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }
}
