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
//   7 rain    matrix code falling down the sphere in columns, heads bright
//   8 hex     bestagons: bevelled iridescent tiles, some popping out, some
//             drifting loose off the edge
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

int sid() { return int(style + 0.5); }

// how lit the surface point n (view space, unit) is
float pattern(vec3 n, bool front) {
    vec3 m = transpose(mat3(rotation)) * n;          // back to the globe's own frame
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);

    if (sid() == 2) {
        // binary: every cell a 0 or a 1, flipping now and then, some bright
        vec2 id, f, c;
        cells(lat, lon, rings * 1.6, id, f, c);
        float k = step(0.5, hash(id + floor(time * (0.15 + 0.6 * hash(id.yx)))));
        float lit = 0.35 + 0.65 * step(0.55, hash(id * 1.7 + floor(time * 0.7)));
        return glyph(k, f) * lit * 1.2;
    }
    if (sid() == 3) {
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
    if (sid() == 7) {
        // matrix rain: each column of glyphs has drops falling from the
        // north, a bright head churning through glyphs and a fading trail
        vec2 id, f, c;
        float rowsN = rings * 1.7;
        cells(lat, lon, rowsN, id, f, c);
        float y = rowsN * 0.5 - id.y;                         // rows down from the top
        float b = 0.0, headness = 0.0;
        for (int k = 0; k < 3; k++) {
            float kk = float(k);
            float speed = 4.0 + 9.0 * hash(vec2(id.x, 3.0 + kk));
            float span = rowsN * 1.3;
            float head = mod(time * speed + hash(vec2(id.x, 7.0 + kk)) * span, span);
            float dist = head - y;
            float len = 10.0 + 22.0 * hash(vec2(id.x, 11.0 + kk));
            if (dist >= 0.0) {
                b = max(b, exp(-dist / len * 1.8));
                headness = max(headness, 1.0 - step(1.0, dist));
            }
        }
        float rate = headness > 0.5 ? 14.0 : 0.6 + 2.0 * hash(id);
        float k = 2.0 + floor(hash(id + floor(time * rate)) * (glyphCount - 2.0));
        float g = glyph(k, f);
        return g * (0.12 + b * 1.25 + headness * 1.6);
    }
    if (sid() == 4) {
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
    if (sid() == 1) {
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
// the planet-eater, all on the turning body: a hull of small plates, a
// cratered armour cap over the north with a jagged edge and a trench cut
// across it, a ribbed belt round the middle with antennae bristling where it
// meets the edge, a great glowing eye-vent, and a mouth between two horned
// mandibles that fires a beam straight out of it. A ring of lights on
// spokes hangs round it all, still.
const vec3 U_MOUTH = vec3(0.80, -0.12, 0.58);   // model directions (normalised in use)
const vec3 U_EYE = vec3(-0.86, -0.08, 0.50);
const vec3 U_BELT = vec3(0.10, 1.0, 0.0);       // the belt's axis

float angTo(vec3 m, vec3 dir) { return acos(clamp(dot(m, normalize(dir)), -1.0, 1.0)); }

// where we are round a feature at dir: angle about it, in its own frame
float around(vec3 m, vec3 dir) {
    vec3 w = normalize(dir);
    vec3 u = normalize(cross(vec3(0.0, 1.0, 0.0), w));
    vec3 v = cross(w, u);
    return atan(dot(m, v), dot(m, u));
}

vec3 unicronSurface(vec3 n, out float glowAmt, out float hot) {
    vec3 m = transpose(mat3(rotation)) * n;
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);
    vec3 L = normalize(vec3(-0.5, 0.6, 0.62));
    float diff = 0.22 + 0.78 * max(dot(n, L), 0.0);
    glowAmt = 0.0; hot = 0.0;

    // the hull: courses of small plates, each row offset like brickwork
    float rowsN = rings * 1.1;
    float row = floor((lat + PI / 2.0) / PI * rowsN);
    float per = max(4.0, floor(2.4 * rowsN * cos(lat)));
    float u = (lon + PI) / (2.0 * PI) * per + 0.5 * mod(row, 2.0);
    vec2 f = vec2(fract(u), fract((lat + PI / 2.0) / PI * rowsN));
    vec2 id = vec2(floor(u), row);
    float seam = 1.0 - smoothstep(0.0, 0.08, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
    vec3 hull = mix(vec3(0.13, 0.13, 0.22), vec3(0.19, 0.19, 0.30), hash(id)) * (1.0 - 0.45 * seam);
    hull = mix(hull, hull + glowColor.rgb * 0.05, 0.5);

    // the armour cap: grey, cratered, a jagged lower edge
    float edge = 0.30 + 0.07 * sin(lon * 4.0 + 0.7) + 0.04 * sin(lon * 13.0) + 0.025 * sin(lon * 29.0 + 2.0);
    float cap = smoothstep(0.0, 0.015, m.y - edge);
    vec2 cc = vec2(lon * 3.2, lat * 7.0);
    float crater = smoothstep(0.3, 0.2, length(fract(cc) - 0.5)) * step(0.5, hash(floor(cc)));
    float craterRim = smoothstep(0.06, 0.0, abs(length(fract(cc) - 0.5) - 0.3)) * step(0.5, hash(floor(cc)));
    vec3 capCol = mix(vec3(0.50, 0.52, 0.58), vec3(0.32, 0.33, 0.39), crater) + craterRim * 0.12;
    // a trench cut across it, on a tilted great circle
    float trench = smoothstep(0.03, 0.012, abs(dot(m, normalize(vec3(0.85, 0.15, -0.5))))) * smoothstep(0.0, 0.1, m.y);
    capCol = mix(capCol, vec3(0.12, 0.12, 0.17), trench);
    // the cap's shadowed lip
    float lip = smoothstep(0.035, 0.0, m.y - edge) * step(edge - 0.035, m.y);
    vec3 col = mix(hull, capCol, cap) * diff;
    col *= 1.0 - lip * 0.6;

    // the belt round the middle, ribbed, its edges lit
    float bd = dot(m, normalize(U_BELT));
    float belt = smoothstep(0.075, 0.065, abs(bd));
    float rib = 0.6 + 0.4 * step(0.5, fract(lon * 40.0));
    float beltEdge = smoothstep(0.012, 0.0, abs(abs(bd) - 0.07));
    col = mix(col, vec3(0.20, 0.18, 0.24) * rib * diff, belt);
    glowAmt += beltEdge * 0.6 + belt * step(0.93, fract(lon * 6.0)) * 0.8;   // lights along it

    // little vents, glowing, over the hull
    vec2 vc = vec2(lon * 5.0, lat * 9.0);
    float vent = step(0.86, hash(floor(vc) + 3.3)) * (1.0 - cap) * (1.0 - belt);
    float vd = length(fract(vc) - 0.5);
    glowAmt += vent * smoothstep(0.17, 0.09, vd);
    col *= 1.0 - vent * smoothstep(0.22, 0.17, vd) * 0.6;

    // the eye-vent: a great glowing disc in a dark socket
    float ea = angTo(m, U_EYE);
    float eye = smoothstep(0.34, 0.31, ea);
    col = mix(col, vec3(0.02), smoothstep(0.38, 0.35, ea) * (1.0 - eye));
    float grill = 0.75 + 0.25 * step(0.5, fract(ea * 40.0));
    glowAmt += eye * grill * (0.9 + 0.1 * sin(time * 2.0));
    hot += eye * smoothstep(0.31, 0.1, ea) * 0.6;

    // the mouth: a socket with a molten core
    float ma = angTo(m, U_MOUTH);
    col = mix(col, vec3(0.03), smoothstep(0.24, 0.21, ma));
    hot += smoothstep(0.17, 0.0, ma) * 1.6;
    glowAmt += exp(-ma * 12.0) * 0.8;
    // two horned mandibles hooked round it, tapering to points
    float phi = around(m, U_MOUTH);
    float upper = smoothstep(-0.4, 0.2, phi) * smoothstep(2.4, 1.6, phi);
    float lower = smoothstep(-2.8, -2.2, phi) * smoothstep(-0.3, -0.9, phi);
    float taper = max(upper, lower);
    float horn = smoothstep(0.05 * taper + 0.002, 0.0, abs(ma - 0.29 - 0.05 * (1.0 - taper))) * step(0.05, taper);
    col = mix(col, vec3(0.30, 0.26, 0.26) * diff, horn);
    glowAmt += horn * smoothstep(0.31, 0.27, ma) * 0.9;           // their inner edges catch the fire
    return col;
}

vec4 unicron(vec2 d, float r2) {
    float rr = sqrt(r2);
    vec3 hotCol = mix(dotColor.rgb, vec3(1.0), 0.45);
    vec3 col = vec3(0.0);
    float a = 0.0;
    if (r2 < 1.0) {
        float z = sqrt(1.0 - r2);
        float g, h;
        col = unicronSurface(vec3(d, z), g, h);
        col += dotColor.rgb * g + hotCol * h;
        col += glowColor.rgb * pow(1.0 - z, 2.6) * 0.5;          // rim
        a = 1.0;
    }

    // the ring of lights, its spokes (still, round the turning body)
    float Rr = 1.36;
    float ringLine = smoothstep(0.014, 0.005, abs(rr - Rr));
    float th = atan(d.y, d.x) + time * 0.04;
    float beads = 44.0;
    float bk = floor(th / (2.0 * PI) * beads);
    float bd = abs(fract(th / (2.0 * PI) * beads) - 0.5) * (2.0 * PI / beads) * Rr;
    float bead = exp(-(bd * bd + (rr - Rr) * (rr - Rr)) * 7000.0) * (0.55 + 0.45 * sin(time * 4.0 + bk * 1.7));
    float spoke = smoothstep(0.014, 0.005, abs(d.x)) * step(0.99, abs(d.y)) * step(abs(d.y), Rr);
    float spokeStud = smoothstep(0.04, 0.025, length(vec2(d.x, abs(d.y) - 1.17)));
    vec3 frameCol = mix(vec3(0.32, 0.28, 0.26), dotColor.rgb, 0.55);
    col += frameCol * (ringLine * 0.8 + spoke * 0.9 + spokeStud * 0.7) + hotCol * bead * 1.5;
    a = max(a, max(max(ringLine, spoke), max(spokeStud, bead)));

    // antennae bristling from the belt where it meets the edge
    vec3 B = mat3(rotation) * normalize(U_BELT);
    vec3 t3 = cross(B, vec3(0.0, 0.0, 1.0));
    if (length(t3.xy) > 0.05 && rr > 0.99) {
        vec2 t = normalize(t3.xy);
        float ang = atan(d.y, d.x);
        for (int s = 0; s < 2; s++) {
            vec2 dir = s == 0 ? t : -t;
            float da = ang - atan(dir.y, dir.x);
            da = mod(da + PI, 2.0 * PI) - PI;
            if (abs(da) < 0.5) {
                float k = floor(da * 22.0);
                float len = 1.06 + 0.2 * hash(vec2(k, float(s))) * (1.0 - abs(da) * 1.6);
                float line = smoothstep(0.006, 0.0, abs(fract(da * 22.0) - 0.5) / 22.0 * rr) * step(rr, len);
                float tip = smoothstep(0.018, 0.0, abs(rr - len)) * line;
                col += frameCol * line * 0.8 + hotCol * tip * 0.8;
                a = max(a, line);
            }
        }
    }

    // the beam, out of the mouth wherever it has turned to
    vec3 mv = mat3(rotation) * normalize(U_MOUTH);
    float facing = smoothstep(0.0, 0.35, mv.z);
    if (facing > 0.0) {
        vec2 M = mv.xy;
        vec2 D = length(M) > 0.05 ? normalize(M) : vec2(0.7, -0.7);
        vec2 q = d - M;
        float along = dot(q, D);
        float perp = abs(q.x * D.y - q.y * D.x);
        float w = 0.06 + along * 0.26;
        float beam = step(0.0, along) * smoothstep(w, w * 0.15, perp) * exp(-along * 0.4);
        float streak = hash(vec2(floor(perp / w * 9.0), 0.0));
        float run = fract(along * 1.4 - time * (1.0 + streak) + streak);
        beam *= 0.6 + 0.4 * smoothstep(0.7, 1.0, run) * step(0.5, streak);
        beam *= (0.85 + 0.15 * sin(time * 7.0)) * facing;
        col += mix(hotCol, dotColor.rgb, smoothstep(0.0, 1.5, along)) * beam * 1.1;
        a = max(a, beam * 0.9);
    }

    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.35;
    a = max(a, halo * 0.35);
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

// ---------------------------------------------------------------- bestagons
// hex tiles over the sphere: each cube face of the sphere carries a hex grid
// (equal-angle, so they stay even), every tile bevelled with a neon seam
// round it, coloured in an iridescent sweep of the theme; some pop out, and
// a few loose ones drift by off the edge
vec4 hexCell(vec2 p) {                       // (offset in the cell, cell id)
    const vec2 s = vec2(1.0, 1.7320508);
    vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
    vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
    return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
}
float hexEdge(vec2 q) {                      // 0 at the rim, 0.5 at the centre
    q = abs(q);
    return 0.5 - max(dot(q, vec2(0.5, 0.8660254)), q.x);
}
vec3 iridescent(vec3 n, float h) {
    float t = 0.5 + 0.5 * sin(dot(n, vec3(2.1, 1.4, -1.2)) * 1.6 + h * 1.4 + time * 0.25);
    return mix(mix(glowColor.rgb, dotColor.rgb, t), vec3(0.85, 0.9, 1.0), 0.12 * (1.0 - t));
}
vec3 hexTile(vec4 hx, vec3 n, float face, out float seamOut) {
    float e = hexEdge(hx.xy);
    vec2 id = hx.zw + face * 37.0;
    float h = hash(id);
    float pop = step(0.9, h);
    float gap = 0.045;
    seamOut = smoothstep(gap, gap * 0.4, e);
    float bevel = 1.0 - smoothstep(gap, gap + 0.09, e);
    vec3 L = normalize(vec3(-0.5, 0.6, 0.62));
    float diff = 0.3 + 0.7 * max(dot(n, L), 0.0);
    vec2 dir = normalize(hx.xy + 1e-4);
    float slope = dot(dir, vec2(-0.55, 0.75));             // bevels facing the light are bright
    vec3 col = iridescent(n, h) * diff * (0.55 + 0.45 * hash(id + 2.0));
    col *= 1.0 + bevel * slope * 0.7;
    col += pop * (iridescent(n, h + 1.0) * 0.35 + 0.08);
    float spec = pow(max(dot(reflect(-L, n), vec3(0.0, 0.0, 1.0)), 0.0), 24.0);
    col += spec * 0.35 * (1.0 - seamOut);
    col = mix(col, dotColor.rgb * 0.55, seamOut);       // the neon seam
    return col;
}
vec4 hexGlobe(vec2 d, float r2) {
    float rr = sqrt(r2);
    vec3 col = vec3(0.0);
    float a = 0.0;
    float k = rings * 0.13;                  // hexes across a face, about
    if (r2 < 1.0) {
        float z = sqrt(1.0 - r2);
        vec3 n = vec3(d, z);
        vec3 m = transpose(mat3(rotation)) * n;
        vec3 am = abs(m);
        vec2 uv;
        float face;
        if (am.x >= am.y && am.x >= am.z) { uv = m.yz / am.x; face = m.x > 0.0 ? 1.0 : 2.0; }
        else if (am.y >= am.z)            { uv = m.xz / am.y; face = m.y > 0.0 ? 3.0 : 4.0; }
        else                              { uv = m.xy / am.z; face = m.z > 0.0 ? 5.0 : 6.0; }
        uv = atan(uv) * (4.0 / PI);          // equal-angle: even tiles out to the face edges
        float seam;
        col = hexTile(hexCell(uv * k), n, face, seam);
        col += glowColor.rgb * pow(1.0 - z, 2.4) * 0.5;
        a = 1.0;
    }
    // loose tiles drifting past the edge
    if (rr > 0.98 && rr < 1.45) {
        vec2 p = d * k * 1.6 + vec2(time * 0.05, 0.0);
        vec4 hx = hexCell(p);
        float h = hash(hx.zw + 91.0);
        float keep = step(h, 0.5 * (1.0 - smoothstep(1.0, 1.45, rr))) * step(0.5, hash(hx.zw + floor(time * 0.15 + h * 5.0)));
        float e = hexEdge(hx.xy * 1.35);
        if (keep > 0.5 && e > 0.0 && rr > 1.0) {
            float seam;
            vec3 tn = normalize(vec3(d * 0.6, 0.6));
            vec3 c = hexTile(vec4(hx.xy * 1.35, hx.zw), tn, 9.0, seam);
            float ta = smoothstep(0.0, 0.02, e) * (1.0 - smoothstep(1.2, 1.45, rr));
            col = mix(col, c, ta);
            a = max(a, ta);
        }
    }
    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.3;
    a = max(a, halo * 0.3);
    return vec4(col, a);
}

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    vec2 d = (px - center) / radius;
    d.y = -d.y;
    float r2 = dot(d, d);
    if (sid() == 5 || sid() == 6 || sid() == 8) {
        vec4 o = sid() == 5 ? unicron(d, r2) : sid() == 6 ? dyson(d, r2) : hexGlobe(d, r2);
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
        float backLevel = sid() == 4 ? 0.3 : sid() >= 2 ? 0.1 : 0.16;
        col = dotColor.rgb * front * light * (1.0 + 0.6 * pulse)
            + dotColor.rgb * back * backLevel
            + glowColor.rgb * rim * 0.55;
        a = clamp(front * 0.9 + back * backLevel * 1.2 + rim * 0.5 + 0.06, 0.0, 1.0);
        float body = sid() == 4 ? 0.16 : sid() == 2 ? 0.12 : sid() == 7 ? 0.08 : 0.05;
        col += glowColor.rgb * body;                                 // a faint body
        a = max(a, body * 1.5);
        if (sid() >= 2) {
            // a soft highlight, upper left
            float spec = pow(max(dot(vec3(d, z), normalize(vec3(-0.45, 0.5, 0.75))), 0.0), 14.0);
            col += mix(dotColor.rgb, vec3(1.0), 0.5) * spec * 0.25;
        }
    }
    float rr = sqrt(r2);
    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.55;
    a = max(a, halo * 0.55);

    if (sid() == 2 && rr > 0.97) {
        // binary: light rays fanning out from the rim
        float ang = atan(d.y, d.x);
        float s = ang * 70.0 + time * 0.08;
        float ray = mix(hash(vec2(floor(s), 1.0)), hash(vec2(floor(s) + 1.0, 1.0)), smoothstep(0.0, 1.0, fract(s)));
        ray = pow(ray, 7.0) * exp(-(rr - 1.0) * 3.2) * smoothstep(0.97, 1.02, rr);
        col += mix(glowColor.rgb, dotColor.rgb, 0.5) * ray * 0.9;
        a = max(a, ray * 0.8);
    }
    if (sid() == 3 && rr > 1.02) {
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
    if (sid() == 4) {
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
