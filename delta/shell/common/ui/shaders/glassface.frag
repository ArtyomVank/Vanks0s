#version 440
// Цифры часов «стеклом» или «пустыми внутри» (GlassFace.qml). На вход —
// цифры, нарисованные сплошным цветом: форма берётся из их прозрачности
// целиком, поэтому места, где линии и контуры букв накладываются друг на
// друга («восьмёрка из двух колец»), не темнеют и не видны изнутри.
//   • кромка — полоса шириной rim у края формы (эрозия по кольцу отсчётов);
//   • hollowK = 1 — только кромка: цифры пустые внутри;
//   • иначе стекло: лёгкая заливка, светлее сверху, и блик по кромке —
//     ярче там, куда падает свет (сверху слева), слабее напротив.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;         // 1 / размер, в долях текстуры на пиксель
    float rim;          // ширина кромки, px
    float hollowK;      // 1 — только кромка
    float fill;         // заливка стекла 0…1
    vec4 tintV;         // цвет, a — сила
};

layout(binding = 1) uniform sampler2D source;

float shapeAt(vec2 uv) { return texture(source, uv).a; }

void main() {
    vec2 uv = qt_TexCoord0;
    float a = shapeAt(uv);

    // минимум по двум кольцам вокруг точки: внутри формы дальше rim от края — 1
    float m = a;
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 0.5236;
        vec2 d = vec2(cos(ang), sin(ang)) * texel;
        m = min(m, shapeAt(uv + d * rim));
        m = min(m, shapeAt(uv + d * rim * 0.5));
    }
    float edge = clamp(a - m, 0.0, 1.0);

    float alpha;
    if (hollowK > 0.5) {
        alpha = edge;
    } else {
        // нормаль края наружу — против роста непрозрачности
        float h = max(1.0, rim * 0.7);
        vec2 g = vec2(shapeAt(uv + vec2(h, 0.0) * texel) - shapeAt(uv - vec2(h, 0.0) * texel),
                      shapeAt(uv + vec2(0.0, h) * texel) - shapeAt(uv - vec2(0.0, h) * texel));
        float gl = length(g);
        float facing = gl > 0.001 ? dot(-g / gl, normalize(vec2(-0.35, -1.0))) : 0.0;
        float shine = edge * (0.38 + 0.62 * max(facing, 0.0) + 0.2 * max(-facing, 0.0));
        float body = a * fill * (1.2 - 0.45 * uv.y);
        alpha = clamp(body + shine, 0.0, 1.0);
    }
    fragColor = vec4(tintV.rgb, 1.0) * alpha * tintV.a * qt_Opacity;
}
