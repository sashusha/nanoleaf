import Foundation
import Darwin
import NanoleafCore

let help = """
Usage: nanoleaf <command>

  on | off | toggle             Control power
  day | evening | night         Apply a saved profile (night = evening)
  brightness <0-100> | up|down   Set brightness or adjust by 5%
  temp <2700-6500> | up|down     Set Kelvin or adjust by 100 K
  schedule enable|disable|status Local sunset transition
  config | status               Show defaults or saved device settings
  service enable|disable|status Manage background control

Profile options: --temp K --brightness N --save
Without --save, overrides leave profile defaults unchanged.

More: https://github.com/sashusha/nanoleaf#readme
"""

func execute(_ args: [String], transport supplied: HIDTransport? = nil, manual: Bool = true, emit: (String) -> Void = { Swift.print($0) }) throws {
    let print = emit
    let command = try Command.parse(args)
    if command == .help { print(help); return }
    let store = ConfigStore()
    // Serialize profile read/modify/write and device transactions across CLI processes.
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let lockPath = store.url.deletingLastPathComponent().appendingPathComponent(".lock").path
    let fd = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw CLIError("Cannot open configuration lock: \(String(cString: strerror(errno)))") }
    defer { close(fd) }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CLIError("Another nanoleaf command is running. Retry when it finishes.") }
    defer { flock(fd, LOCK_UN) }
    if case let .schedule(enabled) = command {
        var config = try store.load()
        if let enabled { config.sunsetAutomation = enabled; try store.save(config) }
        if ServiceControl.isEnabled {
            // The service owns location permission and holds the current fix.
            if let reply = try? ServiceIPC.call(["__schedule_status"]) { print(reply.output) }
            else { print(SunsetSchedule.summary(enabled: config.sunsetAutomation == true, now: Date())) }
        } else { print(SunsetSchedule.summary(enabled: config.sunsetAutomation == true, now: Date())) }
        if !ServiceControl.isEnabled { print("Run nanoleaf service enable for automatic transitions.") }
        return
    }
    if command == .config {
        let config = try store.load()
        print("day:     \(config.day.temperature) K, \(config.day.brightness)%")
        print("evening: \(config.evening.temperature) K, \(config.evening.brightness)%")
        print("Config: \(store.url.path)")
        print(SunsetSchedule.summary(enabled: config.sunsetAutomation == true, now: Date()))
        return
    }
    // Validate config before touching hardware. A corrupt profile never changes LEDs.
    var config: Configuration?
    var selected: Profile?
    if case let .profile(name, temp, brightness, _) = command {
        config = try store.load()
        var profile = name == "day" ? config!.day : config!.evening
        if let temp { profile.temperature = temp }
        if let brightness { profile.brightness = brightness }
        try profile.validate(); selected = profile
    }
    let transport = try supplied ?? HIDTransport()
    let stateStore = StateStore(url: store.url.deletingLastPathComponent().appendingPathComponent("state.json"))
    let savedState = try stateStore.load(device: transport.identifier)
    let calibrationStore = CalibrationStore(url: store.url.deletingLastPathComponent().appendingPathComponent("calibration.json"))
    let hardware: HardwareIdentity?
    var hardwareError: String?
    do { hardware = try transport.hardwareIdentity() }
    catch { hardware = nil; hardwareError = String(describing: error) }
    let calibration = try hardware.flatMap { try calibrationStore.load(hardware: $0, serial: transport.identifier) }
    let calibrationDescription: String
    if let c = calibration {
        calibrationDescription = "Calibration: \(c.device.model) hardware \(c.device.hardwareVersion) [\(c.id)]"
    } else if let h = hardware {
        calibrationDescription = "No matching calibration for \(h.model) hardware \(h.hardwareVersion). Using generic RGB approximation."
    } else {
        calibrationDescription = "Hardware revision unavailable: \(hardwareError ?? "unknown error") Using generic RGB approximation."
    }
    func printCalibration() {
        print(calibrationDescription)
        if let c = calibration, let firmware = hardware?.firmwareVersion {
            print(c.testedFirmwareVersions.contains(firmware)
                ? "Firmware: \(firmware) (tested)"
                : "Firmware: \(firmware) (not listed as tested for this calibration)")
        }
    }
    let device = Lightstrip(transport: transport, state: savedState ?? DisplayState(), calibration: calibration)
    if command == .status {
        print("Connected LED zones: \(try device.zones())")
        printCalibration()
        if let state = savedState {
            print("Last CLI setting: \(state.isOn ? "on" : "off"), \(state.temperature) K requested, \(state.isOn ? state.brightness : 0)%")
            print("Remembered on brightness: \(state.brightness)%")
        } else { print("Last CLI setting: unknown. Run day, evening, or on to establish one.") }
        print("Saved settings, not measured LED output. Idle blanking, other controllers, or power loss may change the visible light.")
        return
    }
    switch command {
    case .on: try device.power(true)
    case .off: try device.power(false)
    case .toggle:
        guard savedState != nil else { throw CLIError("No previous CLI state for toggle. Run on, off, day, or evening first.") }
        try device.power(!device.state.isOn)
    case .brightness(let percent): try device.setBrightness(percent)
    case .brightnessStep(let delta): try device.stepBrightness(delta)
    case .temperatureStep(let delta): try device.stepTemperature(delta)
    case .temperature(let kelvin): try device.temperature(kelvin)
    case .profile(let name, _, _, _): try device.apply(selected!, name: name)
    case .help, .config, .status, .schedule: return
    }
    var remembered = device.state
    if manual { remembered.lastManualChange = Date() }
    do { try stateStore.save(remembered, device: transport.identifier) }
    catch { throw CLIError("Frame sent, but its restore state could not be saved: \(error)") }
    if case let .profile(name, _, _, save) = command, save {
        if name == "day" { config!.day = selected! } else { config!.evening = selected! }
        do { try store.save(config!) }
        catch { throw CLIError("Frame sent, but defaults could not be saved: \(error)") }
    }
    let state = device.state
    let colorLabel = calibration == nil ? "approximately \(state.temperature) K" : "\(state.temperature) K"
    print(state.isOn ? "On: \(colorLabel), \(state.brightness)%" : "Off")
    printCalibration()
    if case .profile(_, _, _, true) = command { print("Profile defaults saved.") }

}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "service" { try ServiceControl.run(Array(args.dropFirst())); return }
    let command = try Command.parse(args)
    if case .schedule = command { try execute(args); return }
    if command == .help || command == .config { try execute(args); return }
    if ServiceControl.isEnabled {
        let reply = try ServiceIPC.call(args)
        if !reply.output.isEmpty { print(reply.output) }
        if let error = reply.error { throw CLIError(error) }
        return
    }
    try execute(args)
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("nanoleaf: \(error)\n".utf8))
    exit(1)
}
