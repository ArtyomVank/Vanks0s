#version 440
// «Желе»: снимок окна со скруглёнными углами и рамкой снаружи, как у
// Hyprland (углы — суперэллипс со степенью rounding_power 2.4), под ними
// мягкая тень (shadow: range 18, render_power 3, 0x55000000).
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
    float shade;
    vec4 borderColor;
    vec4 o12;
    vec4 o34;
    vec4 o5;
};

layout(binding = 1) uniform sampler2D source;

// расстояние до края скруглённого прямоугольника (внутри — меньше нуля)
float box(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    vec2 m = max(q, 0.0);
    float corner = pow(pow(m.x, 2.4) + pow(m.y, 2.4), 1.0 / 2.4);
    return corner + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 size = rect.zw;
    vec2 p = coord * size - size * 0.5;
    float r = min(radius, min(size.x, size.y) * 0.5);
    float inner = box(p, size * 0.5, r);
    float outer = border > 0.0 ? box(p, size * 0.5 + border, r + border) : inner;
    float content = 1.0 - smoothstep(-0.6, 0.6, inner);
    float shape = 1.0 - smoothstep(-0.6, 0.6, outer);
    vec4 c = texture(source, clamp(coord, vec2(0.0), vec2(1.0))) * content;
    vec4 b = vec4(borderColor.rgb * borderColor.a, borderColor.a) * (shape - content);
    float s = shade > 0.0 ? pow(1.0 - clamp(outer / shade, 0.0, 1.0), 3.0) * 0.33 : 0.0;
    fragColor = (c + b + vec4(0.0, 0.0, 0.0, s) * (1.0 - shape)) * qt_Opacity;
}
