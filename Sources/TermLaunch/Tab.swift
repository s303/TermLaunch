import AppKit

/// What a Tab shows: a terminal surface or the built-in Launcher.
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
final class Tab {
    enum Kind: Equatable {
        case shell
        case command(id: String)
    }

    let kind: Kind
    let view: TabContent
    var title: String

    init(kind: Kind, view: TabContent, title: String) {
        self.kind = kind
        self.view = view
        self.title = title
    }
}
