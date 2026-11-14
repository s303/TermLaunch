import Foundation

/// What a Tab is: a Shell Tab or the (unique per id) Command Tab of a Command key.
enum TabKind: Equatable {
    case shell
    case command(id: String)
}

/// The part of a Tab the list bookkeeping needs; keeps this file free of AppKit.
protocol TabListEntry: AnyObject {
    var kind: TabKind { get }
}

/// Ordered Tabs, the active one, and Shell Tab numbering. Pure value type so the
/// rules (closing, moving, wraparound) are unit-tested without any views.
struct TabList<Element: TabListEntry> {
    /// What closing a Tab did: where it was, and the index to activate (nil if now empty).
    struct Removal: Equatable {
        let index: Int
        let nextActive: Int?
    }

    private(set) var items: [Element] = []
    private(set) var activeIndex = 0
    private(set) var shellCount = 0
    /// Shell Tabs, least to most recently active; Command Tabs never appear here.
    private var shellRecency: [Element] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    var active: Element? { items.indices.contains(activeIndex) ? items[activeIndex] : nil }

    /// Title for the next Shell Tab ("shell N"); numbering restarts once the list has emptied.
    mutating func nextShellTitle() -> String {
        shellCount += 1
        return "shell \(shellCount)"
    }

    /// Appends and activates the new Tab.
    mutating func append(_ element: Element) {
        items.append(element)
        activeIndex = items.count - 1
        touchActive()
    }

    func index(of element: Element) -> Int? { items.firstIndex { $0 === element } }
    func index(ofCommand id: String) -> Int? { items.firstIndex { $0.kind == .command(id: id) } }
    var firstShellIndex: Int? { items.firstIndex { $0.kind == .shell } }
    /// The most recently active Shell Tab (the Activation key's landing spot), if any.
    var lastActiveShellIndex: Int? { shellRecency.last.flatMap { index(of: $0) } }

    /// Records the active Tab as most recent if it is a Shell Tab.
    private mutating func touchActive() {
        guard let a = active, a.kind == .shell else { return }
        shellRecency.removeAll { $0 === a }
        shellRecency.append(a)
    }
    func isCommandTabActive(_ id: String) -> Bool { active?.kind == .command(id: id) }

    /// Returns false (and changes nothing) for an out-of-range index.
    @discardableResult
    mutating func select(_ index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        activeIndex = index
        touchActive()
        return true
    }

    mutating func selectNext() {
        if !items.isEmpty { activeIndex = (activeIndex + 1) % items.count; touchActive() }
    }

    mutating func selectPrevious() {
        if !items.isEmpty { activeIndex = (activeIndex - 1 + items.count) % items.count; touchActive() }
    }

    /// Drag-reorder; the same Tab stays active.
    mutating func move(from: Int, to: Int) {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return }
        let current = active
        items.insert(items.remove(at: from), at: to)
        if let current, let i = index(of: current) { activeIndex = i }
    }

    /// Removes a Tab. Closing one before the active Tab shifts the active index down,
    /// closing the active one keeps the index (clamped to the end), closing a later one keeps it.
    @discardableResult
    mutating func remove(_ element: Element) -> Removal? {
        guard let index = index(of: element) else { return nil }
        items.remove(at: index)
        shellRecency.removeAll { $0 === element }
        if items.isEmpty {
            shellCount = 0
            activeIndex = 0
            return Removal(index: index, nextActive: nil)
        }
        let next = index < activeIndex ? activeIndex - 1
            : index == activeIndex ? min(index, items.count - 1)
            : activeIndex
        activeIndex = next // not recorded as used: F1 falls back to the previous most recent shell
        return Removal(index: index, nextActive: next)
    }
}
