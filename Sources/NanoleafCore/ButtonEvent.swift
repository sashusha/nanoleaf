import Foundation

public enum ButtonAction: Equatable { case power, mode }

public enum ButtonEvent {
    // Firmware 1.5.0 uses button IDs 0/1; the published protocol uses 1/2.
    public static func actions(_ bytes: [UInt8]) -> [ButtonAction] {
        guard bytes.count >= 7, bytes[0] == 0x85, bytes[1] == 0, bytes[2] == 4,
              bytes[3] <= 1, bytes[5] == bytes[3] + 1,
              bytes[4] <= 3, bytes[6] <= 3 else { return [] }
        var result: [ButtonAction] = []
        if bytes[4] > 0 { result.append(.power) }
        if bytes[6] > 0 { result.append(.mode) }
        return result
    }
    public static func isPowerPress(_ bytes: [UInt8]) -> Bool { actions(bytes).contains(.power) }
}
