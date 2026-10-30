#version 440
// Блик «жидкого стекла» (Sheen.qml): светлая кромка по краю скруглённого
// прямоугольника — ярче там, куда падает свет (сверху слева) и напротив,
// мягкое свечение от края внутрь и отблеск сверху. После правки:
// tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;          // размер, px
    float radius;       // скругление, px
    float strength;     // 0…1
};

float box(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 hs = area * 0.5;
    vec2 p = qt_TexCoord0 * area - hs;
    float r = min(radius, min(hs.x, hs.y));
    float d = box(p, hs, r);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);

    // нормаль края: в углах — от центра скругления, на сторонах — по оси
    vec2 q = abs(p) - hs + r;
    vec2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    n *= vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
    float lit = dot(n, normalize(vec2(-0.6, -1.0)));
    float spec = pow(max(lit, 0.0), 2.0) + 0.6 * pow(max(-lit, 0.0), 3.0);

    // тонкая кромка ~1.5 px у самого края
    float rim = smoothstep(-2.4, -1.0, d) * (1.0 - smoothstep(-0.8, 0.3, d));
    // свечение внутрь: у края — как будто стекло преломляет свет
    float glow = exp(d / max(4.0, min(hs.x, hs.y) * 0.22));
    float top = pow(1.0 - qt_TexCoord0.y, 4.0);

    float a = rim * (0.22 + 0.78 * spec) * 0.95
            + glow * (0.05 + 0.16 * spec)
            + top * 0.09;
    a = clamp(a * strength, 0.0, 1.0) * inside;
    fragColor = vec4(a, a, a, a) * qt_Opacity;
}
