import AppKit

private final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TemperatureBar: NSView {
    var kelvin = 4000 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0, dy: 3)
        NSGradient(starting: .systemOrange, ending: .systemBlue)?.draw(in: NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3), angle: 0)
        let fraction = CGFloat(max(2700, min(6500, kelvin)) - 2700) / 3800
        let marker = NSRect(x: 2 + fraction * (bounds.width - 8), y: 0, width: 4, height: bounds.height)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: marker, xRadius: 2, yRadius: 2).fill()
    }
}

/// A passive indicator, created only when a keyboard adjustment needs feedback.
final class BrightnessOverlay {
    private var panel: IndicatorPanel?
    private let value = NSTextField(labelWithString: "")
    private let temperatureBar = TemperatureBar()
    private let bar = NSProgressIndicator()
    private var dismissal: Timer?
    private var generation = 0

    private func makePanel() -> IndicatorPanel {
        let panel = IndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 86),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let bounds = NSRect(x: 0, y: 0, width: 260, height: 86)
        let content: NSView
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .clear
            glass.cornerRadius = 18
            let container = NSView(frame: bounds)
            glass.contentView = container
            content = container
            background = glass
        } else {
            let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 86))
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            // Mask the system material itself, including its window shadow. Layer
            // corner clipping alone does not shape the behind-window backdrop.
            let radius: CGFloat = 18
            let maskSize = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
            let mask = NSImage(size: maskSize, flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            mask.resizingMode = .stretch
            glass.maskImage = mask
            content = glass
            background = glass
        }
        let title = NSTextField(labelWithString: "Nanoleaf")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.frame = NSRect(x: 20, y: 48, width: 100, height: 19)
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        value.alignment = .right
        value.frame = NSRect(x: 112, y: 48, width: 128, height: 19)
        bar.isIndeterminate = false
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 100
        bar.frame = NSRect(x: 20, y: 22, width: 220, height: 12)
        content.addSubview(title)
        content.addSubview(value)
        content.addSubview(bar)
        temperatureBar.frame = bar.frame
        temperatureBar.isHidden = true
        content.addSubview(temperatureBar)
        panel.contentView = background
        return panel
    }

    func show(brightness: Int? = nil, temperature: Int? = nil, message: String? = nil) {
        if panel == nil { panel = makePanel() }
        guard let panel,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        generation += 1
        let current = generation
        dismissal?.invalidate()
        let percent = max(0, min(100, brightness ?? 0))
        value.stringValue = message ?? temperature.map { "\($0) K" } ?? "\(percent)%"
        temperatureBar.isHidden = temperature == nil
        if let temperature { temperatureBar.kelvin = temperature }
        bar.isHidden = brightness == nil
        bar.doubleValue = Double(percent)
        let area = screen.frame
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        dismissal = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
            guard let self, self.generation == current else { return }
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard self?.generation == current else { return }
                panel.orderOut(nil)
            }
        }
    }
}
