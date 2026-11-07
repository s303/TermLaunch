import AppKit

/// Kitty-style tab strip: content-sized `N. title` tabs joined by a separator, the active
/// one a solid block. Colors and font come from the Ghostty theme (see `[tabbar]` overrides);
/// tabs can be dragged sideways to reorder.
@MainActor
final class TabBarView: NSView {
    static let maxCells: CGFloat = 24
    static let minCells: CGFloat = 8
    private static let dragThreshold: CGFloat = 4

    var titles: [String] = [] { didSet { needsDisplay = true } }
    var activeIndex = 0 { didSet { needsDisplay = true } }
    var theme = TerminalTheme() { didSet { rebuildFont() } }
    var style = TabBarStyle() { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    /// Called on drop with the tab's old and new index.
    var onMove: ((Int, Int) -> Void)?

    private var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var cellWidth: CGFloat = 8

    // Drag state: the grabbed tab, its x offset from the cursor, the cursor x, and its slot so far.
    private var dragIndex: Int?
    private var dragOffset: CGFloat = 0
    private var dragX: CGFloat = 0
    private var dragTarget = 0
    private var dragging = false

    override var isFlipped: Bool { true }

    private func rebuildFont() {
        font = theme.fontFamily.flatMap { NSFont(name: $0, size: theme.fontSize) }
            ?? NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        cellWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        needsDisplay = true
    }

    // MARK: Colors

    private func resolve(_ spec: ColorSpec?, default fallback: NSColor) -> NSColor {
        switch spec {
        case .rgb(let r, let g, let b)?:
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        case .palette(let n)?: return theme.color(n)
        case nil: return fallback
        }
    }

    private var barColor: NSColor {
        resolve(style.background, default: theme.background.blended(withFraction: 0.3, of: .black) ?? theme.background)
    }

    // MARK: Layout

    private func label(_ index: Int) -> (number: String, title: String) { ("\(index + 1).", " " + titles[index]) }

    private var separatorWidth: CGFloat {
        style.separator.isEmpty ? 0 : (style.separator as NSString).size(withAttributes: [.font: font]).width
    }

    /// Tab widths: content-sized within [minCells, maxCells], shrunk evenly when they don't fit.
    private func tabWidths(separator: CGFloat) -> [CGFloat] {
        let lo = Self.minCells * cellWidth, hi = Self.maxCells * cellWidth
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let natural = titles.indices.map { i -> CGFloat in
            let l = label(i)
            let w = (l.number + l.title as NSString).size(withAttributes: attrs).width + 2 * cellWidth
            return min(max(w, lo), hi)
        }
        let avail = bounds.width - separator * CGFloat(max(titles.count - 1, 0))
        if natural.reduce(0, +) <= avail { return natural }
        var low: CGFloat = 0, high = hi
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if natural.map({ min($0, mid) }).reduce(0, +) > avail { high = mid } else { low = mid }
        }
        return natural.map { min($0, max(low, 1)) }
    }

    /// Slot rects for the tabs laid out in `order`.
    private func frames(widths: [CGFloat], order: [Int], separator: CGFloat) -> [Int: NSRect] {
        var x: CGFloat = 0
        var out: [Int: NSRect] = [:]
        for index in order {
            out[index] = NSRect(x: x, y: 0, width: widths[index], height: bounds.height)
            x += widths[index] + separator
        }
        return out
    }

    /// Tab order as drawn: during a drag the grabbed tab sits in its prospective slot.
    private var visualOrder: [Int] {
        var order = Array(titles.indices)
        if dragging, let from = dragIndex, order.indices.contains(from) {
            order.remove(at: from)
            order.insert(from, at: min(dragTarget, order.count))
        }
        return order
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        barColor.setFill()
        bounds.fill()
        guard !titles.isEmpty else { return }

        let sepW = separatorWidth
        let widths = tabWidths(separator: sepW)
        let order = visualOrder
        let slots = frames(widths: widths, order: order, separator: sepW)
        if sepW > 0 {
            let sepColor = theme.color(8)
            for n in order.indices.dropFirst() {
                let prev = slots[order[n - 1]]!
                drawText(style.separator, in: NSRect(x: prev.maxX, y: 0, width: sepW, height: bounds.height),
                         color: sepColor, align: .center)
            }
        }
        let grabbed = dragging ? dragIndex : nil
        for index in order where index != grabbed { drawTab(index, in: slots[index]!) }
        if let grabbed, let slot = slots[grabbed] {
            var r = slot
            r.origin.x = min(max(dragX - dragOffset, 0), max(bounds.width - r.width, 0))
            drawTab(grabbed, in: r)
        }
    }

    private func drawTab(_ index: Int, in rect: NSRect) {
        let active = index == activeIndex
        if active {
            resolve(style.activeBackground, default: theme.color(5)).setFill()
            rect.fill()
        }
        let numberColor = resolve(style.number, default: theme.color(2))
        let titleColor = active
            ? resolve(style.activeForeground, default: theme.background)
            : resolve(style.foreground, default: theme.foreground)
        let l = label(index)
        let inner = rect.insetBy(dx: cellWidth, dy: 0)
        let numW = (l.number as NSString).size(withAttributes: [.font: font]).width
        drawText(l.number, in: NSRect(x: inner.minX, y: 0, width: numW, height: bounds.height), color: numberColor, align: .left)
        drawText(l.title, in: NSRect(x: inner.minX + numW, y: 0, width: max(inner.width - numW, 0), height: bounds.height),
                 color: titleColor, align: .left)
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor, align: NSTextAlignment) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        para.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let h = (text as NSString).size(withAttributes: attrs).height
        (text as NSString).draw(in: NSRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h),
                                withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard !titles.isEmpty else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let sepW = separatorWidth
        let slots = frames(widths: tabWidths(separator: sepW), order: Array(titles.indices), separator: sepW)
        // Separator gaps belong to the tab on their left.
        guard let i = titles.indices.last(where: { x >= slots[$0]!.minX }) else { return }
        dragIndex = i
        dragOffset = x - slots[i]!.minX
        dragX = x
        dragTarget = i
        dragging = false
        onSelect?(i)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let from = dragIndex, titles.indices.contains(from) else { return }
        let x = convert(event.locationInWindow, from: nil).x
        if !dragging {
            guard abs(x - dragX) >= Self.dragThreshold else { return }
            dragging = true
        }
        dragX = x
        let sepW = separatorWidth
        let widths = tabWidths(separator: sepW)
        // Target slot: how many of the other tabs' midpoints lie left of the dragged tab's centre.
        let centre = min(max(x - dragOffset, 0), bounds.width) + widths[from] / 2
        var cursor: CGFloat = 0
        var target = 0
        for i in titles.indices where i != from {
            if centre > cursor + widths[i] / 2 { target += 1 }
            cursor += widths[i] + sepW
        }
        dragTarget = target
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragIndex = nil; dragging = false; needsDisplay = true }
        guard let from = dragIndex, dragging else { return }
        if dragTarget != from { onMove?(from, dragTarget) }
    }

    // Clicking the strip must not steal focus from the terminal.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
