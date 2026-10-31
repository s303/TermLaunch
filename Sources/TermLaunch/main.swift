import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var ghostty: GhosttyApp?
    private var panel: DropdownPanel?
    private var content: DropdownContentView?
    private var hotKey: HotKey?
    private var commandHotKeys: [HotKey] = []
    private var windowHotKey: HotKey?
    private var config = Config()
    private var configWatcher: ConfigWatcher?
    // Window mode: the Tabs live in `termWindow`; the Dropdown then only shows as a Temporary console.
    private var termWindow: TermWindow?
    private var windowMode = false
    private var tempConsole = false
    private var previousApp: NSRunningApplication?
    private static let windowHotKeyID: UInt32 = 1000
    private let loginItemEntry = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

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

    @objc private func reloadConfigAction() { reloadConfig(initial: false) }

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
            panel.chordWindow = TimeInterval(cfg.chordWindowMs) / 1000
            panel.commandKeys = Set(cfg.commands.compactMap(\.key))
        }
        if let termWindow {
            termWindow.chordWindow = TimeInterval(cfg.chordWindowMs) / 1000
            termWindow.commandKeys = Set(cfg.commands.compactMap(\.key))
        }
        if windowMode { NSApp.mainMenu = makeMainMenu() }
        hotKey = nil // unregisters the old one
        if let spec = KeySpec.parse(cfg.activation) {
            hotKey = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
                self?.toggleDropdown()
            }
        }
        windowHotKey = nil
        if let text = cfg.windowHotkey, let spec = KeySpec.parse(text) {
            windowHotKey = HotKey(id: Self.windowHotKeyID, keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
                self?.windowHotkeyPressed()
            }
            if windowHotKey == nil { NSLog("TermLaunch: could not register window hotkey \"%@\"", text) }
        }
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

    @objc private func openConfig() {
        _ = Config.load() // ensures the file exists
        NSWorkspace.shared.open(Config.path)
    }

    // MARK: Dropdown

    private func handle(_ shortcut: TabShortcut) {
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
        if startChord { panel.beginChord() }
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
            termWindow?.beginChord()
        default:
            break
        }
    }

    // MARK: Window mode

    private func windowHotkeyPressed() {
        switch Presentation.windowHotkey(presentationState) {
        case .enterWindowMode: enterWindowMode()
        case .leaveWindowMode: leaveWindowMode()
        default: break
        }
    }

    private func makeWindow() -> TermWindow {
        let window = TermWindow(background: ghostty?.background ?? .black)
        window.onCloseRequested = { [weak self] in self?.leaveWindowMode() }
        window.onTabShortcut = { [weak self] in self?.handle($0) }
        window.onCommandKey = { [weak self] key in self?.runCommand(key: key) }
        window.chordWindow = TimeInterval(config.chordWindowMs) / 1000
        window.commandKeys = Set(config.commands.compactMap(\.key))
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
        panel.contentView = NSView()
        window.contentView = content
        content.barOnTop = true
        windowMode = true
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = Self.dockIcon
        NSApp.mainMenu = makeMainMenu()
        if content.isEmpty { content.addShellTab() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        content.setDisplayed(true)
    }

    private func leaveWindowMode() {
        guard let panel, let content, windowMode else { return }
        windowMode = false
        tempConsole = false
        content.setDisplayed(false)
        panel.hideImmediately()
        termWindow?.alphaValue = 1
        termWindow?.ignoresMouseEvents = false
        termWindow?.contentView = NSView()
        termWindow?.close() // also drops a minimised window's Dock tile
        content.barOnTop = false
        panel.contentView = content
        NSApp.mainMenu = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Window mode, Window not active: the Dropdown takes the Tabs over for a moment.
    private func beginTempConsole() {
        guard let panel, let content, let window = termWindow else { return }
        tempConsole = true
        // A regular app's panel only keeps key status while the app is active.
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0 == NSRunningApplication.current ? nil : $0
        }
        NSLog("TermLaunch: temporary console opened over %@", previousApp?.localizedName ?? "nothing")
        content.setDisplayed(false)
        window.contentView = NSView()
        content.barOnTop = false
        panel.contentView = content
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
        tempConsole = false
        content.setDisplayed(false)
        panel.hideImmediately()
        panel.contentView = NSView()
        window.contentView = content
        content.barOnTop = true
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        content.setDisplayed(!window.isMiniaturized)
        // Hand focus back to where the user was.
        NSLog("TermLaunch: temporary console closed, returning to %@ (frontmost now %@)",
              previousApp?.localizedName ?? "nothing",
              NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing")
        previousApp?.activate()
        previousApp = nil
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        let app = submenu("TermLaunch")
        let close = app.addItem(withTitle: "Close Window", action: #selector(closeWindowMode), keyEquivalent: "q")
        close.target = self

        let shell = submenu("Shell")
        func add(to menu: NSMenu, _ title: String, _ key: String, _ mods: NSEvent.ModifierFlags, _ shortcut: TabShortcut) {
            let item = NSMenuItem(title: title, action: #selector(tabMenuItem(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            item.representedObject = TabShortcutBox(shortcut)
            menu.addItem(item)
        }
        add(to: shell, "New Tab", "t", .command, .new)
        add(to: shell, "Close Tab", "w", .command, .close)

        let window = submenu("Window")
        add(to: window, "Show Previous Tab", "[", [.command, .shift], .previous)
        add(to: window, "Show Next Tab", "]", [.command, .shift], .next)

        if !config.commands.isEmpty {
            let commands = submenu("Commands")
            for binding in config.commands {
                let item = NSMenuItem(title: binding.run, action: #selector(commandMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = CommandBox(binding)
                commands.addItem(item)
            }
        }
        return main
    }

    private final class CommandBox {
        let binding: CommandBinding
        init(_ binding: CommandBinding) { self.binding = binding }
    }

    @objc private func commandMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        content?.openCommandTab(box.binding)
    }

    private final class TabShortcutBox {
        let shortcut: TabShortcut
        init(_ shortcut: TabShortcut) { self.shortcut = shortcut }
    }

    @objc private func tabMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? TabShortcutBox else { return }
        handle(box.shortcut)
    }

    @objc private func closeWindowMode() { leaveWindowMode() }

    /// The menu bar's `terminal` glyph on a terminal-coloured tile, for the Dock in Window mode.
    private static let dockIcon: NSImage = {
        let side: CGFloat = 512
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let tile = rect.insetBy(dx: side * 0.09, dy: side * 0.09)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: tile, xRadius: side * 0.18, yRadius: side * 0.18).fill()
            let config = NSImage.SymbolConfiguration(pointSize: side * 0.42, weight: .regular)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let g = glyph.size
                glyph.draw(in: NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2, width: g.width, height: g.height))
            }
            return true
        }
    }()

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "TermLaunch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Config", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfigAction), keyEquivalent: "")
        menu.addItem(.separator())
        loginItemEntry.action = #selector(toggleLoginItem)
        menu.addItem(loginItemEntry)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TermLaunch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItemEntry.state = LoginItem.isEnabled ? .on : .off
        loginItemEntry.title = LoginItem.needsApproval
            ? "Launch at Login (approve in System Settings)" : "Launch at Login"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
