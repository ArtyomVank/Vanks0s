#version 440
// «Акрил» (Contour.qml): светящийся контур поверх стеклянной подложки.
//   • по кромке — тонкая линия света: ярче сверху слева (откуда свет), к
//     низу справа гаснет и становится тёплой (отсвет акцента в толще акрила);
//   • вдоль кромки внутри — мягкое свечение в пару пикселей;
//   • у верхнего края — едва заметный свет, как в толстом листе акрила.
// Фон под панелью даёт размытие композитора, здесь — только свет.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;          // размер, px
    float radius;       // скругление, px
    float strength;     // 0…1
    float lightBg;      // 1 — светлая тема
    vec4 warm;          // отсвет снизу справа (акцент)
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

    // где на контуре: -1 — верх слева, +1 — низ справа
    vec2 n = p / max(hs, vec2(1.0));
    float diag = clamp(dot(n, vec2(0.62, 0.78)), -1.0, 1.0);
    float lit = 0.5 - 0.5 * diag;                   // 1 сверху слева
    float far = smoothstep(0.15, 0.95, diag);       // тёплый угол

    // линия кромки 1.2 px и свечение внутри
    float line = (1.0 - smoothstep(0.0, 1.3, abs(d + 0.7))) * inside;
    float halo = exp(max(d, -40.0) / 5.0) * inside;
    // свет у верхнего края
    float top = (1.0 - smoothstep(0.0, max(18.0, hs.y * 0.9), p.y + hs.y)) * inside;

    float k = strength * (lightBg > 0.5 ? 0.7 : 1.0);
    vec3 white = vec3(1.0);
    float aw = line * (0.18 + 0.55 * pow(lit, 1.6)) + halo * 0.10 * lit + top * 0.045;
    float aWarm = (line * 0.42 + halo * 0.12) * far * warm.a;
    vec3 col = white * aw + warm.rgb * aWarm;
    float a = clamp(aw + aWarm, 0.0, 1.0) * k;
    // премультиплицированный цвет
    fragColor = vec4(col * k, a) * qt_Opacity;
}
