#if DEBUG
import Metal
import MetalKit
import simd

// Most of this DEBUG-only file is the inline Metal `shaderSource` string (a data blob, not
// logic), so the file/type length rules don't meaningfully apply here.
// swiftlint:disable file_length

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
    // Phase 8 — polar warp + audio envelope-follower punches.
    var swirl: Float
    var swirlFreq: Float
    var warpMode: Float     // 0 = curl-flow (legacy), 1 = polar warp (hero)
    var bassPunch: Float
    var midPunch: Float
    var treblePunch: Float
    // Phase 8b — kaleidoscope wedge count (0 = off) for the present-time polar fold.
    var kaleido: Float
    // Phase 8c — radial spectrum spokes (Radiant): ray count (0 = off) + radial bar length.
    var spokes: Float
    var spokeLen: Float
    // Phase 8c-2 — inject spokes into the feedback field (1) for bloom + trails, vs present-only (0).
    var spokeInject: Float
    // Phase 8c-3 — whirlpool: center-weighted rotational warp (spins fast at centre).
    var whirl: Float
    // Phase 9 — polar lattice (intersecting rings + radial lines → moiré) + colour wash overlay.
    var lattice: Float
    var latticeR: Float
    var latticeA: Float
    var wash: Float
    // Phase 10 — fractal fold (nested self-similar mandala) + Voronoi liquid cells.
    var fractal: Float
    var cells: Float
    // Phase 11 — logarithmic (Droste) spiral warp: self-similar fractal spiral / nautilus.
    var spiral: Float
    // Phase 12 — angular: mirror-tiling (grid), pixelate (cubist blocks), Truchet maze.
    var tile: Float
    var pixelate: Float
    var truchet: Float
    // Phase 13 — outside-the-box: 3D tunnel, sine plasma, phyllotaxis, ripples, hex, chroma.
    var tunnel3d: Float
    var plasma: Float
    var phyllo: Float
    var ripple: Float
    var hex: Float
    var chroma: Float
    // Phase 14 — 3D raymarch: scene selector + host-accumulated forward camera position.
    var sceneMode: Float
    var camZ: Float
}

// swiftlint:disable type_body_length
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
    private let raymarchPSO: MTLRenderPipelineState   // Phase 14 — 3D raymarch tunnel
    private let presentPSO: MTLRenderPipelineState

    static let marchSteps = 64                        // bounded raymarch cap (mirrors MAXS in pv_raymarch)
    // 3D raymarch internal resolution. The march (per-step orb/tunnel SDF) is the 3D cost, and on
    // iPhone the GPU drops to a low power state under sustained load — quarter-res keeps the frame
    // light enough (~10ms) to hold a locked 60fps, and the smooth orbs/tunnel upscale cleanly via
    // the linear present sampler. macOS has the headroom to stay full-res. Platform-fixed and
    // deterministic (no adaptive runtime scaling, no per-preset knob). 2D presets ignore this
    // (they use the full-res feedback field). Reported in the proof.
    #if os(iOS)
    private(set) var raymarchScale: CGFloat = 0.25
    #else
    private(set) var raymarchScale: CGFloat = 1.0
    #endif

    static let maxWaveVerts = 1024
    private let waveBuffer: MTLBuffer                 // NDC float2 positions for the wave line
    private var waveCount = 0

    private var texA: MTLTexture?
    private var texB: MTLTexture?
    private var bloomTex: MTLTexture?                 // half-res bloom (Phase 4)
    private var raymarchTex: MTLTexture?             // 3D raymarch target at raymarchScale (Phase 15)
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

            // Raymarch pass (Phase 14) — fullscreen 3D tunnel into the feedback-format target.
            let rd14 = MTLRenderPipelineDescriptor()
            rd14.vertexFunction = lib.makeFunction(name: "pv_vertex")
            rd14.fragmentFunction = lib.makeFunction(name: "pv_raymarch")
            rd14.colorAttachments[0].pixelFormat = Self.feedbackFormat
            raymarchPSO = try device.makeRenderPipelineState(descriptor: rd14)

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
        // Mipmapped so the 3D raymarch pass can store its per-pixel step count in alpha and we
        // read the top (1×1) mip via generateMipmaps for a true frame-average (avgSteps proof).
        // 2D feedback samples mip 0 only, so the mip chain is inert there.
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.feedbackFormat,
            width: Int(newSize.width), height: Int(newSize.height), mipmapped: true)
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

        // 3D raymarch target at raymarchScale (half-res on iOS, full-res on macOS). Mipmapped like
        // the feedback field so readAvgSteps can mip-reduce its per-pixel step count. Present/bloom
        // sample this via the linear sampler, so the half-res image upscales cleanly to the drawable.
        let rw = max(1, Int((newSize.width * raymarchScale).rounded()))
        let rh = max(1, Int((newSize.height * raymarchScale).rounded()))
        let rmd = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.feedbackFormat, width: rw, height: rh, mipmapped: true)
        rmd.usage = [.renderTarget, .shaderRead]
        rmd.storageMode = .private
        raymarchTex = device.makeTexture(descriptor: rmd)

        clearNext = true
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func render(in view: MTKView, uniforms: PermissiveUniforms) {
        guard let texA, let texB, let bloomTex, let raymarchTex,
              let drawable = view.currentDrawable,
              let presentRPD = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }
        var u = uniforms
        let is3D = u.sceneMode > 0.5
        let read = readIsA ? texA : texB
        let write = readIsA ? texB : texA
        // 3D renders into the (possibly quarter-res) raymarch target; 2D uses the full-res ping-pong
        // field. Pass B/C and the proof readback all read whichever was written this frame.
        let scene = is3D ? raymarchTex : write

        // Pass A — feedback (2D, full-res `write`) OR raymarch (3D, `raymarchTex` at raymarchScale).
        // The render-target size sets the viewport, so the 3D shader naturally runs at reduced res on iOS.
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = scene
        rpd.colorAttachments[0].loadAction = (is3D || clearNext) ? .clear : .load
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rpd.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            if is3D {
                enc.setRenderPipelineState(raymarchPSO)
                enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
            } else {
                enc.setRenderPipelineState(feedbackPSO)
                enc.setFragmentTexture(read, index: 0)
                enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
                enc.setFragmentBuffer(bandsBuffer, offset: 0, index: 1)   // for spoke injection
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // Pass A2 — waveform line (2D only): draw the audio waveform as thin bright additive
        // geometry INTO the feedback field, so next frame's warp/flow/tunnel pulls it into
        // filaments. Loads (not clears) the field written by Pass A.
        if !is3D && waveCount > 1 {
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
            enc.setFragmentTexture(scene, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // Pass C — present: field + bloom + audio-spectrum overlay → drawable.
        if let enc = cb.makeRenderCommandEncoder(descriptor: presentRPD) {
            enc.setRenderPipelineState(presentPSO)
            enc.setFragmentTexture(scene, index: 0)
            enc.setFragmentTexture(bloomTex, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
            enc.setFragmentBuffer(bandsBuffer, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        cb.present(drawable)
        cb.commit()
        lastWritten = scene          // 3D → raymarchTex (mipmapped) for avgSteps; 2D → field
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

    /// Mean raymarch step count across the frame (proof-only, ~once/sec). The raymarch pass
    /// stores `steps/marchSteps` in the alpha channel; we `generateMipmaps` and read the top
    /// (1×1) mip's alpha — a true frame average — then scale back to a step count.
    func readAvgSteps() -> Int {
        guard let src = lastWritten, src.mipmapLevelCount > 1 else { return 0 }
        if staging == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
            d.storageMode = .shared
            staging = device.makeTexture(descriptor: d)
        }
        guard let staging,
              let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return 0 }
        blit.generateMipmaps(for: src)
        let top = src.mipmapLevelCount - 1                      // 1×1 mip = whole-frame average
        blit.copy(from: src, sourceSlice: 0, sourceLevel: top,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var halves = [UInt16](repeating: 0, count: 4)
        staging.getBytes(&halves, bytesPerRow: 8,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: 1, height: 1, depth: 1)),
                         mipmapLevel: 0)
        return Int((Self.halfToFloat(halves[3]) * Float(Self.marchSteps)).rounded())
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
        float swirl;
        float swirlFreq;
        float warpMode;
        float bassPunch;
        float midPunch;
        float treblePunch;
        float kaleido;
        float spokes;
        float spokeLen;
        float spokeInject;
        float whirl;
        float lattice;
        float latticeR;
        float latticeA;
        float wash;
        float fractal;
        float cells;
        float spiral;
        float tile;
        float pixelate;
        float truchet;
        float tunnel3d;
        float plasma;
        float phyllo;
        float ripple;
        float hex;
        float chroma;
        float sceneMode;
        float camZ;
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

    float3 pv_cospalette(float t, int idx);   // forward decl (defined below; used by inject)

    // Feedback pass. When `flow > 0` (hero path) the prior frame is advected along the
    // curl of an animated fbm potential — a flowing, non-centered vector field — and the
    // beat injects a bright flash that the flow then carries. When `flow == 0` (legacy /
    // debug presets) it falls back to the old center rotate/zoom warp. With `spokeInject`,
    // the radial spectrum spokes are also drawn into the field here so they bloom + trail.
    fragment float4 pv_feedback(VSOut in [[stage_in]],
                                texture2d<float> prev [[texture(0)]],
                                constant Uniforms& u [[buffer(0)]],
                                constant float* bands [[buffer(1)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 samplePos;

        if (u.warpMode > 0.5) {
            // Polar warp (hero): decompose to radius/angle, modulate the angle by radius +
            // time (the radius-dependent swirl is the vortex/spiral), and zoom the radius a
            // tiny amount per frame (the breathing tunnel — bassPunch deepens it). Seam-free:
            // we modify the angle and recompose with cos/sin, which are periodic, so the
            // atan2 branch cut vanishes. Small per-frame transforms compound through feedback.
            float2 p = uv - 0.5; p.x *= aspect;
            float r = length(p);
            float ang = atan2(p.y, p.x);
            ang += sin(r * u.swirlFreq - u.time * 0.6) * u.swirl * (1.0 + 1.5 * u.midPunch);
            r *= (1.0 - 0.006 * u.tunnel - 0.030 * u.bassPunch);
            float2 q = float2(cos(ang), sin(ang)) * r; q.x /= aspect;
            samplePos = q + 0.5;
        } else {
            // Legacy center path (used only when flow == 0).
            float2 c = uv - 0.5;
            float a = u.rotate * (0.4 + u.rotateTreble * u.treble);
            float ca = cos(a), sa = sin(a);
            c = float2(c.x * ca - c.y * sa, c.x * sa + c.y * ca);
            c *= (1.0 - u.zoom * (0.5 + u.zoomBass * u.bass));
            float2 centerPos = c + 0.5;

            // Curl-noise advection.
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

            float2 sp = (u.flow > 0.0001) ? flowPos : centerPos;
            float2 fc = sp - 0.5;                                // tunnel pull
            fc *= (1.0 + u.tunnel * (0.02 + 0.05 * u.beatPulse));
            samplePos = fc + 0.5;
        }

        // Whirlpool: rotate the sample coordinate around centre by an angle that grows toward
        // the centre (1/r falloff) — a drain/vortex twist that accumulates through feedback.
        if (abs(u.whirl) > 0.0001) {
            float2 wc = samplePos - 0.5;
            float wr = length(wc);
            float wa = u.whirl * 0.03 / (wr + 0.08) * (1.0 + 0.5 * u.bassPunch);
            float wca = cos(wa), wsa = sin(wa);
            wc = float2(wc.x * wca - wc.y * wsa, wc.x * wsa + wc.y * wca);
            samplePos = wc + 0.5;
        }
        float3 fed = prev.sample(s, samplePos).rgb * u.decay;

        // Energy injection: a soft core that flashes on the beat (beatPulse) with a small
        // continuous bass floor — the flow carries it outward into structure.
        float d = length(uv - 0.5);
        float inj = (0.05 + u.pulseScale * (0.12 * u.bass + 0.55 * u.beatPulse)) * exp(-d * 4.0);
        float3 add = inj * (0.45 + 0.55 * float3(u.bass, u.mid, u.treble));

        float3 sum = fed + add;

        // Spectral-spoke injection (Spectral Spokes): draw the radial bars INTO the field so
        // they bloom (the bloom pass reads the field) and trail (feedback decay carries them).
        // Same math as the present-pass spokes; gated by spokeInject so Radiant stays present-only.
        if (u.spokes > 0.5 && u.spokeInject > 0.5) {
            float2 qq = uv - 0.5; qq.x *= aspect;
            float rr = length(qq);
            // Radius-dependent twist: inner radii rotate more than outer → the straight rays
            // bend into spiral arms drawn into the centre (the whirlpool), turning over time.
            float swirlTwist = u.whirl * 0.22 / (rr + 0.12);
            float sang = fract(atan2(qq.y, qq.x) / 6.2831853 + 0.5 + u.time * 0.02
                               + u.treblePunch * 0.08 + swirlTwist);
            float sma = (sang < 0.5) ? sang : (1.0 - sang);
            float sfa = sma * 2.0 * u.spokes;
            int sN = max(int(u.spokes), 1);
            int sbi = clamp(int(sfa), 0, sN - 1);
            int sband = clamp(sbi * 32 / sN, 0, 31);
            float samp = clamp(bands[sband], 0.0, 1.0);
            float sr0 = 0.05 + 0.04 * u.bassPunch;   // reach toward centre so the whirl has content to spiral
            // (2) tips oscillate in/out: a per-band sine over time, swelled by bass.
            float tipOsc = 0.045 * sin(u.time * 5.0 + float(sband) * 0.6) * (1.0 + u.bassPunch);
            float sOuter = sr0 + samp * u.spokeLen + tipOsc;
            float sAngFrac = fract(sfa);
            float sgap = smoothstep(0.045, 0.0, abs(sAngFrac - 0.5));   // thin centred line
            float sbar = step(sr0, rr) * smoothstep(sOuter, sOuter - 0.012, rr) * sgap;
            // (1) vibrating-string ripple: bright/dark bands travel outward along the spoke.
            float ripple = 0.55 + 0.45 * sin(rr * 70.0 - u.time * 7.0 + u.treblePunch * 5.0);
            float3 sCol = pv_cospalette(float(sband) / 32.0 + u.time * 0.10, int(u.paletteIndex));
            sum += sbar * ripple * sCol * (0.6 + 0.9 * samp + 0.7 * u.beatPulse);
        }

        // Soft-saturate so the field can't blow out to uniform white.
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
        } else if (idx == 7) {     // Acid — lime / green / yellow
            a = float3(0.30, 0.45, 0.10); b = float3(0.45, 0.45, 0.30);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.15, 0.10, 0.05);
        } else if (idx == 8) {     // Ice — cyan / blue / white
            a = float3(0.25, 0.45, 0.60); b = float3(0.40, 0.40, 0.40);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.55, 0.62, 0.70);
        } else if (idx == 9) {     // Sunset — orange / pink / violet
            a = float3(0.55, 0.25, 0.35); b = float3(0.45, 0.35, 0.45);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.05, 0.18, 0.40);
        } else if (idx == 10) {    // Mono — high-contrast greyscale (B&W marble)
            a = float3(0.55); b = float3(0.48);
            cc = float3(1.0, 1.0, 1.0);   dd = float3(0.0, 0.0, 0.0);
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

    // Voronoi liquid cells: animated feature points; returns cell-border closeness (.x, small
    // near a boundary) and a per-cell id (.y). Standard cellular noise; original.
    float2 pv_cells(float2 p, float t) {
        float2 ip = floor(p), fp = fract(p);
        float f1 = 8.0, f2 = 8.0; float2 cellId = float2(0.0);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float2 g = float2(dx, dy);
                float2 h = float2(pv_hash21(ip + g), pv_hash21(ip + g + 17.3));
                float2 o = 0.5 + 0.5 * sin(t * 0.8 + 6.2831853 * h);   // animated point
                float2 r = g + o - fp;
                float d = dot(r, r);
                if (d < f1) { f2 = f1; f1 = d; cellId = h; } else if (d < f2) { f2 = d; }
            }
        }
        return float2(sqrt(f2) - sqrt(f1), cellId.x);
    }

    // Truchet tiles: each grid cell randomly draws one of two quarter-arc orientations, so the
    // arcs connect across cells into a continuous interconnecting maze/circuit. Original.
    float pv_truchet(float2 p) {
        float2 ip = floor(p), fp = fract(p);
        if (pv_hash21(ip) < 0.5) fp.x = 1.0 - fp.x;     // flip → the two tile orientations
        float d1 = abs(length(fp) - 0.5);
        float d2 = abs(length(fp - float2(1.0, 1.0)) - 0.5);
        return smoothstep(0.09, 0.0, min(d1, d2));      // thin arc lines
    }

    // --- Phase 14: 3D raymarched tunnel (signed-distance / sphere tracing). General-CG
    // demoscene concept; our own SDF, shading, and audio mapping. We are INSIDE the tube.
    float pv_tunnelMap(float3 p, constant Uniforms& u) {
        // Winding centerline sway (bass widens it).
        p.xy += float2(sin(p.z * 0.30 + u.time * 0.5), cos(p.z * 0.25)) * (0.5 + 0.3 * u.bass);
        float wall = 1.0 - length(p.xy);                          // TUNNEL_R = 1.0
        float ribs = (0.05 + 0.04 * u.treble) * sin(p.z * 4.0 - u.time * 2.0);  // treble → rib detail
        return wall + ribs;
    }
    float3 pv_tunnelNormal(float3 p, constant Uniforms& u) {
        float e = 0.003;
        float dx = pv_tunnelMap(p + float3(e, 0, 0), u) - pv_tunnelMap(p - float3(e, 0, 0), u);
        float dy = pv_tunnelMap(p + float3(0, e, 0), u) - pv_tunnelMap(p - float3(0, e, 0), u);
        float dz = pv_tunnelMap(p + float3(0, 0, e), u) - pv_tunnelMap(p - float3(0, 0, e), u);
        return normalize(float3(dx, dy, dz) + 1e-5);
    }

    // --- Phase 15: glowing-orb / metaball field (sceneMode 2). Smooth-min union of 8 animated
    // spheres + glow accumulation + fresnel rim. General-CG metaball/SDF; our own field + audio.
    float pv_smin(float a, float b, float k) {
        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, h) - k * h * (1.0 - h);
    }
    float pv_orbMap(float3 p, constant Uniforms& u, thread float &nearID) {
        float d = 1e9, k = 0.55;
        float rscale = 1.0 + 0.6 * u.bass + 0.8 * u.bassPunch;     // bass breathing + kick expansion
        for (int i = 0; i < 8; i++) {
            float fi = float(i);
            float3 c = float3(1.3 * sin(u.time * (0.30 + 0.05 * fi) + fi * 1.7),
                              1.0 * cos(u.time * (0.25 + 0.04 * fi) + fi * 2.3),
                              3.0 + 0.45 * sin(u.time * 0.2 + fi * 2.0));   // Lissajous drift, spread in depth
            float r = (0.34 + 0.12 * sin(u.time + fi)) * rscale;
            float ds = length(p - c) - r;
            if (ds < d) nearID = fi;                              // nearest orb → its hue
            d = pv_smin(d, ds, k);                                // smooth-min union (metaball merge)
        }
        return d;
    }
    float3 pv_orbNormal(float3 p, constant Uniforms& u) {
        float e = 0.004; float dummy = 0.0;
        float dx = pv_orbMap(p + float3(e, 0, 0), u, dummy) - pv_orbMap(p - float3(e, 0, 0), u, dummy);
        float dy = pv_orbMap(p + float3(0, e, 0), u, dummy) - pv_orbMap(p - float3(0, e, 0), u, dummy);
        float dz = pv_orbMap(p + float3(0, 0, e), u, dummy) - pv_orbMap(p - float3(0, 0, e), u, dummy);
        return normalize(float3(dx, dy, dz) + 1e-5);
    }
    float4 pv_renderOrbs(float2 uv, constant Uniforms& u) {
        const int MAXS = 64;
        int idx = int(u.paletteIndex);
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 uvc = uv * 2.0 - 1.0; uvc.x *= aspect;
        // Orbiting camera looking at the cluster (beat pushes it in).
        float3 target = float3(0.0, 0.0, 3.0);
        float3 ro = float3(1.6 * sin(u.time * 0.2), 1.0 * sin(u.time * 0.13), -1.6 - u.beatPulse * 0.7);
        float3 fwd = normalize(target - ro);
        float3 right = normalize(cross(float3(0, 1, 0), fwd));
        float3 vup = cross(fwd, right);
        float3 rd = normalize(fwd + uvc.x * right + uvc.y * vup);
        float t = 0.0, d = 0.0, glow = 0.0, nearID = 0.0;
        int steps = MAXS;
        for (int i = 0; i < MAXS; i++) {
            d = pv_orbMap(ro + rd * t, u, nearID);
            glow += 0.03 / (1.0 + d * d * 18.0);                 // halo glow into the dark
            if (d < 0.003 || t > 30.0) { steps = i; break; }
            t += d * 0.7;                                        // under-step (smin is approximate)
        }
        float3 glowCol = pv_cospalette(nearID * 0.13 + u.time * 0.15, idx);
        float3 col = float3(0.0);
        if (d < 0.01) {                                          // hit a surface
            float3 p = ro + rd * t;
            float3 n = pv_orbNormal(p, u);
            float3 lightDir = normalize(float3(0.6, 0.8, -0.5) - p);
            float diff = max(dot(n, lightDir), 0.0);
            float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);  // fresnel rim glow
            float spec = pow(max(dot(reflect(rd, n), lightDir), 0.0), 16.0 + 40.0 * u.treble);
            col = glowCol * (0.20 + 0.85 * diff) + glowCol * fres * 1.2
                + float3(spec) * (0.4 + 0.6 * u.treble) + glowCol * 0.30;   // + emissive
        }
        col += glow * glowCol * (0.8 + 0.5 * u.beatPulse);       // halos + beat flash
        return float4(max(col * u.vibrance, 0.0), float(steps) / float(MAXS));
    }

    fragment float4 pv_raymarch(VSOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        if (u.sceneMode > 1.5) { return pv_renderOrbs(in.uv, u); }   // sceneMode 2 = glowing orbs
        const int MAXS = 64;                                     // bounded march (perf cap)
        int idx = int(u.paletteIndex);
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 uvc = in.uv * 2.0 - 1.0; uvc.x *= aspect;
        float3 rd = normalize(float3(uvc, 1.3));                 // perspective ray
        float3 ro = float3(u.beatPulse * 0.12 * sin(u.time * 28.0),
                           u.beatPulse * 0.12 * cos(u.time * 23.0), u.camZ);  // forward + beat kick
        float t = 0.0, d = 0.0;
        int steps = MAXS;
        for (int i = 0; i < MAXS; i++) {
            d = pv_tunnelMap(ro + rd * t, u);
            if (d < 0.002 || t > 40.0) { steps = i; break; }
            t += d * 0.8;                                        // under-step (inexact SDF)
        }
        float3 p = ro + rd * t;
        float3 n = pv_tunnelNormal(p, u);
        float fog = exp(-t * 0.09);                             // dark foggy vanishing point
        float diff = max(dot(n, -rd), 0.0);
        // Angle as fraction of a turn (−0.5…0.5): it jumps by exactly 1.0 across the atan2 cut,
        // so an INTEGER number of hue cycles wraps seamlessly around the tube (no seam line).
        float hueA = atan2(p.y, p.x) / 6.2831853;
        // Strong global hue cycle (time) + a beat hue-kick, on top of the depth/angle hue.
        float3 base = pv_cospalette(p.z * 0.04 + hueA * 2.0 + u.time * 0.5 + u.beatPulse * 0.35, idx);
        float3 col = base * (0.15 + 0.85 * diff) * fog;
        float rib = 0.5 + 0.5 * sin(p.z * 4.0 - u.time * 2.0);  // emissive rib bands
        col += base * fog * rib * (0.25 + 0.5 * u.treble) * 0.5;
        col += pv_cospalette(0.5, idx) * u.beatBloom * u.beatPulse * fog;   // beat light burst
        col = max(col * u.vibrance, 0.0);
        return float4(col, float(steps) / float(MAXS));         // alpha = normalised step count (proof)
    }

    fragment float4 pv_present(VSOut in [[stage_in]],
                               texture2d<float> field [[texture(0)]],
                               texture2d<float> bloom [[texture(1)]],
                               constant Uniforms& u [[buffer(0)]],
                               constant float* bands [[buffer(1)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        // 3D scene mode: the raymarch pass already produced the final lit colour in `field`.
        // Just composite bloom + a mild vignette and skip all the 2D waveform/feedback logic.
        if (u.sceneMode > 0.5) {
            float3 c3 = field.sample(s, in.uv).rgb;
            c3 += bloom.sample(s, in.uv).rgb * u.bloomStrength;
            c3 = 1.0 - exp(-max(c3, 0.0));        // tone-map: highlights glow + roll off (no blowout)
            float vig3 = smoothstep(1.05, 0.25, length(in.uv - 0.5));
            c3 *= mix(1.0, vig3, 0.35);
            return float4(c3, 1.0);
        }

        int idx = int(u.paletteIndex);

        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
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
        // Kaleidoscope wedge fold (present-time only — the feedback physics stay
        // un-folded): fold the angle into `kaleido` mirrored wedges, recompose with cos/sin
        // (seam-free). Folds the already waveform-fed/warped field, so detail multiplies into
        // a mandala. A slow time drift + treble punch turns it.
        if (u.kaleido > 0.5) {
            float2 p = suv - 0.5; p.x *= aspect;
            float r = length(p);
            float a = atan2(p.y, p.x) + u.time * 0.03 + u.treblePunch * 0.40;
            float seg = 6.2831853 / u.kaleido;
            a = a - seg * floor(a / seg);       // wrap into [0, seg)
            a = fabs(a - seg * 0.5);            // mirror within the wedge (reflected edges)
            float2 q = float2(cos(a), sin(a)) * r; q.x /= aspect;
            suv = q + 0.5;
        }
        // Symmetry: 1 = vertical (L/R) mirror, 2 = quad (4-way) rectilinear fold. NOT a polar
        // kaleidoscope (that's `kaleido`); orthogonal, a preset may use either/both.
        if (u.symmetry > 0.5) { suv.x = 0.5 - abs(suv.x - 0.5); }
        if (u.symmetry > 1.5) { suv.y = 0.5 - abs(suv.y - 0.5); }

        // Logarithmic (Droste) spiral: in log-polar space, twist the angle by log-radius (a
        // logarithmic spiral) and wrap the log-radius into self-similar bands → an infinite-
        // zoom fractal spiral (nautilus). Self-similar, NOT a kaleidoscope fold.
        if (u.spiral > 0.0) {
            float2 sp = (suv - 0.5); sp.x *= aspect;
            float sr = max(length(sp), 1e-4);
            float sa = atan2(sp.y, sp.x);
            float slr = log(sr);
            sa += slr * u.spiral;                       // log-spiral twist
            slr = fract(slr * 0.65 + u.time * 0.05);    // self-similar repeating scale bands
            sr = exp((slr - 0.5) * 1.6);
            sp = float2(cos(sa), sin(sa)) * sr; sp.x /= aspect;
            suv = sp + 0.5;
        }

        // Fractal fold (Kaliset-style): iterate abs-fold + rotate + scale so the field is
        // sampled through a self-similar coordinate → nested, recursive mandala detail.
        if (u.fractal > 0.5) {
            float2 fp = (suv - 0.5) * 2.0;
            int it = min(int(u.fractal), 8);
            for (int i = 0; i < it; i++) {
                fp = abs(fp) - 0.5;
                float fa = 0.5 + u.time * 0.05;
                fp = float2(fp.x * cos(fa) - fp.y * sin(fa), fp.x * sin(fa) + fp.y * cos(fa));
                fp *= 1.3;
            }
            suv = fract(fp * 0.5 + 0.5);
        }

        // Mirror-tiling: repeat the field in a grid, reflected at cell edges (seamless) → a
        // kaleidoscopic tiled mosaic.
        if (u.tile > 0.0) {
            float2 t = (suv - 0.5) * u.tile;
            suv = abs(fract(t) - 0.5) * 2.0;
        }
        // Pixelate: quantise the sample coordinate to blocks → cubist mosaic.
        if (u.pixelate > 0.0) {
            suv = (floor(suv * u.pixelate) + 0.5) / u.pixelate;
        }

        // Chromatic aberration: split the RGB channels by sampling at offset positions.
        float3 v;
        if (u.chroma > 0.0) {
            float2 coff = (suv - 0.5) * u.chroma * 0.05;
            v = float3(field.sample(s, suv + coff).r, field.sample(s, suv).g, field.sample(s, suv - coff).b);
        } else {
            v = field.sample(s, suv).rgb;
        }
        float intensity = clamp(length(v) * 0.85, 0.0, 1.0);
        float3 col;

        if (idx >= 2) {
            // Flow path: colour from the coherent cosine palette, positioned by a smooth
            // RADIAL field + hue drift + beat kick + a treble hue-shift (colour dances with
            // the music). No atan2 angle term (its -x branch cut drew a seam). Radial = no seam.
            float2 q = in.uv - 0.5;
            float rad = length(q);
            // Hue from a smooth radial field + slow drift + beat + a treble PUNCH accent
            // (smoothed envelope, not raw FFT → musical, not twitchy). Raw treble stays a
            // tiny secondary term.
            float tpos = rad * 0.65 + u.time * u.hueDrift * 0.08 + u.beatPulse * 0.15
                       + u.treblePunch * 0.30 + u.treble * 0.05 + u.paletteShift;
            col = pv_cospalette(tpos, idx) * intensity;
            // Brightness pumped by the bass PUNCH (raw bass a gentle secondary floor).
            col *= (1.0 + 0.60 * u.bassPunch + 0.10 * u.bass);
        } else {
            // Legacy/fallback presets: original intensity-driven 3-stop palette.
            col = pv_palette(intensity + u.time * 0.02, u.paletteShift, idx) * intensity;
        }

        // Bloom: base + beat kick + a treble-punch shimmer (smoothed, not twitchy).
        col += bloom.sample(s, suv).rgb * (u.bloomStrength + u.beatBloom * u.beatPulse + 0.40 * u.treblePunch);

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

        // Radial spectrum spokes (Radiant): filled bars whose length = band energy, the 32
        // FFT bands FOLDED around the vertical axis into a bilaterally-symmetric EQ halo (so
        // it reads ornamental, not a left-to-right bar graph). Thin angular gaps keep the rays
        // crisp; additive bright on the dark field; hue varies per band; beat flashes them.
        // Present-only when spokeInject == 0 (Radiant); injected presets draw them in feedback.
        if (u.spokes > 0.5 && u.spokeInject < 0.5) {
            float2 q = in.uv - 0.5; q.x *= aspect;
            float r = length(q);
            float ang = fract(atan2(q.y, q.x) / 6.2831853 + 0.5 + u.time * 0.02 + u.treblePunch * 0.08);
            float ma = (ang < 0.5) ? ang : (1.0 - ang);      // bilateral fold (L/R mirror)
            float fa = ma * 2.0 * u.spokes;
            int sN = max(int(u.spokes), 1);
            int bi = clamp(int(fa), 0, sN - 1);
            int band = clamp(bi * 32 / sN, 0, 31);
            float amp = clamp(bands[band], 0.0, 1.0);
            float r0 = 0.12 + 0.04 * u.bassPunch;             // inner radius breathes on bass
            float barOuter = r0 + amp * u.spokeLen;
            float angFrac = fract(fa);                        // within-spoke position
            float gap = smoothstep(0.045, 0.0, abs(angFrac - 0.5));   // thin centred line
            float bar = step(r0, r) * smoothstep(barOuter, barOuter - 0.012, r) * gap;
            float3 spokeCol = pv_cospalette(float(band) / 32.0 + u.time * 0.05, idx);
            col += bar * spokeCol * (0.7 + 1.0 * amp + 0.8 * u.beatPulse);
        }

        // Colour wash: a slow moving fullscreen hue gradient overlaid (additive, breathing).
        if (u.wash > 0.0) {
            float washT = in.uv.x * 0.4 + in.uv.y * 0.25 + u.time * 0.07 + u.bassPunch * 0.2;
            float3 washCol = pv_cospalette(washT, idx);
            col += washCol * u.wash * (0.45 + 0.35 * sin(u.time + in.uv.x * 6.0));
        }

        // Polar lattice: thin concentric rings (circular) + radial lines (angular) intersecting
        // → a moiré grid over the warped field. Intersections glow brighter.
        if (u.lattice > 0.0) {
            float2 lq = in.uv - 0.5; lq.x *= aspect;
            float lr = length(lq);
            float la01 = atan2(lq.y, lq.x) / 6.2831853 + 0.5;
            float ringL = smoothstep(0.08, 0.0, abs(fract(lr * u.latticeR - u.time * 0.3) - 0.5));
            float radL  = smoothstep(0.08, 0.0, abs(fract(la01 * u.latticeA + u.time * 0.1) - 0.5));
            float grid = max(ringL, radL) + ringL * radL;   // lines + brighter intersections
            float3 gridCol = pv_cospalette(lr * 1.5 + u.time * 0.10, idx);
            col += grid * gridCol * u.lattice * (0.7 + 0.5 * u.treblePunch);
        }

        // Voronoi liquid cells: dim palette-tinted cell fills with bright glowing borders —
        // the molten / reaction-diffusion look. Cells drift over time and pulse with bass.
        if (u.cells > 0.0) {
            float2 cp = (in.uv - 0.5); cp.x *= aspect;
            float2 cv = pv_cells(cp * 6.0 + 10.0, u.time);
            float border = smoothstep(0.12, 0.0, cv.x);
            float3 fillCol = pv_cospalette(cv.y + u.time * 0.04, idx) * 0.30;
            float3 edgeCol = pv_cospalette(cv.y + 0.45, idx) * 1.30;
            col += (fillCol + border * edgeCol) * u.cells * (0.7 + 0.6 * u.bassPunch);
        }

        // Truchet maze: interconnecting arc-tile circuits (angular), drifting + beat-bright.
        if (u.truchet > 0.0) {
            float2 tp = in.uv; tp.x *= aspect;
            float arcs = pv_truchet(tp * 8.0 + float2(u.time * 0.05, 0.0));
            float3 arcCol = pv_cospalette(in.uv.x + in.uv.y + u.time * 0.1, idx);
            col += arcs * arcCol * u.truchet * (0.7 + 0.6 * u.beatPulse);
        }

        float2 cq = in.uv - 0.5; cq.x *= aspect;
        float cr = length(cq);

        // 3D tunnel (demoscene): map angle + 1/r depth to a scrolling wall texture → infinite
        // receding tunnel; darker toward the vanishing point.
        if (u.tunnel3d > 0.0) {
            float ang = atan2(cq.y, cq.x) / 6.2831853;
            float depth = 0.30 / max(cr, 0.02) + u.time * (0.4 + u.bassPunch);
            float pat = 0.5 + 0.5 * sin(ang * 6.2831853 * 6.0) * sin(depth * 6.2831853 * 2.0);
            float3 tc = pv_cospalette(depth * 0.25, idx) * pat * clamp(cr * 2.2, 0.0, 1.0);
            col = mix(col, tc * 1.4, u.tunnel3d);
        }

        // Sine plasma (demoscene): smooth multi-sine colour field.
        if (u.plasma > 0.0) {
            float2 pp = in.uv * 7.0;
            float pv = sin(pp.x + u.time) + sin(pp.y + u.time * 1.3)
                     + sin((pp.x + pp.y) * 0.7 + u.time * 0.7) + sin(cr * 18.0 - u.time * 2.0);
            col += pv_cospalette(pv * 0.12 + u.time * 0.05, idx) * u.plasma * (0.5 + 0.3 * sin(pv));
        }

        // Phyllotaxis (sunflower): golden-angle spiral of glowing seeds.
        if (u.phyllo > 0.0) {
            float a = atan2(cq.y, cq.x);
            float n = cr * cr * 60.0;
            float dots = pow(max(0.0, cos(a - n * 2.39996 + u.time * 0.4)), 24.0)
                       * pow(max(0.0, cos(n * 3.14159)), 8.0);
            col += dots * pv_cospalette(n * 0.04, idx) * u.phyllo * (1.0 + u.beatPulse);
        }

        // Ripple interference: concentric waves from a few drifting sources (pond).
        if (u.ripple > 0.0) {
            float rv = 0.0;
            for (int i = 0; i < 3; i++) {
                float2 src = 0.3 * float2(sin(u.time * 0.5 + float(i) * 2.1), cos(u.time * 0.4 + float(i) * 1.7));
                rv += sin(length(cq - src) * 38.0 - u.time * 3.0);
            }
            col += pv_cospalette(rv * 0.1 + 0.5, idx) * u.ripple * (0.4 + 0.3 * rv);
        }

        // Hex honeycomb: glowing hexagonal cell borders.
        if (u.hex > 0.0) {
            float2 hp = in.uv * 10.0;
            const float2 hs = float2(1.0, 1.7320508);
            float2 ha = fmod(hp, hs) - hs * 0.5;
            float2 hb = fmod(hp - hs * 0.5, hs) - hs * 0.5;
            float2 hg = dot(ha, ha) < dot(hb, hb) ? ha : hb;
            float hd = abs(max(abs(hg.x) * 0.8660254 + hg.y * 0.5, hg.y) - 0.42);
            float hl = smoothstep(0.06, 0.0, hd);
            col += hl * pv_cospalette(in.uv.x + u.time * 0.08, idx) * u.hex * (0.7 + 0.5 * u.treblePunch);
        }
        return float4(col, 1.0);
    }
    """
}
// swiftlint:enable type_body_length
#endif
