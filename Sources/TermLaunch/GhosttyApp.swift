import AppKit
import GhosttyKit

/// What libghostty holds as a surface's userdata. libghostty calls back from
/// arbitrary threads, possibly after the view's Tab has closed, so callbacks
/// reach the view only through this retained handle's weak reference (and
/// only on the main thread). The view releases the handle after freeing the
/// surface.
final class SurfaceHandle {
    weak var view: GhosttySurfaceView?
    /// Copies the view's values that callbacks read off the main thread.
    let exitFilePath: String?
    private let lock = NSLock()
    private var _surface: ghostty_surface_t?
    /// The surface pointer, nil once it has been freed.
    var surface: ghostty_surface_t? {
        get { lock.lock(); defer { lock.unlock() }; return _surface }
        set { lock.lock(); _surface = newValue; lock.unlock() }
    }

    init(exitFilePath: String?) {
        self.exitFilePath = exitFilePath
    }
}

/// Owns the single `ghostty_app_t`. The C callbacks below capture nothing and
/// hop to the main thread.
final class GhosttyApp {
    private(set) var app: ghostty_app_t?

    init?() {
        Self.configureResources()

        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            NSLog("ghostty_init failed")
            return nil
        }
        guard let config = ghostty_config_new() else {
            NSLog("ghostty_config_new returned nil")
            return nil
        }
        // Reuse the user's Ghostty config for appearance (see CONTEXT.md).
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { userdata in
            guard let userdata else { return }
            let box = Unmanaged<GhosttyApp>.fromOpaque(userdata)
            DispatchQueue.main.async { box.takeUnretainedValue().tick() }
        }
        runtime.action_cb = { _, target, action in
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let raw = ghostty_surface_userdata(target.target.surface) else { return false }
            let handle = Unmanaged<SurfaceHandle>.fromOpaque(raw).takeUnretainedValue()

            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                guard let cTitle = action.action.set_title.title else { return false }
                // Copy before hopping threads; the C string is only valid in this call.
                let title = String(cString: cTitle)
                DispatchQueue.main.async { handle.view?.onTitle?(title) }
                return true

            case GHOSTTY_ACTION_CELL_SIZE:
                DispatchQueue.main.async { handle.view?.onCellSize?() }
                return true

            case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
                // Command Tabs report their real exit code through a file; Ghostty's
                // own exit code is unreliable on macOS. Returning true suppresses
                // Ghostty's "press any key" message, so only do that on success.
                guard let path = handle.exitFilePath,
                      let text = try? String(contentsOfFile: path, encoding: .utf8),
                      Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) == 0 else { return false }
                DispatchQueue.main.async { handle.view?.onSuccessfulExit?() }
                return true

            default:
                return false
            }
        }
        runtime.read_clipboard_cb = { userdata, location, state, _, _, _ in
            // Only the standard clipboard; text only.
            guard location == GHOSTTY_CLIPBOARD_STANDARD, let userdata else {
                return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED
            }
            let handle = Unmanaged<SurfaceHandle>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = handle.surface,
                  let text = NSPasteboard.general.string(forType: .string) else {
                return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE
            }
            GhosttyApp.complete(surface: surface, text: text, state: state, confirmed: false)
            return GHOSTTY_CLIPBOARD_READ_STARTED
        }
        runtime.confirm_read_clipboard_cb = { userdata, confirm, state, request in
            guard let userdata, let confirm else { return }
            let handle = Unmanaged<SurfaceHandle>.fromOpaque(userdata).takeUnretainedValue()
            guard request == GHOSTTY_CLIPBOARD_REQUEST_PASTE, handle.surface != nil,
                  let contents = confirm.pointee.contents, confirm.pointee.contents_len > 0,
                  let data = contents[0].data else {
                // Programs reading the clipboard (OSC 52) are denied.
                if let surface = handle.surface { ghostty_surface_deny_clipboard_request(surface, state) }
                return
            }
            // Copy now; the pointers are only valid during this call.
            let text = String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: contents[0].len), as: UTF8.self)
            DispatchQueue.main.async {
                let ok = GhosttyApp.confirmPaste(text)
                // The Tab may have closed while the dialog was up.
                guard let surface = handle.surface else { return }
                if ok {
                    GhosttyApp.complete(surface: surface, text: text, state: state, confirmed: true)
                } else {
                    ghostty_surface_deny_clipboard_request(surface, state)
                }
            }
        }
        runtime.write_clipboard_cb = { _, location, content, len, confirm in
            guard location == GHOSTTY_CLIPBOARD_STANDARD, !confirm, let content else { return }
            for i in 0..<len {
                guard let mime = content[i].mime, String(cString: mime).hasPrefix("text/plain"),
                      let data = content[i].data else { continue }
                let text = String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: content[i].len), as: UTF8.self)
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                return
            }
        }
        runtime.close_surface_cb = { userdata, _ in
            guard let userdata else { return }
            let handle = Unmanaged<SurfaceHandle>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async { handle.view?.surfaceDidClose() }
        }

        guard let app = ghostty_app_new(&runtime, config) else {
            ghostty_config_free(config)
            NSLog("ghostty_app_new failed")
            return nil
        }
        ghostty_config_free(config)
        self.app = app
    }

    deinit {
        if let app { ghostty_app_free(app) }
    }

    func tick() {
        if let app { ghostty_app_tick(app) }
    }

    /// libghostty finds shell integration and themes via GHOSTTY_RESOURCES_DIR.
    /// terminfo must be a sibling of the `ghostty` directory; never set TERMINFO.
    private static func configureResources() {
        guard let res = Bundle.main.resourceURL?.appendingPathComponent("ghostty"),
              FileManager.default.fileExists(atPath: res.path) else { return }
        setenv("GHOSTTY_RESOURCES_DIR", res.path, 1)
    }

    // MARK: Clipboard helpers

    /// Completes a pending clipboard read with plain text.
    static func complete(surface: ghostty_surface_t, text: String, state: UnsafeMutableRawPointer?, confirmed: Bool) {
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buf in
            "text/plain".withCString { mime in
                var content = ghostty_clipboard_content_s(
                    mime: mime,
                    data: UnsafeRawPointer(buf.baseAddress ?? UnsafePointer(bitPattern: 1)!).assumingMemoryBound(to: CChar.self),
                    len: buf.count)
                withUnsafePointer(to: &content) { ptr in
                    var complete = ghostty_clipboard_complete_s(
                        contents: ptr, contents_len: 1,
                        available: nil, available_len: 0,
                        confirmed: confirmed, remember: false)
                    ghostty_surface_complete_clipboard_request(surface, &complete, state)
                }
            }
        }
    }

    /// Paste protection: asks before pasting text libghostty considers risky
    /// (multi-line or containing control sequences).
    static func confirmPaste(_ text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Paste this text?"
        alert.informativeText = String(text.prefix(600)) + (text.count > 600 ? "…" : "")
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")
        DropdownPanel.suppressHideOnResign = true
        defer { DropdownPanel.suppressHideOnResign = false }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
