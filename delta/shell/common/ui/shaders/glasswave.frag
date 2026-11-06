#version 440
// Стеклянная волна (GlassWave.qml): кольцо из центра преломляет то, что под
// ним, как прозрачная выпуклость. Тяжёлая: в начале всё вокруг центра
// вздрагивает (thump), впереди гребня фон уже гнётся, на гребне — светлая
// кромка с радугой, следом идёт второй, слабый вал, за ним — тень.
// После правки: tools/delta-shaders.sh.

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
    float thump;        // 0…1: толчок в самом начале
};

layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 px = qt_TexCoord0 * res;
    // толчок: картинку у центра на миг втягивает внутрь
    vec2 v0 = px - center;
    px = center + v0 * (1.0 - 0.045 * thump * exp(-length(v0) / (res.y * 0.55)));
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
    // второй вал следом — у тяжёлой волны есть тело
    float s2 = d + 2.4;
    float second = -s2 * exp(-s2 * s2 * 2.0) * 0.42;
    float k = strength * waveWidth * 0.9;
    // у самого центра направление не определено — там не гнём (иначе воронка)
    vec2 off = dir * (slope + pre + second) * k * smoothstep(0.0, waveWidth * 0.9, dist);

    vec2 uv = (px - off) / res;
    vec2 uvR = (px - off * 1.24) / res;
    vec2 uvB = (px - off * 0.76) / res;
    vec3 col = vec3(texture(src, uvR).r, texture(src, uv).g, texture(src, uvB).b);
    float alpha = texture(src, uv).a;

    // стекло на гребне чуть светлее, кромка ловит свет сверху слева
    vec2 L = normalize(vec2(-0.5, -0.85));
    float lit = 0.55 + 0.45 * dot(dir, L);
    col *= 1.0 + 0.1 * crest * strength;
    col += vec3(1.0) * (pow(crest, 4.0) * 0.35 + pow(crest, 14.0) * 0.5) * lit * rim * strength;
    // тень за гребнем — объём и вес
    float b = d + 1.0;
    col *= 1.0 - 0.2 * exp(-b * b * 3.0) * strength;

    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
