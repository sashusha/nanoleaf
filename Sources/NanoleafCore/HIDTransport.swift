import Foundation
import IOKit.hid

private final class Inbox {
    var expected: UInt8 = 0
    var report: [UInt8]?
    var failure: IOReturn?
}

private let receive: IOHIDReportCallback = { context, result, _, _, _, bytes, count in
    guard let context else { return }
    let inbox = Unmanaged<Inbox>.fromOpaque(context).takeUnretainedValue()
    guard result == kIOReturnSuccess else { inbox.failure = result; return }
    guard count > 0, bytes[0] == inbox.expected else { return }
    inbox.report = Array(UnsafeBufferPointer(start: bytes, count: count))
}

public final class HIDTransport: Transport {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let inbox = Inbox()
    private let buffer: UnsafeMutablePointer<UInt8>
    private let runLoop: CFRunLoop
    private let reportSize: Int

    public var identifier: String {
        (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String) ?? "37FA-8202"
    }

    public func hardwareIdentity() throws -> HardwareIdentity {
        let modelBytes = try request(0x0C, payload: [], valueCount: 6)
        let revision = try request(0x0B, payload: [], valueCount: 2)
        guard let model = String(bytes: modelBytes, encoding: .ascii),
              revision.count == 2, revision.allSatisfy({ (48...57).contains($0) }) else {
            throw CLIError("Device returned an unrecognized model or hardware revision.")
        }
        let firmwareBytes = try? request(0x0A, payload: [], valueCount: 1)
        let firmware = firmwareBytes?.first.map { "\($0 >> 4).\($0 & 15).0" }
        return HardwareIdentity(model: model, hardwareVersion: "\(revision[0] - 48).\(revision[1] - 48).0", firmwareVersion: firmware)
    }

    public init() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x37FA, kIOHIDProductIDKey: 0x8202] as CFDictionary)
        // Enumeration does not require opening every matching HID device.
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            throw CLIError("Nanoleaf lightstrip not found (USB 37FA:8202). Check its USB connection.")
        }
        guard devices.count == 1, let device = devices.first else {
            throw CLIError("Multiple Nanoleaf lightstrips found; connect only the one you want to control.")
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            throw CLIError("Cannot open Nanoleaf USB device (\(String(format: "0x%08X", result))). Quit Nanoleaf Desktop or any other USB lighting controller and retry.")
        }
        self.manager = manager; self.device = device
        reportSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64
        let inputSize = max(64, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64)
        buffer = .allocate(capacity: inputSize)
        runLoop = CFRunLoopGetCurrent()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, inputSize, receive, Unmanaged.passUnretained(inbox).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }
    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 0, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        IOHIDManagerClose(manager, 0)
        buffer.deallocate()
    }
    public func request(_ command: UInt8, payload: [UInt8], valueCount: Int) throws -> [UInt8] {
        inbox.expected = command | 0x80; inbox.report = nil; inbox.failure = nil
        for report in try Wire.reports(command: command, payload: payload, size: reportSize) {
            let result = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, report.count)
            }
            guard result == kIOReturnSuccess else {
                throw CLIError("USB write failed (\(String(format: "0x%08X", result))). Check the connection.")
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let code = inbox.failure { throw CLIError("USB read failed (\(code)).") }
            if let bytes = inbox.report { return try Wire.response(bytes, command: command, valueCount: valueCount) }
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        throw CLIError("Timed out waiting for Nanoleaf command \(String(format: "0x%02X", command)). Check the connection and quit other lighting apps.")
    }
}
