#version 440
// Globe-Launcher: the "jacked in" pass over the whole scene. Always: faint
// scanlines and a vignette. In a burst (intensity > 0), one of:
//   0 tear    horizontal slices torn sideways, colours split, noise lines
//   1 blocks  datamosh: blocks shoved out of place, coarse and recoloured
//   2 vhs     a wobble, a tracking band rolling down, colour bleeding
//   3 crt     the picture collapses to a bright line and snaps back
//   4 bleed   code bleed: columns smear downwards, drips of light
//   5 invert  a negative flash, posterised, jittering
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    float intensity;   // 0 calm .. 1 full burst
    float seed;        // changes per burst, so each tears differently
    float scanlines;   // 0..1
    vec4 tint;         // noise lines take this colour
    float kind;
};
layout(binding = 1) uniform sampler2D source;

float hash(float x) { return fract(sin(x * 127.1 + seed * 311.7) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453); }

vec3 split(vec2 uv, float amount) {
    vec4 c = texture(source, uv);
    return vec3(texture(source, uv + vec2(amount, 0.0)).r, c.g, texture(source, uv - vec2(amount, 0.0)).b);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float k = intensity;
    vec3 col;

    if (k < 0.001 || kind < 0.5) {
        // tear: bands of rows shifted sideways
        float band = floor(uv.y * mix(14.0, 46.0, hash(3.0)));
        float tear = (hash(band) - 0.5) * 0.08 * k * step(0.55, hash(band + 7.0));
        vec2 tuv = uv + vec2(tear, 0.0);
        col = split(tuv, 0.006 * k + 0.0008);
        float row = floor(uv.y * resolution.y / 2.0);
        col += tint.rgb * step(1.0 - 0.012 * k, hash(row + floor(time * 30.0))) * 0.6;
    } else if (kind < 1.5) {
        // blocks: some blocks pulled from elsewhere, pixelated, tinted
        vec2 grid = vec2(mix(18.0, 40.0, hash(1.0)), mix(10.0, 24.0, hash(2.0)));
        vec2 b = floor(uv * grid);
        float hit = step(1.0 - 0.28 * k, hash2(b + floor(time * 12.0)));
        vec2 shove = (vec2(hash2(b + 3.1), hash2(b + 5.7)) - 0.5) * vec2(0.18, 0.06) * hit;
        float px = mix(1.0, 90.0, hit) ;
        vec2 cell = resolution / px;
        vec2 q = hit > 0.5 ? (floor((uv + shove) * cell) + 0.5) / cell : uv;
        col = split(q, 0.004 * k);
        col = mix(col, tint.rgb * dot(col, vec3(0.33)) * 1.6, hit * step(0.5, hash2(b + 9.9)));
    } else if (kind < 2.5) {
        // vhs: wobble, a rolling tracking band, colour bleed, a little roll
        float roll = fract(uv.y + k * 0.04 * hash(4.0));
        float wob = sin(roll * 40.0 + time * 9.0) * 0.004 * k + sin(roll * 7.0 - time * 3.0) * 0.003 * k;
        float bandY = fract(time * 0.6 + hash(6.0));
        float inBand = smoothstep(0.06, 0.0, abs(roll - bandY));
        float noise = hash2(vec2(floor(roll * resolution.y / 2.0), floor(time * 40.0)));
        vec2 vuv = vec2(uv.x + wob + inBand * (noise - 0.5) * 0.05 * k, roll);
        vec3 c = split(vuv, 0.003 + 0.01 * k);
        // the colour smears to the right
        vec3 smear = (texture(source, vuv - vec2(0.004, 0.0)).rgb + texture(source, vuv - vec2(0.009, 0.0)).rgb) * 0.5;
        col = mix(c, vec3(smear.r, c.g, smear.b), 0.6 * k);
        col += vec3(noise) * inBand * 0.35 * k;
    } else if (kind < 3.5) {
        // crt: squashed to a line, with a flash in the middle
        float squash = 1.0 - 0.96 * k;
        float y = (uv.y - 0.5) / squash + 0.5;
        float inside = step(0.0, y) * step(y, 1.0);
        col = split(vec2(uv.x, clamp(y, 0.0, 1.0)), 0.002 * k) * inside * (1.0 + 1.5 * k);
        float line = exp(-abs(uv.y - 0.5) * resolution.y / (2.0 + 30.0 * squash));
        col += mix(tint.rgb, vec3(1.0), 0.6) * line * k;
    } else if (kind < 4.5) {
        // code bleed: each column dragged down by its own amount, drips of light
        float colW = mix(6.0, 14.0, hash(8.0));
        float c = floor(uv.x * resolution.x / colW);
        float drag = pow(hash2(vec2(c, 1.0)), 3.0) * 0.25 * k;
        vec2 buv = vec2(uv.x, uv.y - drag);
        vec3 a = texture(source, buv).rgb;
        vec3 b = texture(source, buv - vec2(0.0, drag * 0.5)).rgb;
        col = max(a, b * 0.8);
        float drip = step(0.9, hash2(vec2(c, 3.0))) * smoothstep(0.0, 0.02, drag) * exp(-abs(uv.y - fract(hash2(vec2(c, 5.0)) + time * 0.7)) * 60.0);
        col += tint.rgb * drip * 1.2 * k;
        col = mix(col, col * tint.rgb * 1.6, 0.35 * k);
    } else {
        // invert: a negative, posterised, jittering
        vec2 j = (vec2(hash(floor(time * 50.0)), hash(floor(time * 50.0) + 1.0)) - 0.5) * 0.012 * k;
        vec3 c = split(uv + j, 0.005 * k);
        vec3 neg = floor((1.0 - c) * 4.0 + 0.5) / 4.0;
        col = mix(c, neg * 0.7, step(0.25, k));          // dimmed: a flash, not a flashbang
    }

    // scanlines and vignette
    float sl = 0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159);
    col *= 1.0 - scanlines * 0.12 * sl;
    vec2 v = uv - 0.5;
    col *= 1.0 - dot(v, v) * 0.55;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
