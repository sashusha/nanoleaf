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
    static func run(_ args: [String]) throws {
        guard args.count == 1 else { throw CLIError("Usage: nanoleaf service enable|disable|status") }
        switch args[0] {
        case "run": try BackgroundService().run()
        case "enable":
            guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { throw CLIError("Cannot locate this executable.") }
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ServiceIPC.directory, withIntermediateDirectories: true)
            let settings: [String: Any] = ["Label": label, "ProgramArguments": [executable, "service", "run"],
                "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 30,
                "StandardErrorPath": ServiceIPC.directory.appendingPathComponent("service.log").path]
            let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            try stopIfLoaded()
            try data.write(to: plist, options: .atomic)
            try launchctl(["bootstrap", domain, plist.path])
            print("Service enabled and starts at login. Physical power restores saved CLI settings.")
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
    private var transport: HIDTransport?
    private var timer: Timer?
    private var retry: Timer?
    private var busy = false
    private var asleep = false
    private var buttons = 0
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
        transport?.onButton = nil; transport = nil; buttons = 0
    }
    private func reconcile() {
        guard !busy else { return }
        disconnect()
        guard !asleep else { return }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let usb = try HIDTransport()
            // Restore only after a successful state/config read through the regular command path.
            let state = try StateStore(url: ServiceIPC.directory.appendingPathComponent("state.json")).load(device: usb.identifier)
            try execute([state?.isOn == true ? "on" : "off"], transport: usb, emit: { _ in })
            transport = usb
            usb.onButton = { [weak self] bytes in
                guard ButtonEvent.isPowerPress(bytes) else { return }
                self?.buttons += 1
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
    }
    private func drainButtons() {
        guard !busy, let usb = transport else { return }
        while buttons > 0 {
            buttons -= 1; busy = true
            do { try execute(["toggle"], transport: usb, emit: { _ in }) }
            catch { log(error) }
            busy = false
        }
    }
    private func handle(_ args: [String]) -> ServiceReply {
        if args == ["__service_status"] {
            return ServiceReply(output: transport == nil ? "Waiting for device.\(lastError.map { " Last error: \($0)" } ?? "")" : "Connected. Keepalive: 3 seconds. Physical power handling active.")
        }
        guard !busy else { return ServiceReply(output: "", error: "Device is busy; retry the command.") }
        var lines: [String] = []
        busy = true
        defer { busy = false; DispatchQueue.main.async { self.drainButtons() } }
        do {
            let command = try Command.parse(args)
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
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [self] _ in asleep = true; disconnect() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [self] _ in asleep = false; reconcile() })
        reconcile()
        // HID replies may stop a nested run loop; return to waiting without periodic polling.
        while true { CFRunLoopRun() }
    }
}
