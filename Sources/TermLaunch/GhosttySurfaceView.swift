import AppKit
import GhosttyKit

/// One terminal surface. All terminals stay mounted (toggle opacity/focus)
/// rather than being re-hosted, to avoid Metal drawable flicker.
final class GhosttySurfaceView: NSView, NSTextInputClient {
    private let ghostty: GhosttyApp
    private let command: String?
    private let workingDirectory: String?
    /// Command Tabs: file the wrapper writes the real exit code to.
    let exitFilePath: String?
    private let waitAfterCommand: Bool
    private(set) var surface: ghostty_surface_t? { didSet { handle.surface = surface } }
    private let handle: SurfaceHandle
    private var surfaceAttempted = false
    var onClose: (() -> Void)?
    var onTitle: ((String) -> Void)?
    /// Cell size changed (font size change, display scale change).
    var onCellSize: (() -> Void)?
    /// Command exited 0: the owner closes the Tab.
    var onSuccessfulExit: (() -> Void)?

    // strdup'd buffers must outlive surface creation.
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var trackingArea: NSTrackingArea?
    private var cCommand: UnsafeMutablePointer<CChar>?
    private var cWorkingDirectory: UnsafeMutablePointer<CChar>?

    init(
        ghostty: GhosttyApp,
        command: String? = nil,
        workingDirectory: String? = nil,
        exitFilePath: String? = nil,
        waitAfterCommand: Bool = false
    ) {
        self.ghostty = ghostty
        self.command = command
        self.workingDirectory = workingDirectory
        self.exitFilePath = exitFilePath
        self.waitAfterCommand = waitAfterCommand
        handle = SurfaceHandle(exitFilePath: exitFilePath)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        handle.view = self
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        // The one place the surface is freed. Clear the handle first so callbacks
        // already in flight see no surface.
        handle.surface = nil
        if let surface { ghostty_surface_free(surface) }
        free(cCommand)
        free(cWorkingDirectory)
        if let exitFilePath { try? FileManager.default.removeItem(atPath: exitFilePath) }
    }

    override var acceptsFirstResponder: Bool { true }

    /// Inactive Tabs stay mounted at zero opacity; they must not take clicks or scrolls.
    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue == 0 ? nil : super.hitTest(point)
    }

    // MARK: Surface lifecycle

    /// A surface created at zero size renders blank, so wait for a real frame.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !surfaceAttempted, newSize.width > 0, newSize.height > 0, window != nil {
            createSurface()
        }
        syncSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !surfaceAttempted, window != nil, frame.width > 0, frame.height > 0 {
            createSurface()
        }
        syncSize()
    }

    private func createSurface() {
        guard let app = ghostty.app else { return }
        surfaceAttempted = true // one attempt: a retry per layout pass would leak the strdup'd strings
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        cfg.userdata = Unmanaged.passUnretained(handle).toOpaque()
        cfg.scale_factor = Double(window?.backingScaleFactor ?? 2)
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        cfg.wait_after_command = waitAfterCommand
        if let command { cCommand = strdup(command); cfg.command = UnsafePointer(cCommand) }
        if let workingDirectory {
            cWorkingDirectory = strdup(workingDirectory)
            cfg.working_directory = UnsafePointer(cWorkingDirectory)
        }
        surface = ghostty_surface_new(app, &cfg)
        if surface == nil {
            // A Tab without a surface would be blank and unclosable.
            NSLog("TermLaunch: ghostty_surface_new failed; closing the Tab")
            DispatchQueue.main.async { [weak self] in self?.onClose?() }
        }
    }

    private func syncSize() {
        guard let surface else { return }
        let backing = convertToBacking(bounds.size)
        let scale = window?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
    }

    /// Cell size and non-grid padding in points, or nil before the surface exists.
    func cellMetrics() -> (cell: CGSize, padding: CGSize)? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.cell_width_px > 0, size.cell_height_px > 0 else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        let cw = CGFloat(size.cell_width_px), ch = CGFloat(size.cell_height_px)
        let padW = CGFloat(size.width_px) - CGFloat(size.columns) * cw
        let padH = CGFloat(size.height_px) - CGFloat(size.rows) * ch
        return (CGSize(width: cw / scale, height: ch / scale),
                CGSize(width: max(padW, 0) / scale, height: max(padH, 0) / scale))
    }

    #if DEBUG
    var debugGrid: (columns: Int, rows: Int)? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        return (Int(size.columns), Int(size.rows))
    }
    #endif

    func setFocused(_ focused: Bool) {
        if let surface { ghostty_surface_set_focus(surface, focused) }
    }

    func setOccluded(_ occluded: Bool) {
        if let surface { ghostty_surface_set_occlusion(surface, !occluded) }
    }

    func surfaceDidClose() {
        onClose?()
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard surface != nil else { return }
        keyTextAccumulator = []
        let hadMarked = markedText.length > 0
        // Routes through the input method; results arrive via insertText/setMarkedText.
        interpretKeyEvents([event])
        syncPreedit(clearIfNeeded: hadMarked)

        let texts = keyTextAccumulator ?? []
        keyTextAccumulator = nil
        if texts.isEmpty {
            sendKey(event, action: GHOSTTY_ACTION_PRESS, text: Self.text(for: event),
                    composing: markedText.length > 0 || hadMarked)
        } else {
            for text in texts {
                sendKey(event, action: GHOSTTY_ACTION_PRESS, text: text, composing: false)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKey(event, action: GHOSTTY_ACTION_RELEASE, text: nil, composing: false)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier-only transitions: press if the modifier is now down, else release.
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 56, 60: flag = .shift
        case 59, 62: flag = .control
        case 58, 61: flag = .option
        case 55, 54: flag = .command
        case 57: flag = .capsLock
        default: return
        }
        let down = event.modifierFlags.contains(flag)
        sendKey(event, action: down ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE, text: nil, composing: false)
    }

    private func sendKey(_ event: NSEvent, action: ghostty_input_action_e, text: String?, composing: Bool) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = event.isARepeat && action == GHOSTTY_ACTION_PRESS ? GHOSTTY_ACTION_REPEAT : action
        key.keycode = UInt32(event.keyCode)
        key.mods = Self.mods(event.modifierFlags)
        // Mods that went into producing `text` (e.g. shift for capitals) are consumed.
        key.consumed_mods = text == nil ? GHOSTTY_MODS_NONE
            : Self.mods(event.modifierFlags.subtracting([.control, .command]))
        key.composing = composing
        key.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp,
           let ch = event.characters(byApplyingModifiers: [])?.unicodeScalars.first {
            key.unshifted_codepoint = ch.value
        }
        if let text {
            text.withCString { ptr in
                key.text = ptr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            key.text = nil
            _ = ghostty_surface_key(surface, key)
        }
    }

    /// Text to send for a key event, or nil for control characters and
    /// function keys (libghostty encodes those from the key code).
    private static func text(for event: NSEvent) -> String? {
        guard let chars = event.characters, let scalar = chars.unicodeScalars.first else { return nil }
        if scalar.value < 0x20 || scalar.value == 0x7F { return nil }
        if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        return chars
    }

    /// ⌘C/⌘V/⌘A/⌘K and font size, routed to libghostty's own actions.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Every tab's view stays in the hierarchy, so AppKit offers the key to
        // all of them; only the focused one may act on it.
        guard let surface, window?.firstResponder === self,
              let action = TerminalShortcut.action(for: event) else { return false }
        _ = action.withCString { ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }
        return true
    }

    private static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw: UInt32 = 0
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    // MARK: Mouse

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func sendMousePos(_ event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        // Ghostty's origin is top-left.
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, Self.mods(event.modifierFlags))
    }

    private func sendMouseButton(_ event: NSEvent, state: ghostty_input_mouse_state_e, button: ghostty_input_mouse_button_e) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, state, button, Self.mods(event.modifierFlags))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMousePos(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMousePos(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        sendMousePos(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMousePos(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        sendMousePos(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_MIDDLE)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        sendMousePos(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_MIDDLE)
    }

    override func mouseMoved(with event: NSEvent) { sendMousePos(event) }
    override func mouseDragged(with event: NSEvent) { sendMousePos(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMousePos(event) }
    override func otherMouseDragged(with event: NSEvent) { sendMousePos(event) }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        // Negative position tells libghostty the cursor left the surface.
        ghostty_surface_mouse_pos(surface, -1, -1, Self.mods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }
        // Packed: bit 0 precision, bits 1-3 momentum phase.
        var mods: Int32 = precision ? 1 : 0
        mods |= Self.momentum(event.momentumPhase) << 1
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    private static func momentum(_ phase: NSEvent.Phase) -> Int32 {
        switch phase {
        case .began: return 1
        case .stationary: return 2
        case .changed: return 3
        case .ended: return 4
        case .cancelled: return 5
        case .mayBegin: return 6
        default: return 0
        }
    }

    // MARK: Input method (IME / dead keys)

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let text = markedText.string
            text.withCString { ghostty_surface_preedit(surface, $0, UInt(text.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func hasMarkedText() -> Bool { markedText.length > 0 }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let s as NSAttributedString: markedText = NSMutableAttributedString(attributedString: s)
        case let s as String: markedText = NSMutableAttributedString(string: s)
        default: return
        }
        // Outside a key event (e.g. input source switch) there's no keyDown to sync.
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x = 0.0, y = 0.0, w = 0.0, h = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        // Ghostty reports from the top-left; AppKit wants bottom-left.
        let viewRect = NSRect(x: x, y: frame.height - y - h, width: max(w, 1), height: max(h, 1))
        return window.convertToScreen(convert(viewRect, to: nil))
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        switch string {
        case let s as NSAttributedString: text = s.string
        case let s as String: text = s
        default: return
        }
        // Committing text ends any composition.
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else if let surface {
            // Text arriving outside a key event (e.g. emoji picker, dictation).
            text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
        }
    }

    override func doCommand(by selector: Selector) {
        // Commands (arrows, delete, ...) are encoded by libghostty from the key
        // event itself; swallow the selector so AppKit doesn't beep.
    }
}
