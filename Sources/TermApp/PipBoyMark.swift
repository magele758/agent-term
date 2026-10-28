import AppKit

/// Small original screen-face mark. Geometric only: round head, eyes, smile, antenna.
/// Not derived from any published character artwork.
final class PipBoyMark: NSView {
    static let side: CGFloat = 36

    private static let amber = NSColor(srgbRed: 0.95, green: 0.62, blue: 0.12, alpha: 1)
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        let box = frame.isEmpty ? NSRect(x: 0, y: 0, width: Self.side, height: Self.side) : frame
        super.init(frame: box)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.side, height: Self.side)
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        guard side > 1 else { return }
        let origin = NSPoint(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2
        )
        let ink = Self.amber
        ink.setStroke()
        ink.setFill()

        let head = NSRect(x: origin.x + side * 0.16, y: origin.y + side * 0.10, width: side * 0.68, height: side * 0.68)
        let outline = NSBezierPath(ovalIn: head)
        outline.lineWidth = max(1.2, side * 0.045)
        outline.stroke()

        let eye = side * 0.075
        let leftEye = NSRect(x: head.minX + head.width * 0.28, y: head.minY + head.height * 0.52, width: eye, height: eye)
        let rightEye = NSRect(x: head.minX + head.width * 0.60, y: head.minY + head.height * 0.52, width: eye, height: eye)
        NSBezierPath(ovalIn: leftEye).fill()
        NSBezierPath(ovalIn: rightEye).fill()

        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: head.minX + head.width * 0.32, y: head.minY + head.height * 0.34))
        smile.curve(
            to: NSPoint(x: head.minX + head.width * 0.68, y: head.minY + head.height * 0.34),
            controlPoint1: NSPoint(x: head.minX + head.width * 0.40, y: head.minY + head.height * 0.18),
            controlPoint2: NSPoint(x: head.minX + head.width * 0.60, y: head.minY + head.height * 0.18)
        )
        smile.lineWidth = max(1.1, side * 0.04)
        smile.lineCapStyle = .round
        smile.stroke()

        let mast = NSBezierPath()
        mast.move(to: NSPoint(x: head.midX, y: head.maxY))
        mast.line(to: NSPoint(x: head.midX, y: origin.y + side * 0.90))
        mast.lineWidth = max(1.1, side * 0.035)
        mast.lineCapStyle = .round
        mast.stroke()

        let tip = side * 0.07
        NSBezierPath(ovalIn: NSRect(
            x: head.midX - tip / 2,
            y: origin.y + side * 0.90 - tip / 2,
            width: tip,
            height: tip
        )).fill()
    }
}
