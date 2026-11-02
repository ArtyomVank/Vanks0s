#version 440
// Живые обои при запуске: слои-полотна расцвечиваются снизу и замирают. intro
// идёт от 0 до 1 один раз за сессию, потом кадр неподвижен и не тратит видеокарту.
// Цвета задаёт SuperWalls.qml. После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float intro;
    vec4 colorA;   // глубина
    vec4 colorB;   // тело полотен
    vec4 colorC;   // блик
};

float ease(float t) { return 1.0 - pow(1.0 - clamp(t, 0.0, 1.0), 3.0); }

// Край i-го полотна (0 — ближнее, снизу): плавная волна, за время intro поднимается
float edge(float x, float i, float t) {
    float rise = ease(t * 1.5 - (5.0 - i) * 0.07);
    float base = mix(-1.9, -0.82 + i * 0.33, rise);
    float phase = (1.0 - rise) * 2.4 + i * 1.7;
    return base
        + 0.26 * sin(x * (0.95 + i * 0.09) + phase)
        + 0.10 * sin(x * (2.1 - i * 0.14) - phase * 1.4 + 1.2)
        + 0.03 * sin(x * 4.1 + phase * 2.0 + i);
}

void main() {
    vec2 p = (qt_TexCoord0 * 2.0 - 1.0) * vec2(res.x / res.y, -1.0);
    float t = clamp(intro, 0.0, 1.0);
    // волны идут наискось
    float ang = -0.24;
    vec2 w = mat2(cos(ang), -sin(ang), sin(ang), cos(ang)) * p;

    // небо: сверху глубокий цвет, ниже — свечение, которое разгорается
    float glow = ease(t * 1.2);
    vec3 col = mix(colorA.rgb * 0.75, colorA.rgb * 1.5, (1.0 - smoothstep(-0.4, 1.2, p.y)));
    col += colorB.rgb * 0.30 * glow * exp(-dot(p - vec2(0.7, 0.55), p - vec2(0.7, 0.55)) * 1.1);

    const int N = 6;
    for (int k = N - 1; k >= 0; k--) {
        float i = float(k);
        float e = edge(w.x + i * 0.35, i, t);
        float d = e - w.y;             // > 0 — внутри полотна (под его краем)
        float px = 2.0 / res.y;
        float mask = smoothstep(-px, px, d);
        // мягкая тень полотна на том, что позади
        col *= 1.0 - 0.30 * (1.0 - smoothstep(0.0, 0.26, -d)) * (1.0 - mask);
        // ближние полотна глубже по цвету, дальние светлее
        float depth = i / float(N - 1);
        vec3 body = mix(mix(colorA.rgb, colorB.rgb, 0.45), colorB.rgb * 1.08, depth);
        // переливы вдоль полотна
        body = mix(body, mix(colorB.rgb, colorC.rgb, 0.35), 0.45 * smoothstep(0.2, 1.0, sin(w.x * 1.15 + i * 1.5 + 0.8)));
        vec3 fill = mix(body * 1.08, body * 0.62, smoothstep(0.0, 0.62, d));
        fill += colorC.rgb * 0.26 * exp(-max(d, 0.0) * 9.0);
        // стеклянная кромка
        fill += colorC.rgb * 0.46 * exp(-max(d, 0.0) * 70.0);
        col = mix(col, fill, mask * 0.90);
    }
    // до начала — почти чёрный экран, из которого проступает картина
    col *= mix(0.04, 1.0, ease(t * 2.0));
    col = pow(clamp(col, 0.0, 1.0), vec3(0.95));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
