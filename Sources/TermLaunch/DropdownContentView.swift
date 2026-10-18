import AppKit

/// Holds every Tab's surface (all stay mounted; only the active one is
/// visible and unoccluded) plus the tab bar, which hides for a single Tab.
final class DropdownContentView: NSView {
    private let ghostty: GhosttyApp
    private let bar = TabBarView()
    private(set) var tabs: [Tab] = []
    private(set) var activeIndex = 0
    private var shellCount = 0
    /// Whether the Dropdown is on screen. Hidden surfaces are unfocused and occluded
    /// so the renderer stops, and Tab changes while hidden must not undo that.
    private(set) var displayed = false

    /// Called when the last Tab has closed.
    var onEmpty: (() -> Void)?
    /// Cell size or tab bar visibility changed, so the Dropdown's frame should be recomputed.
    var onMetricsChanged: (() -> Void)?
    /// Called when a Command Tab has closed (success or after a held failure).
    var onCommandTabClosed: (() -> Void)?

    var isEmpty: Bool { tabs.isEmpty }
    #if DEBUG
    var debugGrid: (columns: Int, rows: Int)? { active?.view.debugGrid }
    #endif
    var barHeight: CGFloat { bar.isHidden ? 0 : TabBarView.height }

    func cellMetrics() -> (cell: CGSize, padding: CGSize)? { active?.view.cellMetrics() }
    private var active: Tab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    init(ghostty: GhosttyApp) {
        self.ghostty = ghostty
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        addSubview(bar)
        bar.onSelect = { [weak self] in self?.select($0) }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Tabs

    @discardableResult
    func addShellTab() -> Tab {
        shellCount += 1
        return add(kind: .shell, title: "shell \(shellCount)", command: nil)
    }

    /// Opens the Command Tab for a binding, or focuses the existing one
    /// (at most one Command Tab per Command key).
    func openCommandTab(_ binding: CommandBinding) {
        if let existing = tabs.firstIndex(where: { $0.kind == .command(key: binding.key) }) {
            select(existing)
            return
        }
        NSLog("TermLaunch: opening command tab for key %@", binding.key)
        let exitFile = NSTemporaryDirectory() + "termlaunch-exit-\(UUID().uuidString)"
        let cwd = binding.cwd.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory()
        add(
            kind: .command(key: binding.key),
            title: binding.run,
            command: Self.wrapperCommand(run: binding.run, exitFile: exitFile),
            workingDirectory: cwd,
            exitFile: exitFile
        )
    }

    /// `/bin/sh` runs the user's login shell (so PATH matches a normal terminal;
    /// the app itself is started by launchd with a minimal environment) and
    /// records the real exit code in a file.
    static func wrapperCommand(run: String, exitFile: String) -> String {
        let shell = loginShell()
        let script = "\(shQuote(shell)) -l -c \(shQuote(run)); printf %s $? > \(shQuote(exitFile))"
        return "/bin/sh -c \(shQuote(script))"
    }

    private static func loginShell() -> String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private func add(
        kind: Tab.Kind, title: String, command: String?,
        workingDirectory: String? = nil, exitFile: String? = nil
    ) -> Tab {
        let isCommand = command != nil
        let view = GhosttySurfaceView(
            ghostty: ghostty, command: command, workingDirectory: workingDirectory,
            exitFilePath: exitFile, waitAfterCommand: isCommand)
        let tab = Tab(kind: kind, view: view, title: title)
        view.onSuccessfulExit = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.close(tab)
        }
        view.onClose = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.close(tab)
        }
        view.onCellSize = { [weak self] in self?.onMetricsChanged?() }
        view.onTitle = { [weak self, weak tab] title in
            guard let self, let tab, !title.isEmpty else { return }
            tab.title = title
            self.refreshBar()
        }
        addSubview(view)
        tabs.append(tab)
        needsLayout = true
        select(tabs.count - 1)
        return tab
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        applyVisibility()
        refreshBar()
        if displayed { window?.makeFirstResponder(tabs[index].view) }
    }

    private func applyVisibility() {
        for (i, tab) in tabs.enumerated() {
            let isActive = i == activeIndex
            tab.view.alphaValue = isActive ? 1 : 0
            tab.view.setOccluded(!(isActive && displayed))
            tab.view.setFocused(isActive && displayed)
        }
    }

    /// Called when the Dropdown is shown or hidden.
    func setDisplayed(_ displayed: Bool) {
        self.displayed = displayed
        applyVisibility()
        if displayed, let tab = active { window?.makeFirstResponder(tab.view) }
    }

    func selectNext() { if !tabs.isEmpty { select((activeIndex + 1) % tabs.count) } }
    func selectPrevious() { if !tabs.isEmpty { select((activeIndex - 1 + tabs.count) % tabs.count) } }

    func closeActive() {
        if let tab = active { close(tab) }
    }

    private func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        #if DEBUG
        NSLog("TermLaunch[debug]: tab closed (%d left)", tabs.count - 1)
        #endif
        tabs.remove(at: index)
        tab.view.removeFromSuperview()
        if case .command = tab.kind { onCommandTabClosed?() }
        if tabs.isEmpty {
            shellCount = 0
            refreshBar()
            needsLayout = true
            onEmpty?()
            return
        }
        // Focus the previously adjacent Tab; keep the active one if another closed.
        let next = index < activeIndex ? activeIndex - 1
            : index == activeIndex ? min(index, tabs.count - 1)
            : activeIndex
        needsLayout = true
        select(next)
    }

    // MARK: Layout

    private func refreshBar() {
        bar.titles = tabs.map(\.title)
        bar.activeIndex = activeIndex
        let show = tabs.count > 1
        if bar.isHidden == show { bar.isHidden = !show; needsLayout = true; onMetricsChanged?() }
    }

    override func layout() {
        super.layout()
        let barHeight = bar.isHidden ? 0 : TabBarView.height
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        let area = NSRect(x: 0, y: barHeight, width: bounds.width, height: bounds.height - barHeight)
        for tab in tabs { tab.view.frame = area }
    }
}
