import AppKit

/// The Dropdown: one borderless panel anchored to the top edge of the screen
/// under the mouse cursor, sized as a fraction of that screen.
final class DropdownPanel: NSPanel {
    var columns = 120
    var rows = 30
    /// Supplies the active surface's cell size and padding (points), plus the tab bar height.
    var metrics: (() -> (cell: CGSize, padding: CGSize)?)?
    var barHeight: (() -> CGFloat)?
    var fadeDuration: TimeInterval = 0.12
    var edge = Edge.top

    // Chord window: after the Dropdown is shown, a Command key opens its command.
    // Any other key ends the window and is delivered to the terminal as usual.
    var commandKeys: Set<String> = []
    var chordWindow: TimeInterval = 0.3
    var onCommandKey: ((String) -> Void)?
    private var chordTimer: Timer?
    private var swallowedKeyCodes = Set<UInt16>()
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        alphaValue = 0
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// kVK_ANSI_1 … kVK_ANSI_9, in digit order.
    private static let digitKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    enum TabShortcut { case new, close, next, previous, select(Int) }
    var onTabShortcut: ((TabShortcut) -> Void)?

    /// ⌘T new, ⌘W close, ⌘⇧[ / ⌘⇧] cycle, ⌘1–9 jump.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        // Digit keys by physical key code, so non-US layouts (digits behind shift) work.
        if !shift, let slot = Self.digitKeyCodes.firstIndex(of: Int(event.keyCode)) {
            onTabShortcut?(.select(slot))
            return true
        }
        switch (chars, shift) {
        case ("t", false): onTabShortcut?(.new)
        case ("w", false): onTabShortcut?(.close)
        case ("[", _), ("{", _): onTabShortcut?(.previous)
        case ("]", _), ("}", _): onTabShortcut?(.next)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Set while a modal dialog (paste confirmation) owns focus, so losing key
    /// status doesn't hide the Dropdown out from under it.
    static var suppressHideOnResign = false

    override func resignKey() {
        super.resignKey()
        if !Self.suppressHideOnResign { onResignKey?() }
    }

    var isShown: Bool { isVisible && alphaValue > 0 }

    /// Frame for the configured grid on the given screen, clamped to the visible area.
    private func targetFrame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        var width = area.width * 0.5
        var height = area.height * 0.5 // until the first surface reports its cell size
        if let m = metrics?() {
            width = CGFloat(columns) * m.cell.width + m.padding.width
            height = CGFloat(rows) * m.cell.height + m.padding.height + (barHeight?() ?? 0)
        }
        width = min(width.rounded(), area.width)
        height = min(height.rounded(), area.height)
        switch edge {
        case .top: return NSRect(x: area.midX - width / 2, y: area.maxY - height, width: width, height: height)
        case .bottom: return NSRect(x: area.midX - width / 2, y: area.minY, width: width, height: height)
        case .left: return NSRect(x: area.minX, y: area.midY - height / 2, width: width, height: height)
        case .right: return NSRect(x: area.maxX - width, y: area.midY - height / 2, width: width, height: height)
        }
    }

    /// Recomputes the frame while visible (font size or tab bar changed).
    func relayout() {
        guard isVisible else { return }
        setFrame(targetFrame(on: screen ?? Self.screenUnderMouse()), display: true)
    }

    /// Creates the first surface early and hidden: surfaces are only created once
    /// their view has a real size, and the grid size needs the cell size.
    func warmUp() {
        setFrame(targetFrame(on: Self.screenUnderMouse()), display: false)
        alphaValue = 0
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.alphaValue == 0 else { return }
            self.orderOut(nil)
        }
    }

    /// When `show()` last ran, for ignoring the deactivation right after a Temporary console appears.
    private(set) var shownAt = Date.distantPast
    func show() {
        shownAt = Date()
        swallowedKeyCodes.removeAll()
        let frame = targetFrame(on: Self.screenUnderMouse())
        setFrame(frame, display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            animator().alphaValue = 1
        }
    }

    func beginChord() {
        endChord()
        guard !commandKeys.isEmpty, chordWindow > 0 else { return }
        chordTimer = Timer.scheduledTimer(withTimeInterval: chordWindow, repeats: false) { [weak self] _ in
            self?.chordTimer = nil
        }
    }

    private func endChord() {
        chordTimer?.invalidate()
        chordTimer = nil
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown where swallowedKeyCodes.contains(event.keyCode):
            // Auto-repeat of a Command key that already ran its command.
            return
        case .keyDown where chordTimer != nil:
            endChord()
            let blocking: NSEvent.ModifierFlags = [.command, .control, .option]
            // Match the physical key, like the Activation key, so non-US layouts work.
            if event.modifierFlags.isDisjoint(with: blocking),
               let key = KeySpec.name(forKeyCode: event.keyCode),
               commandKeys.contains(key) {
                swallowedKeyCodes.insert(event.keyCode)
                onCommandKey?(key)
                return
            }
        case .keyUp where swallowedKeyCodes.remove(event.keyCode) != nil:
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Hides without the fade, for handing the content to the Window.
    func hideImmediately() {
        endChord()
        swallowedKeyCodes.removeAll()
        alphaValue = 0
        orderOut(nil)
    }

    func hide() {
        endChord()
        swallowedKeyCodes.removeAll() // keyUps for these won't reach us once hidden
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.alphaValue == 0 else { return }
            self.orderOut(nil)
        })
    }

    private static func screenUnderMouse() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
