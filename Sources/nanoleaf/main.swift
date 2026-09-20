import Foundation
import Darwin
import NanoleafCore

let help = """
Usage: nanoleaf <command>

Commands:
  on                     Restore remembered color and nonzero brightness
  off                    Display black; keep remembered settings for on
  toggle                 Switch the saved CLI on/off state; requires prior state
  brightness <0-100>     Set integer brightness; positive turns on, zero blanks
  temp <2700-6500>       Set integer Kelvin; turn on at remembered brightness
  day [options]          Apply saved day defaults (initially 4800 K, 30%)
  evening [options]      Apply saved evening defaults (initially 3500 K, 30%)
  config                 Show profile defaults and their file path; no device needed
  status                 Show last CLI setting and connected LED zone count
  service enable|disable|status  Manage optional background control
  help | --help | -h     Show this help; no arguments also shows help

Options for day/evening only (use a space before each value):
  --temp <2700-6500>     Override this run's temperature
  --brightness <0-100>  Override this run's brightness
  --save                 Apply and save the resulting defaults for that profile
                         Unspecified values come from the saved profile.

Remembered settings:
  off and brightness 0 preserve the last nonzero brightness for on.
  A zero-brightness profile also remembers its requested temperature.
  Without prior state, remembered settings start at 4800 K and 30%,
  independently of saved day/evening defaults. toggle requires prior CLI state.
  One-time overrides update remembered settings but not profile defaults.

Files under ~/Library/Application Support/nanoleaf/:
  config.json            Saved day/evening defaults
  state.json             Last CLI settings per device
  calibration.json       Optional hardware calibration override

status and toggle use saved CLI state, not measured LED state. Buttons, other
controllers, and power loss can make it stale. Light commands and status require
a connected device. Quit other lighting controllers before use.
Calibration matches model and hardware revision exactly; status shows the match.
Without a match, temperature uses approximate RGB white.
Matching Desktop does not establish instrument-measured color temperature.
No Nanoleaf Desktop, pairing, or network connection is required.
Optional service: starts at login, keeps USB online every 3 seconds, and handles
physical power presses using saved CLI settings. Normal commands route through
it. Stops USB traffic when disconnected or asleep. Scene presses are ignored.
Disable the service before using another lighting controller.

Examples:
  nanoleaf day
  nanoleaf evening --brightness 20
  nanoleaf day --temp 5000 --brightness 35 --save
  nanoleaf off
  nanoleaf on
"""

func execute(_ args: [String], transport supplied: HIDTransport? = nil, emit: (String) -> Void = { Swift.print($0) }) throws {
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
    if command == .config {
        let config = try store.load()
        print("day:     \(config.day.temperature) K, \(config.day.brightness)%")
        print("evening: \(config.evening.temperature) K, \(config.evening.brightness)%")
        print("Config: \(store.url.path)")
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
            print("Last CLI setting: \(state.isOn ? "on" : "off"), approximately \(state.temperature) K, \(state.isOn ? state.brightness : 0)%")
            print("Remembered on brightness: \(state.brightness)%")
        } else { print("Last CLI setting: unknown. Run day, evening, or on to establish one.") }
        print("This is saved command state, not a measurement of the LEDs. Other apps, buttons, or a power cycle can change them.")
        return
    }
    switch command {
    case .on: try device.power(true)
    case .off: try device.power(false)
    case .toggle:
        guard savedState != nil else { throw CLIError("No previous CLI state for toggle. Run on, off, day, or evening first.") }
        try device.power(!device.state.isOn)
    case .brightness(let percent): try device.setBrightness(percent)
    case .temperature(let kelvin): try device.temperature(kelvin)
    case .profile: try device.apply(selected!)
    case .help, .config, .status: return
    }
    do { try stateStore.save(device.state, device: transport.identifier) }
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
