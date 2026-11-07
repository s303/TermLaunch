import AppKit

/// The Dropdown: one borderless panel anchored to the top edge of the screen
/// under the mouse cursor, sized as a fraction of that screen.
@MainActor
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
    let chord = ChordController()
    var onCommandKey: ((String) -> Void)?
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

    var onTabShortcut: ((TabShortcut) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let shortcut = TabShortcut.from(event) else { return super.performKeyEquivalent(with: event) }
        onTabShortcut?(shortcut)
        return true
    }

    override func resignKey() {
        super.resignKey()
        if !ModalGuard.isActive { onResignKey?() }
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
            // AppKit calls the completion handler on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        }
    }

    /// When `show()` last ran, for ignoring the deactivation right after a Temporary console appears.
    private(set) var shownAt = Date.distantPast
    func show() {
        shownAt = Date()
        chord.reset()
        let frame = targetFrame(on: Self.screenUnderMouse())
        setFrame(frame, display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            animator().alphaValue = 1
        }
    }

    override func sendEvent(_ event: NSEvent) {
        switch chord.handle(event) {
        case .pass: super.sendEvent(event)
        case .swallow: break
        case .command(let key): onCommandKey?(key)
        }
    }

    /// Hides without the fade, for handing the content to the Window.
    func hideImmediately() {
        chord.reset()
        alphaValue = 0
        orderOut(nil)
    }

    func hide() {
        chord.reset() // keyUps for held keys won't reach us once hidden
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit calls the completion handler on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }

    private static func screenUnderMouse() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
