#version 440
// Стеклянная волна (GlassWave.qml): кольцо из центра преломляет то, что под
// ним, как прозрачная выпуклость. Перед гребнем фон уже чуть гнётся (лёгкая
// рябь-предвестник), на гребне — светлая кромка с радугой, за ним всё
// возвращается на место. После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;           // размер, px
    vec2 center;        // откуда идёт волна, px
    float radius;       // где сейчас гребень, px
    float waveWidth;    // ширина гребня, px
    float strength;     // 0…1: сила (к концу гаснет)
    float rim;          // яркость кромки
};

layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 v = px - center;
    float dist = length(v);
    vec2 dir = v / max(dist, 1.0);
    float d = (dist - radius) / max(waveWidth, 1.0);

    // гребень — выпуклая линза: смещение по наклону гауссова «бугра»
    float crest = exp(-d * d * 2.2);
    float slope = -d * crest;
    // впереди гребня фон уже немного гнётся
    float a = d - 1.7;
    float pre = 0.32 * exp(-a * a * 1.4) * -a;
    float k = strength * waveWidth * 0.55;
    vec2 off = dir * (slope + pre) * k;

    vec2 uv = (px - off) / res;
    vec2 uvR = (px - off * 1.18) / res;
    vec2 uvB = (px - off * 0.82) / res;
    vec3 col = vec3(texture(src, uvR).r, texture(src, uv).g, texture(src, uvB).b);
    float alpha = texture(src, uv).a;

    // стекло на гребне чуть светлее, кромка ловит свет сверху слева
    vec2 L = normalize(vec2(-0.5, -0.85));
    float lit = 0.55 + 0.45 * dot(dir, L);
    col *= 1.0 + 0.07 * crest * strength;
    col += vec3(1.0) * pow(crest, 7.0) * lit * rim * strength * 0.55;
    // тонкая тёмная тень за гребнем — объём
    float b = d + 0.9;
    col *= 1.0 - 0.10 * exp(-b * b * 5.0) * strength;

    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
