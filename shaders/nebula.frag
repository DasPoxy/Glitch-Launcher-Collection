#version 440
// Globe-Launcher: a nebula over the starfield, in layers that shift by
// different amounts as the globe turns and the mouse moves (parallax).
//   mode 0  far clouds: two layers of swirling, domain-warped gas in the
//           theme's colours (drawn at half resolution - it's all soft)
//   mode 1  near dust: dark lanes dimming the stars behind them, and motes
//           of dust drifting closest of all
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec2 shift;        // the parallax: how far the scene has turned, in screens
    vec4 tintA;        // the glow colour
    vec4 tintB;        // the theme colour
    vec4 dark;         // the background, for the dust
    float mode;
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p, int oct) {
    float v = 0.0, a = 0.5;
    mat2 r = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 6; i++) {
        if (i >= oct) break;
        v += a * noise(p);
        p = r * p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

// a layer of gas at a depth (how much it moves with the parallax)
vec4 cloud(vec2 uv, float depth, float scale, float seed) {
    vec2 p = uv * scale + shift * depth * scale + vec2(seed, seed * 0.7) + vec2(time * 0.004, time * 0.002) * scale;
    vec2 w = vec2(fbm(p + vec2(0.0, time * 0.01), 5), fbm(p + vec2(5.2, 1.3), 5));
    float n = fbm(p + 1.8 * w, 5);
    float dens = smoothstep(0.42, 0.85, n);
    float fil = smoothstep(0.02, 0.0, abs(n - 0.62)) * 0.5;       // bright filaments at the edges
    vec3 col = mix(tintA.rgb, tintB.rgb, smoothstep(0.3, 0.8, w.x)) * (0.6 + 0.9 * dens) + tintB.rgb * fil;
    float a = clamp(dens * 0.32 + fil * 0.35, 0.0, 0.5);
    return vec4(col, a);
}

void main() {
    vec2 uv = qt_TexCoord0 * vec2(resolution.x / resolution.y, 1.0);
    if (mode < 0.5) {
        vec4 far = cloud(uv, 0.25, 1.4, 3.0);
        vec4 mid = cloud(uv, 0.55, 2.3, 17.0);
        vec3 col = far.rgb * far.a;
        float a = far.a;
        col = col * (1.0 - mid.a) + mid.rgb * mid.a;
        a = a + mid.a * (1.0 - a);
        fragColor = vec4(col, a) * qt_Opacity;
    } else {
        // dust lanes, dark, near
        vec2 p = uv * 3.2 + shift * 0.9 * 3.2 + vec2(time * 0.006, 0.0);
        float lane = smoothstep(0.55, 0.78, fbm(p + fbm(p * 0.5 + 3.0, 3), 4));
        float a = lane * 0.55;
        vec3 col = dark.rgb * a;
        // motes: soft specks, nearest of all, catching the theme's light
        vec2 px = qt_TexCoord0 * resolution + shift * 1.3 * resolution.y + vec2(time * 6.0, time * 2.0);
        vec2 g = px / 26.0, id = floor(g);
        float h = hash(id);
        vec2 c = vec2(hash(id + 1.7), hash(id + 4.1));
        float d = length(fract(g) - c);
        float mote = step(0.93, h) * smoothstep(0.09, 0.0, d) * (0.5 + 0.5 * sin(time * (1.0 + 2.0 * h) + h * 40.0));
        vec3 mc = mix(tintB.rgb, vec3(1.0), 0.3) * mote * 0.55;
        col = col * (1.0 - mote * 0.55) + mc;
        a = a + mote * 0.55 * (1.0 - a);
        fragColor = vec4(col, a) * qt_Opacity;
    }
}
