import XCTest

private final class Entry: TabListEntry {
    let kind: TabKind
    init(_ kind: TabKind) { self.kind = kind }
}

final class TabListTests: XCTestCase {
    private func make(_ n: Int, active: Int? = nil) -> (TabList<Entry>, [Entry]) {
        var list = TabList<Entry>()
        let es = (0..<n).map { _ in Entry(.shell) }
        es.forEach { list.append($0) }
        if let active { list.select(active) }
        return (list, es)
    }

    func testAppendActivatesNewTab() {
        let (list, _) = make(3)
        XCTAssertEqual(list.activeIndex, 2)
    }

    func testCloseBeforeActiveShiftsDown() {
        var (list, es) = make(4, active: 2)
        let r = list.remove(es[0])
        XCTAssertEqual(r, .init(index: 0, nextActive: 1))
        XCTAssertTrue(list.active === es[2])
    }

    func testCloseActiveKeepsIndex() {
        var (list, es) = make(4, active: 1)
        XCTAssertEqual(list.remove(es[1])?.nextActive, 1)
        XCTAssertTrue(list.active === es[2])
    }

    func testCloseActiveLastClampsToEnd() {
        var (list, es) = make(3, active: 2)
        XCTAssertEqual(list.remove(es[2])?.nextActive, 1)
        XCTAssertTrue(list.active === es[1])
    }

    func testCloseAfterActiveKeeps() {
        var (list, es) = make(4, active: 1)
        XCTAssertEqual(list.remove(es[3])?.nextActive, 1)
        XCTAssertTrue(list.active === es[1])
    }

    func testCloseUnknownIsNil() {
        var (list, _) = make(2)
        XCTAssertNil(list.remove(Entry(.shell)))
        XCTAssertEqual(list.count, 2)
    }

    func testClosingLastEmptiesAndResetsNumbering() {
        var list = TabList<Entry>()
        XCTAssertEqual(list.nextShellTitle(), "shell 1")
        XCTAssertEqual(list.nextShellTitle(), "shell 2")
        let e = Entry(.shell)
        list.append(e)
        let r = list.remove(e)
        XCTAssertEqual(r, .init(index: 0, nextActive: nil))
        XCTAssertTrue(list.isEmpty)
        XCTAssertNil(list.active)
        XCTAssertEqual(list.nextShellTitle(), "shell 1")
    }

    func testNumberingNotResetWhileTabsRemain() {
        var (list, es) = make(2)
        _ = list.nextShellTitle()
        list.remove(es[0])
        XCTAssertEqual(list.nextShellTitle(), "shell 2")
    }

    func testWraparound() {
        var (list, _) = make(3, active: 2)
        list.selectNext()
        XCTAssertEqual(list.activeIndex, 0)
        list.selectPrevious()
        XCTAssertEqual(list.activeIndex, 2)
    }

    func testSelectOutOfRangeIgnored() {
        var (list, _) = make(2, active: 0)
        XCTAssertFalse(list.select(5))
        XCTAssertFalse(list.select(-1))
        XCTAssertEqual(list.activeIndex, 0)
    }

    func testEmptyNavigationIsSafe() {
        var list = TabList<Entry>()
        list.selectNext()
        list.selectPrevious()
        XCTAssertEqual(list.activeIndex, 0)
    }

    func testMoveKeepsSameTabActive() {
        var (list, es) = make(4, active: 1)
        list.move(from: 1, to: 3)
        XCTAssertTrue(list.active === es[1])
        XCTAssertEqual(list.activeIndex, 3)
        list.move(from: 0, to: 2)
        XCTAssertTrue(list.active === es[1])
        XCTAssertEqual(list.activeIndex, 3)
        list.move(from: 3, to: 0)
        XCTAssertTrue(list.active === es[1])
        XCTAssertEqual(list.activeIndex, 0)
    }

    func testMoveInvalidIgnored() {
        var (list, es) = make(3, active: 1)
        list.move(from: 0, to: 9)
        list.move(from: 1, to: 1)
        XCTAssertTrue(list.items[0] === es[0])
        XCTAssertEqual(list.activeIndex, 1)
    }

    func testCommandLookupAndActive() {
        var list = TabList<Entry>()
        let shell = Entry(.shell), a = Entry(.command(id: "a")), b = Entry(.command(id: "b"))
        [shell, a, b].forEach { list.append($0) }
        XCTAssertEqual(list.index(ofCommand: "a"), 1)
        XCTAssertEqual(list.index(ofCommand: "b"), 2)
        XCTAssertNil(list.index(ofCommand: "c"))
        XCTAssertTrue(list.isCommandTabActive("b"))
        XCTAssertFalse(list.isCommandTabActive("a"))
        list.select(0)
        XCTAssertFalse(list.isCommandTabActive("b"))
    }

    func testFirstShellIndex() {
        var list = TabList<Entry>()
        XCTAssertNil(list.firstShellIndex)
        list.append(Entry(.command(id: "a")))
        XCTAssertNil(list.firstShellIndex)
        list.append(Entry(.shell))
        list.append(Entry(.shell))
        XCTAssertEqual(list.firstShellIndex, 1)
    }
}
