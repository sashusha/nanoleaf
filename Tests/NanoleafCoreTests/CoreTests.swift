import Foundation
import NanoleafCore

final class CoreTests {
    func testParsing() throws {
        XCTAssertEqual(try Command.parse(["day"]), .profile("day", temperature: nil, brightness: nil, save: false))
        XCTAssertEqual(try Command.parse(["evening", "--temp", "3300", "--brightness", "0", "--save"]), .profile("evening", temperature: 3300, brightness: 0, save: true))
        for bad in [["brightness", "101"], ["brightness", "-1"], ["temp", "2699"], ["temp", "6501"], ["off", "oops"], ["day", "--temp"], ["day", "--save", "--save"], ["evening", "--brightness", "NaN"], ["day", "--temp", "3000", "--temp", "4000"], ["foo"]] {
            XCTAssertThrowsError(try Command.parse(bad), "\(bad)")
        }
        XCTAssertEqual(try Command.parse(["brightness", "0"]), .brightness(0))
        XCTAssertEqual(try Command.parse(["temp", "6500"]), .temperature(6500))
    }
    func testConfigurationRoundTripAndCorruption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        let defaults = try store.load()
        XCTAssertEqual(defaults.day, Profile(temperature: 4800, brightness: 30))
        XCTAssertEqual(defaults.evening, Profile(temperature: 3500, brightness: 30))
        var updated = defaults; updated.day = Profile(temperature: 5200, brightness: 40)
        try store.save(updated)
        XCTAssertEqual(try store.load(), updated)
        XCTAssertEqual(try store.load().evening, defaults.evening)
        updated.day.brightness = 101
        XCTAssertThrowsError(try store.save(updated))
        try Data("{}".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }
    func testPacketBoundaries() throws {
        XCTAssertEqual(try Wire.reports(command: 7, payload: [1])[0].prefix(4), [7, 0, 1, 1])
        for count in [0, 60, 61, 62, 192, 765] {
            let payload = (0..<count).map { UInt8($0 % 256) }
            let reports = try Wire.reports(command: 2, payload: payload)
            XCTAssertTrue(reports.allSatisfy { $0.count == 64 })
            let bytes = reports.flatMap { $0 }
            XCTAssertEqual(Array(bytes[3..<(3+count)]), payload)
            XCTAssertEqual(Int(bytes[1]) << 8 | Int(bytes[2]), count)
            XCTAssertTrue(bytes.dropFirst(3 + count).allSatisfy { $0 == 0 })
        }
    }
    func testResponseValidation() throws {
        XCTAssertEqual(try Wire.response([0x88, 0, 2, 0, 77, 0, 0], command: 8, valueCount: 1), [77])
        for response: [UInt8] in [[0x88], [0x88, 0, 2, 0], [0x88, 0, 2, 1, 77], [0x87, 0, 2, 0, 77], [0x88, 0, 0], [0x88, 0, 1, 0]] {
            XCTAssertThrowsError(try Wire.response(response, command: 8, valueCount: 1))
        }
    }
    func testBrightnessAndColor() {
        XCTAssertEqual(Wire.brightness(0), 0)
        XCTAssertEqual(Wire.brightness(30), 77)
        XCTAssertEqual(Wire.brightness(100), 255)
        XCTAssertEqual(Wire.rgb(kelvin: 2700), [255, 167, 87])
        XCTAssertEqual(Wire.rgb(kelvin: 6500), [255, 254, 250])
    }
    func testReferenceFrames() throws {
        // Independent fixtures from the standalone, visually checked probes.
        XCTAssertEqual(try Frame.zone(kelvin: 4800, brightness: 30), [78, 87, 71])
        XCTAssertEqual(try Frame.zone(kelvin: 4800, brightness: 10), [36, 39, 34])
        XCTAssertEqual(try Frame.zone(kelvin: 3500, brightness: 0), [15, 15, 15])
        XCTAssertThrowsError(try Frame.zone(kelvin: 4800, brightness: 101))
    }
    func testOffAndRestoreAcrossInvocations() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        let fake = FakeTransport(); let first = Lightstrip(transport: fake)
        try first.apply(Profile(temperature: 4800, brightness: 30))
        let original = fake.rgb
        try first.power(false)
        XCTAssertEqual(fake.rgb, Array(repeating: 15, count: 225))
        try store.save(first.state, device: "test-device")
        let second = Lightstrip(transport: fake, state: try store.load(device: "test-device")!)
        try second.power(true)
        XCTAssertEqual(fake.rgb, original)
        XCTAssertEqual(second.state.brightness, 30)
        XCTAssertEqual(try store.load(device: "other-device"), nil)
    }
    func testZeroAndLowBrightness() throws {
        let fake = FakeTransport(); let device = Lightstrip(transport: fake)
        try device.apply(Profile(temperature: 3500, brightness: 0))
        XCTAssertEqual(fake.rgb, Array(repeating: 15, count: 225))
        XCTAssertTrue(!device.state.isOn)
        try device.setBrightness(1)
        XCTAssertTrue(fake.rgb.contains { $0 > 15 })
        XCTAssertTrue(fake.rgb.allSatisfy { $0 <= 17 })
        try device.setBrightness(0)
        XCTAssertEqual(fake.rgb, Array(repeating: 15, count: 225))
        try device.power(true)
        XCTAssertEqual(device.state.brightness, 1)
    }
    func testRejectedFramePreservesRestoreState() throws {
        let fake = FakeTransport(); let device = Lightstrip(transport: fake)
        try device.apply(Profile(temperature: 4800, brightness: 30))
        let before = device.state
        fake.rejectRGB = true
        XCTAssertThrowsError(try device.power(false))
        XCTAssertEqual(device.state, before)
        XCTAssertThrowsError(try device.apply(Profile(temperature: 3500, brightness: 10)))
        XCTAssertEqual(device.state, before)
    }
    func testTemperaturePreservesExistingBrightness() throws {
        let fake = FakeTransport()
        let device = Lightstrip(transport: fake, state: DisplayState(temperature: 3500, brightness: 10, isOn: true))
        try device.temperature(4800)
        XCTAssertEqual(device.state.brightness, 10)
        XCTAssertEqual(Array(fake.rgb.prefix(3)), [36, 39, 34])
    }
    func testCorruptState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        try Data("{broken".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load(device: "test"))
        XCTAssertThrowsError(try store.save(DisplayState(), device: "test"))
    }
}

private final class FakeTransport: Transport {
    var rejectRGB = false
    var rgb: [UInt8] = []
    func request(_ command: UInt8, payload: [UInt8], valueCount: Int) throws -> [UInt8] {
        switch command {
        case 3: return [75]
        case 2:
            guard !rejectRGB else { throw CLIError("RGB rejected") }
            guard payload.count == 225 else { throw CLIError("Wrong zone payload size") }
            rgb = payload
        default:
            // Never use native power/brightness commands to control streamed RGB.
            throw CLIError("Unexpected command \(command)")
        }
        return []
    }
}

// Minimal runner keeps checks usable with Command Line Tools installations
// that do not include XCTest. Failures exit nonzero, including release builds.
private var failures = 0
private func XCTFail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1
    print("FAIL \(file):\(line): \(message)")
}
private func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { XCTFail("Expected true", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
private func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let lhs = try a(), rhs = try b()
    if lhs != rhs { XCTFail("\(lhs) != \(rhs)", file: file, line: line) }
    } catch { XCTFail("\(error)", file: file, line: line) }
}
private func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "Expected error", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); XCTFail(message, file: file, line: line) } catch {}
}

@main
struct Checks {
    static func main() {
        let tests = CoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("Parsing", tests.testParsing),
            ("Configuration", tests.testConfigurationRoundTripAndCorruption),
            ("Packet boundaries", tests.testPacketBoundaries),
            ("Response validation", tests.testResponseValidation),
            ("Color approximation", tests.testBrightnessAndColor),
            ("Reference frame fixtures", tests.testReferenceFrames),
            ("Off and restore across invocations", tests.testOffAndRestoreAcrossInvocations),
            ("Zero and low brightness", tests.testZeroAndLowBrightness),
            ("Rejected frame preserves state", tests.testRejectedFramePreservesRestoreState),
            ("Temperature preserves brightness", tests.testTemperaturePreservesExistingBrightness),
            ("Corrupt saved state", tests.testCorruptState)
        ]
        for (name, test) in cases {
            let before = failures
            do { try test() } catch { XCTFail("\(name): \(error)") }
            print("\(failures == before ? "PASS" : "FAIL"): \(name)")
        }
        print("\(cases.count) test groups, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
