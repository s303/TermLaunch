import AppKit

/// What a Tab shows: a terminal surface or the built-in Launcher.
@MainActor
protocol TabContent: NSView {
    /// Cell size and padding in points; nil for content that is not a terminal grid.
    func cellMetrics() -> (cell: CGSize, padding: CGSize)?
    func setFocused(_ focused: Bool)
    func setOccluded(_ occluded: Bool)
    /// The view that takes keyboard focus when the Tab is selected.
    var focusView: NSView { get }
}

extension GhosttySurfaceView: TabContent {
    var focusView: NSView { self }
}

/// One Tab in the Dropdown. Shell Tabs run the default shell; Command Tabs
/// run a bound command (see Config) and are unique per command.
@MainActor
final class Tab: TabListEntry {
    typealias Kind = TabKind

    let kind: Kind
    let view: TabContent
    var title: String

    init(kind: Kind, view: TabContent, title: String) {
        self.kind = kind
        self.view = view
        self.title = title
    }
}

extension TabContent {
    /// Inactive Tabs stay mounted at zero opacity; their views must not take
    /// clicks or scrolls. Conformers' `hitTest` returns nil unless this holds.
    var isTabVisible: Bool { alphaValue > 0 }
}
