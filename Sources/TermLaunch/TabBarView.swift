import AppKit

/// Thin custom tab strip. Equal-width cells; click selects.
final class TabBarView: NSView {
    static let height: CGFloat = 24

    var titles: [String] = [] { didSet { needsDisplay = true } }
    var activeIndex = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 1).setFill()
        bounds.fill()
        guard !titles.isEmpty else { return }

        let cellWidth = bounds.width / CGFloat(titles.count)
        let font = NSFont.systemFont(ofSize: 11)
        for (i, title) in titles.enumerated() {
            let cell = NSRect(x: CGFloat(i) * cellWidth, y: 0, width: cellWidth, height: bounds.height)
            let active = i == activeIndex
            if active {
                NSColor(white: 0.18, alpha: 1).setFill()
                cell.fill()
            }
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(white: active ? 0.95 : 0.55, alpha: 1),
                .paragraphStyle: para,
            ]
            let text = "\(i + 1)  \(title)" as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(
                in: cell.insetBy(dx: 8, dy: (cell.height - size.height) / 2),
                withAttributes: attrs
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !titles.isEmpty else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let index = Int(x / (bounds.width / CGFloat(titles.count)))
        onSelect?(min(max(index, 0), titles.count - 1))
    }

    // Clicking the strip must not steal focus from the terminal.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
