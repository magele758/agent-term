import AppKit

enum Glass {
    static func install(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func effect(_ material: NSVisualEffectView.Material) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    static func titleInset(in view: NSView) -> CGFloat {
        guard let window = view.window else { return 16 }
        return max(16, window.frame.height - window.contentLayoutRect.maxY)
    }
}

final class LensSheen: NSView {
    private let shine = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        shine.colors = [
            NSColor.white.withAlphaComponent(0.42).cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor,
        ]
        shine.locations = [0, 0.05, 0.18]
        shine.startPoint = CGPoint(x: 0.5, y: 1)
        shine.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(shine)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        shine.frame = bounds
        layer?.cornerRadius = 22
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
