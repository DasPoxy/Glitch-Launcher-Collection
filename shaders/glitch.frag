#version 440
// Globe-Launcher: the "jacked in" pass over the whole scene. Always: faint
// scanlines and a vignette. In a burst (intensity > 0): horizontal slices
// torn sideways, the colour channels split apart, and bright noise lines.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    float intensity;   // 0 calm .. 1 full burst
    float seed;        // changes per burst, so each tears differently
    float scanlines;   // 0..1
    vec4 tint;         // noise lines take this colour
};
layout(binding = 1) uniform sampler2D source;

float hash(float x) { return fract(sin(x * 127.1 + seed * 311.7) * 43758.5453); }

void main() {
    vec2 uv = qt_TexCoord0;
    float k = intensity;
    // torn slices: bands of rows shifted sideways
    float band = floor(uv.y * mix(14.0, 46.0, hash(3.0)));
    float tear = (hash(band) - 0.5) * 0.08 * k * step(0.55, hash(band + 7.0));
    vec2 tuv = uv + vec2(tear, 0.0);
    // colour channels apart
    float split = 0.006 * k + 0.0008;
    vec4 c = texture(source, tuv);
    float rC = texture(source, tuv + vec2(split, 0.0)).r;
    float bC = texture(source, tuv - vec2(split, 0.0)).b;
    vec3 col = vec3(rC, c.g, bC);
    // noise lines
    float row = floor(uv.y * resolution.y / 2.0);
    float line = step(1.0 - 0.012 * k, hash(row + floor(time * 30.0)));
    col += tint.rgb * line * 0.6;
    // scanlines and vignette
    float sl = 0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159);
    col *= 1.0 - scanlines * 0.12 * sl;
    vec2 v = uv - 0.5;
    col *= 1.0 - dot(v, v) * 0.55;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
