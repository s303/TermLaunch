import Foundation

/// One Tab in the Dropdown. Shell Tabs run the default shell; Command Tabs
/// run a bound command (see Config) and are unique per command.
final class Tab {
    enum Kind: Equatable {
        case shell
        case command(id: String)
    }

    let kind: Kind
    let view: GhosttySurfaceView
    var title: String

    init(kind: Kind, view: GhosttySurfaceView, title: String) {
        self.kind = kind
        self.view = view
        self.title = title
    }
}
