#version 440
// Globe-Launcher: your network traffic, drawn. Downloads stream in from the
// edges to the globe as packets of light, uploads stream out of it; how many
// lanes run, and how fast, follows the throughput. Static crackles over the
// screen with it, and bits (0 / 1) flick past along the busiest lanes.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec2 center;      // the globe's centre, px
    float radius;     // the globe's radius, px
    float down;       // 0..1, download level
    float up;         // 0..1, upload level
    vec4 inColor;
    vec4 outColor;
    float glyphCount;
};
layout(binding = 1) uniform sampler2D glyphs;    // the globe's atlas: 0 and 1 first

const float PI = 3.14159265;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// one direction's lanes: dashes running along rays from the centre.
// dir -1 inbound, +1 outbound
float lanes(vec2 px, float level, float dir, float salt, out float bits) {
    bits = 0.0;
    if (level < 0.01) return 0.0;
    vec2 q = px - center;
    float r = length(q);
    float ang = atan(q.y, q.x) / (2.0 * PI) + 0.5;
    float n = 180.0;
    float lane = floor(ang * n);
    float within = abs(fract(ang * n) - 0.5) * (2.0 * PI * r / n);   // px from the lane's line
    // which lanes run changes every few seconds; more of them when busy
    float epoch = floor(time * 0.25 + hash(vec2(lane, salt)) * 4.0);
    float live = step(hash(vec2(lane, epoch + salt)), 0.08 + 0.55 * level);
    if (live < 0.5) return 0.0;
    float speed = (180.0 + 900.0 * level) * (0.7 + 0.6 * hash(vec2(lane, salt + 3.0)));
    float spacing = mix(420.0, 90.0, level) * (0.7 + 0.6 * hash(vec2(lane, salt + 5.0)));
    float s = (r + dir * -1.0 * time * speed) / spacing + hash(vec2(lane, salt + 9.0));
    float f = fract(s);
    float len = mix(0.05, 0.18, level);
    // inbound packets are led by their head toward the centre, outbound away
    float t = dir < 0.0 ? f : 1.0 - f;
    float dash = smoothstep(len, 0.0, t) * step(0.0, t);
    float head = smoothstep(0.02, 0.0, t);
    float line = smoothstep(1.6, 0.4, within);
    // fade near the globe and toward the edges
    float rn = r / radius;
    float fade = smoothstep(1.05, 1.35, rn) * (1.0 - smoothstep(0.75, 1.0, r / (0.5 * length(resolution))));
    // bits riding the busy lanes
    if (level > 0.35 && hash(vec2(lane, epoch + salt + 13.0)) < 0.25) {
        float cell = 16.0;
        float k = floor((r + dir * -1.0 * time * speed * 0.5) / cell);
        vec2 gf = vec2(within / 10.0 + 0.5, fract((r + dir * -1.0 * time * speed * 0.5) / cell));
        if (abs(gf.x - 0.5) < 0.5 && hash(vec2(k, lane + salt)) < 0.35) {
            float b = step(0.5, hash(vec2(k, lane)));
            bits = texture(glyphs, vec2((b + clamp(gf.x, 0.0, 1.0)) / glyphCount, 1.0 - gf.y)).r * fade * 0.6;
        }
    }
    return (dash * 0.55 + head * 1.2) * line * fade;
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    float bi, bo;
    float i = lanes(px, down, -1.0, 0.0, bi);
    float o = lanes(px, up, 1.0, 50.0, bo);
    vec3 col = inColor.rgb * (i + bi) + outColor.rgb * (o + bo);
    float a = clamp(i + o + bi + bo, 0.0, 1.0);
    // static: specks crackling across the screen, more with more traffic
    float level = max(down, up);
    vec2 cell = floor(px / 3.0);
    float sp = step(1.0 - 0.0025 * level, hash(cell + floor(time * 24.0)));
    // and now and then a faint interference line
    float row = floor(px.y / 2.0);
    float il = step(1.0 - 0.004 * level, hash(vec2(row, floor(time * 12.0)))) * 0.25;
    col += mix(inColor.rgb, vec3(1.0), 0.4) * (sp * 0.8 + il);
    a = max(a, max(sp * 0.8, il));
    fragColor = vec4(col * a, a) * qt_Opacity;
}
