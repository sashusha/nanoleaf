import AppKit
import NanoleafCore

/// Intercepts only the chosen media-key chord; USB work runs outside the tap callback.
final class BrightnessKeys {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var captured = Set<Int>()
    private var capturedFunctions = Set<UInt16>()
    var onStep: ((Int, Bool) -> Void)?
    var status: String {
        tap == nil ? "Keyboard shortcuts unavailable. Allow nanoleaf in System Settings > Privacy & Security > Accessibility, then run nanoleaf service status." : "Shift + Brightness Up/Down active (5 percentage points). F18/F19: warmer/cooler by 100 K."
    }

    func start() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                listener.captured.removeAll()
                listener.capturedFunctions.removeAll()
                if let tap = listener.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let key = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
            if key.type == .keyDown || key.type == .keyUp {
                guard key.keyCode == 79 || key.keyCode == 80 else { return Unmanaged.passUnretained(event) }
                if key.type == .keyUp {
                    return listener.capturedFunctions.remove(key.keyCode) != nil ? nil : Unmanaged.passUnretained(event)
                }
                // Function-key events include the .function flag even without Fn held.
                let modifiers = key.modifierFlags.intersection([.shift, .control, .option, .command])
                guard modifiers.isEmpty else { return Unmanaged.passUnretained(event) }
                listener.capturedFunctions.insert(key.keyCode)
                let delta = key.keyCode == 79 ? -100 : 100
                DispatchQueue.main.async { listener.onStep?(delta, true) }
                return nil
            }
            guard key.type == .systemDefined, key.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            let code = (key.data1 >> 16) & 0xffff
            guard [2, 3].contains(code) else { return Unmanaged.passUnretained(event) }
            let phase = (key.data1 >> 8) & 0xff
            if phase == 0x0b {
                if listener.captured.remove(code) != nil { return nil }
                return Unmanaged.passUnretained(event)
            }
            guard phase == 0x0a else { return Unmanaged.passUnretained(event) }
            let modifiers = key.modifierFlags.intersection([.shift, .control, .option, .command, .function])
            guard modifiers == .shift else { return Unmanaged.passUnretained(event) }
            listener.captured.insert(code)
            let delta = code == 2 ? 5 : -5
            DispatchQueue.main.async { listener.onStep?(delta, false) }
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: (CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue) |
                (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
