import Foundation

public struct HardwareIdentity: Equatable {
    public let model: String
    public let vendorId: String
    public let productId: String
    public let hardwareVersion: String
    public let firmwareVersion: String?
    public init(model: String = "NL82K2", vendorId: String = "0x37FA", productId: String = "0x8202", hardwareVersion: String, firmwareVersion: String? = nil) {
        self.model = model; self.vendorId = vendorId; self.productId = productId
        self.hardwareVersion = hardwareVersion; self.firmwareVersion = firmwareVersion
    }
}

public struct Calibration: Codable {
    public struct Device: Codable {
        public let model: String
        public let vendorId: String
        public let productId: String
        public let hardwareVersion: String
    }
    public struct TemperatureRange: Codable {
        public let min: Int
        public let max: Int
        public let step: Int
    }
    public let schemaVersion: Int
    public let id: String
    public let device: Device
    public let testedFirmwareVersions: [String]
    public let temperatureRange: TemperatureRange
    public let rgbByKelvin: [[Int]]

    public init(id: String = "custom", hardwareVersion: String, testedFirmwareVersions: [String] = [], rgbByKelvin: [[Int]]) throws {
        self.schemaVersion = 1; self.id = id
        self.device = Device(model: "NL82K2", vendorId: "0x37FA", productId: "0x8202", hardwareVersion: hardwareVersion)
        self.testedFirmwareVersions = testedFirmwareVersions
        self.temperatureRange = TemperatureRange(min: 2700, max: 6500, step: 1)
        self.rgbByKelvin = rgbByKelvin
        try validate()
    }
    public func validate() throws {
        guard schemaVersion == 1, !id.isEmpty, !device.model.isEmpty,
              device.vendorId.lowercased() == "0x37fa", device.productId.lowercased() == "0x8202",
              !device.hardwareVersion.isEmpty,
              temperatureRange.min == 2700, temperatureRange.max == 6500, temperatureRange.step == 1,
              rgbByKelvin.count == 3801,
              rgbByKelvin.allSatisfy({ $0.count == 3 && $0.allSatisfy { (0...255).contains($0) } }) else {
            throw CLIError("Invalid calibration: expected schema 1, device metadata and 3801 RGB triples for 2700–6500 K.")
        }
    }
    public func matches(_ hardware: HardwareIdentity) -> Bool {
        device.model == hardware.model && device.hardwareVersion == hardware.hardwareVersion &&
        device.vendorId.lowercased() == hardware.vendorId.lowercased() &&
        device.productId.lowercased() == hardware.productId.lowercased()
    }
    public func rgb(kelvin: Int) throws -> [UInt8] {
        try Profile(temperature: kelvin, brightness: 30).validate()
        let index = kelvin - 2700
        guard rgbByKelvin.indices.contains(index), rgbByKelvin[index].count == 3,
              rgbByKelvin[index].allSatisfy({ (0...255).contains($0) }) else {
            throw CLIError("Invalid calibration sample at \(kelvin) K.")
        }
        return rgbByKelvin[index].map(UInt8.init)
    }
}

public struct CalibrationStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func bundledProfiles() throws -> [Calibration] {
        let profiles = try JSONDecoder().decode([Calibration].self, from: BundledCalibrationData.json)
        for p in profiles { try p.validate() }
        return profiles
    }
    private static func matching(_ profiles: [Calibration], hardware: HardwareIdentity) throws -> Calibration? {
        for p in profiles { try p.validate() }
        let matches = profiles.filter { $0.matches(hardware) }
        guard matches.count <= 1 else { throw CLIError("Multiple calibrations match \(hardware.model) hardware \(hardware.hardwareVersion).") }
        return matches.first
    }
    public func load(hardware: HardwareIdentity, serial: String) throws -> Calibration? {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let object = try JSONSerialization.jsonObject(with: data)
                let profiles: [Calibration]
                if object is [Any] {
                    profiles = try decoder.decode([Calibration].self, from: data)
                } else if let dict = object as? [String: Any], dict["schemaVersion"] != nil {
                    profiles = [try decoder.decode(Calibration.self, from: data)]
                } else {
                    // Read the previous serial-keyed format without displaying or
                    // exporting its optional source field. Still require exact hardware.
                    struct Legacy: Decodable { let hardwareVersion: String; let rgbByKelvin: [[Int]] }
                    let legacy = try decoder.decode([String: Legacy].self, from: data)
                    if let value = legacy[serial] {
                        profiles = [try Calibration(id: "legacy-local", hardwareVersion: value.hardwareVersion, rgbByKelvin: value.rgbByKelvin)]
                    } else { profiles = [] }
                }
                if let match = try Self.matching(profiles, hardware: hardware) { return match }
            } catch { throw CLIError("Cannot read calibration at \(url.path): \(error)") }
        }
        return try Self.matching(Self.bundledProfiles(), hardware: hardware)
    }
}
