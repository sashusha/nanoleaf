import Foundation

public struct ReconnectPolicy {
    private var disconnected = false
    public init() {}
    public mutating func observeDevicePresence(_ present: Bool) {
        if !present { disconnected = true }
    }
    public func shouldTurnOn(savedState: DisplayState?) -> Bool {
        disconnected || savedState?.isOn == true
    }
    public mutating func didRestore() { disconnected = false }
}
