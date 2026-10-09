#version 440
// Globe-Launcher, after <namek: the debris field. Three depths of fragments
// (tumbling shards of hull, specks of dust, embers in the blast's colour)
// drifting outward and slowly on, each layer at its own speed; they appear
// as the blast front passes them. For the first moments, sparks streak out
// from where the globe was.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec2 center;      // where the globe was, px
    float age;        // seconds since it blew
    vec4 metal;       // hull shards
    vec4 ember;       // the blast's colour
    vec4 glow;        // the theme's
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// one layer: a grid of cells, some holding a fragment, the grid drifting
// outward from the blast (and on with time)
vec4 layer(vec2 px, float cell, float speed, float salt, float front) {
    vec2 rel = px - center;
    float r = length(rel);
    // drift: pushed out from the centre, easing, then a slow sideways float
    float push = (1.0 - exp(-age * 1.2)) * speed * 2.5 + age * speed * 0.12;
    vec2 q = rel - normalize(rel + 1e-4) * push * (r / (r + 200.0)) + vec2(time * speed * 0.05, time * speed * 0.02);
    vec2 g = q / cell, id = floor(g), f = fract(g) - 0.5;
    float h = hash(id + salt);
    if (h > 0.42) return vec4(0.0);
    vec2 off = (vec2(hash(id + salt + 1.1), hash(id + salt + 2.3)) - 0.5) * 0.6;
    float kind = hash(id + salt + 3.7);                // shard / dust / ember
    float sz = kind < 0.45 ? mix(0.07, 0.17, hash(id + 5.0)) : kind < 0.8 ? 0.035 : 0.05;
    float ang = time * (hash(id + 6.1) - 0.5) * 2.0 + h * 40.0;
    vec2 p = mat2(cos(ang), sin(ang), -sin(ang), cos(ang)) * (f - off);
    // a shard is a thin irregular sliver; dust and embers are round
    float shape;
    if (kind < 0.45) {
        vec2 b = abs(p) - vec2(sz, sz * mix(0.25, 0.6, hash(id + 7.3)));
        shape = 1.0 - smoothstep(0.0, 0.02, max(b.x, b.y + p.x * 0.4));
    } else {
        shape = smoothstep(sz, sz * 0.3, length(p));
    }
    if (shape <= 0.0) return vec4(0.0);
    // only once the blast front has passed it
    float shown = smoothstep(0.0, 80.0, front - r);
    vec3 col;
    float a;
    if (kind < 0.45) {
        float lit = 0.5 + 0.5 * sin(ang * 3.0 + time * 1.5);          // catching the light as it turns
        col = metal.rgb * (0.5 + 0.9 * lit) + glow.rgb * 0.08;
        a = shape * 0.9;
    } else if (kind < 0.8) {
        col = mix(metal.rgb, vec3(0.8), 0.4) * 0.7;
        a = shape * 0.45;
    } else {
        float flick = 0.6 + 0.4 * sin(time * (3.0 + 4.0 * h) + h * 50.0);
        col = ember.rgb * (1.2 + 0.6 * flick) * mix(1.0, 0.5, smoothstep(2.0, 12.0, age));   // cooling
        a = shape * flick;
    }
    return vec4(col, a * shown);
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    float front = age * 1400.0;                        // the blast front, px
    vec4 far = layer(px, 26.0, 40.0, 0.0, front);
    vec4 mid = layer(px, 48.0, 90.0, 17.0, front);
    vec4 near = layer(px, 90.0, 170.0, 41.0, front);
    vec3 col = far.rgb * far.a * 0.6;
    float a = far.a * 0.6;
    col = col * (1.0 - mid.a) + mid.rgb * mid.a;
    a = a + mid.a * (1.0 - a);
    col = col * (1.0 - near.a) + near.rgb * near.a;
    a = a + near.a * (1.0 - a);

    // sparks streaking out, the first couple of seconds
    if (age < 2.5) {
        vec2 rel = px - center;
        float r = length(rel);
        float ang = atan(rel.y, rel.x);
        float lane = floor(ang * 60.0);
        float speed = 600.0 + 900.0 * hash(vec2(lane, 9.0));
        float head = age * speed * (0.8 + 0.4 * hash(vec2(lane, 4.0)));
        float on = step(0.55, hash(vec2(lane, 2.0)));
        float within = abs(fract(ang * 60.0) - 0.5) / 60.0 * r;
        float tail = smoothstep(head - 140.0, head, r) * step(r, head);
        float spark = on * tail * smoothstep(2.0, 0.3, within) * (1.0 - age / 2.5);
        col += mix(ember.rgb, vec3(1.0), 0.5) * spark;
        a = max(a, spark);
    }
    fragColor = vec4(col, clamp(a, 0.0, 1.0)) * qt_Opacity;
}
