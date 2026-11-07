import Foundation

/// Calls `onChange` (on the main queue, debounced) when the config file is
/// edited. Watches the file itself for in-place writes and its directory for
/// atomic replaces (rename-over), re-arming the file watch each time.
@MainActor
final class ConfigWatcher {
    private let fileURL: URL
    private let onChange: () -> Void
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        watchDirectory()
        watchFile()
    }

    isolated deinit {
        fileSource?.cancel()
        dirSource?.cancel()
        pending?.cancel()
    }

    private func watchDirectory() {
        dirSource = makeSource(path: fileURL.deletingLastPathComponent().path, mask: .write)
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: fileURL.path, mask: [.write, .extend, .delete, .rename, .attrib])
    }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // The file may have been replaced; follow the new inode.
            self.watchFile()
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
