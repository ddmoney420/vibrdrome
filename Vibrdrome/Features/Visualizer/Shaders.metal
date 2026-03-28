#include <metal_stdlib>
using namespace metal;

// Shared helpers

float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float noise2d(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    for (int i = 0; i < 5; i++) {
        v += a * noise2d(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

float3 hsv2rgb(float3 c) {
    float3 p = abs(fract(float3(c.x) + float3(0.0, 0.333, 0.667)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// MARK: - 1. Plasma

[[ stitchable ]] half4 plasma(float2 position, half4 color, float2 size, float time, float energy,
                               float bass, float mid, float treble) {
    float2 uv = position / size;
    float t = time * (0.5 + energy * 0.8);

    float scale = 10.0 + bass * 8.0;
    float v1 = sin(uv.x * scale + t + bass * 3.0);
    float v2 = sin(uv.y * scale + t * 0.7 + mid * 2.0);
    float v3 = sin((uv.x + uv.y) * scale + t * 0.5);
    float v4 = sin(length(uv - 0.5) * (14.0 + mid * 10.0) - t * 1.3);

    float v = (v1 + v2 + v3 + v4) * 0.25;
    v = v * (0.4 + energy * 0.8);

    float hueShift = treble * 0.6 + bass * 0.3;
    float r = sin(v * 3.14159 + hueShift) * 0.5 + 0.5;
    float g = sin(v * 3.14159 + 2.094 + hueShift) * 0.5 + 0.5;
    float b2 = sin(v * 3.14159 + 4.189 + hueShift) * 0.5 + 0.5;

    float brightness = 0.5 + energy * 0.6;
    float3 col = float3(r, g, b2) * brightness;
    // Boost saturation
    float gray = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(gray), col, 1.4);
    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 2. Aurora

[[ stitchable ]] half4 aurora(float2 position, half4 color, float2 size, float time, float energy,
                               float bass, float mid, float treble) {
    float2 uv = position / size;
    float t = time * 0.3;

    float y = uv.y;
    float wave = 0.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float freq = 1.5 + fi * 0.8;
        float amp = 0.08 / (fi * 0.5 + 1.0);
        amp *= (0.5 + bass * 0.8);
        wave += sin(uv.x * freq * 6.0 + t * (1.0 + fi * 0.3) + fi * 1.7) * amp;
    }

    float band1 = smoothstep(0.08 + mid * 0.04, 0.0, abs(y - 0.35 - wave));
    float band2 = smoothstep(0.06 + mid * 0.03, 0.0, abs(y - 0.5 - wave * 0.7));
    float band3 = smoothstep(0.05 + mid * 0.02, 0.0, abs(y - 0.65 - wave * 0.5));

    // Vivid aurora colors that shift with frequency
    float hShift = treble * 0.4 + t * 0.05;
    float3 c1 = hsv2rgb(float3(fract(0.35 + hShift), 0.9, 1.0)) * band1;
    float3 c2 = hsv2rgb(float3(fract(0.6 + hShift), 0.8, 1.0)) * band2;
    float3 c3 = hsv2rgb(float3(fract(0.8 + hShift), 0.85, 1.0)) * band3;

    float3 col = c1 + c2 + c3;
    col *= (0.6 + energy * 0.6);

    // Background glow reacts to mid
    float glow = fbm(uv * 3.0 + float2(t * 0.15, mid)) * (0.05 + mid * 0.1);
    col += hsv2rgb(float3(fract(0.5 + hShift), 0.5, glow));

    // Bass pulse at horizon
    float horizon = exp(-abs(uv.y - 0.5) * 8.0) * bass * 0.4;
    col += float3(0.3, 0.8, 0.5) * horizon;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 3. Nebula

[[ stitchable ]] half4 nebula(float2 position, half4 color, float2 size, float time, float energy,
                               float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    float t = time * (0.3 + bass * 0.3);

    // Bass warps the coordinate space
    float2 warp = float2(sin(t + uv.y * 2.0) * bass * 0.4, cos(t * 0.8 + uv.x * 2.0) * bass * 0.4);
    float2 p = uv * (3.0 + bass * 3.0) + warp;

    float f1 = fbm(p + float2(t, t * 0.7));
    float f2 = fbm(p + float2(f1 * (2.0 + mid * 2.0) + t * 0.3, f1 * 1.5));
    float f3 = fbm(p + float2(f2 * 1.5 - t * 0.2, f2 * (2.0 + bass) + t * 0.1));

    float v = f3 * (0.5 + energy * 0.7);

    // Color wash that shifts with frequency bands
    float hueShift = bass * 0.4 + treble * 0.3 + t * 0.05;
    float3 col = float3(0.0);
    col = mix(col, hsv2rgb(float3(fract(0.75 + hueShift), 0.8, 0.3)), smoothstep(0.0, 0.3, v));
    col = mix(col, hsv2rgb(float3(fract(0.85 + hueShift), 0.7, 0.6)), smoothstep(0.15, 0.5, v));
    col = mix(col, hsv2rgb(float3(fract(0.0 + hueShift), 0.6, 0.8)), smoothstep(0.3, 0.7, v));
    col = mix(col, hsv2rgb(float3(fract(0.1 + hueShift), 0.4, 1.0)), smoothstep(0.5, 0.9, v));

    // Mid-driven pulsing glow
    float radius = length(uv);
    float pulse = exp(-radius * (1.5 - mid * 0.5)) * mid * 0.6;
    col += hsv2rgb(float3(fract(t * 0.08 + 0.6), 0.7, 1.0)) * pulse;

    // Stars shimmer with treble
    float stars = pow(hash(floor(uv * 120.0)), 18.0);
    float starFlicker = 0.5 + 0.5 * sin(hash(floor(uv * 120.0)) * 100.0 + t * 5.0);
    col += stars * starFlicker * (0.4 + treble * 1.0);

    // Boost vibrancy
    float gray = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(gray), col, 1.3);

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 4. Waveform

[[ stitchable ]] half4 waveform(float2 position, half4 color, float2 size, float time, float energy,
                                 float bass, float mid, float treble) {
    float2 uv = position / size;
    float t = time;
    float3 col = float3(0.02, 0.02, 0.05);

    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float freq = 2.0 + fi * 1.5;
        float phase = fi * 1.047;
        float speed = 1.0 + fi * 0.4;

        // Strong frequency-band response per layer
        float bandEnergy = (i < 3) ? bass : (i < 6) ? mid : treble;
        float amp = (0.04 + bandEnergy * 0.15) / (fi * 0.25 + 1.0);

        float wave = sin(uv.x * freq * 6.28 + t * speed + phase + bandEnergy * 4.0) * amp;
        wave += sin(uv.x * freq * 3.14 + t * speed * 0.7 + bandEnergy * 2.0) * amp * 0.6;

        float y = 0.5 + wave;
        float d = abs(uv.y - y);

        // Thicker, brighter glow
        float glowWidth = 0.004 + bandEnergy * 0.003;
        float glow = glowWidth / (d + 0.0005);
        glow = min(glow, 5.0);
        glow *= (0.4 + energy * 0.8);

        float hue = fract(fi / 8.0 + t * 0.04 + bandEnergy * 0.2);
        float3 waveColor = hsv2rgb(float3(hue, 0.8, 1.0));

        col += waveColor * glow * 0.1;
    }

    // Bass pulse behind waves
    float bassPulse = (0.5 + 0.5 * sin(t * 4.0)) * bass * 0.15;
    col += float3(0.2, 0.1, 0.4) * bassPulse;

    // Center line glow
    float mirror = smoothstep(0.015, 0.0, abs(uv.y - 0.5)) * energy * 0.5;
    col += float3(0.4, 0.6, 1.0) * mirror;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 5. Tunnel

[[ stitchable ]] half4 tunnel(float2 position, half4 color, float2 size, float time, float energy,
                               float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time * (0.5 + bass * 0.8);

    float angle = atan2(uv.y, uv.x);
    float radius = length(uv);

    float tunnelU = 0.5 / (radius + 0.001) + t;
    float tunnelV = angle / 3.14159;

    float pattern = sin(tunnelU * 8.0) * sin(tunnelV * (6.0 + mid * 4.0));
    float pattern2 = sin(tunnelU * 4.0 + t) * sin(tunnelV * 3.0 - t * 0.3);

    float v = (pattern + pattern2) * 0.5;
    v *= smoothstep(2.0, 0.2, radius);

    float pulse = 0.5 + 0.5 * sin(t * 4.0 + radius * 3.0);
    pulse = mix(0.5, pulse, mid);

    float3 col;
    col.r = sin(v * 2.0 + t + treble * 2.0) * 0.5 + 0.5;
    col.g = sin(v * 2.0 + t + 2.094) * 0.5 + 0.5;
    col.b = sin(v * 2.0 + t + 4.189) * 0.5 + 0.5;

    col *= pulse;
    col *= smoothstep(2.5, 0.0, radius);

    float centerGlow = 0.02 / (radius + 0.02) * (bass + 0.2);
    col += float3(0.5, 0.3, 0.8) * centerGlow;

    return half4(half3(col), 1.0h);
}

// MARK: - 6. Kaleidoscope

[[ stitchable ]] half4 kaleidoscope(float2 position, half4 color, float2 size, float time, float energy,
                                     float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time * (0.3 + bass * 0.3);

    float angle = atan2(uv.y, uv.x);
    float radius = length(uv);

    float segments = 6.0 + mid * 4.0;
    angle = fmod(abs(angle), 3.14159 * 2.0 / segments);
    angle = abs(angle - 3.14159 / segments);

    float2 kUv = float2(cos(angle), sin(angle)) * radius;

    float2 p = kUv * 3.0 + float2(t, t * 0.7);
    float f = fbm(p);
    f += fbm(p * 2.0 + float2(f * bass, t * 0.5)) * 0.5;

    float pulse = 0.7 + 0.3 * sin(t * 3.0 + radius * 5.0) * energy;

    float3 col;
    col.r = sin(f * 4.0 + t + treble) * 0.5 + 0.5;
    col.g = sin(f * 4.0 + t + 2.094) * 0.5 + 0.5;
    col.b = sin(f * 4.0 + t + 4.189) * 0.5 + 0.5;

    col *= pulse;
    col *= smoothstep(1.8, 0.0, radius);
    col *= 1.0 - radius * 0.3;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 7. Particles

[[ stitchable ]] half4 particles(float2 position, half4 color, float2 size, float time, float energy,
                                  float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time;
    float3 col = float3(0.02, 0.01, 0.05);

    // Background nebula glow
    float bgNoise = fbm(uv * 2.0 + float2(t * 0.05, t * 0.03));
    col += float3(0.05, 0.02, 0.1) * bgNoise * (0.5 + bass * 0.5);

    // Particle field
    for (int i = 0; i < 50; i++) {
        float fi = float(i);
        float seed = hash(float2(fi * 13.7, fi * 7.3));
        float seed2 = hash(float2(fi * 31.1, fi * 17.9));

        // Spiral outward from center, speed driven by bass
        float angle = seed * 6.28 + t * (0.3 + seed2 * 0.5) + bass * 3.0;
        float dist = fract(seed2 + t * (0.08 + bass * 0.12)) * 1.2;

        float2 particlePos = float2(cos(angle), sin(angle)) * dist;
        float d = length(uv - particlePos);

        // Larger particles that pulse with energy
        float particleSize = 0.008 + mid * 0.012 + energy * 0.005;
        float glow = particleSize / (d * d + 0.0001);
        glow = min(glow, 4.0);

        // Bright color with hue cycling
        float hue = fract(seed + t * 0.03 + treble * 0.5);
        float3 pColor = hsv2rgb(float3(hue, 0.7, 1.0));

        col += pColor * glow * 0.08 * (0.4 + energy * 0.6);
    }

    // Center energy burst
    float centerDist = length(uv);
    float burst = exp(-centerDist * 3.0) * bass * 0.8;
    col += float3(0.6, 0.3, 1.0) * burst;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 8. Fractal

[[ stitchable ]] half4 fractal(float2 position, half4 color, float2 size, float time, float energy,
                                float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;

    // Zoom driven by bass
    float zoom = 2.0 + sin(time * 0.1) * 0.5 + bass * 1.5;
    float2 c = float2(-0.745 + sin(time * 0.03) * 0.01,
                       0.186 + cos(time * 0.04) * 0.01);

    float2 z = uv / zoom;
    int maxIter = 40 + int(mid * 20.0);
    int iter = 0;

    for (int i = 0; i < 60; i++) {
        if (i >= maxIter) break;
        if (dot(z, z) > 4.0) break;
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        iter = i;
    }

    float t2 = float(iter) / float(maxIter);
    t2 = sqrt(t2);

    float hue = fract(t2 + time * 0.02 + treble * 0.3);
    float sat = 0.7 + energy * 0.3;
    float val = t2 * (0.7 + energy * 0.3);

    float3 col = hsv2rgb(float3(hue, sat, val));

    // Glow at escape boundary
    float edgeGlow = smoothstep(0.0, 0.1, t2) * smoothstep(1.0, 0.8, t2);
    col += float3(0.3, 0.1, 0.5) * edgeGlow * bass;

    return half4(half3(col), 1.0h);
}

// MARK: - 9. Fluid

[[ stitchable ]] half4 fluid(float2 position, half4 color, float2 size, float time, float energy,
                              float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time;

    // Strong bass-driven warping — the core "fluid" feel
    float2 warp = float2(
        sin(uv.y * 3.0 + t * 1.5) * bass * 1.5 + cos(uv.y * 7.0 + t) * mid * 0.5,
        cos(uv.x * 3.0 + t * 1.2) * bass * 1.5 + sin(uv.x * 5.0 - t) * mid * 0.5
    );

    float2 p = uv + warp * 0.3;

    // Layered fluid motion — each layer reacts to different frequency
    float f1 = fbm(p * 2.0 + float2(t * 0.8, t * 0.6));
    float f2 = fbm(p * 3.0 + float2(f1 * bass * 3.0, -t * 0.5));
    float f3 = fbm(p * 5.0 + float2(f2 * mid * 2.0, f1 + t * 0.3));

    // Treble adds shimmering detail
    float detail = noise2d(uv * 12.0 + float2(t * 2.0, f3)) * treble;

    float v = f1 * 0.4 + f2 * 0.35 + f3 * 0.25 + detail * 0.3;
    v *= (0.6 + energy * 0.8);

    // Vivid color palette that shifts with frequency
    float hueBase = fract(t * 0.03 + bass * 0.2);
    float3 col;
    col.r = sin(v * 5.0 + hueBase * 6.28 + 0.0) * 0.5 + 0.5;
    col.g = sin(v * 5.0 + hueBase * 6.28 + 2.094) * 0.5 + 0.5;
    col.b = sin(v * 5.0 + hueBase * 6.28 + 4.189) * 0.5 + 0.5;

    // Boost saturation
    float gray = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(gray), col, 1.5);

    // Bass shock waves ripple outward
    float radius = length(uv);
    float wave = sin(radius * 8.0 - t * 4.0 - bass * 10.0) * 0.5 + 0.5;
    wave *= exp(-radius * 1.5) * bass;
    col += float3(0.4, 0.2, 0.8) * wave;

    // Mid-frequency swirl
    float swirl = sin(atan2(uv.y, uv.x) * 3.0 + t + mid * 5.0) * mid * 0.2;
    col *= 1.0 + swirl;

    col *= (0.7 + energy * 0.5);

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 10. Rings

[[ stitchable ]] half4 rings(float2 position, half4 color, float2 size, float time, float energy,
                              float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time;
    float3 col = float3(0.03, 0.01, 0.06);

    float radius = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Background energy wash
    float bgWash = fbm(uv * 1.5 + float2(t * 0.1, bass)) * energy * 0.15;
    col += hsv2rgb(float3(fract(t * 0.02), 0.5, bgWash));

    // Concentric rings — each strongly tied to a frequency band
    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float ringRadius = 0.1 + fi * 0.17;
        float pulseAmt = (i < 4) ? bass : (i < 7) ? mid : treble;

        // Strong pulsing — rings breathe with the music
        ringRadius += sin(t * (3.0 + fi * 0.7) + fi * 1.5) * 0.05 * (1.0 + pulseAmt * 4.0);

        float d = abs(radius - ringRadius);
        // Wider, brighter rings
        float ringWidth = 0.012 + pulseAmt * 0.02;
        float glow = ringWidth / (d + 0.0005);
        glow = min(glow, 5.0);

        // Rotating angular pattern — breaks up the rings
        float rotAngle = angle + t * (0.3 + fi * 0.15) * (fmod(fi, 2.0) > 0.5 ? 1.0 : -1.0);
        float segments = 4.0 + fi * 2.0;
        float angularPattern = 0.5 + 0.5 * sin(rotAngle * segments + pulseAmt * 3.0);

        // Vivid colors cycling through rainbow
        float hue = fract(fi / 10.0 + t * 0.04 + pulseAmt * 0.3);
        float3 ringColor = hsv2rgb(float3(hue, 0.85, 1.0));

        col += ringColor * glow * angularPattern * 0.1 * (0.3 + energy * 0.8);
    }

    // Center bass burst
    float centerGlow = exp(-radius * 4.0) * bass * 1.2;
    col += hsv2rgb(float3(fract(t * 0.06), 0.6, 1.0)) * centerGlow;

    // Outer treble shimmer
    float outerShimmer = smoothstep(1.0, 1.8, radius) * treble * 0.3;
    col += float3(0.5, 0.3, 0.8) * outerShimmer * sin(angle * 8.0 + t * 2.0);

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 11. Spectrum Visualizer

[[ stitchable ]] half4 spectrumVis(float2 position, half4 color, float2 size, float time, float energy,
                                    float bass, float mid, float treble) {
    float2 uv = position / size;
    float3 col = float3(0.02, 0.02, 0.04);

    // Create bars across the screen
    float barCount = 32.0;
    float barIndex = floor(uv.x * barCount);
    float barCenter = (barIndex + 0.5) / barCount;
    float barWidth = 0.8 / barCount;

    // Simulate frequency magnitude per bar using bass/mid/treble interpolation
    float normalizedPos = barIndex / barCount;
    float barHeight;
    if (normalizedPos < 0.33) {
        barHeight = bass * (0.8 + 0.4 * sin(barIndex * 1.7 + time * 3.0));
    } else if (normalizedPos < 0.66) {
        barHeight = mid * (0.7 + 0.3 * sin(barIndex * 2.3 + time * 2.5));
    } else {
        barHeight = treble * (0.6 + 0.4 * sin(barIndex * 3.1 + time * 4.0));
    }

    barHeight = clamp(barHeight, 0.02, 0.95);

    // Draw bar from bottom
    float inBar = step(abs(uv.x - barCenter), barWidth * 0.5) * step(1.0 - uv.y, barHeight);

    // Gradient color based on height
    float hue = fract(normalizedPos * 0.7 + time * 0.02);
    float3 barColor = hsv2rgb(float3(hue, 0.8, 0.9));

    // Glow effect
    float distToBar = abs(uv.x - barCenter);
    float barGlow = 0.002 / (distToBar + 0.002) * barHeight * 0.1;

    col += barColor * inBar * (0.6 + energy * 0.4);
    col += barColor * barGlow * 0.3;

    // Reflection at bottom
    float reflection = step(1.0 - uv.y, barHeight * 0.3) * step(uv.y, 0.15);
    col += barColor * reflection * 0.15;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 12. Vortex

[[ stitchable ]] half4 vortex(float2 position, half4 color, float2 size, float time, float energy,
                               float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time;

    float radius = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Spiral distortion driven by bass
    float spiral = angle + radius * (3.0 + bass * 5.0) - t * (1.0 + bass * 0.5);

    // Multiple spiral arms
    float arms = 3.0;
    float pattern = sin(spiral * arms) * 0.5 + 0.5;
    pattern *= smoothstep(1.5, 0.0, radius);

    // Turbulence from treble
    float turb = noise2d(uv * 5.0 + float2(t * 0.5, t * 0.3)) * treble * 0.3;
    pattern += turb;

    // Mid-frequency ripples
    float ripple = sin(radius * 15.0 - t * 3.0) * mid * 0.15;
    pattern += ripple;

    // Vivid color cycling
    float hue = fract(angle / 6.28 + t * 0.05 + radius * 0.2);
    float3 col = hsv2rgb(float3(hue, 0.85, pattern * (0.5 + energy * 0.7)));

    // Center glow
    float centerGlow = 0.05 / (radius + 0.05) * (bass * 0.7 + 0.3);
    col += float3(0.6, 0.3, 0.9) * centerGlow;

    // Boost saturation
    float gray = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(gray), col, 1.3);

    // Edge vignette
    col *= smoothstep(2.0, 0.5, radius);

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}
