import Foundation
import NanoleafCore

final class CoreTests {
    private let potsdam = SolarLocation(latitude: 52.4009, longitude: 13.0591)
    func testSunsetSchedule() throws {
        let date = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00Z")!
        let window = SunsetSchedule.window(on: date, location: potsdam)!
        var config = Configuration()
        config.sunsetAutomation = true
        config.day = Profile(temperature: 5000, brightness: 40)
        config.evening = Profile(temperature: 3000, brightness: 20)
        var state = DisplayState(isOn: true)
        XCTAssertEqual(try Command.parse(["schedule", "enable"]), .schedule(true))
        XCTAssertEqual(try Command.parse(["schedule", "disable"]), .schedule(false))
        XCTAssertEqual(try Command.parse(["schedule", "status"]), .schedule(nil))
        XCTAssertThrowsError(try Command.parse(["schedule", "bogus"]))
        XCTAssertEqual(SunsetSchedule.target(now: window.start.addingTimeInterval(-1), configuration: config, state: state, location: potsdam), nil)
        XCTAssertEqual(SunsetSchedule.target(now: window.start, configuration: config, state: state, location: potsdam), config.day)
        let midpoint = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start) / 2)
        XCTAssertEqual(SunsetSchedule.target(now: midpoint, configuration: config, state: state, location: potsdam), Profile(temperature: 4000, brightness: 30))
        XCTAssertEqual(SunsetSchedule.target(now: window.end, configuration: config, state: state, location: potsdam), config.evening)
        XCTAssertEqual(SunsetSchedule.target(now: window.end.addingTimeInterval(3600), configuration: config, state: state, location: potsdam), config.evening)
        state.lastManualChange = midpoint
        XCTAssertEqual(SunsetSchedule.target(now: window.end, configuration: config, state: state, location: potsdam), nil)
        let restored = try JSONDecoder().decode(DisplayState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        let tomorrow = SunsetSchedule.window(on: date.addingTimeInterval(86400), location: potsdam)!
        XCTAssertEqual(SunsetSchedule.target(now: tomorrow.start, configuration: config, state: restored, location: potsdam), config.day)
        state.lastManualChange = window.start.addingTimeInterval(-1)
        XCTAssertEqual(SunsetSchedule.target(now: midpoint, configuration: config, state: state, location: potsdam), Profile(temperature: 4000, brightness: 30))
        state.isOn = false
        XCTAssertEqual(SunsetSchedule.target(now: midpoint, configuration: config, state: state, location: potsdam), nil)
        state.isOn = true
        config.sunsetAutomation = false
        XCTAssertEqual(SunsetSchedule.target(now: midpoint, configuration: config, state: state, location: potsdam), nil)
        let legacy = Data(#"{"day":{"temperature":4800,"brightness":30},"evening":{"temperature":3500,"brightness":30}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: legacy).sunsetAutomation, nil)
    }

    func testLocationSolarEvents() {
        let date = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let greenwich = SunsetSchedule.window(on: date, location: SolarLocation(latitude: 0, longitude: 0), timeZone: utc)!
        let east = SunsetSchedule.window(on: date, location: SolarLocation(latitude: 0, longitude: 15), timeZone: utc)!
        XCTAssertTrue(abs(greenwich.start.timeIntervalSince(east.start) - 3600) < 60)
        XCTAssertEqual(SunsetSchedule.window(on: date, location: SolarLocation(latitude: 90, longitude: 0)), nil)
        XCTAssertEqual(SunsetSchedule.window(on: date, location: SolarLocation(latitude: .nan, longitude: 0)), nil)
        XCTAssertEqual(SunsetSchedule.window(on: date, location: SolarLocation(latitude: 0, longitude: 181)), nil)
        XCTAssertTrue(SunsetSchedule.summary(enabled: true, now: date).contains("waiting for system location"))
    }

    func testSystemTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-09-23T00:30:00Z")!
        let system = SunsetSchedule.window(on: date, location: potsdam)!
        let explicit = SunsetSchedule.window(on: date, location: potsdam, timeZone: .autoupdatingCurrent)!
        XCTAssertEqual(system.start, explicit.start)
        XCTAssertEqual(SunsetSchedule.calendar.timeZone.secondsFromGMT(for: date), TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let berlin = SunsetSchedule.window(on: date, location: potsdam, timeZone: TimeZone(identifier: "Europe/Berlin")!)!
        let newYork = SunsetSchedule.window(on: date, location: potsdam, timeZone: TimeZone(identifier: "America/New_York")!)!
        // The same instant belongs to different calendar days in these zones.
        XCTAssertTrue(berlin.start.timeIntervalSince(newYork.start) > 23 * 3600)
        XCTAssertTrue(berlin.start.timeIntervalSince(newYork.start) < 25 * 3600)
    }

    func testSolarDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let parser = ISO8601DateFormatter()
        // Seasonal sanity checks in local time, independent of the Mac timezone.
        for (day, earliest, latest) in [("2026-06-21", 21, 22), ("2026-12-21", 15, 17), ("2026-09-20", 19, 20)] {
            let window = SunsetSchedule.window(on: parser.date(from: day + "T12:00:00Z")!, location: potsdam, timeZone: calendar.timeZone)!
            let hour = calendar.component(.hour, from: window.start)
            XCTAssertTrue(hour >= earliest && hour < latest)
            XCTAssertTrue(window.end.timeIntervalSince(window.start) > 1200)
            XCTAssertTrue(window.end.timeIntervalSince(window.start) < 4800)
        }
        // Every date in a leap year has ordered events within the same Potsdam day.
        let start = parser.date(from: "2024-01-01T12:00:00Z")!
        for offset in 0..<366 {
            let date = start.addingTimeInterval(Double(offset) * 86400)
            let window = SunsetSchedule.window(on: date, location: potsdam, timeZone: calendar.timeZone)!
            XCTAssertTrue(window.end > window.start)
            XCTAssertTrue(calendar.isDate(date, inSameDayAs: window.start))
            XCTAssertTrue(calendar.isDate(date, inSameDayAs: window.end))
        }
    }


    func testIdlePolicy() {
        var reasons = IdlePolicy()
        reasons.set(.screensaver, active: true)
        reasons.set(.displaySleep, active: true)
        XCTAssertEqual(reasons.statusReasons, "screensaver active, display asleep")
        reasons.set(.screensaver, active: false)
        XCTAssertEqual(reasons.statusReasons, "display asleep")
        var policy = IdlePolicy()
        XCTAssertTrue(!policy.isSuppressed)
        policy.set(.screensaver, active: true)
        policy.set(.screensaver, active: true)
        policy.set(.displaySleep, active: true)
        policy.set(.screensaver, active: false)
        XCTAssertTrue(policy.isSuppressed)
        policy.set(.systemSleep, active: true)
        policy.set(.displaySleep, active: false)
        XCTAssertTrue(policy.isSuppressed)
        policy.set(.systemSleep, active: false)
        XCTAssertTrue(!policy.isSuppressed)
        policy.set(.displaySleep, active: false)
        XCTAssertTrue(!policy.isSuppressed)
        // Wake alone must not cancel a still-running screensaver.
        policy.set(.screensaver, active: true)
        policy.set(.displaySleep, active: true)
        policy.set(.displaySleep, active: false)
        XCTAssertTrue(policy.isSuppressed)
        policy.set(.screensaver, active: false)
        XCTAssertTrue(!policy.isSuppressed)
    }

    func testTemperatureSteps() throws {
        XCTAssertEqual(try Command.parse(["temp", "up"]), .temperatureStep(100))
        XCTAssertEqual(try Command.parse(["temp", "down"]), .temperatureStep(-100))
        let transport = FakeTransport()
        let device = Lightstrip(transport: transport, state: DisplayState(temperature: 6450, brightness: 30, isOn: true, lastProfile: "day"))
        try device.stepTemperature(100)
        XCTAssertEqual(device.state.temperature, 6500)
        try device.stepTemperature(100)
        XCTAssertEqual(device.state.temperature, 6500)
        XCTAssertEqual(device.state.brightness, 30)
        XCTAssertEqual(device.state.lastProfile, "day")
        try device.temperature(2750)
        try device.stepTemperature(-100)
        XCTAssertEqual(device.state.temperature, 2700)
        try device.power(false)
        try device.stepTemperature(100)
        XCTAssertTrue(!device.state.isOn)
        XCTAssertEqual(device.state.temperature, 2800)
        transport.rejectRGB = true
        XCTAssertThrowsError(try device.stepTemperature(100))
        XCTAssertEqual(device.state.temperature, 2800)
    }

    func testBrightnessSteps() throws {
        XCTAssertEqual(try Command.parse(["brightness", "up"]), .brightnessStep(5))
        XCTAssertEqual(try Command.parse(["brightness", "down"]), .brightnessStep(-5))
        let transport = FakeTransport()
        let device = Lightstrip(transport: transport, state: DisplayState(temperature: 4000, brightness: 98, isOn: true))
        try device.stepBrightness(5)
        XCTAssertEqual(device.state.brightness, 100)
        try device.stepBrightness(5)
        XCTAssertEqual(device.state.brightness, 100)
        try device.setBrightness(3)
        try device.stepBrightness(-5)
        XCTAssertTrue(!device.state.isOn)
        try device.stepBrightness(-5)
        XCTAssertTrue(!device.state.isOn)
        try device.stepBrightness(5)
        XCTAssertEqual(device.state.brightness, 5)
        XCTAssertTrue(device.state.isOn)
        XCTAssertEqual(device.state.temperature, 4000)
        transport.rejectRGB = true
        XCTAssertThrowsError(try device.stepBrightness(5))
        XCTAssertEqual(device.state.brightness, 5)
    }

    func testButtonEvents() {
        // Captured NL82K2 firmware 1.5.0 power event, including HID padding.
        let power: [UInt8] = [0x85, 0, 4, 0, 1, 1, 0]
        XCTAssertTrue(ButtonEvent.isPowerPress(power + Array(repeating: 0, count: 57)))
        XCTAssertTrue(ButtonEvent.isPowerPress([0x85, 0, 4, 0, 2, 1, 0]))
        XCTAssertTrue(ButtonEvent.isPowerPress([0x85, 0, 4, 0, 3, 1, 0]))
        XCTAssertTrue(!ButtonEvent.isPowerPress([0x85, 0, 4, 0, 0, 1, 1]))
        XCTAssertTrue(!ButtonEvent.isPowerPress([0x86, 0, 2, 0, 1]))
        XCTAssertTrue(!ButtonEvent.isPowerPress([0x85, 0, 4, 0, 4, 1, 0]))
        XCTAssertTrue(!ButtonEvent.isPowerPress([0x85, 0, 6, 0, 1, 1, 0]))
        for count in 0..<power.count { XCTAssertTrue(!ButtonEvent.isPowerPress(Array(power.prefix(count)))) }
    }

    func testModeProfiles() throws {
        XCTAssertEqual(try Command.parse(["night"]), try Command.parse(["evening"]))
        XCTAssertEqual(try Command.parse(["night", "--temp", "3200", "--brightness", "15", "--save"]),
                       try Command.parse(["evening", "--temp", "3200", "--brightness", "15", "--save"]))
        XCTAssertEqual(ButtonEvent.actions([0x85, 0, 4, 0, 0, 1, 1]), [.mode])
        XCTAssertEqual(ButtonEvent.actions([0x85, 0, 4, 1, 0, 2, 1]), [.mode])
        XCTAssertEqual(ButtonEvent.actions([0x85, 0, 4, 0, 1, 1, 1]), [.power, .mode])
        XCTAssertEqual(ButtonEvent.actions([0x85, 0, 4, 0, 0, 1, 4]), [])
        let legacy = Data(#"{"temperature":4000,"brightness":30,"isOn":true}"#.utf8)
        let initial = try JSONDecoder().decode(DisplayState.self, from: legacy)
        XCTAssertEqual(initial.nextProfile, "day")
        let transport = FakeTransport()
        let device = Lightstrip(transport: transport, state: initial)
        try device.apply(Profile(temperature: 4800, brightness: 40), name: "day")
        XCTAssertEqual(device.state.nextProfile, "evening")
        try device.power(false); try device.power(true); try device.setBrightness(20)
        XCTAssertEqual(device.state.nextProfile, "evening")
        let restored = try JSONDecoder().decode(DisplayState.self, from: JSONEncoder().encode(device.state))
        XCTAssertEqual(restored.nextProfile, "evening")
        transport.rejectRGB = true
        XCTAssertThrowsError(try device.apply(Profile(temperature: 3500, brightness: 30), name: "evening"))
        XCTAssertEqual(device.state.nextProfile, "evening")
        transport.rejectRGB = false
        try device.apply(Profile(temperature: 3500, brightness: 30), name: "evening")
        XCTAssertEqual(device.state.nextProfile, "day")
        XCTAssertEqual(device.state.temperature, 3500)
        XCTAssertEqual(device.state.brightness, 30)
    }

    func testReconnectPowerPolicy() {
        var policy = ReconnectPolicy()
        let off = DisplayState(temperature: 5250, brightness: 30, isOn: false, lastProfile: "day")
        policy.observeDevicePresence(true)
        XCTAssertTrue(!policy.shouldTurnOn(savedState: off))
        XCTAssertTrue(!policy.shouldTurnOn(savedState: nil))
        policy.observeDevicePresence(false)
        policy.observeDevicePresence(true)
        XCTAssertTrue(policy.shouldTurnOn(savedState: off))
        XCTAssertTrue(policy.shouldTurnOn(savedState: nil))
        // A failed restore does not consume the reconnect request.
        policy.observeDevicePresence(true)
        XCTAssertTrue(policy.shouldTurnOn(savedState: off))
        policy.didRestore()
        XCTAssertTrue(!policy.shouldTurnOn(savedState: off))
        XCTAssertTrue(policy.shouldTurnOn(savedState: DisplayState(isOn: true)))
    }

    func testParsing() throws {
        XCTAssertEqual(try Command.parse(["status", "--verbose"]), .status)
        XCTAssertThrowsError(try Command.parse(["status", "--unknown"]))
        XCTAssertThrowsError(try Command.parse(["status", "--verbose", "extra"]))
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
    func testCalibratedFrameScaling() throws {
        let calibration = try Calibration(id: "synthetic test", hardwareVersion: "test",
            rgbByKelvin: Array(repeating: [255,128,64], count: 3801))
        XCTAssertEqual(try Frame.zone(kelvin: 4000, brightness: 30, calibration: calibration), [51,87,33])
        XCTAssertEqual(try Frame.zone(kelvin: 4000, brightness: 10, calibration: calibration), [27,39,21])
        XCTAssertEqual(try Frame.zone(kelvin: 4000, brightness: 0, calibration: calibration), [15,15,15])
        XCTAssertEqual(try Frame.zone(kelvin: 4000, brightness: 100, calibration: calibration), [135,255,75])
    }
    func testCalibrationValidationAndBounds() throws {
        var samples = Array(repeating: [255,128,64], count: 3801)
        samples[0] = [1,2,3]; samples[3800] = [4,5,6]
        let c = try Calibration(id: "test", hardwareVersion: "test", rgbByKelvin: samples)
        XCTAssertEqual(try c.rgb(kelvin: 2700), [1,2,3])
        XCTAssertEqual(try c.rgb(kelvin: 6500), [4,5,6])
        XCTAssertThrowsError(try c.rgb(kelvin: 2699))
        XCTAssertThrowsError(try c.rgb(kelvin: 6501))
        XCTAssertThrowsError(try Calibration(id: "test", hardwareVersion: "test", rgbByKelvin: []))
        samples[100] = [256,0,0]
        XCTAssertThrowsError(try Calibration(id: "test", hardwareVersion: "test", rgbByKelvin: samples))
        samples[100] = [0,0]
        XCTAssertThrowsError(try Calibration(id: "test", hardwareVersion: "test", rgbByKelvin: samples))
    }
    func testCalibrationStoreMatchesDevice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CalibrationStore(url: dir.appendingPathComponent("calibration.json"))
        let unknown = HardwareIdentity(hardwareVersion: "test")
        XCTAssertTrue(try store.load(hardware: unknown, serial: "a") == nil)
        let c = try Calibration(id: "synthetic", hardwareVersion: "test", rgbByKelvin: Array(repeating: [255,128,64], count: 3801))
        try JSONEncoder().encode(c).write(to: store.url)
        XCTAssertEqual(try store.load(hardware: unknown, serial: "a")?.rgb(kelvin: 4000), [255,128,64])
        // New profiles are reusable on another unit with the same hardware.
        XCTAssertEqual(try store.load(hardware: unknown, serial: "b")?.id, "synthetic")
        XCTAssertTrue(try store.load(hardware: HardwareIdentity(hardwareVersion: "1.0.0"), serial: "a") == nil)
        try JSONEncoder().encode([c,c]).write(to: store.url)
        XCTAssertThrowsError(try store.load(hardware: unknown, serial: "a"))
        try Data("{invalid".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load(hardware: unknown, serial: "a"))
    }
    func testBundledHardwareProfile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CalibrationStore(url: dir.appendingPathComponent("absent.json"))
        let c = try store.load(hardware: HardwareIdentity(hardwareVersion: "1.1.0", firmwareVersion: "9.9.0"), serial: "any-unit")
        XCTAssertEqual(c?.id, "nl82k2-hw-1.1.0")
        XCTAssertEqual(c?.testedFirmwareVersions, ["1.5.0"])
        XCTAssertTrue(try store.load(hardware: HardwareIdentity(hardwareVersion: "1.0.0"), serial: "any-unit") == nil)
        XCTAssertTrue(try store.load(hardware: HardwareIdentity(model: "OTHER", hardwareVersion: "1.1.0"), serial: "any-unit") == nil)
        XCTAssertEqual(try c?.rgb(kelvin: 4000), [255,210,109])
        XCTAssertEqual(try Frame.zone(kelvin: 4000, brightness: 30, calibration: c), [74,87,46])
        let encoded = try JSONEncoder().encode(c!)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(!json.contains("source"))
        XCTAssertTrue(!json.contains("serial"))
    }
    func testLegacyCalibrationCompatibility() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CalibrationStore(url: dir.appendingPathComponent("calibration.json"))
        let old: [String:Any] = ["a": ["source":"old optional field", "hardwareVersion":"test", "rgbByKelvin":Array(repeating:[255,128,64],count:3801)]]
        try JSONSerialization.data(withJSONObject:old).write(to:store.url)
        XCTAssertEqual(try store.load(hardware:HardwareIdentity(hardwareVersion:"test"),serial:"a")?.id,"legacy-local")
        XCTAssertTrue(try store.load(hardware:HardwareIdentity(hardwareVersion:"different"),serial:"a") == nil)
        XCTAssertTrue(try store.load(hardware:HardwareIdentity(hardwareVersion:"test"),serial:"b") == nil)
    }
    func testCalibratedRestore() throws {
        let c = try Calibration(id: "synthetic", hardwareVersion: "test", rgbByKelvin: Array(repeating: [255,128,64], count: 3801))
        let fake = FakeTransport()
        let first = Lightstrip(transport: fake, calibration: c)
        try first.apply(Profile(temperature: 4000, brightness: 30))
        let original = fake.rgb
        try first.power(false)
        XCTAssertEqual(fake.rgb, Array(repeating: 15, count: 225))
        let second = Lightstrip(transport: fake, state: first.state, calibration: c)
        try second.power(true)
        XCTAssertEqual(fake.rgb, original)
        try second.setBrightness(10)
        XCTAssertEqual(Array(fake.rgb.prefix(3)), [27,39,21])
        XCTAssertEqual(second.state.temperature, 4000)
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
            ("Sunset schedule and manual overrides", tests.testSunsetSchedule),
            ("Solar dates and seasons", tests.testSolarDates),
            ("System time zone and date boundary", tests.testSystemTimeZone),
            ("Location and polar solar events", tests.testLocationSolarEvents),
            ("Relative brightness", tests.testBrightnessSteps),
            ("Relative temperature", tests.testTemperatureSteps),
            ("Overlapping idle events", tests.testIdlePolicy),
            ("Physical button events", tests.testButtonEvents),
            ("Mode profile cycling and persistence", tests.testModeProfiles),
            ("Reconnect power policy", tests.testReconnectPowerPolicy),
            ("Configuration", tests.testConfigurationRoundTripAndCorruption),
            ("Packet boundaries", tests.testPacketBoundaries),
            ("Response validation", tests.testResponseValidation),
            ("Color approximation", tests.testBrightnessAndColor),
            ("Reference frame fixtures", tests.testReferenceFrames),
            ("Off and restore across invocations", tests.testOffAndRestoreAcrossInvocations),
            ("Zero and low brightness", tests.testZeroAndLowBrightness),
            ("Rejected frame preserves state", tests.testRejectedFramePreservesRestoreState),
            ("Temperature preserves brightness", tests.testTemperaturePreservesExistingBrightness),
            ("Corrupt saved state", tests.testCorruptState),
            ("Calibrated frame scaling", tests.testCalibratedFrameScaling),
            ("Calibration bounds and validation", tests.testCalibrationValidationAndBounds),
            ("Calibration device matching", tests.testCalibrationStoreMatchesDevice),
            ("Calibrated off/on restoration", tests.testCalibratedRestore),
            ("Bundled exact hardware matching", tests.testBundledHardwareProfile),
            ("Legacy calibration compatibility", tests.testLegacyCalibrationCompatibility)
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
