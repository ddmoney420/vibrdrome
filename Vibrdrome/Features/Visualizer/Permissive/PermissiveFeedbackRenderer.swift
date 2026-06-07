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
    private let presentPSO: MTLRenderPipelineState

    private var texA: MTLTexture?
    private var texB: MTLTexture?
    private var readIsA = true
    private var lastWritten: MTLTexture?
    private var staging: MTLTexture?          // 1x1 readback (proof only)
    private var size: CGSize = .zero
    private var clearNext = true

    static let feedbackFormat: MTLPixelFormat = .rgba16Float

    init?(device: MTLDevice) {
        self.device = device
        guard let q = device.makeCommandQueue() else { return nil }
        queue = q
        do {
            let lib = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let fd = MTLRenderPipelineDescriptor()
            fd.vertexFunction = lib.makeFunction(name: "pv_vertex")
            fd.fragmentFunction = lib.makeFunction(name: "pv_feedback")
            fd.colorAttachments[0].pixelFormat = Self.feedbackFormat
            feedbackPSO = try device.makeRenderPipelineState(descriptor: fd)

            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = lib.makeFunction(name: "pv_vertex")
            pd.fragmentFunction = lib.makeFunction(name: "pv_present")
            pd.colorAttachments[0].pixelFormat = .bgra8Unorm
            presentPSO = try device.makeRenderPipelineState(descriptor: pd)
        } catch {
            return nil
        }
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
        clearNext = true
    }

    @MainActor
    func render(in view: MTKView, uniforms: PermissiveUniforms) {
        guard let texA, let texB,
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

        // Pass B — present: palette-map the field to the drawable.
        if let enc = cb.makeRenderCommandEncoder(descriptor: presentRPD) {
            enc.setRenderPipelineState(presentPSO)
            enc.setFragmentTexture(write, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PermissiveUniforms>.stride, index: 0)
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

    // Feedback pass: sample the prior frame through a zoom/rotate warp around center,
    // fade by decay, and add a soft bass-driven radial pulse.
    fragment float4 pv_feedback(VSOut in [[stage_in]],
                                texture2d<float> prev [[texture(0)]],
                                constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 c = in.uv - 0.5;
        float a = u.rotate * (0.4 + u.rotateTreble * u.treble);
        float ca = cos(a), sa = sin(a);
        c = float2(c.x * ca - c.y * sa, c.x * sa + c.y * ca);
        c *= (1.0 - u.zoom * (0.5 + u.zoomBass * u.bass));
        float3 fed = prev.sample(s, c + 0.5).rgb * u.decay;

        float d = length(in.uv - 0.5);
        float pulse = exp(-d * (9.0 - 6.0 * u.bass)) * u.pulseScale * (0.10 + u.pulseBass * u.bass);
        float3 add = pulse * (0.5 + 0.5 * float3(u.bass, u.mid, u.treble));
        // Soft-saturate so the field can't blow out to uniform white — keeps spatial
        // structure (warp/trails) and palette differences visible.
        float3 sum = fed + add;
        sum = sum / (1.0 + 0.55 * sum);
        return float4(sum, 1.0);
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

    fragment float4 pv_present(VSOut in [[stage_in]],
                               texture2d<float> field [[texture(0)]],
                               constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float3 v = field.sample(s, in.uv).rgb;
        float intensity = clamp(length(v) * 0.85, 0.0, 1.0);
        float3 col = pv_palette(intensity + u.time * 0.02, u.paletteShift, int(u.paletteIndex));
        return float4(col * intensity, 1.0);
    }
    """
}
#endif
