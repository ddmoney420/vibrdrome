#if DEBUG
import Metal
import MetalKit
import simd

/// Uniforms shared with the inline Metal source (layout must match `struct Uniforms`
/// in `shaderSource`: float2 first for 8-byte alignment, then packed scalars).
struct PermissiveUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var decay: Float        // feedback persistence
    var zoom: Float         // per-frame feedback zoom
    var rotate: Float       // per-frame feedback rotation
    var paletteShift: Float
    // Preset-driven (Phase 3): selected palette + audio→effect mapping coefficients.
    var paletteIndex: Float
    var pulseScale: Float
    var zoomBass: Float
    var rotateTreble: Float
    var pulseBass: Float
    // Phase 4 visual-depth knobs.
    var bloomStrength: Float
    var waveformStrength: Float
    // Phase 6 flow-engine knobs + the CPU-computed onset envelope.
    var flow: Float
    var flowScale: Float
    var beatFlow: Float
    var beatBloom: Float
    var hueDrift: Float
    var beatPulse: Float    // 0..1 onset envelope from the spectral-flux detector
    // Phase 7 — tunnel pull + waveform-line brightness.
    var tunnel: Float
    var waveBright: Float
    // Phase 7b — bilateral mirror + vibrance.
    var symmetry: Float     // 0 = off, 1 = vertical mirror (L/R), 2 = quad (4-way)
    var vibrance: Float     // saturation + brightness multiplier (1 = neutral)
    // Phase 7c "wow" — field spin (time + beat driven rotation).
    var spin: Float
}

/// Research Step 2 — DEBUG-only native Metal feedback prototype (permissive visualizer
/// spike). Two `rgba16Float` textures are ping-ponged: each frame warps + decays the
/// prior frame and adds a small audio-reactive pulse, then a present pass maps the
/// field through a palette to the drawable. Original Vibrdrome code; Apple Metal only.
///
/// The inline `shaderSource` is a HARDCODED DEBUG constant compiled at runtime
/// (`makeLibrary(source:)`) solely to keep the prototype out of the release metallib.
/// It is NOT loaded from disk/network/user input. Future user/community presets must
/// NOT compile arbitrary/downloaded shader code without a separate security review.
final class PermissiveFeedbackRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let feedbackPSO: MTLRenderPipelineState
    private let bloomPSO: MTLRenderPipelineState     // Phase 4
    private let wavePSO: MTLRenderPipelineState       // Phase 7 — waveform line geometry
    private let presentPSO: MTLRenderPipelineState

    static let maxWaveVerts = 1024
    private let waveBuffer: MTLBuffer                 // NDC float2 positions for the wave line
    private var waveCount = 0

    private var texA: MTLTexture?
    private var texB: MTLTexture?
    private var bloomTex: MTLTexture?                 // half-res bloom (Phase 4)
    private var readIsA = true
    private var lastWritten: MTLTexture?
    private var staging: MTLTexture?          // 1x1 readback (proof only)
    private var size: CGSize = .zero
    private var clearNext = true

    static let bandCount = 32
    private let bandsBuffer: MTLBuffer        // 32 FFT magnitudes for the overlay (Phase 4)

    static let feedbackFormat: MTLPixelFormat = .rgba16Float

    init?(device: MTLDevice) {
        self.device = device
        guard let q = device.makeCommandQueue(),
              let bands = device.makeBuffer(length: Self.bandCount * MemoryLayout<Float>.stride,
                                            options: .storageModeShared),
              let wave = device.makeBuffer(length: Self.maxWaveVerts * MemoryLayout<SIMD2<Float>>.stride,
                                           options: .storageModeShared) else { return nil }
        queue = q
        bandsBuffer = bands
        waveBuffer = wave
        do {
            let lib = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let fd = MTLRenderPipelineDescriptor()
            fd.vertexFunction = lib.makeFunction(name: "pv_vertex")
            fd.fragmentFunction = lib.makeFunction(name: "pv_feedback")
            fd.colorAttachments[0].pixelFormat = Self.feedbackFormat
            feedbackPSO = try device.makeRenderPipelineState(descriptor: fd)

            let bd = MTLRenderPipelineDescriptor()
            bd.vertexFunction = lib.makeFunction(name: "pv_vertex")
            bd.fragmentFunction = lib.makeFunction(name: "pv_bloom")
            bd.colorAttachments[0].pixelFormat = Self.feedbackFormat
            bloomPSO = try device.makeRenderPipelineState(descriptor: bd)

            // Wave line pass — additive blend so thin bright lines accumulate into the
            // feedback field (the warp loop then pulls them into filaments).
            let wd = MTLRenderPipelineDescriptor()
            wd.vertexFunction = lib.makeFunction(name: "pv_wave_vertex")
            wd.fragmentFunction = lib.makeFunction(name: "pv_wave_fragment")
            wd.colorAttachments[0].pixelFormat = Self.feedbackFormat
            wd.colorAttachments[0].isBlendingEnabled = true
            wd.colorAttachments[0].rgbBlendOperation = .add
            wd.colorAttachments[0].alphaBlendOperation = .add
            wd.colorAttachments[0].sourceRGBBlendFactor = .one
            wd.colorAttachments[0].destinationRGBBlendFactor = .one
            wd.colorAttachments[0].sourceAlphaBlendFactor = .one
            wd.colorAttachments[0].destinationAlphaBlendFactor = .one
            wavePSO = try device.makeRenderPipelineState(descriptor: wd)

            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = lib.makeFunction(name: "pv_vertex")
            pd.fragmentFunction = lib.makeFunction(name: "pv_present")
            pd.colorAttachments[0].pixelFormat = .bgra8Unorm
            presentPSO = try device.makeRenderPipelineState(descriptor: pd)
        } catch {
            return nil
        }
    }

    /// Upload the current 32-band magnitudes for the overlay (called each frame).
    func setBands(_ bands: [Float]) {
        let ptr = bandsBuffer.contents().bindMemory(to: Float.self, capacity: Self.bandCount)
        for i in 0..<Self.bandCount { ptr[i] = i < bands.count ? bands[i] : 0 }
    }

    /// Upload the waveform line as NDC positions (built host-side from PCM). Pass an empty
    /// array to draw no line this frame (e.g. legacy presets, or no PCM available).
    func setWaveform(_ points: [SIMD2<Float>]) {
        let n = min(points.count, Self.maxWaveVerts)
        if n > 0 {
            let ptr = waveBuffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: Self.maxWaveVerts)
            for i in 0..<n { ptr[i] = points[i] }
        }
        waveCount = n
    }

    func resize(to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0, newSize != size else { return }
        size = newSize
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.feedbackFormat,
            width: Int(newSize.width), height: Int(newSize.height), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        texA = device.makeTexture(descriptor: d)
        texB = device.makeTexture(descriptor: d)

        // Quarter-res bloom target (cheap; keeps the prototype near 60fps on device).
        let bw = max(1, Int(newSize.width) / 4), bh = max(1, Int(newSize.height) / 4)
        let bd = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.feedbackFormat, width: bw, height: bh, mipmapped: false)
        bd.usage = [.renderTarget, .shaderRead]
        bd.storageMode = .private
        bloomTex = device.makeTexture(descriptor: bd)

        clearNext = true
    }

    @MainActor
    func render(in view: MTKView, uniforms: PermissiveUniforms) {
        guard let texA, let texB, let bloomTex,
              let drawable = view.currentDrawable,
              let presentRPD = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }
        var u = uniforms
        let read = readIsA ? texA : texB
        let write = readIsA ? texB : texA

        // Pass A — feedback (offscreen): warp + decay the prior frame, add audio pulse.
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = write
        rpd.colorAttachments[0].loadAction = clearNext ? .clear : .load
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rpd.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(feedbackPSO)
            enc.setFragmentTexture(read, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // Pass A2 — waveform line (NEW): draw the audio waveform as thin bright additive
        // geometry INTO the feedback field, so next frame's warp/flow/tunnel pulls it into
        // filaments. Loads (not clears) the field written by Pass A.
        if waveCount > 1 {
            let wrpd = MTLRenderPassDescriptor()
            wrpd.colorAttachments[0].texture = write
            wrpd.colorAttachments[0].loadAction = .load
            wrpd.colorAttachments[0].storeAction = .store
            if let enc = cb.makeRenderCommandEncoder(descriptor: wrpd) {
                enc.setRenderPipelineState(wavePSO)
                enc.setVertexBuffer(waveBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 1)
                enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
                enc.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: waveCount)
                enc.endEncoding()
            }
        }

        // Pass B — bloom (half-res): bright-pass + small blur of the feedback field.
        let brpd = MTLRenderPassDescriptor()
        brpd.colorAttachments[0].texture = bloomTex
        brpd.colorAttachments[0].loadAction = .clear
        brpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        brpd.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: brpd) {
            enc.setRenderPipelineState(bloomPSO)
            enc.setFragmentTexture(write, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // Pass C — present: field + bloom + audio-spectrum overlay → drawable.
        if let enc = cb.makeRenderCommandEncoder(descriptor: presentRPD) {
            enc.setRenderPipelineState(presentPSO)
            enc.setFragmentTexture(write, index: 0)
            enc.setFragmentTexture(bloomTex, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
            enc.setFragmentBuffer(bandsBuffer, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        cb.present(drawable)
        cb.commit()
        lastWritten = write
        readIsA.toggle()
        clearNext = false
    }

    /// 1×1 center-texel readback of the latest feedback frame. **Proof-only — called
    /// ~once per second, never per frame** (issues its own blit + waitUntilCompleted).
    func readCenter() -> (UInt8, UInt8, UInt8) {
        guard let src = lastWritten else { return (0, 0, 0) }
        if staging == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
            d.storageMode = .shared
            staging = device.makeTexture(descriptor: d)
        }
        guard let staging,
              let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return (0, 0, 0) }
        blit.copy(from: src, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: src.width / 2, y: src.height / 2, z: 0),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        // rgba16Float = 4 half-floats. Read raw UInt16 (Float16 isn't available on
        // x86_64) and convert to a 0-255 byte for the proof indicator.
        var halves = [UInt16](repeating: 0, count: 4)
        staging.getBytes(&halves, bytesPerRow: 8,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: 1, height: 1, depth: 1)),
                         mipmapLevel: 0)
        func toByte(_ h: UInt16) -> UInt8 { UInt8(max(0, min(255, Self.halfToFloat(h) * 255))) }
        return (toByte(halves[0]), toByte(halves[1]), toByte(halves[2]))
    }

    /// IEEE-754 half (binary16) → Float. Avoids the `Float16` type, which is
    /// unavailable on x86_64.
    private static func halfToFloat(_ h: UInt16) -> Float {
        let sign: Float = (h & 0x8000) != 0 ? -1 : 1
        let exp = Int((h >> 10) & 0x1F)
        let mant = Float(h & 0x3FF)
        if exp == 0 { return sign * (mant / 1024) * powf(2, -14) }      // subnormal/zero
        if exp == 0x1F { return mant == 0 ? sign * .infinity : .nan }   // inf/nan
        return sign * (1 + mant / 1024) * powf(2, Float(exp - 15))
    }

    // MARK: - Inline Metal source (hardcoded DEBUG constant; original Vibrdrome code)

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float time;
        float bass;
        float mid;
        float treble;
        float decay;
        float zoom;
        float rotate;
        float paletteShift;
        float paletteIndex;
        float pulseScale;
        float zoomBass;
        float rotateTreble;
        float pulseBass;
        float bloomStrength;
        float waveformStrength;
        float flow;
        float flowScale;
        float beatFlow;
        float beatBloom;
        float hueDrift;
        float beatPulse;
        float tunnel;
        float waveBright;
        float symmetry;
        float vibrance;
        float spin;
    };

    struct VSOut {
        float4 position [[position]];
        float2 uv;
    };

    // Fullscreen triangle: 3 verts cover the screen; uv is 0..1 over the visible area.
    vertex VSOut pv_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VSOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = p;
        return o;
    }

    // --- Value noise + fbm (2 octaves) for the curl-noise flow field. Standard
    // general-CG hash/noise; original constants. Used only to build a divergence-free
    // advection field so trails circulate instead of collapsing to the center.
    float pv_hash21(float2 p) {
        p = fract(p * float2(123.34, 345.45));
        p += dot(p, p + 34.345);
        return fract(p.x * p.y);
    }
    float pv_vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 w = f * f * (3.0 - 2.0 * f);
        float a = pv_hash21(i);
        float b = pv_hash21(i + float2(1.0, 0.0));
        float c = pv_hash21(i + float2(0.0, 1.0));
        float d = pv_hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
    }
    float pv_fbm(float2 p) {
        float v = 0.0, amp = 0.5;
        for (int i = 0; i < 2; i++) { v += amp * pv_vnoise(p); p *= 2.0; amp *= 0.5; }
        return v;
    }

    // Feedback pass. When `flow > 0` (hero path) the prior frame is advected along the
    // curl of an animated fbm potential — a flowing, non-centered vector field — and the
    // beat injects a bright flash that the flow then carries. When `flow == 0` (legacy /
    // debug presets) it falls back to the old center rotate/zoom warp.
    fragment float4 pv_feedback(VSOut in [[stage_in]],
                                texture2d<float> prev [[texture(0)]],
                                constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);

        // Legacy center path (used only when flow == 0).
        float2 c = uv - 0.5;
        float a = u.rotate * (0.4 + u.rotateTreble * u.treble);
        float ca = cos(a), sa = sin(a);
        c = float2(c.x * ca - c.y * sa, c.x * sa + c.y * ca);
        c *= (1.0 - u.zoom * (0.5 + u.zoomBass * u.bass));
        float2 centerPos = c + 0.5;

        // Curl-noise advection (hero path).
        float2 p = (uv - 0.5); p.x *= aspect;
        float t = u.time * 0.15;
        float eps = 0.0025;
        float n0 = pv_fbm(p * u.flowScale + float2(0.0, t));
        float nx = pv_fbm((p + float2(eps, 0.0)) * u.flowScale + float2(0.0, t));
        float ny = pv_fbm((p + float2(0.0, eps)) * u.flowScale + float2(0.0, t));
        float2 curl = float2(ny - n0, -(nx - n0)) / eps;     // divergence-free
        curl = curl / (length(curl) + 1e-4);                 // direction only
        float speed = u.flow * (1.0 + u.beatFlow * u.beatPulse + 0.4 * u.bass);
        float2 adv = curl * speed * 0.0025;
        adv.x /= aspect;                                     // back to uv space
        float2 flowPos = uv - adv;                           // sample upstream

        float2 samplePos = (u.flow > 0.0001) ? flowPos : centerPos;
        // Tunnel pull: sample slightly outward so the field flows toward the viewer (a
        // tunnel/spiral that drags the waveform lines into filaments); the beat deepens it.
        float2 fc = samplePos - 0.5;
        fc *= (1.0 + u.tunnel * (0.02 + 0.05 * u.beatPulse));
        samplePos = fc + 0.5;
        float3 fed = prev.sample(s, samplePos).rgb * u.decay;

        // Energy injection: a soft core that flashes on the beat (beatPulse) with a small
        // continuous bass floor — the flow carries it outward into structure.
        float d = length(uv - 0.5);
        float inj = (0.05 + u.pulseScale * (0.12 * u.bass + 0.55 * u.beatPulse)) * exp(-d * 4.0);
        float3 add = inj * (0.45 + 0.55 * float3(u.bass, u.mid, u.treble));

        // Soft-saturate so the field can't blow out to uniform white.
        float3 sum = fed + add;
        sum = sum / (1.0 + 0.55 * sum);
        return float4(sum, 1.0);
    }

    // Bloom pass (half-res): bright-pass + small 3x3 box blur of the feedback field.
    fragment float4 pv_bloom(VSOut in [[stage_in]],
                             texture2d<float> field [[texture(0)]],
                             constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 texel = 4.0 / u.resolution;   // wider offset to keep the glow at quarter-res
        float3 sum = float3(0.0);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float3 c = field.sample(s, in.uv + float2(dx, dy) * texel).rgb;
                sum += max(c - 0.35, 0.0);   // soft bright-pass
            }
        }
        return float4(sum / 9.0, 1.0);
    }

    // Two original 3-stop gradient palettes selected by index (0 = cool, 1 = warm),
    // with a slowly-shifting position.
    float3 pv_palette(float t, float shift, int idx) {
        t = fract(t + shift);
        float3 c1, c2, c3;
        if (idx == 1) {
            c1 = float3(0.10, 0.00, 0.05);
            c2 = float3(1.00, 0.45, 0.00);
            c3 = float3(0.95, 0.95, 0.20);
        } else {
            c1 = float3(0.05, 0.00, 0.22);
            c2 = float3(0.90, 0.20, 0.55);
            c3 = float3(0.20, 0.90, 1.00);
        }
        float3 col = mix(c1, c2, smoothstep(0.0, 0.5, t));
        col = mix(col, c3, smoothstep(0.5, 1.0, t));
        return col;
    }

    // Cosine-gradient palettes (IQ-style a + b*cos(2π(c·t + d))) — coherent and vivid with
    // no muddy midpoint, dark in the troughs for depth. Distinct themes selected by index
    // (2 = deep-space, 3 = aurora, 4 = fire, 5 = nebula, 6 = rainbow). Original coefficients;
    // general-CG concept. Used by the flow path (paletteIndex >= 2).
    float3 pv_cospalette(float t, int idx) {
        float3 a, b, cc, dd;
        if (idx == 3) {            // Aurora — green / teal / violet
            a = float3(0.10, 0.30, 0.26); b = float3(0.40, 0.45, 0.45);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.50, 0.40, 0.25);
        } else if (idx == 4) {     // Fire — red / orange / yellow
            a = float3(0.40, 0.18, 0.05); b = float3(0.55, 0.40, 0.20);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.00, 0.10, 0.20);
        } else if (idx == 5) {     // Nebula — magenta / blue / pink
            a = float3(0.28, 0.12, 0.34); b = float3(0.55, 0.40, 0.55);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.30, 0.55, 0.85);
        } else if (idx == 6) {     // Rainbow — full spectrum
            a = float3(0.50, 0.50, 0.50); b = float3(0.50, 0.50, 0.50);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.00, 0.33, 0.67);
        } else {                   // 2 = deep-space — violet / magenta / teal
            a = float3(0.18, 0.10, 0.30); b = float3(0.55, 0.45, 0.65);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.00, 0.18, 0.40);
        }
        return clamp(a + b * cos(6.2831853 * (cc * t + dd)), 0.0, 1.0);
    }

    // Waveform line geometry: positions are prebuilt in NDC host-side from raw PCM, drawn
    // as an additive lineStrip into the feedback field (Phase 7).
    vertex VSOut pv_wave_vertex(uint vid [[vertex_id]],
                                constant float2* pts [[buffer(0)]],
                                constant Uniforms& u [[buffer(1)]]) {
        VSOut o;
        o.position = float4(pts[vid], 0.0, 1.0);
        o.uv = pts[vid] * 0.5 + 0.5;
        return o;
    }

    // Thin bright line colour (additive): white-hot core tinted by the cosine palette,
    // with a continuous floor and a beat punch.
    fragment float4 pv_wave_fragment(VSOut in [[stage_in]],
                                     constant Uniforms& u [[buffer(0)]]) {
        float b = u.waveBright * (0.55 + 0.7 * u.beatPulse);
        float3 tint = pv_cospalette(in.uv.x * 0.5 + u.time * 0.05 + u.paletteShift, int(u.paletteIndex));
        float3 col = mix(float3(1.0), tint, 0.45) * b;
        return float4(col, b);
    }

    fragment float4 pv_present(VSOut in [[stage_in]],
                               texture2d<float> field [[texture(0)]],
                               texture2d<float> bloom [[texture(1)]],
                               constant Uniforms& u [[buffer(0)]],
                               constant float* bands [[buffer(1)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        int idx = int(u.paletteIndex);

        // Spin: rotate the sampled coordinate around centre (time + beat), so the field
        // kaleidoscopes instead of sitting still.
        float2 suv = in.uv;
        if (abs(u.spin) > 0.0001) {
            float2 c = suv - 0.5;
            float a = u.time * u.spin + u.beatPulse * u.spin * 2.0;
            float ca = cos(a), sa = sin(a);
            c = float2(c.x * ca - c.y * sa, c.x * sa + c.y * ca);
            suv = c + 0.5;
        }
        // Symmetry: 1 = vertical (L/R) mirror, 2 = quad (4-way) kaleidoscope fold. A clean
        // rectilinear fold — NOT a polar kaleidoscope (no centred blob).
        if (u.symmetry > 0.5) { suv.x = 0.5 - abs(suv.x - 0.5); }
        if (u.symmetry > 1.5) { suv.y = 0.5 - abs(suv.y - 0.5); }

        float3 v = field.sample(s, suv).rgb;
        float intensity = clamp(length(v) * 0.85, 0.0, 1.0);
        float3 col;

        if (idx >= 2) {
            // Flow path: colour from the coherent cosine palette, positioned by a smooth
            // RADIAL field + hue drift + beat kick + a treble hue-shift (colour dances with
            // the music). No atan2 angle term (its -x branch cut drew a seam). Radial = no seam.
            float2 q = in.uv - 0.5;
            float rad = length(q);
            float tpos = rad * 0.65 + u.time * u.hueDrift * 0.08
                       + u.beatPulse * 0.15 + u.treble * 0.15 + u.paletteShift;
            col = pv_cospalette(tpos, idx) * intensity;
            col *= (1.0 + 0.30 * u.bass);          // bass pumps brightness
        } else {
            // Legacy/fallback presets: original intensity-driven 3-stop palette.
            col = pv_palette(intensity + u.time * 0.02, u.paletteShift, idx) * intensity;
        }

        // Bloom + beat-kick glow (beatBloom is 0 for legacy presets, so no change there).
        col += bloom.sample(s, suv).rgb * (u.bloomStrength + u.beatBloom * u.beatPulse);

        if (idx >= 2) {
            // Eased vignette (lighter than before so the image isn't muted at the edges).
            float vig = smoothstep(0.98, 0.18, length(in.uv - 0.5));
            col *= mix(1.0, vig, 0.40);
            // Vibrance: lift saturation + brightness. Safe here because the cosine palette
            // has no muddy midpoint, so boosting stays vivid rather than grey.
            float luma = dot(col, float3(0.299, 0.587, 0.114));
            col = mix(float3(luma), col, u.vibrance);
            col *= (0.80 + 0.35 * u.vibrance);
        }
        col = max(col, 0.0);

        // Audio-spectrum overlay: a glowing curve whose height follows the 32 bands.
        if (u.waveformStrength > 0.0) {
            int bi = clamp(int(in.uv.x * 32.0), 0, 31);
            float bandH = clamp(bands[bi], 0.0, 1.0);
            float curveY = 1.0 - bandH;                       // loud = high
            float line = exp(-abs(in.uv.y - curveY) * 60.0) * u.waveformStrength;
            float3 lineCol = (idx >= 2) ? pv_cospalette(0.7, idx)
                                        : pv_palette(0.75, u.paletteShift, idx);
            col += line * lineCol * 1.4;
        }
        return float4(col, 1.0);
    }
    """
}
#endif
