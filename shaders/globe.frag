#version 440
// Globe-Launcher: the globe, per pixel. For a pixel over the sphere, the
// point on its surface is turned back by the globe's rotation into latitude
// and longitude, and the style draws there:
//   0 dots    glowing dots on rings of latitude (fewer near the poles)
//   1 wire    lines along the rings and meridians
//   2 binary  a skin of flickering 0s and 1s, light rays round the rim
//   3 code    the continents built of matrix glyphs, debris drifting about
//   4 holo    dotted continents with lit coastlines, orbit rings round it
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

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    vec2 d = (px - center) / radius;
    d.y = -d.y;
    float r2 = dot(d, d);
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
