import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    private var ghostty: GhosttyApp?
    private var panel: DropdownPanel?
    var content: DropdownContentView?
    private var hotKey: HotKey?
    private var commandHotKeys: [HotKey] = []
    private var windowKeySpec: KeySpec?
    private var windowKeyMonitor: Any?
    var config = Config()
    private var configWatcher: ConfigWatcher?
    // Window mode: the Tabs live in `termWindow`; the Dropdown then only shows as a Temporary console.
    private var termWindow: TermWindow?
    /// Where the Tabs are shown. `returnTo` is the app to hand focus back to when the Temporary console ends.
    enum Mode {
        case dropdown
        case window
        case windowWithConsole(returnTo: NSRunningApplication?)
    }
    private var mode = Mode.dropdown
    private var windowMode: Bool {
        if case .dropdown = mode { return false }
        return true
    }
    private var tempConsole: Bool {
        if case .windowWithConsole = mode { return true }
        return false
    }
    let loginItemEntry = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let ghostty = GhosttyApp() else {
            NSLog("TermLaunch: libghostty failed to initialise")
            NSApp.terminate(nil)
            return
        }
        self.ghostty = ghostty

        let panel = DropdownPanel()
        panel.onResignKey = { [weak self, weak panel] in
            // A Regular app is deactivated right after the Temporary console appears; re-assert key once.
            if let self, let panel, self.tempConsole, Date().timeIntervalSince(panel.shownAt) < 0.3 {
                self.reassertConsoleKey()
                return
            }
            self?.hideDropdown()
        }
        panel.onCommandKey = { [weak self] key in self?.runCommand(key: key) }
        panel.onTabShortcut = { [weak self] in self?.handle($0) }
        let content = DropdownContentView(ghostty: ghostty)
        // Last Tab closing hides the Dropdown; a fresh Shell Tab appears on next show.
        content.onEmpty = { [weak self] in
            guard let self else { return }
            if self.windowMode { self.leaveWindowMode() } else { self.hideDropdown() }
        }
        // A finished Command Tab is a "run and dismiss" action; in the Window only the Tab goes.
        content.onCommandTabClosed = { [weak self] in
            guard let self, !(self.windowMode && !self.tempConsole) else { return }
            self.hideDropdown()
        }
        panel.contentView = content
        panel.metrics = { [weak content] in content?.cellMetrics() }
        panel.barHeight = { [weak content] in content?.barHeight ?? 0 }
        content.onMetricsChanged = { [weak panel] in panel?.relayout() }
        self.panel = panel
        self.content = content
        content.addShellTab()

        reloadConfig(initial: true)
        configWatcher = ConfigWatcher(fileURL: Config.path) { [weak self] in
            self?.reloadConfig(initial: false)
        }
        installStatusItem()
        LoginItem.applyDefaultIfNeeded()
        panel.warmUp()

        #if DEBUG
        if ProcessInfo.processInfo.environment["TERMLAUNCH_DEBUG_SIZE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showDropdown(startChord: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    let g = self?.content?.debugGrid
                    NSLog("TermLaunch[debug]: grid %dx%d frame %@", g?.columns ?? -1, g?.rows ?? -1,
                          NSStringFromRect(self?.panel?.frame ?? .zero))
                    self?.content?.addShellTab()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        let g = self?.content?.debugGrid
                        NSLog("TermLaunch[debug]: with tab bar grid %dx%d frame %@", g?.columns ?? -1, g?.rows ?? -1,
                              NSStringFromRect(self?.panel?.frame ?? .zero))
                    }
                }
            }
        }
        if let key = ProcessInfo.processInfo.environment["TERMLAUNCH_DEBUG_COMMAND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                NSLog("TermLaunch[debug]: showing and running command key %@", key)
                self?.showDropdown(startChord: false)
                self?.runCommand(key: key)
            }
        }
        #endif
    }

    // MARK: Config

    /// Dropdown and Window get identical chord config. The Dropdown needs the Activation key
    /// too: as the Temporary console the app is active, so the hotkey's keyDown also reaches
    /// the panel and would end the Chord window it just started (and type into the terminal).
    private func applyChordConfig(_ cfg: Config) {
        panel?.chord.apply(cfg)
        termWindow?.chord.apply(cfg)
    }

    @objc func reloadConfigAction() { reloadConfig(initial: false) }

    private func reloadConfig(initial: Bool) {
        let (loaded, warnings) = Config.load()
        warnings.forEach { NSLog("TermLaunch: config: %@", $0) }
        // On a bad edit keep what is running; only the first load falls back to defaults.
        guard let cfg = loaded ?? (initial ? Config() : nil) else { return }
        guard initial || cfg != config else { return }
        config = cfg

        if let panel {
            panel.columns = cfg.columns
            panel.rows = cfg.rows
            panel.fadeDuration = TimeInterval(cfg.fadeMs) / 1000
            panel.edge = cfg.edge
        }
        applyChordConfig(cfg)
        content?.tabBarStyle = cfg.tabBar
        content?.currency = cfg.currency
        if windowMode { NSApp.mainMenu = makeMainMenu() }
        hotKey = nil // unregisters the old one
        if let spec = KeySpec.parse(cfg.activation) {
            hotKey = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
                self?.toggleDropdown()
            }
        }
        windowKeySpec = cfg.windowHotkey.flatMap(KeySpec.parse)
        installWindowKeyMonitor()
        commandHotKeys = []
        for (i, binding) in cfg.commands.enumerated() {
            guard let text = binding.hotkey, let spec = KeySpec.parse(text) else { continue }
            let hk = HotKey(id: UInt32(i + 2), keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
                self?.commandHotkeyPressed(binding)
            }
            if let hk { commandHotKeys.append(hk) } else {
                NSLog("TermLaunch: could not register hotkey \"%@\"", text)
            }
        }
        if hotKey == nil { NSLog("TermLaunch: could not register activation key \"%@\"", cfg.activation) }
        NSLog("TermLaunch: config loaded (%d command(s), %d hotkey(s))",
              cfg.commands.count, commandHotKeys.count)
    }

    @objc func openConfig() {
        _ = Config.load() // ensures the file exists
        NSWorkspace.shared.open(Config.path)
    }

    // MARK: Dropdown

    func handle(_ shortcut: TabShortcut) {
        switch shortcut {
        case .new: content?.addShellTab()
        case .close: content?.closeActive()
        case .next: content?.selectNext()
        case .previous: content?.selectPrevious()
        case .select(let i): content?.select(i)
        }
    }

    private func runCommand(key: String) {
        guard let binding = config.commands.first(where: { $0.key == key }) else { return }
        content?.openCommandTab(binding)
    }

    private var presentationState: Presentation.State {
        .init(windowMode: windowMode, consoleShown: panel?.isShown ?? false,
              windowIsKey: NSApp.isActive && (termWindow?.isKeyWindow ?? false) && windowIsOnScreen)
    }

    /// Window managers (AeroSpace) hide a window on another workspace by parking it almost
    /// off-screen while the app stays active, so "key" alone does not mean the user sees it.
    private var windowIsOnScreen: Bool {
        guard let frame = termWindow?.frame, frame.width > 0, frame.height > 0 else { return false }
        let visible = NSScreen.screens.reduce(CGFloat(0)) { total, screen in
            let r = frame.intersection(screen.frame)
            return total + (r.isNull ? 0 : r.width * r.height)
        }
        return visible >= frame.width * frame.height / 2
    }

    /// Global hotkey: show the Dropdown on the command's Tab; pressed again
    /// while that Tab is showing, hide it. In Window mode the Window gets the Tab.
    private func commandHotkeyPressed(_ binding: CommandBinding) {
        guard let content else { return }
        let active = content.isCommandTabActive(binding.id)
        switch Presentation.commandHotkey(presentationState, commandTabActive: active) {
        case .hideConsole:
            hideDropdown()
        case .useWindow:
            content.openCommandTab(binding)
            termWindow?.makeKeyAndOrderFront(nil)
        default:
            content.openCommandTab(binding) // before showing, so an empty Dropdown gets no stray Shell Tab
            showDropdown(startChord: false)
        }
    }

    private func showDropdown(startChord: Bool) {
        guard let panel, let content else { return }
        if content.isEmpty { content.addShellTab() }
        if windowMode && !tempConsole { beginTempConsole() }
        panel.show()
        if tempConsole { reassertConsoleKey() }
        content.setDisplayed(true)
        if startChord { panel.chord.begin() }
    }

    private func hideDropdown() {
        if tempConsole {
            endTempConsole()
            return
        }
        panel?.hide()
        content?.setDisplayed(false)
    }

    private func toggleDropdown() {
        switch Presentation.activation(presentationState) {
        case .hideConsole:
            hideDropdown()
        case .showConsole:
            content?.selectMainTab() // the Activation key always lands on the main Shell Tab
            showDropdown(startChord: true)
        case .windowChord:
            termWindow?.chord.begin()
        default:
            break
        }
    }

    // MARK: Window mode

    /// The Window hotkey is app-local, not a global hotkey: it only acts while the
    /// Dropdown or the Window is in front, so other apps keep the key (e.g. ⌘Enter).
    private func installWindowKeyMonitor() {
        guard windowKeyMonitor == nil else { return }
        windowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.windowKeySpec?.matches(event) == true else { return event }
            switch Presentation.windowHotkey(self.presentationState) {
            case .enterWindowMode: if !event.isARepeat { self.enterWindowMode() }
            case .leaveWindowMode: if !event.isARepeat { self.leaveWindowMode() }
            default: return event
            }
            return nil
        }
    }

    private func makeWindow() -> TermWindow {
        let window = TermWindow(background: ghostty?.background ?? .black)
        window.onCloseRequested = { [weak self] in self?.leaveWindowMode() }
        window.onTabShortcut = { [weak self] in self?.handle($0) }
        window.onCommandKey = { [weak self] key in self?.runCommand(key: key) }
        window.chord.apply(config)
        window.onVisibilityChanged = { [weak self] visible in
            guard let self, self.windowMode, !self.tempConsole else { return }
            self.content?.setDisplayed(visible)
        }
        // First frame: the Dropdown's grid size, centred.
        var size = NSSize(width: 800, height: 500)
        if let m = content?.cellMetrics() {
            size = NSSize(
                width: CGFloat(config.columns) * m.cell.width + m.padding.width,
                height: CGFloat(config.rows) * m.cell.height + m.padding.height + (content?.barHeight ?? 0))
        }
        if let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            size = NSSize(width: min(size.width.rounded(), area.width), height: min(size.height.rounded(), area.height))
        }
        window.setContentSize(size)
        window.center()
        return window
    }

    private func enterWindowMode() {
        guard let panel, let content, !windowMode else { return }
        let window = termWindow ?? makeWindow()
        termWindow = window
        content.setDisplayed(false)
        panel.hideImmediately()
        mountContent(inWindow: true)
        mode = .window
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = Self.dockIcon
        NSApp.mainMenu = makeMainMenu()
        if content.isEmpty { content.addShellTab() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        content.setDisplayed(true)
    }

    /// Reparents the shared content view between the Window and the Dropdown panel,
    /// leaving a placeholder behind in the other one.
    private func mountContent(inWindow: Bool) {
        guard let panel, let content else { return }
        if inWindow {
            panel.contentView = NSView()
            termWindow?.contentView = content
        } else {
            termWindow?.contentView = NSView()
            panel.contentView = content
        }
        content.barOnTop = inWindow
    }

    func leaveWindowMode() {
        guard let panel, let content, windowMode else { return }
        mode = .dropdown
        content.setDisplayed(false)
        panel.hideImmediately()
        termWindow?.alphaValue = 1
        termWindow?.ignoresMouseEvents = false
        mountContent(inWindow: false)
        termWindow?.close() // also drops a minimised window's Dock tile
        NSApp.mainMenu = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Window mode, Window not active: the Dropdown takes the Tabs over for a moment.
    private func beginTempConsole() {
        guard panel != nil, let content, let window = termWindow else { return }
        // A regular app's panel only keeps key status while the app is active.
        let previousApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0 == NSRunningApplication.current ? nil : $0
        }
        mode = .windowWithConsole(returnTo: previousApp)
        NSLog("TermLaunch: temporary console opened over %@", previousApp?.localizedName ?? "nothing")
        content.setDisplayed(false)
        mountContent(inWindow: false)
        // Keep the window in place, only invisible: ordering it out and back makes window
        // managers (AeroSpace) lose track of it and misplace focus.
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    /// Window mode makes this a Regular app, which macOS deactivates right after the
    /// Temporary console appears; take key status back once it settles.
    private func reassertConsoleKey() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.tempConsole, let panel = self.panel, panel.isShown else { return }
            if !NSApp.isActive || !panel.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func endTempConsole() {
        guard let panel, let content, let window = termWindow else { return }
        guard case .windowWithConsole(let previousApp) = mode else { return }
        mode = .window
        content.setDisplayed(false)
        panel.hideImmediately()
        mountContent(inWindow: true)
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        content.setDisplayed(!window.isMiniaturized)
        // Hand focus back to where the user was.
        NSLog("TermLaunch: temporary console closed, returning to %@ (frontmost now %@)",
              previousApp?.localizedName ?? "nothing",
              NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing")
        previousApp?.activate()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
