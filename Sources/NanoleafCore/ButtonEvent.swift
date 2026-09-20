import Foundation

public enum ButtonEvent {
    /// NL82K2 emits [reserved, power gesture, scene button ID, scene gesture].
    /// Power's leading byte is 0 on the tested firmware, despite the public example.
    public static func isPowerPress(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 7, bytes[0] == 0x85, bytes[1] == 0, bytes[2] == 4,
              bytes[3] == 0 || bytes[3] == 1, (1...3).contains(bytes[4]),
              bytes[5] == 1 || bytes[5] == 2, bytes[6] <= 3 else { return false }
        return true
    }
}
