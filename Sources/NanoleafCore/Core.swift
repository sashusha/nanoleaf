import Foundation

public struct CLIError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}

public struct Profile: Codable, Equatable {
    public var temperature: Int
    public var brightness: Int
    public init(temperature: Int, brightness: Int) {
        self.temperature = temperature; self.brightness = brightness
    }
    public func validate() throws {
        guard (2700...6500).contains(temperature) else { throw CLIError("Temperature must be 2700–6500 K.") }
        guard (0...100).contains(brightness) else { throw CLIError("Brightness must be 0–100%.") }
    }
}

public struct Configuration: Codable, Equatable {
    public var day = Profile(temperature: 4800, brightness: 30)
    public var evening = Profile(temperature: 3500, brightness: 30)
    public init() {}
    public func validate() throws { try day.validate(); try evening.validate() }
}

public struct ConfigStore {
    public let url: URL
    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/nanoleaf/config.json")) { self.url = url }
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        do {
            let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
            try config.validate()
            return config
        } catch { throw CLIError("Cannot read configuration at \(url.path): \(error)") }
    }
    public func save(_ config: Configuration) throws {
        try config.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

public enum Command: Equatable {
    case help, config, status, on, off, toggle
    case brightness(Int), temperature(Int)
    case profile(String, temperature: Int?, brightness: Int?, save: Bool)

    public static func parse(_ args: [String]) throws -> Command {
        guard let name = args.first else { return .help }
        let rest = Array(args.dropFirst())
        switch name {
        case "help", "--help", "-h", "config", "status", "on", "off", "toggle":
            guard rest.isEmpty else { throw CLIError("Unexpected arguments after \(name).") }
            return ["help": .help, "--help": .help, "-h": .help, "config": .config,
                    "status": .status, "on": .on, "off": .off, "toggle": .toggle][name]!
        case "brightness", "temp":
            guard rest.count == 1, let n = Int(rest[0]) else { throw CLIError("\(name) requires one integer.") }
            if name == "brightness" {
                try Profile(temperature: 4800, brightness: n).validate(); return .brightness(n)
            }
            try Profile(temperature: n, brightness: 30).validate(); return .temperature(n)
        case "day", "evening":
            var temp: Int?, brightness: Int?, save = false
            var seen = Set<String>(), i = 0
            while i < rest.count {
                let flag = rest[i]
                guard seen.insert(flag).inserted else { throw CLIError("Duplicate option: \(flag)") }
                if flag == "--save" { save = true; i += 1; continue }
                guard flag == "--temp" || flag == "--brightness" else { throw CLIError("Unknown option: \(flag)") }
                guard i + 1 < rest.count, let n = Int(rest[i+1]) else { throw CLIError("\(flag) requires an integer.") }
                if flag == "--temp" { temp = n } else { brightness = n }
                i += 2
            }
            try Profile(temperature: temp ?? 4800, brightness: brightness ?? 30).validate()
            return .profile(name, temperature: temp, brightness: brightness, save: save)
        default: throw CLIError("Unknown command: \(name). Run nanoleaf --help.")
        }
    }
}

public enum Wire {
    // TLV is a byte stream split across fixed-size HID reports. Only the final
    // report is zero padded; continuation reports do not repeat the TLV header.
    public static func reports(command: UInt8, payload: [UInt8], size: Int = 64) throws -> [[UInt8]] {
        guard size > 0, payload.count <= 1020 else { throw CLIError("Invalid USB payload size.") }
        let bytes = [command, UInt8(payload.count >> 8), UInt8(payload.count & 255)] + payload
        return stride(from: 0, to: bytes.count, by: size).map { start in
            let part = Array(bytes[start..<min(start + size, bytes.count)])
            return part + Array(repeating: 0, count: size - part.count)
        }
    }
    public static func response(_ bytes: [UInt8], command: UInt8, valueCount: Int) throws -> [UInt8] {
        guard bytes.count >= 3, bytes[0] == command | 0x80 else { throw CLIError("Unexpected USB response.") }
        let count = Int(bytes[1]) << 8 | Int(bytes[2])
        guard count >= 1, bytes.count >= count + 3 else { throw CLIError("Truncated USB response.") }
        guard bytes[3] == 0 else { throw CLIError("Device rejected command \(String(format: "0x%02X", command)) (error \(bytes[3])).") }
        guard count == valueCount + 1 else { throw CLIError("Invalid USB response length.") }
        return Array(bytes[4..<(count + 3)])
    }
    public static func brightness(_ percent: Int) -> UInt8 { UInt8((Double(percent) * 255 / 100).rounded()) }
    public static func rgb(kelvin: Int) -> [UInt8] {
        // Adapted from Tanner Helland's BSD-2-Clause Kelvin-to-RGB approximation.
        // See THIRD_PARTY_NOTICES.md. Not calibrated CCT on this RGB lightstrip.
        let t = Double(kelvin) / 100
        func byte(_ n: Double) -> UInt8 { UInt8(max(0, min(255, n.rounded()))) }
        return [255, byte(99.4708025861 * log(t) - 161.1195681661),
                byte(138.5177312231 * log(t - 10) - 305.0447927307)]
    }
}

public protocol Transport: AnyObject {
    func request(_ command: UInt8, payload: [UInt8], valueCount: Int) throws -> [UInt8]
}

// USB RGB streaming uses GRB order and a channel floor of 15 in the
// vendor's desktop implementation. Brightness belongs in the frame, not 0x09.
public enum Frame {
    public static func zone(kelvin: Int, brightness: Int, calibration: Calibration? = nil) throws -> [UInt8] {
        try Profile(temperature: kelvin, brightness: brightness).validate()
        let base = try calibration?.rgb(kelvin: kelvin) ?? Wire.rgb(kelvin: kelvin)
        let rgb = base.map { channel -> UInt8 in
            if calibration != nil {
                // Match Desktop's two stages: round brightness-scaled RGB to
                // bytes first, then map those bytes into the device's 15...255 range.
                let scaled = (Double(channel) * Double(brightness) / 100).rounded()
                return UInt8((15 + 240 * scaled / 255).rounded())
            }
            // Preserve existing output for devices without local calibration.
            return UInt8((15 + 240 * Double(channel) / 255 * Double(brightness) / 100).rounded())
        }
        return [rgb[1], rgb[0], rgb[2]]
    }
}

public struct DisplayState: Codable, Equatable {
    public var temperature: Int
    // Retained nonzero setting for on after off/brightness 0.
    public var brightness: Int
    public var isOn: Bool
    public var lastProfile: String?
    public var nextProfile: String { lastProfile == "day" ? "evening" : "day" }
    public init(temperature: Int = 4800, brightness: Int = 30, isOn: Bool = false, lastProfile: String? = nil) {
        self.temperature = temperature; self.brightness = brightness; self.isOn = isOn; self.lastProfile = lastProfile
    }
    public func validate() throws {
        try Profile(temperature: temperature, brightness: brightness).validate()
        guard lastProfile == nil || lastProfile == "day" || lastProfile == "evening" else { throw CLIError("Invalid saved profile name.") }
        guard brightness > 0 else { throw CLIError("Saved restore brightness must be greater than zero.") }
    }
}

public struct StateStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    private func loadAll() throws -> [String: DisplayState] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let states = try JSONDecoder().decode([String: DisplayState].self, from: Data(contentsOf: url))
            for state in states.values { try state.validate() }
            return states
        } catch { throw CLIError("Cannot read saved CLI state at \(url.path): \(error)") }
    }
    public func load(device: String) throws -> DisplayState? { try loadAll()[device] }
    public func save(_ state: DisplayState, device: String) throws {
        try state.validate()
        var states = try loadAll(); states[device] = state
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(states).write(to: url, options: .atomic)
    }
}

public final class Lightstrip {
    private let transport: Transport
    private let calibration: Calibration?
    public private(set) var state: DisplayState
    public init(transport: Transport, state: DisplayState = DisplayState(), calibration: Calibration? = nil) {
        self.transport = transport; self.state = state; self.calibration = calibration
    }
    public func zones() throws -> Int {
        let value = try transport.request(0x03, payload: [], valueCount: 1)
        guard value.count == 1, value[0] > 0 else { throw CLIError("Invalid LED zone count.") }
        return Int(value[0])
    }
    private func display(_ next: DisplayState) throws {
        try next.validate()
        let zone = try Frame.zone(kelvin: next.temperature, brightness: next.isOn ? next.brightness : 0, calibration: calibration)
        let count = try zones()
        _ = try transport.request(0x02, payload: Array(repeating: zone, count: count).flatMap { $0 }, valueCount: 0)
        // An acknowledgement establishes delivery, not a physical measurement.
        state = next
    }
    public func power(_ on: Bool) throws {
        var next = state; next.isOn = on; try display(next)
    }
    public func setBrightness(_ percent: Int) throws {
        try Profile(temperature: state.temperature, brightness: percent).validate()
        var next = state; next.isOn = percent > 0
        if percent > 0 { next.brightness = percent }
        try display(next)
    }
    public func temperature(_ kelvin: Int) throws {
        var next = state; next.temperature = kelvin; next.isOn = true
        try display(next)
    }
    public func apply(_ profile: Profile, name: String? = nil) throws {
        try profile.validate()
        var next = state; next.lastProfile = name; next.temperature = profile.temperature; next.isOn = profile.brightness > 0
        if profile.brightness > 0 { next.brightness = profile.brightness }
        try display(next)
    }
}
