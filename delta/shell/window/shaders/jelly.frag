#version 440
// «Желе»: снимок окна со скруглёнными углами и рамкой, как у Hyprland.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 rect;
    vec2 grab;
    float reach;
    float radius;
    float border;
    vec4 borderColor;
    vec4 o12;
    vec4 o34;
    vec4 o5;
};

layout(binding = 1) uniform sampler2D source;

// расстояние до края скруглённого прямоугольника (внутри — меньше нуля)
float box(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 size = rect.zw;
    vec2 p = coord * size - size * 0.5;
    float d = box(p, size * 0.5, min(radius, min(size.x, size.y) * 0.5));
    float inside = 1.0 - smoothstep(-0.75, 0.75, d);
    vec4 c = texture(source, coord);
    // рамка поверх края окна, как border у Hyprland
    float edge = border > 0.0 ? smoothstep(-border - 0.75, -border + 0.75, d) : 0.0;
    c = mix(c, vec4(borderColor.rgb * borderColor.a, borderColor.a), edge);
    fragColor = c * inside * qt_Opacity;
}
