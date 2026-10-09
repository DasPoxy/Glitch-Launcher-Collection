#version 440
// Globe-Launcher: the file preview's look, over a picture / video / PDF page.
//   0 clean  as it is
//   1 grid   duotone in the theme, its bright areas traced by glowing blocks
//   2 glyph  redrawn as a mosaic of characters, brighter where it's bright
//   3 rain   the glyph mosaic with code falling down through it
// All of them materialise (reveal 0 -> 1) block by block.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;   // this item's size, px
    float look;
    float reveal;
    float glyphCount;  // glyphs side by side in the atlas
    vec4 primary;
    vec4 glow;
    vec4 bg;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D glyphs;    // white glyphs on black, in a row

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// duotone: the background in the dark, the glow, then the theme colour, then white
vec3 tone(float l) {
    vec3 c = mix(bg.rgb, glow.rgb, smoothstep(0.02, 0.4, l));
    c = mix(c, primary.rgb, smoothstep(0.3, 0.75, l));
    return mix(c, vec3(1.0), smoothstep(0.78, 1.0, l) * 0.55);
}

// a cell's brightness: four samples inside it
float cellLuma(vec2 cell, vec2 n) {
    vec2 s = 1.0 / n, o = cell * s;
    vec4 a = texture(source, o + s * vec2(0.25, 0.25));
    vec4 b = texture(source, o + s * vec2(0.75, 0.25));
    vec4 c = texture(source, o + s * vec2(0.25, 0.75));
    vec4 d = texture(source, o + s * vec2(0.75, 0.75));
    return 0.25 * (luma(a.rgb) * a.a + luma(b.rgb) * b.a + luma(c.rgb) * c.a + luma(d.rgb) * d.a);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 src = texture(source, uv);
    vec3 col;
    float alpha = src.a;

    if (look < 0.5) {
        col = src.a > 0.0 ? src.rgb / src.a : src.rgb;
    } else if (look < 1.5) {
        // grid: duotone, with lit blocks outlined where it's bright
        col = tone(pow(luma(src.rgb), 1.15));
        float px = max(resolution.x, resolution.y) / 30.0;
        vec2 n = resolution / px;
        vec2 g = uv * n, cell = floor(g), f = fract(g);
        float cl = cellLuma(cell, n);
        float lit = step(0.5 + 0.06 * sin(time * 0.8 + hash(cell) * 6.283), cl);
        float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * px;
        float line = 1.0 - smoothstep(0.5, 1.6, d);
        float halo = 1.0 - smoothstep(0.0, 7.0, d);
        float flick = step(0.97, hash(cell + floor(time * 4.0)));
        col += lit * (vec3(0.85) * line + primary.rgb * (0.3 * halo + 0.07 + 0.25 * flick));
        // a fine sub-grid inside the lit blocks
        vec2 sf = fract(g * 2.0);
        float sub = 1.0 - smoothstep(0.3, 1.0, min(min(sf.x, 1.0 - sf.x), min(sf.y, 1.0 - sf.y)) * px * 0.5);
        col += lit * primary.rgb * sub * 0.12;
    } else {
        // glyphs: one character per cell, chosen at random and changing now
        // and then; how bright it is comes from the picture
        vec2 n = floor(resolution / vec2(10.0, 16.0));
        vec2 g = uv * n, cell = floor(g), f = fract(g);
        float cl = cellLuma(cell, n);
        float rate = 0.3 + 2.5 * hash(cell.yx + 3.7);
        float idx = floor(hash(cell + floor(time * rate)) * glyphCount);
        float gm = texture(glyphs, vec2((idx + clamp(f.x, 0.04, 0.96)) / glyphCount, f.y)).r;
        float b = smoothstep(0.03, 0.7, cl);      // a little extra contrast
        if (look > 2.5) {
            // rain: each column has a falling head with a fading trail
            float speed = 0.12 + 0.3 * hash(vec2(cell.x, 1.3));
            float head = fract(time * speed + hash(vec2(cell.x, 9.1)));
            float t = fract(head - cell.y / n.y);            // how far above the head
            float trail = pow(1.0 - smoothstep(0.0, 0.4, t), 2.0);
            float tip = 1.0 - step(1.5 / n.y, t);
            b = max(b * 0.9, trail * 0.5) + tip * 0.6;
            alpha = max(alpha, step(0.001, trail) * 0.85);
        }
        col = tone(b) * gm * 1.8 + tone(cl) * 0.2;
    }

    // materialise: blocks switch on at random, flickering until they do
    if (reveal < 1.0) {
        vec2 rc = floor(uv * resolution / 18.0);
        float on = step(hash(rc + 5.3), reveal * 1.2 - 0.1);
        vec3 noise = primary.rgb * 0.45 * step(0.6, hash(rc + floor(time * 24.0)));
        col = mix(noise, col, on);
        alpha = mix(alpha * 0.6, alpha, on);
    }
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
