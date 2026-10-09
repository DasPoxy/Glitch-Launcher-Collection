#version 440
// Globe-Launcher: a deep starfield, drawn per pixel at full resolution -
// three layers of stars (far, small and many; near, big and few), each
// twinkling and drifting slowly, over a faint tinted haze.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec4 tint;        // haze colour
    vec4 starColor;   // the brightest stars lean to this
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec3 layer(vec2 px, float cell, float density, float speed, float seed) {
    vec2 g = (px + vec2(time * speed, time * speed * 0.35)) / cell;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id + seed);
    if (h > density) return vec3(0.0);
    vec2 off = (vec2(hash(id + seed + 1.31), hash(id + seed + 7.17)) - 0.5) * 0.7;
    vec2 d = (f - off) * cell;                       // in pixels
    float size = mix(0.6, 1.9, pow(hash(id + seed + 3.3), 3.0));
    float tw = 0.55 + 0.45 * sin(time * (0.6 + hash(id + 9.1) * 2.6) + h * 40.0);
    float core = exp(-dot(d, d) / (size * size));
    // a soft cross on the brightest
    float flare = size > 1.5 ? (exp(-abs(d.x) * 0.9) * exp(-abs(d.y) * 0.08) + exp(-abs(d.y) * 0.9) * exp(-abs(d.x) * 0.08)) * 0.18 : 0.0;
    vec3 c = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.85), hash(id + 5.5));
    c = mix(c, starColor.rgb, 0.35 * hash(id + 2.2));
    return c * (core + flare) * tw;
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    vec3 col = layer(px, 9.0, 0.08, 1.5, 0.0) * 0.55
             + layer(px, 23.0, 0.10, 3.5, 17.0) * 0.85
             + layer(px, 61.0, 0.12, 7.0, 41.0) * 1.2;
    // haze: a slow, faint wash of the tint
    vec2 uv = qt_TexCoord0 - 0.5;
    float haze = 0.06 * (1.0 - length(uv) * 1.3) + 0.03 * sin(uv.x * 3.0 + time * 0.05) * sin(uv.y * 4.0 - time * 0.04);
    col += tint.rgb * max(haze, 0.0);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
