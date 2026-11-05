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
    /// `AppEntry.isLaunchTarget` per path; bundles rarely change kind.
    private var launchable: [String: Bool] = [:]

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
        apps = paths.filter {
            !$0.dropLast(4).contains(".app/") && seen.insert($0).inserted && isLaunchable($0)
        }.map(AppEntry.init(path:))
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func isLaunchable(_ path: String) -> Bool {
        if let known = launchable[path] { return known }
        let result = Self.isLaunchTarget(path)
        launchable[path] = result
        return result
    }

    /// Whether a bundle Spotlight reports belongs in the launcher. Reads the
    /// Info.plist, so callers should cache the answer per path.
    static func isLaunchTarget(_ path: String) -> Bool {
        let fm = FileManager.default
        // iOS apps on Apple Silicon: a wrapper with no Contents/.
        if fm.fileExists(atPath: path + "/WrappedBundle/Info.plist") { return isLaunchTarget(path, info: [:]) }
        // Spotlight tags any folder ending in ".app" as an app — including data
        // folders such as a browser's per-site storage ("https+++example.app").
        guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any] else { return false }
        return isLaunchTarget(path, info: info)
    }

    /// The rules, given the bundle's Info.plist: no system agents, helpers
    /// tucked under a Library/, background-only apps, or Xcode build copies.
    static func isLaunchTarget(_ path: String, info: [String: Any]) -> Bool {
        if path.hasPrefix("/System/Library/") {
            return path.hasPrefix("/System/Library/CoreServices/Applications/")
                || path == "/System/Library/CoreServices/Finder.app"
        }
        // Anything else under a Library/ (or Xcode's DerivedData, itself under
        // ~/Library) is a helper, daemon, template, or build copy.
        if path.contains("/Library/") || path.contains("/DerivedData/") { return false }
        // Menu-bar apps (LSUIElement) stay; faceless helpers don't.
        return !flag(info["LSBackgroundOnly"])
    }

    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes"].contains(s.lowercased())
        default: return false
        }
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
