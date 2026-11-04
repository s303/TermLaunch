import AppKit

/// Every installed app, kept current for the whole app session: a live
/// Spotlight query (like `mdfind`, so installs and removals show up), merged
/// with a scan of the standard folders for when Spotlight is off or indexing.
final class AppIndex {
    /// Posted on the main queue when the app list changes.
    static let didChange = Notification.Name("TermLaunchAppIndexDidChange")
    private(set) var apps: [AppEntry] = []
    private let query = NSMetadataQuery()
    private var scanned: [AppEntry] = []

    init() {
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in self?.rebuild() }
        }
        query.start()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.scanFolders()
            DispatchQueue.main.async {
                self?.scanned = found
                self?.rebuild()
            }
        }
    }

    deinit { query.stop() }

    private func rebuild() {
        query.disableUpdates()
        var paths = (query.results as? [NSMetadataItem] ?? []).compactMap {
            $0.value(forAttribute: NSMetadataItemPathKey) as? String
        }
        query.enableUpdates()
        paths += scanned.map(\.path)
        var seen = Set<String>()
        // Helpers bundled inside another app (".../Foo.app/Contents/...") are not launch targets.
        apps = paths.filter { !$0.dropLast(4).contains(".app/") && seen.insert($0).inserted }.map(AppEntry.init(path:))
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func scanFolders() -> [AppEntry] {
        let fm = FileManager.default
        let roots = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"]
        var found: [AppEntry] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let path = root + "/" + name
                if name.hasSuffix(".app") { found.append(AppEntry(path: path)); continue }
                // One level down, like Utilities/.
                for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where sub.hasSuffix(".app") {
                    found.append(AppEntry(path: path + "/" + sub))
                }
            }
        }
        return found
    }
}

/// Launcher rows for apps: fuzzy match × frecency; Enter opens the app.
final class AppProvider: LauncherProvider {
    private let index: AppIndex
    private var frecency = FrecencyStore()

    init(index: AppIndex) {
        self.index = index
        reloadFrecency()
    }

    /// Picks up launches recorded by the `oa` CLI since the last open.
    func reloadFrecency() {
        frecency = FrecencyStore.load()
        frecency.applyDecay()
    }

    func results(for query: String) -> [LauncherItem] {
        AppRanker.rank(index.apps, query: query, frecency: frecency).map { app in
            LauncherItem(title: app.name, iconPath: app.path) { [weak self] in
                self?.reloadFrecency() // don't overwrite what `oa` wrote meanwhile
                self?.frecency.record(app.path)
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    if let error { NSLog("TermLaunch: failed to open %@: %@", app.path, error.localizedDescription) }
                }
            }
        }
    }
}
