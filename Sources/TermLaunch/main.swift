import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var ghostty: GhosttyApp?
    private var panel: DropdownPanel?
    private var content: DropdownContentView?
    private var hotKey: HotKey?
    private var commandHotKeys: [HotKey] = []
    private var config = Config()
    private var configWatcher: ConfigWatcher?
    private let loginItemEntry = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let ghostty = GhosttyApp() else {
            NSLog("TermLaunch: libghostty failed to initialise")
            NSApp.terminate(nil)
            return
        }
        self.ghostty = ghostty

        let panel = DropdownPanel()
        panel.onResignKey = { [weak self] in self?.hideDropdown() }
        panel.onCommandKey = { [weak self] key in self?.runCommand(key: key) }
        panel.onTabShortcut = { [weak self] in self?.handle($0) }
        let content = DropdownContentView(ghostty: ghostty)
        // Last Tab closing hides the Dropdown; a fresh Shell Tab appears on next show.
        content.onEmpty = { [weak self] in self?.hideDropdown() }
        // A finished Command Tab is a "run and dismiss" action.
        content.onCommandTabClosed = { [weak self] in self?.hideDropdown() }
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
        hotKey = nil // unregisters the old one
        if let spec = KeySpec.parse(cfg.activation) {
            hotKey = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
                self?.toggleDropdown()
            }
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

    private func handle(_ shortcut: DropdownPanel.TabShortcut) {
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

    /// Global hotkey: show the Dropdown on the command's Tab; pressed again
    /// while that Tab is showing, hide it.
    private func commandHotkeyPressed(_ binding: CommandBinding) {
        guard let panel, let content else { return }
        if panel.isShown, content.isCommandTabActive(binding.id) {
            hideDropdown()
            return
        }
        content.openCommandTab(binding) // before showing, so an empty Dropdown gets no stray Shell Tab
        showDropdown(startChord: false)
    }

    private func showDropdown(startChord: Bool) {
        guard let panel, let content else { return }
        if content.isEmpty { content.addShellTab() }
        panel.show()
        content.setDisplayed(true)
        if startChord { panel.beginChord() }
    }

    private func hideDropdown() {
        panel?.hide()
        content?.setDisplayed(false)
    }

    private func toggleDropdown() {
        guard let panel else { return }
        if panel.isShown { hideDropdown() } else {
            content?.selectMainTab() // the Activation key always lands on the main Shell Tab
            showDropdown(startChord: true)
        }
    }

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
