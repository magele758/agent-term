import AppKit
import QuartzCore

// Fallout terminal / Pip-Boy CRT, from the in-game screen and the effects
// players actually turn off (flicker, shudder, fade):
// phosphor green grade, scanlines, interlace, glass sheen, vignette,
// rounded tube bezel, rolling refresh bar, grain, sudden flicker, horizontal shudder.
// Drawn as sibling layers above the terminal. Hit testing is off, so typing
// still reaches the shell. Animations are Core Animation, not a per-frame redraw.

final class CRTOverlay: NSView {
    private let grade = CALayer()
    private let scan = CALayer()
    private let sheen = CAGradientLayer()
    private let vignette = CALayer()
    private let noise = CALayer()
    private let sweep = CAGradientLayer()
    private let flicker = CALayer()
    private let bezel = CAShapeLayer()
    private var running = false
    private var sweepSpan: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true

        grade.backgroundColor = NSColor(srgbRed: 0.15, green: 1, blue: 0.35, alpha: 0.07).cgColor
        grade.compositingFilter = "softLightBlendMode"

        scan.backgroundColor = NSColor(patternImage: Self.scanImage()).cgColor
        scan.compositingFilter = "multiplyBlendMode"

        sheen.colors = [
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
        ]
        sheen.locations = [0, 0.42, 1]
        sheen.startPoint = CGPoint(x: 0, y: 1)
        sheen.endPoint = CGPoint(x: 1, y: 0)

        vignette.contents = Self.vignetteImage()
        vignette.contentsGravity = .resize

        noise.contents = Self.noiseImage()
        noise.contentsGravity = .resize
        noise.compositingFilter = "overlayBlendMode"
        noise.opacity = 0.16

        sweep.colors = [
            NSColor.clear.cgColor,
            NSColor(srgbRed: 0.75, green: 1, blue: 0.82, alpha: 0.16).cgColor,
            NSColor.clear.cgColor,
        ]
        sweep.startPoint = CGPoint(x: 0.5, y: 0)
        sweep.endPoint = CGPoint(x: 0.5, y: 1)
        sweep.compositingFilter = "screenBlendMode"

        flicker.backgroundColor = NSColor.black.cgColor
        flicker.opacity = 0

        bezel.fillColor = NSColor(srgbRed: 0.01, green: 0.03, blue: 0.01, alpha: 0.92).cgColor
        bezel.fillRule = .evenOdd

        for sub in [grade, scan, sheen, vignette, noise, sweep, flicker, bezel] {
            layer?.addSublayer(sub)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setEnabled(_ on: Bool) {
        if on == running && isHidden == !on { return }
        isHidden = !on
        if on {
            running = true
            startMotion()
            flashOn()
        } else {
            running = false
            sweepSpan = -1
            layer?.sublayers?.forEach { $0.removeAllAnimations() }
        }
    }

    override func layout() {
        super.layout()
        guard let host = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sub in [grade, scan, sheen, vignette, noise, flicker] {
            sub.frame = host.bounds
        }
        sweep.frame = CGRect(x: 0, y: 0, width: host.bounds.width, height: 10)
        bezel.frame = host.bounds
        bezel.path = Self.bezelPath(host.bounds)
        CATransaction.commit()
        if running, abs(host.bounds.height - sweepSpan) > 2 {
            startSweep(height: host.bounds.height)
        }
    }

    private func startMotion() {
        noise.removeAnimation(forKey: "drift")
        let drift = CABasicAnimation(keyPath: "transform.translation")
        drift.fromValue = CGPoint.zero
        drift.toValue = CGPoint(x: 18, y: -12)
        drift.duration = 0.18
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.isRemovedOnCompletion = false
        noise.add(drift, forKey: "drift")

        flicker.removeAnimation(forKey: "dip")
        let dip = CAKeyframeAnimation(keyPath: "opacity")
        dip.values = [0.0, 0.0, 0.11, 0.0, 0.02, 0.0, 0.16, 0.04, 0.0, 0.07, 0.0]
        dip.keyTimes = [0, 0.18, 0.19, 0.22, 0.45, 0.62, 0.63, 0.66, 0.78, 0.86, 1]
        dip.duration = 2.8
        dip.repeatCount = .infinity
        dip.isRemovedOnCompletion = false
        flicker.add(dip, forKey: "dip")

        scan.removeAnimation(forKey: "shudder")
        let shudder = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shudder.values = [0, 0, 1.5, -1, 0, 0, 2, 0]
        shudder.keyTimes = [0, 0.62, 0.63, 0.65, 0.67, 0.84, 0.85, 1]
        shudder.duration = 3.4
        shudder.repeatCount = .infinity
        shudder.isRemovedOnCompletion = false
        scan.add(shudder, forKey: "shudder")

        startSweep(height: bounds.height)
    }

    private func startSweep(height: CGFloat) {
        sweepSpan = height
        sweep.removeAnimation(forKey: "roll")
        guard height > 20 else { return }
        let roll = CABasicAnimation(keyPath: "position.y")
        roll.fromValue = height + 8
        roll.toValue = -8
        roll.duration = 7.5
        roll.repeatCount = .infinity
        roll.isRemovedOnCompletion = false
        sweep.add(roll, forKey: "roll")
    }

    private func flashOn() {
        let flash = CABasicAnimation(keyPath: "opacity")
        flash.fromValue = 0.55
        flash.toValue = 0
        flash.duration = 0.22
        flicker.add(flash, forKey: "power")
    }

    private static func scanImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 1, height: 4))
        image.lockFocus()
        NSColor(white: 0, alpha: 0.62).setFill()
        NSRect(x: 0, y: 3, width: 1, height: 1).fill()
        NSColor(white: 0, alpha: 0.18).setFill()
        NSRect(x: 0, y: 1, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
    }

    private static func vignetteImage() -> CGImage? {
        let side = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.15).cgColor,
            NSColor.black.withAlphaComponent(0.72).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0.45, 0.78, 1]
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return nil }
        ctx.drawRadialGradient(gradient,
                               startCenter: CGPoint(x: side / 2, y: side / 2), startRadius: 20,
                               endCenter: CGPoint(x: side / 2, y: side / 2), endRadius: CGFloat(side) * 0.72,
                               options: [])
        return ctx.makeImage()
    }

    private static func noiseImage() -> CGImage? {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let n = UInt8.random(in: 0...255)
            bytes[i] = n
            bytes[i + 1] = n
            bytes[i + 2] = n
            bytes[i + 3] = UInt8.random(in: 40...180)
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return image
    }

    private static func bezelPath(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(rect)
        let inner = rect.insetBy(dx: 7, dy: 7)
        path.addRoundedRect(in: inner, cornerWidth: 10, cornerHeight: 10)
        return path
    }
}
