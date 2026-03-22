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
    float t = time * (0.4 + energy * 0.6);

    float scale = 10.0 + bass * 4.0;
    float v1 = sin(uv.x * scale + t);
    float v2 = sin(uv.y * scale + t * 0.7);
    float v3 = sin((uv.x + uv.y) * scale + t * 0.5);
    float v4 = sin(length(uv - 0.5) * (14.0 + mid * 6.0) - t * 1.3);

    float v = (v1 + v2 + v3 + v4) * 0.25;
    v = v * (0.5 + energy * 0.5);

    float hueShift = treble * 0.3;
    float r = sin(v * 3.14159 + hueShift) * 0.5 + 0.5;
    float g = sin(v * 3.14159 + 2.094 + hueShift) * 0.5 + 0.5;
    float b2 = sin(v * 3.14159 + 4.189 + hueShift) * 0.5 + 0.5;

    float brightness = 0.6 + energy * 0.4;
    return half4(half3(r, g, b2) * half(brightness), 1.0h);
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

    float3 c1 = float3(0.1, 0.8, 0.4) * band1;
    float3 c2 = float3(0.2, 0.5, 0.9) * band2;
    float3 c3 = float3(0.6, 0.2, 0.8) * band3;

    float3 col = c1 + c2 + c3;
    col *= (0.7 + treble * 0.5);

    float glow = fbm(uv * 3.0 + float2(t * 0.1, 0.0)) * 0.05;
    col += float3(glow * 0.3, glow * 0.5, glow * 0.7);

    return half4(half3(col), 1.0h);
}

// MARK: - 3. Nebula

[[ stitchable ]] half4 nebula(float2 position, half4 color, float2 size, float time, float energy,
                               float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    float t = time * 0.2;

    float2 p = uv * (3.0 + bass * 2.0);
    float f1 = fbm(p + float2(t, t * 0.7));
    float f2 = fbm(p + float2(f1 * 2.0 + t * 0.3, f1 * 1.5));
    float f3 = fbm(p + float2(f2 * 1.5 - t * 0.2, f2 * 2.0 + t * 0.1));

    float v = f3 * (0.6 + energy * 0.4);

    float3 col = float3(0.0);
    col = mix(col, float3(0.1, 0.0, 0.2), smoothstep(0.0, 0.4, v));
    col = mix(col, float3(0.4, 0.1, 0.6), smoothstep(0.2, 0.6, v));
    col = mix(col, float3(0.8, 0.3, 0.5), smoothstep(0.4, 0.8, v));
    col = mix(col, float3(1.0, 0.8, 0.6), smoothstep(0.6, 1.0, v));

    float stars = pow(hash(floor(uv * 100.0)), 20.0);
    col += stars * (0.3 + treble * 0.7);

    return half4(half3(col), 1.0h);
}

// MARK: - 4. Waveform

[[ stitchable ]] half4 waveform(float2 position, half4 color, float2 size, float time, float energy,
                                 float bass, float mid, float treble) {
    float2 uv = position / size;
    float t = time;
    float3 col = float3(0.02, 0.02, 0.05);

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float freq = 3.0 + fi * 2.0;
        float phase = fi * 1.047;
        float speed = 1.0 + fi * 0.3;

        // Different frequency bands drive different wave layers
        float bandEnergy = (i < 2) ? bass : (i < 4) ? mid : treble;
        float amp = (0.03 + bandEnergy * 0.08) / (fi * 0.3 + 1.0);

        float wave = sin(uv.x * freq * 6.28 + t * speed + phase) * amp;
        wave += sin(uv.x * freq * 3.14 + t * speed * 0.7) * amp * 0.5;

        float y = 0.5 + wave;
        float d = abs(uv.y - y);
        float glow = 0.003 / (d + 0.001);
        glow *= energy * 0.7 + 0.3;

        float hue = fract(fi / 6.0 + t * 0.05);
        float3 waveColor;
        float3 p2 = abs(fract(float3(hue) + float3(0.0, 0.333, 0.667)) * 6.0 - 3.0);
        waveColor = clamp(p2 - 1.0, 0.0, 1.0);
        waveColor = mix(float3(1.0), waveColor, 0.8);

        col += waveColor * glow * 0.15;
    }

    float mirror = smoothstep(0.01, 0.0, abs(uv.y - 0.5)) * energy * 0.3;
    col += float3(0.3, 0.5, 0.8) * mirror;

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
    float3 col = float3(0.01, 0.01, 0.03);

    // Particle field
    for (int i = 0; i < 80; i++) {
        float fi = float(i);
        float seed = hash(float2(fi * 13.7, fi * 7.3));
        float seed2 = hash(float2(fi * 31.1, fi * 17.9));

        // Spiral outward from center, speed driven by bass
        float angle = seed * 6.28 + t * (0.3 + seed2 * 0.5) + bass * 2.0;
        float dist = fract(seed2 + t * (0.1 + bass * 0.15)) * 1.5;

        float2 particlePos = float2(cos(angle), sin(angle)) * dist;

        float d = length(uv - particlePos);

        // Size pulses with mid
        float particleSize = 0.003 + mid * 0.004;
        float glow = particleSize / (d + 0.001);
        glow = min(glow, 3.0);

        // Color based on distance and treble
        float hue = fract(seed + t * 0.05 + treble * 0.5);
        float3 pColor = hsv2rgb(float3(hue, 0.8, 1.0));

        col += pColor * glow * 0.02 * (0.5 + energy);
    }

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
    float t = time * 0.3;

    // Multiple fluid layers with frequency-driven distortion
    float2 p1 = uv * 2.0 + float2(t * 0.5, t * 0.3);
    float2 p2 = uv * 3.0 + float2(-t * 0.3, t * 0.4);

    // Bass creates pressure waves
    float distort = bass * 0.5;
    p1 += float2(sin(uv.y * 4.0 + t) * distort, cos(uv.x * 4.0 + t) * distort);

    float f1 = fbm(p1);
    float f2 = fbm(p2 + float2(f1 * (1.0 + mid)));

    // Treble adds fine turbulence
    float f3 = fbm(uv * 8.0 + float2(f2, t) + treble * 2.0) * treble;

    float v = (f1 + f2 * 0.5 + f3 * 0.3) * (0.5 + energy * 0.5);

    // Deep ocean-like color palette
    float3 col = float3(0.0);
    col = mix(col, float3(0.0, 0.05, 0.15), smoothstep(0.0, 0.3, v));
    col = mix(col, float3(0.05, 0.15, 0.4), smoothstep(0.2, 0.5, v));
    col = mix(col, float3(0.1, 0.4, 0.6), smoothstep(0.4, 0.7, v));
    col = mix(col, float3(0.3, 0.7, 0.9), smoothstep(0.6, 0.85, v));
    col = mix(col, float3(0.9, 0.95, 1.0), smoothstep(0.8, 1.0, v));

    // Bass pulse glow from center
    float centerDist = length(uv);
    float pulse = exp(-centerDist * 2.0) * bass * 0.5;
    col += float3(0.2, 0.5, 0.8) * pulse;

    return half4(half3(col), 1.0h);
}

// MARK: - 10. Rings

[[ stitchable ]] half4 rings(float2 position, half4 color, float2 size, float time, float energy,
                              float bass, float mid, float treble) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time;
    float3 col = float3(0.02, 0.01, 0.04);

    float radius = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Concentric rings that pulse with bass
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float ringRadius = 0.15 + fi * 0.2;
        float pulseAmt = (i < 3) ? bass : (i < 6) ? mid : treble;
        ringRadius += sin(t * (2.0 + fi * 0.5) + fi) * 0.03 * (1.0 + pulseAmt * 2.0);

        float d = abs(radius - ringRadius);
        float ringWidth = 0.008 + pulseAmt * 0.01;
        float glow = ringWidth / (d + 0.001);
        glow = min(glow, 3.0);

        // Rotate each ring at different speeds
        float rotAngle = angle + t * (0.2 + fi * 0.1) * (fmod(fi, 2.0) > 0.5 ? 1.0 : -1.0);
        float angularPattern = 0.7 + 0.3 * sin(rotAngle * (3.0 + fi));

        float hue = fract(fi / 8.0 + t * 0.03);
        float3 ringColor = hsv2rgb(float3(hue, 0.7, 1.0));

        col += ringColor * glow * angularPattern * 0.06 * (0.5 + energy);
    }

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
    float heightNorm = (1.0 - uv.y) / max(barHeight, 0.01);
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

    // Color cycling
    float hue = fract(angle / 6.28 + t * 0.05 + radius * 0.2);
    float3 col = hsv2rgb(float3(hue, 0.7 + energy * 0.3, pattern * (0.6 + energy * 0.4)));

    // Center glow
    float centerGlow = 0.05 / (radius + 0.05) * (bass * 0.7 + 0.3);
    col += float3(0.6, 0.3, 0.9) * centerGlow;

    // Edge vignette
    col *= smoothstep(2.0, 0.5, radius);

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}
