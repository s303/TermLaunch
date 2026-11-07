import AppKit

// Menu bar, status item and Dock icon for AppDelegate.
extension AppDelegate {
    @objc fileprivate func showAbout() { AboutWindowController.shared.show() }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        let app = submenu("TermLaunch")
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
        }
        item(app, "About TermLaunch", #selector(showAbout), target: self)
        app.addItem(.separator())
        item(app, "Settings…", #selector(openConfig), ",", target: self)
        item(app, "Reload Config", #selector(reloadConfigAction), target: self)
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        item(app, "Hide TermLaunch", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp)
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        app.addItem(.separator())
        item(app, "Close Window", #selector(closeWindowMode), "q", target: self)
        item(app, "Quit TermLaunch", #selector(NSApplication.terminate(_:)), target: NSApp)

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
            let activation = KeySpec.parse(config.activation)?.displayString ?? config.activation
            for binding in config.commands {
                let item = NSMenuItem(title: binding.displayName, action: #selector(commandMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = CommandBox(binding)
                if let spec = binding.hotkey.flatMap(KeySpec.parse), let key = spec.menuKeyEquivalent {
                    // Display only: the global hotkey is consumed before the menu sees the key.
                    item.keyEquivalent = key
                    item.keyEquivalentModifierMask = spec.nsModifiers
                } else if binding.hotkey == nil, let key = binding.key, #available(macOS 14.4, *) {
                    item.subtitle = "\(activation) then \(key)"
                }
                commands.addItem(item)
            }
        }
        return main
    }

    fileprivate final class CommandBox {
        let binding: CommandBinding
        init(_ binding: CommandBinding) { self.binding = binding }
    }

    @objc fileprivate func commandMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        content?.openCommandTab(box.binding)
    }

    fileprivate final class TabShortcutBox {
        let shortcut: TabShortcut
        init(_ shortcut: TabShortcut) { self.shortcut = shortcut }
    }

    @objc fileprivate func tabMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? TabShortcutBox else { return }
        handle(box.shortcut)
    }

    @objc fileprivate func closeWindowMode() { leaveWindowMode() }

    /// The menu bar's `terminal` glyph on a terminal-coloured tile, for the Dock in Window mode.
    static let dockIcon: NSImage = {
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

    func installStatusItem() {
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

    @objc fileprivate func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItemEntry.state = LoginItem.isEnabled ? .on : .off
        loginItemEntry.title = LoginItem.needsApproval
            ? "Launch at Login (approve in System Settings)" : "Launch at Login"
    }
}
