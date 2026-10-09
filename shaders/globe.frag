#version 440
// Globe-Launcher: the globe, per pixel. For a pixel over the sphere, the
// point on its surface is turned back by the globe's rotation and placed on
// rings of latitude; dots sit on each ring (fewer near the poles, so they're
// evenly spaced), or, as a wireframe, lines run along the rings and
// meridians. The far side shows faintly through, the rim glows, and a halo
// sits round the outside.
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
    float wire;       // 0 dots, 1 wireframe
    float pulse;      // 0..1, brightens briefly (selection change)
};

const float PI = 3.14159265;

// how lit the surface point n (view space, unit) is
float pattern(vec3 n) {
    vec3 m = transpose(mat3(rotation)) * n;          // back to the globe's own frame
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);
    float step = PI / rings;
    float ringLat = clamp(floor(lat / step + 0.5) * step, -PI / 2.0 + step * 0.5, PI / 2.0 - step * 0.5);
    if (wire > 0.5) {
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

void main() {
    vec2 px = qt_TexCoord0 * resolution;
    vec2 d = (px - center) / radius;
    d.y = -d.y;
    float r2 = dot(d, d);
    vec3 col = vec3(0.0);
    float a = 0.0;
    if (r2 < 1.0) {
        float z = sqrt(1.0 - r2);
        float front = pattern(vec3(d, z));
        float back = pattern(vec3(d, -z));
        float rim = pow(1.0 - z, 2.2);
        float light = 0.45 + 0.55 * z;                               // brighter facing you
        col = dotColor.rgb * front * light * (1.0 + 0.6 * pulse)
            + dotColor.rgb * back * 0.16
            + glowColor.rgb * rim * 0.55;
        a = clamp(front * 0.9 + back * 0.2 + rim * 0.5 + 0.06, 0.0, 1.0);
        col += glowColor.rgb * 0.05;                                 // a faint body
    }
    float rr = sqrt(r2);
    float halo = exp(-max(rr - 1.0, 0.0) * 9.0) * smoothstep(0.92, 1.0, rr);
    col += glowColor.rgb * halo * 0.55;
    a = max(a, halo * 0.55);
    fragColor = vec4(col, a) * qt_Opacity;
}
