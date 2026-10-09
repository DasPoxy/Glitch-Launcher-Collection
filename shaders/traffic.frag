#version 440
// Globe-Launcher: your network traffic, drawn. Downloads stream in from the
// edges to the globe as packets of light, uploads stream out of it; how many
// lanes run, and how fast, follows the throughput. Static crackles over the
// screen with it, and bits (0 / 1) flick past along the busiest lanes.
// mode 1, orbits: the traffic as orbital rings round the globe instead -
// more rings the busier it is (downloads in one colour, uploads the other),
// packets riding them, faster with the rate, hidden behind the globe.
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
    float mode;       // 0 streams, 1 orbits
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

vec3 hash3(float n) { return fract(sin(vec3(n, n + 1.3, n + 2.7) * vec3(127.1, 311.7, 74.7)) * 43758.5453); }

// ring k of one direction: a tilted circle round the globe with packets
// running along it. Returns brightness at d (in globe radii).
float ring(vec2 d, float r2, float k, float level, float dir, float salt) {
    vec3 h = hash3(k * 7.0 + salt);
    vec3 nrm = normalize(vec3(h.x - 0.5, 1.0 + h.y, h.z - 0.5) * vec3(1.6, 1.0, 1.6));
    float R = 1.14 + 0.1 * k + 0.05 * h.z;
    vec3 u = normalize(cross(nrm, abs(nrm.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 v = cross(nrm, u);
    mat2 M = mat2(u.xy * R, v.xy * R);
    if (abs(determinant(M)) < 1e-4) return 0.0;
    mat2 Mi = inverse(M);
    vec2 w = Mi * d;
    float lw = length(w);
    vec2 grad = transpose(Mi) * (w / max(lw, 1e-4));
    float dist = abs(lw - 1.0) / max(length(grad), 1e-4);
    float th = atan(w.y, w.x);
    vec3 p = R * (cos(th) * u + sin(th) * v);
    float hidden = (p.z < 0.0 && r2 < 1.0) ? 0.1 : 1.0;
    float line = smoothstep(0.006, 0.0, dist) * 0.5 + exp(-dist * 80.0) * 0.25;
    // packets: dashes running round it, more and faster with the rate
    float count = floor(4.0 + level * 22.0);
    float speed = (0.15 + level * 0.9) * dir * (0.8 + 0.4 * h.x);
    float f = fract(th / (2.0 * PI) * count - time * speed * count * 0.15 + h.y);
    float dash = smoothstep(0.35, 0.0, f) * smoothstep(0.011, 0.0, dist);
    float head = smoothstep(0.06, 0.0, f) * smoothstep(0.016, 0.0, dist);
    return (line + dash * 1.1 + head * 1.6) * hidden;
}

float orbits(vec2 d, float r2, float level, float dir, float salt) {
    if (level < 0.01) return 0.0;
    float n = 1.0 + floor(level * 3.99);               // 1..4 rings
    float v = 0.0;
    for (int k = 0; k < 4; k++) {
        float kk = float(k);
        if (kk >= n) break;
        float fade = clamp(level * 4.0 - kk, 0.0, 1.0);
        v += ring(d, r2, kk * 2.0 + (dir > 0.0 ? 1.0 : 0.0), level, dir, salt) * fade;
    }
    return v;
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    float i, o, bi = 0.0, bo = 0.0;
    if (mode > 0.5) {
        vec2 d = (px - center) / radius;
        d.y = -d.y;
        float r2 = dot(d, d);
        i = orbits(d, r2, down, 1.0, 0.0);
        o = orbits(d, r2, up, -1.0, 40.0);
    } else {
        i = lanes(px, down, -1.0, 0.0, bi);
        o = lanes(px, up, 1.0, 50.0, bo);
    }
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
