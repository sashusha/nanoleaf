import Foundation

/// Local per-device RGB samples, separate from distributed source and profiles.
/// One entry for each integer Kelvin in 2700...6500, ordered by temperature.
public struct Calibration: Codable {
    public let source: String
    public let hardwareVersion: String
    public let rgbByKelvin: [[Int]]

    public init(source: String, hardwareVersion: String, rgbByKelvin: [[Int]]) throws {
        self.source = source
        self.hardwareVersion = hardwareVersion
        self.rgbByKelvin = rgbByKelvin
        try validate()
    }

    public func validate() throws {
        guard !source.isEmpty, !hardwareVersion.isEmpty, rgbByKelvin.count == 3801,
              rgbByKelvin.allSatisfy({ $0.count == 3 && $0.allSatisfy { (0...255).contains($0) } }) else {
            throw CLIError("Calibration must contain 3801 RGB triples (0–255), one for every Kelvin from 2700 to 6500, with source and hardwareVersion.")
        }
    }

    public func rgb(kelvin: Int) throws -> [UInt8] {
        try Profile(temperature: kelvin, brightness: 30).validate()
        // Also guard decoded values: callers may decode directly rather than use the store.
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

    public func load(device: String) throws -> Calibration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let samples = try JSONDecoder().decode([String: Calibration].self, from: Data(contentsOf: url))
            guard let calibration = samples[device] else { return nil }
            try calibration.validate()
            return calibration
        } catch {
            throw CLIError("Cannot read local calibration at \(url.path): \(error)")
        }
    }
}
