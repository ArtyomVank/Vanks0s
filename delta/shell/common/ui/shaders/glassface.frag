#version 440
// Цифры часов «стеклом» или «пустыми внутри» (GlassFace.qml). На вход —
// цифры, нарисованные сплошным цветом: форма берётся из их прозрачности
// целиком, поэтому места, где линии и контуры букв накладываются друг на
// друга («восьмёрка из двух колец»), не темнеют и не видны изнутри.
//   • кромка — полоса шириной rim у края формы (эрозия по кольцу отсчётов);
//   • hollowK = 1 — только кромка: цифры пустые внутри;
//   • иначе стекло, как у часов Vanks Launcher на телефоне: заливка цветом —
//     светлее и плотнее сверху, блик в верхней трети, кромка от белой сверху
//     к цвету снизу (ярче там, куда падает свет — сверху слева) и мягкая
//     тень под формой, чтобы стекло отделялось от обоев.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;         // 1 / размер, в долях текстуры на пиксель
    float rim;          // ширина кромки, px
    float hollowK;      // 1 — только кромка
    float fill;         // плотность заливки стекла 0…1
    float shadowR;      // радиус тени, px (0 — без тени)
    vec4 tintV;         // цвет, a — сила
    vec4 box;           // форма внутри текстуры: x0, y0, x1, y1 (доли)
};

layout(binding = 1) uniform sampler2D source;

float shapeAt(vec2 uv) { return texture(source, uv).a; }

void main() {
    vec2 uv = qt_TexCoord0;
    float a = shapeAt(uv);
    // высота внутри формы: 0 — верх цифр, 1 — низ (а не всей текстуры с полями)
    float y = clamp((uv.y - box.y) / max(0.0001, box.w - box.y), 0.0, 1.0);

    // минимум по двум кольцам вокруг точки: внутри формы дальше rim от края — 1
    float m = a;
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 0.5236;
        vec2 d = vec2(cos(ang), sin(ang)) * texel;
        m = min(m, shapeAt(uv + d * rim));
        m = min(m, shapeAt(uv + d * rim * 0.5));
    }
    float edge = clamp(a - m, 0.0, 1.0);

    vec3 tint = tintV.rgb;
    if (hollowK > 0.5) {
        fragColor = vec4(tint, 1.0) * edge * tintV.a * qt_Opacity;
        return;
    }

    // тень: форма, размытая по двум кольцам и сдвинутая вниз; только снаружи
    float sh = 0.0;
    if (shadowR > 0.5) {
        vec2 c = uv - vec2(0.0, shadowR * 0.3) * texel;
        float acc = shapeAt(c);
        for (int i = 0; i < 12; i++) {
            float ang = float(i) * 0.5236;
            vec2 d = vec2(cos(ang), sin(ang)) * texel * shadowR;
            acc += shapeAt(c + d) + shapeAt(c + d * 0.5);
        }
        sh = acc / 25.0 * 0.32 * (1.0 - a);
    }

    // нормаль края наружу — против роста непрозрачности
    float hs = max(1.0, rim * 0.7);
    vec2 g = vec2(shapeAt(uv + vec2(hs, 0.0) * texel) - shapeAt(uv - vec2(hs, 0.0) * texel),
                  shapeAt(uv + vec2(0.0, hs) * texel) - shapeAt(uv - vec2(0.0, hs) * texel));
    float gl = length(g);
    float facing = gl > 0.001 ? dot(-g / gl, normalize(vec2(-0.35, -1.0))) : 0.0;

    // заливка: сверху цвет с примесью белого и плотнее, снизу — чистый цвет
    vec3 bodyC = mix(mix(tint, vec3(1.0), 0.25), tint, y);
    float bodyA = a * fill * mix(1.12, 0.8, y);
    // блик в верхней трети
    float hiA = a * 0.15 * clamp(1.0 - y / 0.3, 0.0, 1.0);
    // кромка: белая сверху, к низу — цвет пополам с белым
    vec3 rimC = mix(vec3(1.0), mix(tint, vec3(1.0), 0.5), y);
    float rimA = edge * mix(0.85, 0.45, y) * (0.75 + 0.35 * max(facing, 0.0));

    // слои поверх друг друга (премультиплицированные): тень, заливка, блик, кромка
    vec4 col = vec4(0.0, 0.0, 0.0, sh);
    col = vec4(bodyC * bodyA, bodyA) + col * (1.0 - bodyA);
    col = vec4(vec3(hiA), hiA) + col * (1.0 - hiA);
    col = vec4(rimC * rimA, rimA) + col * (1.0 - rimA);
    fragColor = col * tintV.a * qt_Opacity;
}
