import AppKit

/// Window mode's normal window. It hosts the same content view as the Dropdown;
/// closing it leaves Window mode rather than closing anything.
final class TermWindow: NSWindow, NSWindowDelegate {
    var onCloseRequested: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "TermLaunch"
        isReleasedWhenClosed = false
        backgroundColor = .black
        delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Defer: closing moves the content view out of this window.
        DispatchQueue.main.async { [weak self] in self?.onCloseRequested?() }
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChanged?(false) }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChanged?(true) }
}
