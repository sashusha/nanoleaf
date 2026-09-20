/// Independent reasons must all clear before restoring the light.
public struct IdlePolicy {
    public enum Reason: Hashable { case screensaver, displaySleep, systemSleep }
    private var reasons: Set<Reason> = []
    public init() {}
    public var isSuppressed: Bool { !reasons.isEmpty }
    public mutating func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }
}
