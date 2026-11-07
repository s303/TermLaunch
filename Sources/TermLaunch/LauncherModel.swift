import Foundation

/// One row in the Launcher.
struct LauncherItem {
    let title: String
    /// File whose Finder icon the row shows (an app bundle).
    var iconPath: String? = nil
    /// Short right-aligned note, e.g. "⏎ copy".
    var hint: String? = nil
    let run: @MainActor () -> Void
}

/// A source of Launcher rows. Every provider sees every query; `[]` means no answer.
@MainActor
protocol LauncherProvider: AnyObject {
    func results(for query: String) -> [LauncherItem]
}

/// The Launcher's query, rows and selection, independent of the view.
@MainActor
final class LauncherModel {
    /// In display priority: earlier providers' rows rank above later ones'.
    let providers: [LauncherProvider]
    private(set) var query = ""
    private(set) var items: [LauncherItem] = []
    /// 0 is the best row, drawn nearest the search field.
    private(set) var selected = 0

    init(providers: [LauncherProvider]) {
        self.providers = providers
    }

    var selectedItem: LauncherItem? { items.indices.contains(selected) ? items[selected] : nil }

    func setQuery(_ query: String) {
        self.query = query
        refresh()
    }

    /// Re-asks every provider (query changed, or a provider's data did).
    func refresh() {
        items = providers.flatMap { $0.results(for: query) }
        selected = 0
    }

    /// Toward worse rows (visually up).
    func moveUp() { if selected + 1 < items.count { selected += 1 } }

    /// Toward better rows (visually down, toward the search field).
    func moveDown() { if selected > 0 { selected -= 1 } }

    func select(_ index: Int) { if items.indices.contains(index) { selected = index } }
}
