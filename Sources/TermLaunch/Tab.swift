import Foundation

/// One Tab in the Dropdown. Shell Tabs run the default shell; Command Tabs
/// (not wired to Command keys yet) run a bound command and are unique per key.
final class Tab {
    enum Kind: Equatable {
        case shell
        case command(key: String)
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
