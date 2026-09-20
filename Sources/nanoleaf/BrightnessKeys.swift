import AppKit
import NanoleafCore

/// Intercepts only the chosen media-key chord; USB work runs outside the tap callback.
final class BrightnessKeys {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var captured = Set<Int>()
    var onStep: ((Int) -> Void)?
    var status: String {
        tap == nil ? "Keyboard shortcuts unavailable. Allow nanoleaf in System Settings > Privacy & Security > Accessibility, then run nanoleaf service status." : "Shift + Brightness Up/Down active (5 percentage points)."
    }

    func start() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                listener.captured.removeAll()
                if let tap = listener.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let key = NSEvent(cgEvent: event), key.type == .systemDefined,
                  key.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            let code = (key.data1 >> 16) & 0xffff
            guard code == 2 || code == 3 else { return Unmanaged.passUnretained(event) }
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
            DispatchQueue.main.async { listener.onStep?(delta) }
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
