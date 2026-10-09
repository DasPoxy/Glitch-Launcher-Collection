#version 440
// Globe-Launcher: the globe, per pixel. For a pixel over the sphere, the
// point on its surface is turned back by the globe's rotation into latitude
// and longitude, and the style draws there:
//   0 dots    glowing dots on rings of latitude (fewer near the poles)
//   1 wire    lines along the rings and meridians
//   2 binary  a skin of flickering 0s and 1s, light rays round the rim
//   3 code    the continents built of matrix glyphs, debris drifting about
//   4 holo    dotted continents with lit coastlines, orbit rings round it
//   5 unicron the planet-eater: armour, vents, a mouth firing a beam, a ring
//   6 dyson   a lattice shell round a star, light escaping through the gaps
// The far side shows faintly through, the rim glows, and a halo sits round
// the outside.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec2 center;      // pixels
    float radius;     // pixels
    mat4 rotation;    // the globe's rotation (model -> view)
    vec4 dotColor;
    vec4 glowColor;
    float rings;      // rings of latitude
    float style;
    float pulse;      // 0..1, brightens briefly (selection change)
    float glyphCount; // glyphs in the atlas; the first two are 0 and 1
};
layout(binding = 1) uniform sampler2D land;     // equirectangular, white = land
layout(binding = 2) uniform sampler2D glyphs;   // white glyphs on black, in a row

const float PI = 3.14159265;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// the map at a latitude / longitude (east to the right as you face it)
float landAt(float lat, float lon) {
    return texture(land, vec2(fract(0.5 - lon / (2.0 * PI)), clamp(0.5 - lat / PI, 0.001, 0.999))).r;
}

// glyph k of the atlas at f (0..1 in the cell, y up)
float glyph(float k, vec2 f) {
    f = clamp(f, vec2(0.06, 0.04), vec2(0.94, 0.96));
    return texture(glyphs, vec2((k + f.x) / glyphCount, 1.0 - f.y)).r;
}

// a grid of glyph cells over the sphere: row by latitude, columns spaced for
// a glyph's shape. Gives the cell's id, where we are in it, and its centre.
void cells(float lat, float lon, float n, out vec2 id, out vec2 f, out vec2 c) {
    float stepLat = PI / n;
    float row = floor(lat / stepLat);
    float rowLat = (row + 0.5) * stepLat;
    float count = max(3.0, floor(3.1 * n * cos(rowLat)));       // glyphs ~0.62 as wide as tall
    float stepLon = 2.0 * PI / count;
    float col = floor((lon + PI) / stepLon);
    id = vec2(col, row);
    f = vec2(fract((lon + PI) / stepLon), fract(lat / stepLat));
    c = vec2(rowLat, (col + 0.5) * stepLon - PI);
}

// how lit the surface point n (view space, unit) is
float pattern(vec3 n, bool front) {
    vec3 m = transpose(mat3(rotation)) * n;          // back to the globe's own frame
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);

    if (style > 1.5 && style < 2.5) {
        // binary: every cell a 0 or a 1, flipping now and then, some bright
        vec2 id, f, c;
        cells(lat, lon, rings * 1.6, id, f, c);
        float k = step(0.5, hash(id + floor(time * (0.15 + 0.6 * hash(id.yx)))));
        float lit = 0.35 + 0.65 * step(0.55, hash(id * 1.7 + floor(time * 0.7)));
        return glyph(k, f) * lit * 1.2;
    }
    if (style > 2.5 && style < 3.5) {
        // code earth: glyph cells where there's land, the sea all but empty
        vec2 id, f, c;
        cells(lat, lon, rings * 1.9, id, f, c);
        float l = step(0.4, landAt(c.x, c.y));
        float k = 2.0 + floor(hash(id + floor(time * (0.2 + 1.5 * hash(id.yx)))) * (glyphCount - 2.0));
        float flare = step(0.985, hash(id + floor(time * 3.0)));
        float g = glyph(k, f);
        // each land cell a lit block with its glyph bright inside it
        float box = smoothstep(0.5, 0.4, max(abs(f.x - 0.5), abs(f.y - 0.5)));
        float lit = 0.6 + 0.4 * hash(id) + flare;
        return l * (g * lit * 1.1 + box * 0.28 * lit) + (1.0 - l) * g * 0.06 * step(0.8, hash(id + 4.2));
    }
    if (style > 3.5) {
        // holo earth: a fine lattice of dots on land, the coastlines lit, a
        // faint graticule every 15 degrees
        float l = landAt(lat, lon);
        float e = 0.012;
        float edge = abs(landAt(lat + e, lon) - landAt(lat - e, lon)) + abs(landAt(lat, lon + e / max(cos(lat), 0.2)) - landAt(lat, lon - e / max(cos(lat), 0.2)));
        float fine = PI / (rings * 3.0);
        vec2 g = vec2(lat, lon * cos(lat)) / fine;
        float dotv = smoothstep(0.32, 0.12, length(fract(g) - 0.5));
        float grat = PI / 12.0;
        float dl = abs(fract(lat / grat + 0.5) - 0.5) * grat;
        float dn = abs(fract(lon / grat + 0.5) - 0.5) * grat * cos(lat);
        float lines = max(smoothstep(0.004, 0.0, dl), smoothstep(0.004, 0.0, dn));
        return dotv * l * 0.85 + min(edge, 1.0) * (front ? 1.3 : 0.6) + lines * 0.22 + l * 0.08;
    }

    float step = PI / rings;
    float ringLat = clamp(floor(lat / step + 0.5) * step, -PI / 2.0 + step * 0.5, PI / 2.0 - step * 0.5);
    if (style > 0.5) {
        float dLat = abs(lat - ringLat);
        float lonStep = 2.0 * PI / (rings * 2.0);
        float dLon = abs(fract(lon / lonStep + 0.5) - 0.5) * lonStep * cos(lat);
        float w = 0.010;
        return max(smoothstep(w, 0.0, dLat), smoothstep(w, 0.0, dLon) * smoothstep(0.0, 0.35, cos(lat)));
    }
    float count = max(1.0, floor(2.0 * rings * cos(ringLat) + 0.5));   // dots on this ring
    float lonStep = 2.0 * PI / count;
    float lonC = floor(lon / lonStep + 0.5) * lonStep;
    vec2 d = vec2(lat - ringLat, (lon - lonC) * cos(lat));
    float dist = length(d);
    float r = step * 0.20;
    return smoothstep(r, r * 0.25, dist) + 0.35 * exp(-dist / (r * 1.4));   // dot + its glow
}

// an orbit ring (holo): a circle of radius R tilted to normal nrm, seen
// straight on. Returns its brightness at d, hidden behind the globe.
float orbit(vec2 d, vec3 nrm, float R, float speed, float r2) {
    nrm = normalize(nrm);
    vec3 u = normalize(cross(nrm, abs(nrm.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 v = cross(nrm, u);
    mat2 M = mat2(u.xy * R, v.xy * R);                // circle -> screen ellipse
    float det = determinant(M);
    if (abs(det) < 1e-4) return 0.0;
    mat2 Mi = inverse(M);
    vec2 w = Mi * d;
    float lw = length(w);
    vec2 grad = transpose(Mi) * (w / max(lw, 1e-4));
    float dist = abs(lw - 1.0) / max(length(grad), 1e-4);  // in radii
    float line = smoothstep(0.006, 0.0, dist) + 0.25 * exp(-dist * 90.0);
    float th = atan(w.y, w.x);
    vec3 p = R * (cos(th) * u + sin(th) * v);
    if (p.z < 0.0 && r2 < 1.0) line *= 0.12;           // behind the globe
    // a satellite riding it
    float sat = exp(-pow(abs(mod(th - time * speed + PI, 2.0 * PI) - PI), 2.0) * 900.0) * smoothstep(0.03, 0.0, dist);
    return line * 0.55 + sat * 1.6;
}

// ------------------------------------------------------------------ unicron
// the planet-eater: an armoured sphere of plates with seams and circuitry,
// a cratered cap, vents glowing in the theme colour. The face (a mouth
// with mandibles, firing a beam), the ring of lights round it, its spokes
// and the antennae stay put while the body turns behind them.
vec3 unicronBody(vec3 n, out float glowAmt) {
    vec3 m = transpose(mat3(rotation)) * n;
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);
    vec2 id, f, c;
    cells(lat, lon, rings * 0.5, id, f, c);
    float seam = 1.0 - smoothstep(0.0, 0.06, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
    vec3 L = normalize(vec3(-0.5, 0.55, 0.65));
    float diff = 0.25 + 0.75 * max(dot(n, L), 0.0);
    vec3 metal = mix(vec3(0.10, 0.11, 0.16), vec3(0.20, 0.21, 0.28), hash(id)) ;
    // the cratered cap over the north
    float cap = smoothstep(0.0, 0.04, m.y - (0.42 + 0.12 * sin(lon * 3.0 + 1.0) + 0.05 * sin(lon * 11.0)));
    vec2 cf = fract(vec2(lon * 3.0, lat * 6.0)) - 0.5;
    float crater = smoothstep(0.22, 0.16, length(cf)) * step(0.55, hash(floor(vec2(lon * 3.0, lat * 6.0))));
    vec3 capCol = mix(vec3(0.42, 0.44, 0.50), vec3(0.28, 0.29, 0.34), crater);
    vec3 col = mix(metal, capCol, cap) * diff;
    col *= 1.0 - seam * 0.6;
    // circuitry: thin lit traces across some plates
    float trace = step(0.6, hash(id + 2.0)) * (1.0 - smoothstep(0.0, 0.03, abs(fract(f.y * 3.0 + hash(id) ) - 0.5) - 0.0)) * step(0.15, f.x) * step(f.x, 0.85);
    // vents: round, glowing
    float vent = step(0.9, hash(id + 7.7)) * (1.0 - cap);
    float vd = length(f - 0.5);
    float v = vent * smoothstep(0.3, 0.2, vd);
    glowAmt = v + trace * 0.35 * (1.0 - cap) + seam * 0.12 * (1.0 - cap);
    col = mix(col, vec3(0.0), vent * smoothstep(0.36, 0.3, vd) * (1.0 - v));
    return col;
}

vec4 unicron(vec2 d, float r2) {
    float rr = sqrt(r2);
    vec3 hot = mix(dotColor.rgb, vec3(1.0), 0.35);
    vec3 col = vec3(0.0);
    float a = 0.0;
    vec2 M = vec2(0.40, -0.26);                       // the mouth
    vec2 D = normalize(vec2(0.86, -0.5));             // where it fires
    if (r2 < 1.0) {
        float z = sqrt(1.0 - r2);
        float g;
        col = unicronBody(vec3(d, z), g);
        col += dotColor.rgb * g * (0.8 + 0.2 * sin(time * 3.0));
        col += glowColor.rgb * pow(1.0 - z, 2.5) * 0.6;          // rim
        a = 1.0;
        // the mouth: a dark socket, a molten core
        float md = length(d - M);
        col = mix(col, vec3(0.02), smoothstep(0.24, 0.2, md));
        col += hot * smoothstep(0.15, 0.0, md) * 1.6 + dotColor.rgb * exp(-md * 14.0) * 0.8;
    }
    // mandibles: two arcs hooked round the mouth
    {
        vec2 q = d - M;
        float ang = atan(q.y, q.x);
        float ring = abs(length(q) - 0.27);
        float upper = step(0.2, ang) * step(ang, 1.7);
        float lower = step(-2.3, ang) * step(ang, -0.6);
        float arc = smoothstep(0.035, 0.015, ring) * max(upper, lower);
        col = mix(col, mix(vec3(0.12, 0.12, 0.16), dotColor.rgb * 0.6, 0.4), arc);
        col += dotColor.rgb * smoothstep(0.012, 0.0, abs(ring - 0.03)) * max(upper, lower) * 0.8;
        a = max(a, arc);
    }
    // the ring of lights, its spokes, the antennae
    float Rr = 1.34;
    float ringLine = smoothstep(0.012, 0.004, abs(rr - Rr));
    float th = atan(d.y, d.x) + time * 0.04;
    float beads = 48.0;
    float bd = abs(fract(th / (2.0 * PI) * beads) - 0.5) * (2.0 * PI / beads) * Rr;
    float bead = exp(-(pow(bd, 2.0) + pow(rr - Rr, 2.0)) * 9000.0) * (0.6 + 0.4 * sin(time * 4.0 + floor(th / (2.0 * PI) * beads)));
    float spoke = smoothstep(0.012, 0.004, abs(d.x)) * step(1.0, abs(d.y)) * step(abs(d.y), Rr);
    float sideAng = atan(d.y, abs(d.x));                       // both sides alike
    float sb = floor(sideAng * 14.0);
    float spikeLen = 1.0 + 0.08 + 0.16 * hash(vec2(sb, sign(d.x)));
    float spike = step(abs(sideAng), 0.55) * step(1.0, rr) * step(rr, spikeLen)
                * smoothstep(0.006, 0.0, abs(fract(sideAng * 14.0) - 0.5) / 14.0 * rr);
    vec3 frameCol = mix(vec3(0.35, 0.3, 0.3), dotColor.rgb, 0.6);
    col += frameCol * (ringLine * 0.8 + spoke * 0.9 + spike * 0.8) + hot * bead * 1.5;
    a = max(a, max(max(ringLine, spoke), max(spike, bead)));
    // the beam, widening, with streaks running out along it
    vec2 q = d - M;
    float along = dot(q, D);
    float perp = abs(q.x * D.y - q.y * D.x);
    float w = 0.07 + along * 0.24;
    float beam = step(0.08, along) * smoothstep(w, w * 0.2, perp) * exp(-along * 0.45);
    float streak = hash(vec2(floor(perp / w * 9.0), 0.0));
    float run = fract(along * 1.5 - time * (1.0 + streak) + streak);
    beam *= 0.6 + 0.4 * smoothstep(0.7, 1.0, run) * step(0.5, streak);
    beam *= 0.85 + 0.15 * sin(time * 7.0);
    col += mix(hot, dotColor.rgb, smoothstep(0.0, 1.5, along)) * beam * 1.1;
    a = max(a, beam * 0.9);
    // a soft halo
    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.4;
    a = max(a, halo * 0.4);
    return vec4(col, a);
}

// -------------------------------------------------------------- dyson sphere
// a lattice shell of triangles round a star: some panels, some open, the
// star blazing out through the gaps and lighting the far side from within
void dysonShell(vec3 n, out float frame, out float panel, out float lines) {
    vec3 m = transpose(mat3(rotation)) * n;
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);
    vec2 id, f, c;
    float rowsN = rings * 0.42;
    cells(lat, lon, rowsN, id, f, c);
    float H = PI / rowsN;
    float W = H / 0.62 * cos(c.x) / max(cos(c.x), 0.25);      // ~ the cell's width
    float dx = f.x * W, dy = f.y * H;
    float flip = mod(id.x + id.y, 2.0);
    float diag = flip < 0.5 ? abs(dy * W - dx * H) : abs(dx * H + dy * W - W * H);
    diag /= sqrt(W * W + H * H);
    float side = flip < 0.5 ? step(dx * H, dy * W) : step(W * H, dx * H + dy * W);
    float e = min(min(min(dx, W - dx), min(dy, H - dy)), diag);
    frame = smoothstep(0.008, 0.002, e);
    float tri = hash(id * 2.0 + side + 0.5);
    panel = step(0.5, tri) * smoothstep(0.002, 0.008, e);
    lines = panel * smoothstep(0.35, 0.5, abs(fract(dx / W * 6.0) - 0.5)) * step(0.75, tri);
}

vec4 dyson(vec2 d, float r2) {
    float rr = sqrt(r2);
    vec3 starCol = mix(vec3(1.0, 0.9, 0.75), dotColor.rgb, 0.25);
    float flicker = 0.92 + 0.08 * sin(time * 2.3) * sin(time * 3.7);
    float star = (exp(-rr * 3.0) * 0.9 + exp(-rr * 14.0) * 2.5 + smoothstep(0.2, 0.16, rr) * 2.0) * flicker;
    vec3 col = vec3(0.0);
    float a = 0.0;
    if (r2 < 1.0) {
        float z = sqrt(1.0 - r2);
        float fb, pb, lb, ff, pf, lf;
        dysonShell(vec3(d, -z), fb, pb, lb);
        dysonShell(vec3(d, z), ff, pf, lf);
        // the far side, lit from inside
        col = glowColor.rgb * 0.06 + mix(glowColor.rgb, starCol, 0.35) * pb * 0.35 + dotColor.rgb * (fb * 0.5 + lb * 0.25);
        a = 0.25 + pb * 0.4 + fb * 0.5;
        // the star, inside
        col += starCol * star;
        a = max(a, min(star, 1.0));
        // the near side: panels block the star, their edges catch its light
        vec3 panelCol = vec3(0.02, 0.03, 0.04) + glowColor.rgb * 0.08 + dotColor.rgb * lf * 0.3;
        col = mix(col, panelCol, pf);
        col += dotColor.rgb * ff * (0.7 + star * 0.8);
        col += glowColor.rgb * pow(1.0 - z, 2.4) * 0.5;
        a = max(a, max(pf, ff));
    } else {
        col = starCol * star * 0.6;
        a = min(star * 0.6, 1.0);
    }
    // rays escaping past the rim, and two long orbits
    float ang = atan(d.y, d.x);
    float s = ang * 40.0;
    float ray = mix(hash(vec2(floor(s), 2.0)), hash(vec2(floor(s) + 1.0, 2.0)), smoothstep(0.0, 1.0, fract(s)));
    ray = pow(ray, 9.0) * exp(-max(rr - 1.0, 0.0) * 2.5) * step(1.0, rr);
    float o = orbit(d, vec3(0.15, 1.0, 0.25), 1.55, 0.2, r2) + orbit(d, vec3(-0.5, 0.8, -0.3), 1.35, -0.3, r2);
    col += starCol * ray * 0.5 + mix(glowColor.rgb, dotColor.rgb, 0.5) * o * 0.8;
    a = max(a, max(ray * 0.5, min(o, 1.0)));
    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.45;
    a = max(a, halo * 0.45);
    return vec4(col, clamp(a, 0.0, 1.0));
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    vec2 d = (px - center) / radius;
    d.y = -d.y;
    float r2 = dot(d, d);
    if (style > 4.5) {
        vec4 o = style < 5.5 ? unicron(d, r2) : dyson(d, r2);
        fragColor = vec4(o.rgb, o.a) * qt_Opacity;
        return;
    }
    vec3 col = vec3(0.0);
    float a = 0.0;
    if (r2 < 1.0) {
        float z = sqrt(1.0 - r2);
        float front = pattern(vec3(d, z), true);
        float back = pattern(vec3(d, -z), false);
        float rim = pow(1.0 - z, 2.2);
        float light = 0.45 + 0.55 * z;                               // brighter facing you
        float backLevel = style > 3.5 ? 0.3 : style > 1.5 ? 0.1 : 0.16;
        col = dotColor.rgb * front * light * (1.0 + 0.6 * pulse)
            + dotColor.rgb * back * backLevel
            + glowColor.rgb * rim * 0.55;
        a = clamp(front * 0.9 + back * backLevel * 1.2 + rim * 0.5 + 0.06, 0.0, 1.0);
        float body = style > 3.5 ? 0.16 : style > 1.5 && style < 2.5 ? 0.12 : 0.05;
        col += glowColor.rgb * body;                                 // a faint body
        a = max(a, body * 1.5);
        if (style > 1.5) {
            // a soft highlight, upper left
            float spec = pow(max(dot(vec3(d, z), normalize(vec3(-0.45, 0.5, 0.75))), 0.0), 14.0);
            col += mix(dotColor.rgb, vec3(1.0), 0.5) * spec * 0.25;
        }
    }
    float rr = sqrt(r2);
    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.55;
    a = max(a, halo * 0.55);

    if (style > 1.5 && style < 2.5 && rr > 0.97) {
        // binary: light rays fanning out from the rim
        float ang = atan(d.y, d.x);
        float s = ang * 70.0 + time * 0.08;
        float ray = mix(hash(vec2(floor(s), 1.0)), hash(vec2(floor(s) + 1.0, 1.0)), smoothstep(0.0, 1.0, fract(s)));
        ray = pow(ray, 7.0) * exp(-(rr - 1.0) * 3.2) * smoothstep(0.97, 1.02, rr);
        col += mix(glowColor.rgb, dotColor.rgb, 0.5) * ray * 0.9;
        a = max(a, ray * 0.8);
    }
    if (style > 2.5 && style < 3.5 && rr > 1.02) {
        // code earth: stray glyphs drifting in the dark around it
        vec2 cs = vec2(14.0, 22.0);
        vec2 g = (px + vec2(0.0, time * 12.0)) / cs;
        vec2 id = floor(g);
        float on = step(0.982, hash(id + floor(time * 0.4 + hash(id.yx) * 7.0)));
        float k = 2.0 + floor(hash(id * 3.1) * (glyphCount - 2.0));
        float v = glyph(k, vec2(fract(g.x), 1.0 - fract(g.y))) * on * (0.25 + 0.35 * hash(id + 1.3));
        col += dotColor.rgb * v;
        a = max(a, v);
    }
    if (style > 3.5) {
        // holo earth: three orbits, slowly precessing
        float t = time * 0.05;
        float o = orbit(d, vec3(0.25 + 0.1 * sin(t), 1.0, 0.35), 1.28, 0.35, r2)
                + orbit(d, vec3(-0.7, 0.55, 0.3 + 0.1 * cos(t * 1.3)), 1.42, -0.25, r2)
                + orbit(d, vec3(0.9, -0.2 + 0.1 * sin(t * 0.8), 0.45), 1.16, 0.5, r2);
        col += mix(glowColor.rgb, dotColor.rgb, 0.6) * o;
        a = max(a, min(o, 1.0));
    }
    fragColor = vec4(col, a) * qt_Opacity;
}
