import AppKit

/// Window mode's normal window. It hosts the same content view as the Dropdown;
/// closing it leaves Window mode rather than closing anything.
final class TermWindow: NSWindow, NSWindowDelegate {
    var onCloseRequested: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?
    var onTabShortcut: ((TabShortcut) -> Void)?

    // Chord window: after the Activation key, a Command key runs its command in the Window.
    // Any other key ends the window and is delivered to the terminal as usual.
    var commandKeys: Set<String> = []
    var chordWindow: TimeInterval = 0.3
    var onCommandKey: ((String) -> Void)?
    private var chordTimer: Timer?
    private var swallowedKeyCodes = Set<UInt16>()

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
            return
        case .keyDown where chordTimer != nil:
            endChord()
            let blocking: NSEvent.ModifierFlags = [.command, .control, .option]
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

    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChanged?(false) }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChanged?(true) }
}
