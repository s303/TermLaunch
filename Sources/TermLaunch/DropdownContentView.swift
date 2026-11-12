import AppKit

/// Holds every Tab's surface (all stay mounted; only the active one is
/// visible and unoccluded) plus the tab bar, which hides for a single Tab.
@MainActor
final class DropdownContentView: NSView {
    private let ghostty: GhosttyApp
    /// Started with the app so the Launcher opens on a warm index.
    private let appIndex = AppIndex()
    /// Exchange rates, shared by every Launcher Tab and kept for the app session.
    private let rateStore = RateStore()
    /// `[launcher.currency]` from the config; read on each Launcher query.
    var currency = CurrencySettings()
    private let bar = TabBarView()
    private var list = TabList<Tab>()
    /// Whether the Dropdown is on screen. Hidden surfaces are unfocused and occluded
    /// so the renderer stops, and Tab changes while hidden must not undo that.
    private(set) var displayed = false

    /// Called when the last Tab has closed.
    var onEmpty: (() -> Void)?
    /// Cell size or tab bar visibility changed, so the Dropdown's frame should be recomputed.
    var onMetricsChanged: (() -> Void)?
    /// Called when a Command Tab has closed (success or after a held failure).
    var onCommandTabClosed: (() -> Void)?

    var isEmpty: Bool { list.isEmpty }
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
        if let m = active?.view.cellMetrics() ?? list.items.lazy.compactMap({ $0.view.cellMetrics() }).first {
            lastMetrics = m
        }
        return lastMetrics
    }
    private var lastMetrics: (cell: CGSize, padding: CGSize)?
    func isCommandTabActive(_ id: String) -> Bool { list.isCommandTabActive(id) }
    private var active: Tab? { list.active }

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
        add(kind: .shell, title: list.nextShellTitle(), command: nil)
    }

    /// Focuses the first Shell Tab, creating one if none exists.
    func selectMainTab() {
        if let i = list.firstShellIndex { select(i) } else { addShellTab() }
    }

    /// Opens the Command Tab for a binding, or focuses the existing one
    /// (at most one Command Tab per Command key).
    func openCommandTab(_ binding: CommandBinding) {
        if let existing = list.index(ofCommand: binding.id) {
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
        let view = LauncherView(
            index: appIndex, rates: rateStore, currency: { [weak self] in self?.currency ?? CurrencySettings() },
            theme: ghostty.theme)
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
        list.append(tab)
        needsLayout = true
        select(list.count - 1)
    }

    func select(_ index: Int) {
        guard list.select(index) else { return }
        applyVisibility()
        refreshBar()
        if displayed, let tab = active { window?.makeFirstResponder(tab.view.focusView) }
    }

    /// Drag-reorder: moves a Tab, keeping the same Tab active. Numbers and ⌘1–9 follow the new order.
    private func moveTab(from: Int, to: Int) {
        list.move(from: from, to: to)
        refreshBar()
    }

    private func applyVisibility() {
        for (i, tab) in list.items.enumerated() {
            let isActive = i == list.activeIndex
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

    func selectNext() { list.selectNext(); select(list.activeIndex) }
    func selectPrevious() { list.selectPrevious(); select(list.activeIndex) }

    func closeActive() {
        if let tab = active { close(tab) }
    }

    private func close(_ tab: Tab, exitedCleanly: Bool = false) {
        guard let removal = list.remove(tab) else { return }
        #if DEBUG
        NSLog("TermLaunch[debug]: tab closed (%d left)", list.count)
        #endif
        tab.view.removeFromSuperview()
        if exitedCleanly, case .command = tab.kind { onCommandTabClosed?() }
        guard let next = removal.nextActive else {
            refreshBar()
            needsLayout = true
            onEmpty?()
            return
        }
        needsLayout = true
        select(next)
    }

    // MARK: Layout

    private func refreshBar() {
        bar.titles = list.items.map(\.title)
        bar.activeIndex = list.activeIndex
        let show = list.count > 1
        if bar.isHidden == show { bar.isHidden = !show; needsLayout = true; onMetricsChanged?() }
    }

    override func layout() {
        super.layout()
        let barHeight = self.barHeight
        let barY = barOnTop ? bounds.height - barHeight : 0
        bar.frame = NSRect(x: 0, y: barY, width: bounds.width, height: barHeight)
        let area = NSRect(x: 0, y: barOnTop ? 0 : barHeight, width: bounds.width, height: bounds.height - barHeight)
        for tab in list.items { tab.view.frame = area }
    }
}
