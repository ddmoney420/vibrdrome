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

// MARK: - 1. Plasma

[[ stitchable ]] half4 plasma(float2 position, half4 color, float2 size, float time, float energy) {
    float2 uv = position / size;
    float t = time * (0.4 + energy * 0.6);

    float v1 = sin(uv.x * 10.0 + t);
    float v2 = sin(uv.y * 10.0 + t * 0.7);
    float v3 = sin((uv.x + uv.y) * 10.0 + t * 0.5);
    float v4 = sin(length(uv - 0.5) * 14.0 - t * 1.3);

    float v = (v1 + v2 + v3 + v4) * 0.25;
    v = v * (0.5 + energy * 0.5);

    float r = sin(v * 3.14159 + 0.0) * 0.5 + 0.5;
    float g = sin(v * 3.14159 + 2.094) * 0.5 + 0.5;
    float b = sin(v * 3.14159 + 4.189) * 0.5 + 0.5;

    float brightness = 0.6 + energy * 0.4;
    return half4(half3(r, g, b) * half(brightness), 1.0h);
}

// MARK: - 2. Aurora

[[ stitchable ]] half4 aurora(float2 position, half4 color, float2 size, float time, float energy) {
    float2 uv = position / size;
    float t = time * 0.3;

    float y = uv.y;
    float wave = 0.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float freq = 1.5 + fi * 0.8;
        float amp = 0.08 / (fi * 0.5 + 1.0);
        amp *= (0.5 + energy * 0.5);
        wave += sin(uv.x * freq * 6.0 + t * (1.0 + fi * 0.3) + fi * 1.7) * amp;
    }

    float band1 = smoothstep(0.08, 0.0, abs(y - 0.35 - wave));
    float band2 = smoothstep(0.06, 0.0, abs(y - 0.5 - wave * 0.7));
    float band3 = smoothstep(0.05, 0.0, abs(y - 0.65 - wave * 0.5));

    float3 c1 = float3(0.1, 0.8, 0.4) * band1;
    float3 c2 = float3(0.2, 0.5, 0.9) * band2;
    float3 c3 = float3(0.6, 0.2, 0.8) * band3;

    float3 col = c1 + c2 + c3;
    col *= (0.7 + energy * 0.3);

    // Subtle background glow
    float glow = fbm(uv * 3.0 + float2(t * 0.1, 0.0)) * 0.05;
    col += float3(glow * 0.3, glow * 0.5, glow * 0.7);

    return half4(half3(col), 1.0h);
}

// MARK: - 3. Nebula

[[ stitchable ]] half4 nebula(float2 position, half4 color, float2 size, float time, float energy) {
    float2 uv = (position / size - 0.5) * 2.0;
    float t = time * 0.2;

    float2 p = uv * 3.0;
    float f1 = fbm(p + float2(t, t * 0.7));
    float f2 = fbm(p + float2(f1 * 2.0 + t * 0.3, f1 * 1.5));
    float f3 = fbm(p + float2(f2 * 1.5 - t * 0.2, f2 * 2.0 + t * 0.1));

    float v = f3 * (0.6 + energy * 0.4);

    float3 col = float3(0.0);
    col = mix(col, float3(0.1, 0.0, 0.2), smoothstep(0.0, 0.4, v));
    col = mix(col, float3(0.4, 0.1, 0.6), smoothstep(0.2, 0.6, v));
    col = mix(col, float3(0.8, 0.3, 0.5), smoothstep(0.4, 0.8, v));
    col = mix(col, float3(1.0, 0.8, 0.6), smoothstep(0.6, 1.0, v));

    // Stars
    float stars = pow(hash(floor(uv * 100.0)), 20.0);
    col += stars * 0.5 * energy;

    return half4(half3(col), 1.0h);
}

// MARK: - 4. Waveform

[[ stitchable ]] half4 waveform(float2 position, half4 color, float2 size, float time, float energy) {
    float2 uv = position / size;
    float t = time;
    float3 col = float3(0.02, 0.02, 0.05);

    // Multiple waveform layers
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float freq = 3.0 + fi * 2.0;
        float phase = fi * 1.047;
        float speed = 1.0 + fi * 0.3;
        float amp = (0.03 + energy * 0.06) / (fi * 0.3 + 1.0);

        float wave = sin(uv.x * freq * 6.28 + t * speed + phase) * amp;
        wave += sin(uv.x * freq * 3.14 + t * speed * 0.7) * amp * 0.5;

        float y = 0.5 + wave;
        float d = abs(uv.y - y);
        float glow = 0.003 / (d + 0.001);
        glow *= energy * 0.7 + 0.3;

        float hue = fract(fi / 6.0 + t * 0.05);
        float3 waveColor;
        // HSV to RGB approximation
        float3 p2 = abs(fract(float3(hue) + float3(0.0, 0.333, 0.667)) * 6.0 - 3.0);
        waveColor = clamp(p2 - 1.0, 0.0, 1.0);
        waveColor = mix(float3(1.0), waveColor, 0.8);

        col += waveColor * glow * 0.15;
    }

    // Center reflection
    float mirror = smoothstep(0.01, 0.0, abs(uv.y - 0.5)) * energy * 0.3;
    col += float3(0.3, 0.5, 0.8) * mirror;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - 5. Tunnel

[[ stitchable ]] half4 tunnel(float2 position, half4 color, float2 size, float time, float energy) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time * (0.5 + energy * 0.5);

    float angle = atan2(uv.y, uv.x);
    float radius = length(uv);

    float tunnelU = 0.5 / (radius + 0.001) + t;
    float tunnelV = angle / 3.14159;

    float pattern = sin(tunnelU * 8.0) * sin(tunnelV * 6.0);
    float pattern2 = sin(tunnelU * 4.0 + t) * sin(tunnelV * 3.0 - t * 0.3);

    float v = (pattern + pattern2) * 0.5;
    v *= smoothstep(2.0, 0.2, radius);

    float pulse = 0.5 + 0.5 * sin(t * 4.0 + radius * 3.0);
    pulse = mix(0.5, pulse, energy);

    float3 col;
    col.r = sin(v * 2.0 + t + 0.0) * 0.5 + 0.5;
    col.g = sin(v * 2.0 + t + 2.094) * 0.5 + 0.5;
    col.b = sin(v * 2.0 + t + 4.189) * 0.5 + 0.5;

    col *= pulse;
    col *= smoothstep(2.5, 0.0, radius);

    // Center glow
    float centerGlow = 0.02 / (radius + 0.02) * energy;
    col += float3(0.5, 0.3, 0.8) * centerGlow;

    return half4(half3(col), 1.0h);
}

// MARK: - 6. Kaleidoscope

[[ stitchable ]] half4 kaleidoscope(float2 position, half4 color, float2 size, float time, float energy) {
    float2 uv = (position / size - 0.5) * 2.0;
    uv.x *= size.x / size.y;
    float t = time * 0.3;

    float angle = atan2(uv.y, uv.x);
    float radius = length(uv);

    // Kaleidoscope fold
    float segments = 6.0;
    angle = fmod(abs(angle), 3.14159 * 2.0 / segments);
    angle = abs(angle - 3.14159 / segments);

    float2 kUv = float2(cos(angle), sin(angle)) * radius;

    // Animated pattern
    float2 p = kUv * 3.0 + float2(t, t * 0.7);
    float f = fbm(p);
    f += fbm(p * 2.0 + float2(f * energy, t * 0.5)) * 0.5;

    float pulse = 0.7 + 0.3 * sin(t * 3.0 + radius * 5.0) * energy;

    float3 col;
    col.r = sin(f * 4.0 + t + 0.0) * 0.5 + 0.5;
    col.g = sin(f * 4.0 + t + 2.094) * 0.5 + 0.5;
    col.b = sin(f * 4.0 + t + 4.189) * 0.5 + 0.5;

    col *= pulse;
    col *= smoothstep(1.8, 0.0, radius);

    // Edge darkening
    col *= 1.0 - radius * 0.3;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}
