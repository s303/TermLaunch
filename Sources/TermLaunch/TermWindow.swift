import AppKit

/// Window mode's normal window. It hosts the same content view as the Dropdown;
/// closing it leaves Window mode rather than closing anything.
@MainActor
final class TermWindow: NSWindow, NSWindowDelegate {
    var onCloseRequested: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?
    var onTabShortcut: ((TabShortcut) -> Void)?

    // Chord window: after the Activation key, a Command key runs its command in the Window.
    // Any other key ends the window and is delivered to the terminal as usual.
    let chord = ChordController()
    var onCommandKey: ((String) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        switch chord.handle(event) {
        case .pass: super.sendEvent(event)
        case .swallow: break
        case .command(let key): onCommandKey?(key)
        }
    }

    init(background: NSColor) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "TermLaunch"
        isReleasedWhenClosed = false
        backgroundColor = background
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        delegate = self
    }

    // ⌘1–9 and the other Tab shortcuts work here without menu items, as in the Dropdown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let shortcut = TabShortcut.from(event) else { return super.performKeyEquivalent(with: event) }
        onTabShortcut?(shortcut)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Defer: closing moves the content view out of this window.
        DispatchQueue.main.async { [weak self] in self?.onCloseRequested?() }
        return false
    }

    /// Held keys' keyUps go elsewhere once we lose key status (Temporary console, leaving
    /// Window mode, another app); forget them or the next press of that key is swallowed.
    func windowDidResignKey(_ notification: Notification) { chord.reset() }

    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChanged?(false) }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChanged?(true) }
}
