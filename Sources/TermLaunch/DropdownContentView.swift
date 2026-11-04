import AppKit

/// Holds every Tab's surface (all stay mounted; only the active one is
/// visible and unoccluded) plus the tab bar, which hides for a single Tab.
final class DropdownContentView: NSView {
    private let ghostty: GhosttyApp
    /// Started with the app so the Launcher opens on a warm index.
    private let appIndex = AppIndex()
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
    var debugGrid: (columns: Int, rows: Int)? { (active?.view as? GhosttySurfaceView)?.debugGrid }
    #endif
    /// Window mode shows the tab bar above the terminal; the Dropdown keeps it below.
    var barOnTop = false { didSet { if barOnTop != oldValue { needsLayout = true } } }

    /// One terminal row tall, so the bar reads as a line of the terminal.
    var barHeight: CGFloat {
        bar.isHidden ? 0 : (cellMetrics()?.cell.height ?? 20).rounded()
    }

    var tabBarStyle: TabBarStyle {
        get { bar.style }
        set { bar.style = newValue }
    }

    /// The active terminal's metrics; a Launcher Tab borrows another terminal's
    /// (or the last seen) so the Dropdown keeps its size.
    func cellMetrics() -> (cell: CGSize, padding: CGSize)? {
        if let m = active?.view.cellMetrics() ?? tabs.lazy.compactMap({ $0.view.cellMetrics() }).first {
            lastMetrics = m
        }
        return lastMetrics
    }
    private var lastMetrics: (cell: CGSize, padding: CGSize)?
    func isCommandTabActive(_ id: String) -> Bool { active?.kind == .command(id: id) }
    private var active: Tab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    init(ghostty: GhosttyApp) {
        self.ghostty = ghostty
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        addSubview(bar)
        bar.theme = ghostty.theme
        bar.onSelect = { [weak self] in self?.select($0) }
        bar.onMove = { [weak self] in self?.moveTab(from: $0, to: $1) }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Tabs

    @discardableResult
    func addShellTab() -> Tab {
        shellCount += 1
        return add(kind: .shell, title: "shell \(shellCount)", command: nil)
    }

    /// Focuses the first Shell Tab, creating one if none exists.
    func selectMainTab() {
        if let i = tabs.firstIndex(where: { $0.kind == .shell }) { select(i) } else { addShellTab() }
    }

    /// Opens the Command Tab for a binding, or focuses the existing one
    /// (at most one Command Tab per Command key).
    func openCommandTab(_ binding: CommandBinding) {
        if let existing = tabs.firstIndex(where: { $0.kind == .command(id: binding.id) }) {
            select(existing)
            return
        }
        NSLog("TermLaunch: opening command tab for %@", binding.id)
        guard case .run(let run) = binding.action else {
            openLauncherTab(binding)
            return
        }
        let exitFile = NSTemporaryDirectory() + "termlaunch-exit-\(UUID().uuidString)"
        let cwd = binding.cwd.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory()
        add(
            kind: .command(id: binding.id),
            title: binding.displayName,
            pinnedTitle: binding.name != nil,
            command: ShellCommand.wrapper(run: run, exitFile: exitFile),
            workingDirectory: cwd,
            exitFile: exitFile
        )
    }

    private func openLauncherTab(_ binding: CommandBinding) {
        let view = LauncherView(index: appIndex, theme: ghostty.theme)
        let tab = Tab(kind: .command(id: binding.id), view: view, title: binding.displayName)
        view.onFinish = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.close(tab, exitedCleanly: true)
        }
        insert(tab)
    }

    @discardableResult
    private func add(
        kind: Tab.Kind, title: String, pinnedTitle: Bool = false, command: String?,
        workingDirectory: String? = nil, exitFile: String? = nil
    ) -> Tab {
        let isCommand = command != nil
        let view = GhosttySurfaceView(
            ghostty: ghostty, command: command, workingDirectory: workingDirectory,
            exitFilePath: exitFile, waitAfterCommand: isCommand)
        let tab = Tab(kind: kind, view: view, title: title)
        view.onSuccessfulExit = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.close(tab, exitedCleanly: true)
        }
        view.onClose = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.close(tab)
        }
        view.onCellSize = { [weak self] in self?.onMetricsChanged?() }
        view.onTitle = { [weak self, weak tab] title in
            guard let self, let tab, !title.isEmpty, !pinnedTitle else { return }
            tab.title = title
            self.refreshBar()
        }
        insert(tab)
        return tab
    }

    private func insert(_ tab: Tab) {
        addSubview(tab.view)
        tabs.append(tab)
        needsLayout = true
        select(tabs.count - 1)
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        applyVisibility()
        refreshBar()
        if displayed { window?.makeFirstResponder(tabs[index].view.focusView) }
    }

    /// Drag-reorder: moves a Tab, keeping the same Tab active. Numbers and ⌘1–9 follow the new order.
    private func moveTab(from: Int, to: Int) {
        guard tabs.indices.contains(from), tabs.indices.contains(to), from != to else { return }
        let current = active
        tabs.insert(tabs.remove(at: from), at: to)
        activeIndex = current.flatMap { c in tabs.firstIndex { $0 === c } } ?? activeIndex
        refreshBar()
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
        if displayed, let tab = active { window?.makeFirstResponder(tab.view.focusView) }
    }

    func selectNext() { if !tabs.isEmpty { select((activeIndex + 1) % tabs.count) } }
    func selectPrevious() { if !tabs.isEmpty { select((activeIndex - 1 + tabs.count) % tabs.count) } }

    func closeActive() {
        if let tab = active { close(tab) }
    }

    private func close(_ tab: Tab, exitedCleanly: Bool = false) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        #if DEBUG
        NSLog("TermLaunch[debug]: tab closed (%d left)", tabs.count - 1)
        #endif
        tabs.remove(at: index)
        tab.view.removeFromSuperview()
        if exitedCleanly, case .command = tab.kind { onCommandTabClosed?() }
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
        let barHeight = self.barHeight
        let barY = barOnTop ? bounds.height - barHeight : 0
        bar.frame = NSRect(x: 0, y: barY, width: bounds.width, height: barHeight)
        let area = NSRect(x: 0, y: barOnTop ? 0 : barHeight, width: bounds.width, height: bounds.height - barHeight)
        for tab in tabs { tab.view.frame = area }
    }
}
