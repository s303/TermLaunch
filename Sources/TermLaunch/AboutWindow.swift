import AppKit

/// Old-school demo-scene About box: copper bars, starfield, a spinning
/// extruded vector "MIK" and a sine scroller.
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AboutWindowController()

    private let demo = DemoView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About TermLaunch"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        demo.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { demo.stop() }

    private func makeContent() -> NSView {
        func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .monospacedSystemFont(ofSize: size, weight: weight)
            field.textColor = color
            field.alignment = .center
            return field
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let green = NSColor(calibratedRed: 0.35, green: 1, blue: 0.45, alpha: 1)
        let licenseLink = ClickableLabel(string: "Third-party licenses (THIRD_PARTY_LICENSES.md)") {
            guard let url = Bundle.main.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md") else { return }
            NSWorkspace.shared.open(url)
        }
        let stack = NSStackView(views: [
            demo,
            label("TermLaunch", size: 20, weight: .bold, color: .white),
            label("vibecoded by Mik", size: 13, weight: .regular, color: green),
            label("Terminal engine: Ghostty (MIT)\n\u{00A9} 2024 Mitchell Hashimoto and Ghostty contributors",
                  size: 10, weight: .regular, color: NSColor(white: 0.8, alpha: 1)),
            licenseLink,
            label("v\(version)", size: 10, weight: .regular,
                  color: NSColor(white: 0.5, alpha: 1)),
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        stack.setCustomSpacing(14, after: demo)
        demo.widthAnchor.constraint(equalToConstant: 420).isActive = true
        demo.heightAnchor.constraint(equalToConstant: 240).isActive = true
        return stack
    }
}

private final class ClickableLabel: NSTextField {
    private let onClick: () -> Void

    init(string: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        attributedStringValue = NSAttributedString(string: string, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.5, green: 0.8, blue: 1, alpha: 1),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

private final class DemoView: NSView {
    private var timer: Timer?
    private var t: Double = 0
    private struct Star { var x, y, z: Double }
    private var stars: [Star] = (0..<90).map { _ in
        Star(x: .random(in: -1...1), y: .random(in: -1...1), z: .random(in: 0.05...1))
    }

    private let scroll = "   ***  TERMLAUNCH BY MIK  ***  CODED WITH CLAUDE BY ANTHROPIC  ***  "
        + "TERMINAL ENGINE: LIBGHOSTTY BY MITCHELL HASHIMOTO AND THE GHOSTTY CONTRIBUTORS  ***  "
        + "BUILT WITH SWIFT, APPKIT, CARBON, METAL AND CORE GRAPHICS  ***  "
        + "PROJECT GENERATED WITH XCODEGEN, GHOSTTY BUILT WITH ZIG  ***   "

    // Vector font: strokes on a 1x2 grid per glyph, laid out as "TERMLAUNCH".
    private static let glyphs: [Character: [(Double, Double, Double, Double)]] = [
        "T": [(0, 2, 1, 2), (0.5, 2, 0.5, 0)],
        "E": [(1, 2, 0, 2), (0, 2, 0, 0), (0, 0, 1, 0), (0, 1, 0.8, 1)],
        "R": [(0, 0, 0, 2), (0, 2, 1, 2), (1, 2, 1, 1), (1, 1, 0, 1), (0.3, 1, 1, 0)],
        "M": [(0, 0, 0, 2), (0, 2, 0.5, 1), (0.5, 1, 1, 2), (1, 2, 1, 0)],
        "L": [(0, 2, 0, 0), (0, 0, 1, 0)],
        "A": [(0, 0, 0.5, 2), (0.5, 2, 1, 0), (0.2, 0.8, 0.8, 0.8)],
        "U": [(0, 2, 0, 0), (0, 0, 1, 0), (1, 0, 1, 2)],
        "N": [(0, 0, 0, 2), (0, 2, 1, 0), (1, 0, 1, 2)],
        "C": [(1, 2, 0, 2), (0, 2, 0, 0), (0, 0, 1, 0)],
        "H": [(0, 0, 0, 2), (1, 0, 1, 2), (0, 1, 1, 1)],
    ]
    private static let logoWidth = Double("TERMLAUNCH".count - 1) * 1.4 + 1
    private let strokes: [(Double, Double, Double, Double)] = {
        var out: [(Double, Double, Double, Double)] = []
        for (i, ch) in "TERMLAUNCH".enumerated() {
            let dx = Double(i) * 1.4
            for g in glyphs[ch] ?? [] { out.append((g.0 + dx, g.1, g.2 + dx, g.3)) }
        }
        return out
    }()

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { true }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            self?.t += 1 / 60
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)

        // Copper bars: horizontal gradients bouncing on sines.
        for i in 0..<5 {
            let y = h / 2 + sin(t * 1.3 + Double(i) * 0.5) * (h * 0.32)
            let hue = (t * 0.1 + Double(i) * 0.04).truncatingRemainder(dividingBy: 1)
            let bar = CGRect(x: 0, y: y - 5, width: w, height: 10)
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor(hue: hue, saturation: 1, brightness: 0.1, alpha: 1).cgColor,
                NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).cgColor,
                NSColor(hue: hue, saturation: 1, brightness: 0.1, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 0.5, 1])!
            ctx.saveGState()
            ctx.clip(to: bar)
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: bar.minY), end: CGPoint(x: 0, y: bar.maxY), options: [])
            ctx.restoreGState()
        }

        // Starfield flying towards the viewer.
        for i in stars.indices {
            stars[i].z -= 0.006
            if stars[i].z <= 0.02 { stars[i] = Star(x: .random(in: -1...1), y: .random(in: -1...1), z: 1) }
            let s = stars[i]
            let px = w / 2 + s.x / s.z * w * 0.12 + 0
            let py = h / 2 + s.y / s.z * h * 0.12
            let b = 1 - s.z
            ctx.setFillColor(NSColor(white: 0.4 + 0.6 * b, alpha: 1).cgColor)
            let size = 1 + 2 * b
            ctx.fill(CGRect(x: px, y: py, width: size, height: size))
        }

        drawLogo(ctx, w: w, h: h)
        drawScroller(ctx, w: w, h: h)
    }

    private func drawLogo(_ ctx: CGContext, w: Double, h: Double) {
        let ay = sin(t * 0.9) * 1.1, ax = sin(t * 0.7) * 0.35, az = sin(t * 0.5) * 0.15
        let depth = 0.45
        let scale = 26.0
        func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            // centre the glyph block
            var px = (x - Self.logoWidth / 2), py = y - 1, pz = z
            (px, pz) = (px * cos(ay) + pz * sin(ay), -px * sin(ay) + pz * cos(ay))
            (py, pz) = (py * cos(ax) - pz * sin(ax), py * sin(ax) + pz * cos(ax))
            (px, py) = (px * cos(az) - py * sin(az), px * sin(az) + py * cos(az))
            let f = 6.0 / (6.0 + pz)
            return CGPoint(x: w / 2 + px * scale * f, y: h / 2 + py * scale * f)
        }
        ctx.setLineCap(.round)
        for pass in 0..<2 {
            // pass 0: soft glow, pass 1: crisp line
            ctx.setLineWidth(pass == 0 ? 5 : 1.8)
            for (i, s) in strokes.enumerated() {
                let hue = (t * 0.15 + Double(i) * 0.02).truncatingRemainder(dividingBy: 1)
                let color = NSColor(hue: hue, saturation: pass == 0 ? 1 : 0.35, brightness: 1,
                                    alpha: pass == 0 ? 0.25 : 1)
                ctx.setStrokeColor(color.cgColor)
                let a = project(s.0, s.1, -depth), b = project(s.2, s.3, -depth)
                let c = project(s.0, s.1, depth), d = project(s.2, s.3, depth)
                ctx.move(to: a); ctx.addLine(to: b)
                ctx.move(to: c); ctx.addLine(to: d)
                ctx.move(to: a); ctx.addLine(to: c)
                ctx.move(to: b); ctx.addLine(to: d)
                ctx.strokePath()
            }
        }
    }

    private func drawScroller(_ ctx: CGContext, w: Double, h: Double) {
        let font = NSFont.monospacedSystemFont(ofSize: 16, weight: .heavy)
        let charW = 12.0
        let total = Double(scroll.count) * charW
        let offset = (t * 90).truncatingRemainder(dividingBy: total)
        for (i, ch) in scroll.enumerated() {
            var x = Double(i) * charW - offset
            if x < -charW { x += total }
            if x > w { continue }
            let y = 14 + sin(x * 0.03 + t * 4) * 9
            let hue = (x / w * 0.5 + t * 0.2).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(hue: abs(hue), saturation: 0.7, brightness: 1, alpha: 1),
            ]
            NSAttributedString(string: String(ch), attributes: attrs).draw(at: CGPoint(x: x, y: y))
        }
    }
}
