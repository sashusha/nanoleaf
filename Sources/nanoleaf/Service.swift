import Foundation
import Darwin
import IOKit.hid
import AppKit
import NanoleafCore

struct ServiceReply: Codable {
    var output: String
    var error: String?
}

enum ServiceIPC {
    static var directory: URL { ConfigStore().url.deletingLastPathComponent() }
    static var path: String { directory.appendingPathComponent("service.sock").path }

    static func address<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw CLIError("Home path is too long for the service socket.") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        return try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    static func configure(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
    static func readLine(_ fd: Int32) throws -> Data {
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while data.count < 16384 {
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { throw CLIError("Service connection closed or timed out.") }
            if let end = bytes.prefix(count).firstIndex(of: 10) { data.append(contentsOf: bytes[..<end]); return data }
            data.append(contentsOf: bytes.prefix(count))
        }
        throw CLIError("Service message is too large.")
    }
    static func send<T: Encodable>(_ value: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(value); data.append(10)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                guard count > 0 else { throw CLIError("Cannot send service message.") }
                offset += count
            }
        }
    }
    static func call(_ args: [String]) throws -> ServiceReply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError("Cannot create service connection.") }
        defer { close(fd) }
        configure(fd, seconds: 15)
        let result = try address { Darwin.connect(fd, $0, $1) }
        guard result == 0 else { throw CLIError("Service is enabled but unavailable. Run nanoleaf service status, or disable it for standalone use.") }
        try send(args, to: fd)
        return try JSONDecoder().decode(ServiceReply.self, from: readLine(fd))
    }
}

enum ServiceControl {
    static let label = "io.github.sashusha.nanoleaf"
    static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    static var domain: String { "gui/\(getuid())" }
    @discardableResult static func launchctl(_ args: [String], required: Bool = true) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = args
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if required && process.terminationStatus != 0 { throw CLIError("launchctl: \(output.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return output
    }
    static func stopIfLoaded() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "\(domain)/\(label)"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        if process.terminationStatus == 0 { try launchctl(["bootout", "\(domain)/\(label)"]) }
    }
    static var serviceApp: URL { ServiceIPC.directory.appendingPathComponent("Nanoleaf.app") }
    static func prepareServiceApp(executable: String) throws -> URL {
        let fm = FileManager.default
        let staging = ServiceIPC.directory.appendingPathComponent("Nanoleaf-" + UUID().uuidString + ".app")
        do {
            // Distributed app releases must retain the developer's signature,
            // resource seal, and notarization ticket across installation.
            if Bundle.main.bundleURL.pathExtension == "app" {
                try fm.copyItem(at: Bundle.main.bundleURL, to: staging)
                let verify = Process()
                verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                verify.arguments = ["--verify", "--strict", staging.path]
                let output = Pipe(); verify.standardOutput = output; verify.standardError = output
                try verify.run()
                let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                verify.waitUntilExit()
                guard verify.terminationStatus == 0 else { throw CLIError("Service app signature is invalid: \(message)") }
                return staging
            }
            let contents = staging.appendingPathComponent("Contents")
            let binary = contents.appendingPathComponent("MacOS/nanoleaf")
            try fm.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(atPath: executable, toPath: binary.path)
            let purpose = "Nanoleaf uses your approximate location to time the evening light transition at local sunset."
            let info: [String: Any] = ["CFBundleIdentifier": label, "CFBundleName": "Nanoleaf",
                "CFBundleExecutable": "nanoleaf", "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1", "LSUIElement": true,
                "NSLocationUsageDescription": purpose, "NSLocationWhenInUseUsageDescription": purpose]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", staging.path]
            let output = Pipe(); sign.standardOutput = output; sign.standardError = output
            try sign.run()
            let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            sign.waitUntilExit()
            guard sign.terminationStatus == 0 else { throw CLIError("Cannot prepare service app: \(message)") }
            return staging
        } catch { try? fm.removeItem(at: staging); throw error }
    }
    static func run(_ args: [String]) throws {
        guard args.count == 1 else { throw CLIError("Usage: nanoleaf service enable|disable|status") }
        switch args[0] {
        case "run": try BackgroundService().run()
        case "enable":
            guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { throw CLIError("Cannot locate this executable.") }
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ServiceIPC.directory, withIntermediateDirectories: true)
            let staging = try prepareServiceApp(executable: executable)
            defer { try? FileManager.default.removeItem(at: staging) }
            let serviceExecutable = serviceApp.appendingPathComponent("Contents/MacOS/nanoleaf").path
            let settings: [String: Any] = ["Label": label, "ProgramArguments": [serviceExecutable, "service", "run"],
                "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 30,
                "StandardErrorPath": ServiceIPC.directory.appendingPathComponent("service.log").path]
            let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            try stopIfLoaded()
            if FileManager.default.fileExists(atPath: serviceApp.path) { try FileManager.default.removeItem(at: serviceApp) }
            try FileManager.default.moveItem(at: staging, to: serviceApp)
            try data.write(to: plist, options: .atomic)
            try launchctl(["bootstrap", domain, plist.path])
            print("Service enabled and starts at login. Run nanoleaf service status to check the device, idle blanking, and keyboard shortcuts.")
        case "disable":
            try stopIfLoaded()
            if isEnabled { try FileManager.default.removeItem(at: plist) }
            print("Service disabled. Commands now run standalone; physical buttons return to device control after its online timeout.")
        case "status":
            guard isEnabled else { print("Service disabled."); return }
            print("Service enabled (starts at login).")
            let reply = try ServiceIPC.call(["__service_status"])
            print(reply.output)
            if let error = reply.error { throw CLIError(error) }
        default: throw CLIError("Usage: nanoleaf service enable|disable|status")
        }
    }
}

final class BackgroundService {
    private let systemLocation = SystemLocation()
    private let brightnessKeys = BrightnessKeys()
    private let brightnessOverlay = BrightnessOverlay()
    private var transport: HIDTransport?
    private var timer: Timer?
    private var retry: Timer?
    private var busy = false {
        didSet {
            if !busy { DispatchQueue.main.async { [weak self] in self?.updateIdleOutput() } }
        }
    }
    private var lastScheduleCheck = Date.distantPast
    private var idle = IdlePolicy()
    private var outputSuppressed: Bool?
    private var distributedObservers: [NSObjectProtocol] = []
    private var asleep = false
    private var reconnect = ReconnectPolicy()
    private var buttons: [ButtonAction] = []
    private var lastError: String?
    private var manager: IOHIDManager!
    private var observers: [NSObjectProtocol] = []
    private var socketFD: Int32 = -1
    private var lockFD: Int32 = -1

    private func log(_ error: Error) {
        let message = String(describing: error)
        if message != lastError { FileHandle.standardError.write(Data("nanoleaf service: \(message)\n".utf8)); lastError = message }
    }
    private func disconnect() {
        timer?.invalidate(); timer = nil
        retry?.invalidate(); retry = nil
        transport?.onButton = nil; transport = nil; buttons.removeAll(); outputSuppressed = nil
    }
    private func setIdle(_ reason: IdlePolicy.Reason, active: Bool) {
        idle.set(reason, active: active)
        updateIdleOutput()
    }
    private func blank(_ usb: HIDTransport) throws {
        // Temporary black frame: never overwrite the persisted restore state.
        try Lightstrip(transport: usb).power(false)
    }
    private func updateIdleOutput() {
        guard !busy, !asleep, let usb = transport, let applied = outputSuppressed,
              applied != idle.isSuppressed else { return }
        let suppress = idle.isSuppressed
        busy = true
        defer { busy = false }
        do {
            if suppress { try blank(usb) }
            else {
                let state = try StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json")).load(device: usb.identifier)
                try execute([reconnect.shouldTurnOn(savedState: state) ? "on" : "off"], transport: usb, manual: false, emit: { _ in })
                reconnect.didRestore()
            }
            outputSuppressed = suppress
        } catch {
            // Reconnect/retry on the existing error schedule, not a busy retry loop.
            log(error)
            disconnect()
            retry = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.reconcile() }
        }
    }
    private func reconcile() {
        guard !busy else { return }
        disconnect()
        guard !asleep else { return }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        reconnect.observeDevicePresence(!devices.isEmpty)
        guard !devices.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let usb = try HIDTransport()
            // Restore only after a successful state/config read through the regular command path.
            let state = try StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json")).load(device: usb.identifier)
            let suppress = idle.isSuppressed
            if suppress { try blank(usb) }
            else {
                try execute([reconnect.shouldTurnOn(savedState: state) ? "on" : "off"], transport: usb, manual: false, emit: { _ in })
                reconnect.didRestore()
            }
            transport = usb
            outputSuppressed = suppress
            usb.onButton = { [weak self] bytes in
                let actions = ButtonEvent.actions(bytes)
                guard !actions.isEmpty else { return }
                self?.buttons.append(contentsOf: actions)
                DispatchQueue.main.async { self?.drainButtons() }
            }
            lastError = nil
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.keepalive() }
            timer.tolerance = 0.2
            self.timer = timer
            RunLoop.main.add(timer, forMode: .default)
        } catch {
            log(error)
            // Retry contention/errors only while a matching device is present.
            retry = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.reconcile() }
        }
    }
    private func keepalive() {
        guard !busy, let usb = transport else { return }
        busy = true
        do { _ = try usb.request(0x06, payload: [], valueCount: 1) }
        catch { log(error); busy = false; reconcile(); return }
        busy = false
        drainButtons()
        updateSchedule()
    }
    private func updateSchedule() {
        let now = Date()
        guard !busy, !asleep, !idle.isSuppressed, let usb = transport,
              now.timeIntervalSince(lastScheduleCheck) >= 10 else { return }
        lastScheduleCheck = now
        busy = true
        defer { busy = false }
        do {
            let config = try ConfigStore().load()
            let store = StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json"))
            guard let state = try store.load(device: usb.identifier),
                  let location = systemLocation.location,
                  let target = SunsetSchedule.target(now: now, configuration: config, state: state, location: location) else { return }
            // Scheduling never turns an off strip on. Resume at the current point
            // after wake/reconnect; idle blanking continues to own the output.
            guard state.isOn else { return }
            guard state.temperature != target.temperature || state.brightness != target.brightness else { return }
            try execute(["evening", "--temp", String(target.temperature), "--brightness", String(target.brightness)],
                        transport: usb, manual: false, emit: { _ in })
        } catch { log(error) }
    }
    private func drainButtons() {
        guard !idle.isSuppressed else { buttons.removeAll(); return }
        guard !busy, let usb = transport else { return }
        while !buttons.isEmpty {
            let action = buttons.removeFirst(); busy = true
            do {
                let command: String
                if action == .power { command = "toggle" }
                else {
                    let state = try StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json")).load(device: usb.identifier)
                    command = (state ?? DisplayState()).nextProfile
                }
                try execute([command], transport: usb, emit: { _ in })
            }
            catch { log(error) }
            busy = false
        }
    }
    private func scheduleStatus() -> String {
        systemLocation.refresh()
        do {
            let config = try ConfigStore().load()
            var result = SunsetSchedule.summary(enabled: config.sunsetAutomation == true, now: Date(), location: systemLocation.location)
            if config.sunsetAutomation == true { result += "\n" + systemLocation.status }
            if config.sunsetAutomation == true, let usb = transport,
               let state = try StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json")).load(device: usb.identifier),
               let location = systemLocation.location,
               let window = SunsetSchedule.window(on: Date(), location: location),
               let manual = state.lastManualChange, manual >= window.start {
                result += " Manual override until tomorrow's sunset."
            }
            return result
        } catch { return "Sunset schedule unavailable: \(error)" }
    }
    private func handle(_ args: [String]) -> ServiceReply {
        if args == ["__schedule_status"] { return ServiceReply(output: scheduleStatus()) }
        if args == ["__service_status"] {
            brightnessKeys.start()
            let deviceStatus = transport == nil ? "Waiting for device.\(lastError.map { " Last error: \($0)" } ?? "")" : "Connected. Keepalive: 3 seconds. Physical power and day/evening mode handling active."
            return ServiceReply(output: deviceStatus + "\n" + (idle.isSuppressed ? "Idle blanking active; saved light settings preserved." : "Screensaver/display-sleep blanking ready.") + "\n" + brightnessKeys.status + "\n" + scheduleStatus())
        }
        guard !busy else { return ServiceReply(output: "", error: "Device is busy; retry the command.") }
        var lines: [String] = []
        busy = true
        defer { busy = false; DispatchQueue.main.async { self.drainButtons() } }
        do {
            let command = try Command.parse(args)
            if idle.isSuppressed && command != .status && command != .off {
                throw CLIError("Idle blanking is active. Dismiss the screensaver and wake the display before adjusting the light; off and status remain available.")
            }
            guard command != .help && command != .config else { throw CLIError("Use help and config directly.") }
            guard let usb = transport else { throw CLIError("Lightstrip unavailable. Check USB connection and service status.") }
            try execute(args, transport: usb, emit: { lines.append($0) })
            return ServiceReply(output: lines.joined(separator: "\n"))
        } catch { return ServiceReply(output: lines.joined(separator: "\n"), error: String(describing: error)) }
    }
    func run() throws {
        try FileManager.default.createDirectory(at: ServiceIPC.directory, withIntermediateDirectories: true)
        lockFD = open(ServiceIPC.directory.appendingPathComponent(".service-lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw CLIError("Another service is running.") }
        defer { if lockFD >= 0 { close(lockFD) } }
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw CLIError("Cannot create service socket.") }
        defer { close(socketFD); unlink(ServiceIPC.path) }
        unlink(ServiceIPC.path)
        let previousMask = umask(0o077)
        let bound = try ServiceIPC.address { Darwin.bind(socketFD, $0, $1) }
        umask(previousMask)
        guard bound == 0, listen(socketFD, 8) == 0 else { throw CLIError("Cannot listen on service socket.") }
        DispatchQueue(label: "nanoleaf.clients").async { [self] in
            while true {
                let client = accept(socketFD, nil, nil)
                if client < 0 { return }
                ServiceIPC.configure(client, seconds: 3)
                do {
                    var uid: uid_t = 0; var gid: gid_t = 0
                    guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { throw CLIError("Unauthorized local client.") }
                    let args = try JSONDecoder().decode([String].self, from: ServiceIPC.readLine(client))
                    let done = DispatchSemaphore(value: 0)
                    var reply = ServiceReply(output: "")
                    DispatchQueue.main.async { reply = self.handle(args); done.signal() }
                    done.wait()
                    try ServiceIPC.send(reply, to: client)
                } catch { try? ServiceIPC.send(ServiceReply(output: "", error: String(describing: error)), to: client) }
                close(client)
            }
        }
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x37FA, kIOHIDProductIDKey: 0x8202] as CFDictionary)
        let changed: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let service = Unmanaged<BackgroundService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.reconcile() }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, changed, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, changed, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // AppKit must process application events for display sleep/wake delivery.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        systemLocation.start()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [self] _ in setIdle(.systemSleep, active: true); asleep = true; disconnect() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [self] _ in asleep = false; idle.set(.systemSleep, active: false); reconcile() })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [self] _ in setIdle(.displaySleep, active: true) })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [self] _ in setIdle(.displaySleep, active: false) })
        let distributed = DistributedNotificationCenter.default()
        for (name, active) in [("com.apple.screensaver.didstart", true), ("com.apple.screensaver.didstop", false)] {
            distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [self] _ in setIdle(.screensaver, active: active) })
        }
        brightnessKeys.onStep = { [weak self] delta, temperature in
            guard let self else { return }
            let reply = self.handle([temperature ? "temp" : "brightness", delta > 0 ? "up" : "down"])
            if let error = reply.error {
                self.log(CLIError(error))
                self.brightnessOverlay.show(message: self.transport == nil ? "Disconnected" : "Couldn’t adjust")
            } else if let usb = self.transport {
                do {
                    let state = try StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json")).load(device: usb.identifier)
                    if let state {
                        if temperature { self.brightnessOverlay.show(temperature: state.temperature) }
                        else { self.brightnessOverlay.show(brightness: state.isOn ? state.brightness : 0) }
                    }
                } catch {
                    self.log(error)
                    self.brightnessOverlay.show(message: "State unavailable")
                }
            }
        }
        brightnessKeys.start()
        reconcile()
        app.run()
    }
}
