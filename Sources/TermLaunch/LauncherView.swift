import AppKit

/// The Launcher Tab: a search field at the bottom and results growing upward,
/// best match nearest the field (like `oa`). Rows come from the providers.
final class LauncherView: NSView, TabContent, NSTextFieldDelegate {
    /// An item ran or the user cancelled: the owner closes the Tab.
    var onFinish: (() -> Void)?

    private let model: LauncherModel
    private let appProvider: AppProvider
    private let field = SearchField()
    private let prompt = NSTextField(labelWithString: ">")
    private let list: ResultListView
    private let theme: TerminalTheme
    private let font: NSFont
    private var focused = false
    private var indexObserver: NSObjectProtocol?

    init(index: AppIndex, theme: TerminalTheme) {
        self.theme = theme
        font = theme.fontFamily.flatMap { NSFont(name: $0, size: theme.fontSize) }
            ?? NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        appProvider = AppProvider(index: index)
        let calc = CalcProvider { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        model = LauncherModel(providers: [calc, appProvider])
        list = ResultListView(model: model, theme: theme, font: font)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        wantsLayer = true
        layer?.backgroundColor = theme.background.cgColor

        prompt.font = font
        prompt.textColor = theme.color(4)
        field.font = font
        field.textColor = theme.foreground
        field.insertionColor = theme.foreground
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byClipping
        field.delegate = self
        list.onActivate = { [weak self] in self?.runSelected() }
        addSubview(list)
        addSubview(prompt)
        addSubview(field)

        indexObserver = NotificationCenter.default.addObserver(
            forName: AppIndex.didChange, object: index, queue: .main
        ) { [weak self] _ in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { if let indexObserver { NotificationCenter.default.removeObserver(indexObserver) } }

    // MARK: TabContent

    func cellMetrics() -> (cell: CGSize, padding: CGSize)? { nil }
    var focusView: NSView { field }
    func setOccluded(_ occluded: Bool) {}

    func setFocused(_ focused: Bool) {
        defer { self.focused = focused }
        guard focused, !self.focused else { return }
        // Shown again: fresh history and apps, and typing replaces the old query.
        appProvider.reloadFrecency()
        reload()
        field.selectText(nil)
    }

    /// Inactive Tabs stay mounted at zero opacity; they must not take clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue == 0 ? nil : super.hitTest(point)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let fieldHeight = ceil(lineHeight * 1.8)
        let pad = ceil(lineHeight * 0.6)
        let promptWidth = ceil(("> " as NSString).size(withAttributes: [.font: font]).width)
        let textY = ((fieldHeight - lineHeight) / 2).rounded()
        prompt.frame = NSRect(x: pad, y: textY, width: promptWidth, height: lineHeight)
        field.frame = NSRect(x: pad + promptWidth, y: textY, width: bounds.width - 2 * pad - promptWidth, height: lineHeight)
        list.frame = NSRect(x: 0, y: fieldHeight, width: bounds.width, height: max(bounds.height - fieldHeight, 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Rule between the results and the search field.
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        theme.color(8).withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: ceil(lineHeight * 1.8) - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: Behaviour

    private func reload() {
        model.setQuery(field.stringValue)
        list.reload()
    }

    private func runSelected() {
        guard let item = model.selectedItem else { return }
        item.run()
        onFinish?()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    /// rush's bindings first (several collide with Cocoa's emacs defaults, e.g.
    /// Ctrl-K, Ctrl-H, Ctrl-J), then the standard selectors. Keys match the
    /// physical key, like the chord, so they work in any keyboard layout.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if let event = NSApp.currentEvent, event.type == .keyDown,
           event.modifierFlags.intersection([.control, .command, .option]) == .control {
            switch KeySpec.name(forKeyCode: event.keyCode) {
            case "j", "n": model.moveDown(); list.reload(); return true
            case "k", "p": model.moveUp(); list.reload(); return true
            case "h": textView.moveLeft(nil); return true
            case "l": textView.moveRight(nil); return true
            case "w": textView.deleteWordBackward(nil); return true
            case "u": textView.deleteToBeginningOfLine(nil); return true
            case "c": onFinish?(); return true
            default: break
            }
        }
        switch selector {
        case #selector(NSResponder.moveUp(_:)): model.moveUp(); list.reload()
        case #selector(NSResponder.moveDown(_:)): model.moveDown(); list.reload()
        case #selector(NSResponder.insertNewline(_:)): runSelected()
        case #selector(NSResponder.cancelOperation(_:)): onFinish?()
        default: return false
        }
        return true
    }
}

/// The search field: tints the caret and handles ⌘C/V/X/A/Z itself, since the
/// Dropdown has no Edit menu to route them.
private final class SearchField: NSTextField {
    var insertionColor: NSColor = .white

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.insertionPointColor = insertionColor
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]) == .command,
              let editor = currentEditor() else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        switch KeySpec.name(forKeyCode: event.keyCode) {
        case "c": editor.copy(nil)
        case "v": editor.paste(nil)
        case "x": editor.cut(nil)
        case "a": editor.selectAll(nil)
        case "z": shift ? editor.undoManager?.redo() : editor.undoManager?.undo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

/// Draws the visible rows bottom-up: row 0 (the best match) sits on the search
/// field. The window scrolls only when the selection reaches its top row.
private final class ResultListView: NSView {
    var onActivate: (() -> Void)?
    private let model: LauncherModel
    private let theme: TerminalTheme
    private let font: NSFont
    private let rowHeight: CGFloat
    /// Index of the bottom visible row.
    private var offset = 0
    private var icons: [String: NSImage] = [:]

    init(model: LauncherModel, theme: TerminalTheme, font: NSFont) {
        self.model = model
        self.theme = theme
        self.font = font
        rowHeight = ceil((font.ascender - font.descender + font.leading) * 1.5)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private var visibleRows: Int { max(Int(bounds.height / rowHeight), 1) }

    func reload() {
        let selected = model.selected
        offset = min(offset, max(model.items.count - visibleRows, 0))
        if selected < offset { offset = selected }
        if selected >= offset + visibleRows { offset = selected - visibleRows + 1 }
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reload()
    }

    private func icon(_ path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons[path] = image
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        let pad = ceil(rowHeight * 0.4)
        let textHeight = ceil(font.ascender - font.descender)
        let iconSize = rowHeight - 6
        guard !model.items.isEmpty else {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.color(8)]
            ("no results" as NSString).draw(at: NSPoint(x: pad + iconSize + pad, y: (rowHeight - textHeight) / 2), withAttributes: attrs)
            return
        }
        let end = min(offset + visibleRows, model.items.count)
        for i in offset..<end {
            let item = model.items[i]
            let row = NSRect(x: 0, y: CGFloat(i - offset) * rowHeight, width: bounds.width, height: rowHeight)
            let isSelected = i == model.selected
            if isSelected {
                theme.foreground.withAlphaComponent(0.08).setFill()
                row.fill()
                theme.color(3).setFill()
                NSRect(x: 0, y: row.minY + 3, width: 3, height: rowHeight - 6).fill()
            }
            if let path = item.iconPath {
                icon(path).draw(in: NSRect(x: pad, y: row.minY + 3, width: iconSize, height: iconSize))
            }
            let color = isSelected ? theme.color(3) : theme.foreground
            let textY = row.minY + (rowHeight - textHeight) / 2
            let textX = pad + iconSize + pad
            var hintWidth: CGFloat = 0
            if let hint = item.hint {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.color(8)]
                hintWidth = (hint as NSString).size(withAttributes: attrs).width
                (hint as NSString).draw(at: NSPoint(x: bounds.width - pad - hintWidth, y: textY), withAttributes: attrs)
            }
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
            (item.title as NSString).draw(
                in: NSRect(x: textX, y: textY, width: max(bounds.width - textX - pad - hintWidth - pad, 0), height: textHeight),
                withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        let index = offset + Int(y / rowHeight)
        guard model.items.indices.contains(index) else { return }
        model.select(index)
        reload()
        if event.clickCount == 2 { onActivate?() }
    }

    override func scrollWheel(with event: NSEvent) {
        // Wheel moves the selection, which scrolls the window as needed.
        let delta = event.scrollingDeltaY
        guard abs(delta) >= 1 else { return }
        if delta > 0 { model.moveUp() } else { model.moveDown() }
        reload()
    }
}
