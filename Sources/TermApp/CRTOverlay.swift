import AppKit
import Metal
import QuartzCore

// cool-retro-term look: the terminal pixels themselves are the source.
// A light barrel bow, phosphor bloom, scanline beams, and edge RGB shift.
// Edges stay the sampled terminal — no black tube bezel.
// Hit testing stays off so keystrokes still reach the shell underneath.

final class CRTOverlay: NSView {
    private(set) var isEnabled = false
    private weak var source: NSView?
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var fadePipeline: MTLRenderPipelineState?
    private var frameTex: MTLTexture?
    private var texture: MTLTexture?
    private var ghost = [MTLTexture?](repeating: nil, count: 2)
    private var ghostSlot = 0
    private var clearGhost = false
    private var pixels: UnsafeMutableRawPointer?
    private var pixW = 0
    private var pixH = 0
    private var link: CADisplayLink?
    private var scratch: NSBitmapImageRep?
    private var lastCapture = 0.0
    private let started = CACurrentMediaTime()
    private var clear = MTLClearColor(red: 0.23, green: 0.14, blue: 0.06, alpha: 1)
    private var phosphor = (r: Float(0.87), g: Float(0.52), b: Float(0.13))

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let metal = CAMetalLayer()
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.isOpaque = true
        metal.presentsWithTransaction = true
        return metal
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func bind(_ view: NSView) {
        source = view
        view.wantsLayer = true
    }

    func setBackground(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        clear = MTLClearColor(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: 0.2)
    }

    func setForeground(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        phosphor = (Float(srgb.redComponent), Float(srgb.greenComponent), Float(srgb.blueComponent))
    }

    func setEnabled(_ on: Bool) {
        if on == isEnabled { return }
        isEnabled = on
        isHidden = !on
        if on {
            startMetal()
        } else {
            link?.invalidate()
            link = nil
        }
    }

    override func layout() {
        super.layout()
        attachDevice()
        guard let metal = layer as? CAMetalLayer else { return }
        let scale = window?.backingScaleFactor ?? 2
        metal.contentsScale = scale
        metal.drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, isEnabled else { return }
        attachDevice()
        armLink()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard window != nil, isEnabled else { return }
        attachDevice()
        armLink()
    }

    private func attachDevice() {
        guard let device, let metal = layer as? CAMetalLayer else { return }
        if metal.device == nil { metal.device = device }
    }

    private func startMetal() {
        guard pipeline == nil else { armLink(); return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            FileHandle.standardError.write(Data("crt: no metal device\n".utf8))
            return
        }
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "crt_vert")
            desc.fragmentFunction = library.makeFunction(name: "crt_frag")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
            let fade = MTLRenderPipelineDescriptor()
            fade.vertexFunction = library.makeFunction(name: "crt_vert")
            fade.fragmentFunction = library.makeFunction(name: "fade_frag")
            fade.colorAttachments[0].pixelFormat = .bgra8Unorm
            fadePipeline = try device.makeRenderPipelineState(descriptor: fade)
        } catch {
            FileHandle.standardError.write(Data("crt: \(error)\n".utf8))
            return
        }
        self.device = device
        self.queue = queue
        if let metal = layer as? CAMetalLayer { metal.device = device }
        armLink()
    }

    private func armLink() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        guard isEnabled, isHiddenOrHasHiddenAncestor == false, bounds.width > 2, bounds.height > 2,
              let source, let pipeline, let queue,
              let metal = layer as? CAMetalLayer, metal.device != nil,
              let drawable = metal.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        if now - lastCapture >= 0.032, capture(source, scale: metal.contentsScale) {
            lastCapture = now
        }
        guard texture != nil else { return }
        let dw = max(1, Int(metal.drawableSize.width))
        let dh = max(1, Int(metal.drawableSize.height))
        ensureTargets(dw, dh)
        guard let frameTex, let prev = ghost[ghostSlot], let next = ghost[1 - ghostSlot], let fadePipeline else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: clear.red, green: clear.green, blue: clear.blue, alpha: 1)
        guard let buffer = queue.makeCommandBuffer() else { return }
        if clearGhost {
            for slot in ghost {
                guard let slot else { continue }
                let wipe = MTLRenderPassDescriptor()
                wipe.colorAttachments[0].texture = slot
                wipe.colorAttachments[0].loadAction = .clear
                wipe.colorAttachments[0].storeAction = .store
                wipe.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                buffer.makeRenderCommandEncoder(descriptor: wipe)?.endEncoding()
            }
            clearGhost = false
        }
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var u = CRTUniforms(
            time: Float(CACurrentMediaTime() - started),
            curvature: 0.20,
            frame: 0.008,
            bloom: 0.85,
            scan: 0.85,
            rgbShift: 0.0011,
            lines: Float(bounds.height * metal.contentsScale / 2.0),
            glassR: Float(clear.red),
            glassG: Float(clear.green),
            glassB: Float(clear.blue),
            fgR: phosphor.r,
            fgG: phosphor.g,
            fgB: phosphor.b
        )
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentTexture(prev, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        let fadePass = MTLRenderPassDescriptor()
        fadePass.colorAttachments[0].texture = next
        fadePass.colorAttachments[0].loadAction = .dontCare
        fadePass.colorAttachments[0].storeAction = .store
        if let fadeEnc = buffer.makeRenderCommandEncoder(descriptor: fadePass) {
            fadeEnc.setRenderPipelineState(fadePipeline)
            fadeEnc.setFragmentTexture(texture, index: 0)
            fadeEnc.setFragmentTexture(prev, index: 1)
            fadeEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            fadeEnc.endEncoding()
            ghostSlot = 1 - ghostSlot
        }
        buffer.commit()
        buffer.waitUntilScheduled()
        drawable.present()
    }

    private func ensureTargets(_ w: Int, _ h: Int) {
        let fresh = frameTex?.width != w || ghost[0] == nil
        if frameTex?.width == w, frameTex?.height == h, ghost[0] != nil { return }
        frameTex = makeTarget(w, h)
        ghost = [makeTarget(w, h), makeTarget(w, h)]
        ghostSlot = 0
        if fresh { clearGhost = true }
    }

    private func makeTarget(_ w: Int, _ h: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private
        return device?.makeTexture(descriptor: desc)
    }

    private func capture(_ view: NSView, scale: CGFloat) -> Bool {
        let w = max(1, Int(view.bounds.width * scale))
        let h = max(1, Int(view.bounds.height * scale))
        guard let device else { return false }
        let rep: NSBitmapImageRep
        if let scratch, scratch.pixelsWide == w, scratch.pixelsHigh == h {
            rep = scratch
        } else {
            guard let made = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [.thirtyTwoBitLittleEndian, .alphaFirst],
                bytesPerRow: w * 4, bitsPerPixel: 32) else { return false }
            scratch = made
            rep = made
        }
        guard let data = rep.bitmapData, let gfx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        gfx.cgContext.translateBy(x: 0, y: CGFloat(h))
        gfx.cgContext.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfx
        let hidden = view.layer?.opacity ?? 1
        let contents = view.layer?.contents
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.opacity = 1
        view.layer?.contents = nil
        func reveal(_ v: NSView) {
            v.layer?.opacity = 1
            v.layer?.removeAllAnimations()
            for child in v.subviews { reveal(child) }
        }
        reveal(view)
        view.displayIgnoringOpacity(view.bounds, in: gfx)
        gfx.cgContext.setFillColor(CGColor(red: CGFloat(phosphor.r), green: CGFloat(phosphor.g), blue: CGFloat(phosphor.b), alpha: 1))
        for sub in view.subviews where sub.isHidden == false && sub.frame.width > 1 && sub.frame.height > 1 {
            gfx.cgContext.fill(sub.frame)
        }
        view.layer?.contents = contents
        view.layer?.opacity = hidden
        CATransaction.commit()
        NSGraphicsContext.restoreGraphicsState()
        if pixW != w || pixH != h || texture == nil {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead]
            texture = device.makeTexture(descriptor: desc)
            pixW = w
            pixH = h
        }
        texture?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        return texture != nil
    }

    deinit {
        link?.invalidate()
        pixels?.deallocate()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct U {
        float time;
        float curvature;
        float frame;
        float bloom;
        float scan;
        float rgbShift;
        float lines;
        float glassR;
        float glassG;
        float glassB;
        float fgR;
        float fgG;
        float fgB;
    };

    struct VOut {
        float4 pos [[position]];
        float2 uv;
    };

    vertex VOut crt_vert(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, p.y);
        return o;
    }

    float2 barrel(float2 uv, float curvature, float frame) {
        float2 padded = uv * (1.0 + frame * 2.0) - frame;
        float2 cc = padded - 0.5;
        float dist = dot(cc, cc) * curvature;
        return padded + cc * (1.0 + dist) * dist;
    }

    fragment float4 crt_frag(VOut in [[stage_in]],
                             texture2d<float> src [[texture(0)]],
                             texture2d<float> ghost [[texture(1)]],
                             constant U &u [[buffer(0)]]) {
        constexpr sampler smp(address::clamp_to_edge, filter::linear);
        float2 curved = barrel(in.uv, u.curvature, u.frame);
        float2 box = min(curved, 1.0 - curved);
        float inside = smoothstep(-0.002, 0.012, min(box.x, box.y));
        float2 noiseUv = curved * 6.0 + float2(fract(u.time / 0.051), fract(u.time / 0.237));
        float nA = fract(sin(dot(floor(noiseUv * 48.0), float2(12.9898, 78.233))) * 43758.5453);
        float nB = fract(sin(dot(floor(noiseUv * 48.0) + 19.0, float2(39.346, 11.135))) * 43758.5453);
        float2 su = curved + (float2(nB, nA) - 0.5) * float2(0.00035, 0.0001);
        float hnoise = fract(sin(floor(u.time * 2.5) * 91.7) * 43758.5453);
        float randval = 0.074 - hnoise;
        float dscale = step(0.0, randval) * randval * 0.45;
        float dfreq = mix(4.0, 40.0, fract(sin(floor(u.time * 2.5) * 17.3) * 43758.5453));
        su.x += sin((curved.y + u.time) * dfreq) * dscale * 0.006;
        float2 clamped = clamp(su, 0.0, 1.0);
        float2 suv = clamped;
        float2 texel = 1.0 / float2(src.get_width(), src.get_height());

        float3 glass = float3(u.glassR, u.glassG, u.glassB);
        float3 fg = float3(u.fgR, u.fgG, u.fgB);
        float3 raw = src.sample(smp, suv).rgb;
        float lum = dot(raw, float3(0.30, 0.59, 0.11));
        float3 c = mix(glass, fg, smoothstep(0.04, 0.62, lum));
        float edge = length(curved - 0.5);
        float shift = u.rgbShift * (0.35 + edge * 2.2);
        float3 right = src.sample(smp, suv + float2(shift, 0.0)).rgb;
        float3 left = src.sample(smp, suv - float2(shift, 0.0)).rgb;
        c.r = left.r * 0.18 + c.r * 0.82;
        c.b = right.b * 0.18 + c.b * 0.82;

        float3 glow = float3(0.0);
        float wsum = 0.0;
        for (int i = -3; i <= 3; i++) {
            for (int j = -3; j <= 3; j++) {
                float w = exp(-float(i * i + j * j) * 0.22);
                float s = dot(src.sample(smp, suv + float2(i, j) * texel * 1.8).rgb, float3(0.30, 0.59, 0.11));
                glow += src.sample(smp, suv + float2(i, j) * texel * 1.8).rgb * w * s;
                wsum += w;
            }
        }
        c += glow / max(wsum, 0.0001) * u.bloom * 0.55;

        float beam = abs(sin(curved.y * u.lines * 3.14159));
        c *= mix(0.84, 1.06, beam);

        float2 vig = (clamped - 0.5) * 2.0;
        float vigAmt = clamp(1.0 - dot(vig * float2(0.35, 0.42), vig * float2(0.35, 0.42)), 0.0, 1.0);
        c *= mix(0.78, 1.0, vigAmt);

        float distc = length(curved - 0.5);
        c += fg * nA * 0.028 * max(0.0, 1.0 - distc * 1.3) * inside;
        float sweep = fract(u.time * 0.15);
        float pass = smoothstep(0.03, 0.0, abs(curved.y - sweep));
        c += fg * pass * 0.045 * inside;
        float flickNoise = fract(sin(floor(u.time * 1.5) * 12.9898) * 43758.5453);
        c *= 1.0 + (flickNoise - 0.5) * 0.035;
        float2 puv = in.pos.xy / float2(ghost.get_width(), ghost.get_height());
        float4 acc = ghost.sample(smp, puv);
        float g = dot(raw, float3(0.21, 0.72, 0.04));
        float trail = max(0.0, acc.r - g);
        float span = ghost.get_width();
        trail = max(trail, max(0.0, ghost.sample(smp, puv - float2(8.0 / span, 0.0)).r - g) * 0.72);
        trail = max(trail, max(0.0, ghost.sample(smp, puv - float2(16.0 / span, 0.0)).r - g) * 0.4);
        c = max(c, fg * trail * 0.9);
        c += fg * acc.g * 0.55;
        float rim = smoothstep(0.0, 0.016, min(box.x, box.y)) * smoothstep(0.04, 0.01, min(box.x, box.y));
        c += fg * rim * 0.08;
        c = mix(glass * 0.35, c, inside);
        return float4(c, 1.0);
    }

    fragment float4 fade_frag(VOut in [[stage_in]],
                              texture2d<float> frame [[texture(0)]],
                              texture2d<float> prev [[texture(1)]]) {
        constexpr sampler smp(address::clamp_to_edge, filter::linear);
        float2 curved = barrel(in.uv, 0.20, 0.008);
        float2 clamped = clamp(curved, 0.0, 1.0);
        float lum = dot(frame.sample(smp, clamped).rgb, float3(0.21, 0.72, 0.04));
        float2 texel = 1.0 / float2(frame.get_width(), frame.get_height());
        float left = dot(frame.sample(smp, clamped - float2(3.0, 0.0) * texel).rgb, float3(0.21, 0.72, 0.04));
        float right = dot(frame.sample(smp, clamped + float2(3.0, 0.0) * texel).rgb, float3(0.21, 0.72, 0.04));
        float cursor = lum * step(0.4, lum) * step(0.35, min(left, right));
        float2 puv = in.pos.xy / float2(prev.get_width(), prev.get_height());
        float4 old = prev.sample(smp, puv);
        return float4(max(old.r - 0.028, lum), max(old.g - 0.018, cursor), 0.0, 1.0);
    }
    """
}

private struct CRTUniforms {
    var time: Float
    var curvature: Float
    var frame: Float
    var bloom: Float
    var scan: Float
    var rgbShift: Float
    var lines: Float
    var glassR: Float
    var glassG: Float
    var glassB: Float
    var fgR: Float
    var fgG: Float
    var fgB: Float
}
