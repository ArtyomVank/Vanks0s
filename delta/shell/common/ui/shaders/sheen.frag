#version 440
// «Жидкое стекло» (Sheen.qml) — линза, а не рамка, как Liquid Glass у Apple:
//   • в середине стекло чистое: видно то, что за ним (обои), чуть размытое
//     матовостью (frost) и едва тонированное;
//   • у края стекло скруглено (скос шириной bezel): фон за ним изгибается —
//     берётся всё дальше снаружи, чем ближе к кромке, как в капле воды;
//     на скосе цвета чуть расходятся (дисперсия);
//   • по кромке — тонкий блик: ярче там, куда падает свет (сверху), слабее
//     напротив; вдоль скоса — мягкое свечение.
// Без обоев (hasWall = 0: лаунчер и меню поверх окон, видеообои без кадра)
// фон даёт размытие Hyprland, а шейдер рисует только блик и свечение.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;          // размер, px
    float radius;       // скругление, px
    float strength;     // 0…1
    float frost;        // матовость 0…1
    float lightBg;      // 1 — светлая тема
    float hasWall;      // 1 — преломлять обои
    vec2 origin;        // левый верхний угол на экране, px
    vec4 wallRect;      // где на экране обои: x, y, ширина, высота
    vec4 tint;          // цвет темы, a — сила
};

layout(binding = 1) uniform sampler2D source;

float box(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 wallUv(vec2 sp) { return clamp((sp - wallRect.xy) / wallRect.zw, vec2(0.001), vec2(0.999)); }

// фон в точке экрана sp, размытый на blur px: смещение уровня mip-карты
// (bias — textureLod нет в GLSL ES 1.0) и кольцо отсчётов вокруг
float lodBias(float blur) { return log2(max(1.0, blur * 0.3)); }
vec3 backdrop(vec2 sp, float blur) {
    float lod = lodBias(blur);
    vec3 c = texture(source, wallUv(sp), lod).rgb * 2.0;
    float w = 2.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7854 + 0.39;
        c += texture(source, wallUv(sp + vec2(cos(a), sin(a)) * blur * 0.6), lod).rgb;
        w += 1.0;
    }
    return c / w;
}

void main() {
    vec2 hs = area * 0.5;
    vec2 p = qt_TexCoord0 * area - hs;
    float r = min(radius, min(hs.x, hs.y));
    float d = box(p, hs, r);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);

    // нормаль края наружу
    vec2 q = abs(p) - hs + r;
    vec2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    n *= vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);

    // скос: e = 1 у самой кромки, 0 на плоском стекле
    float bezel = clamp(min(hs.x, hs.y) * 0.5, 8.0, 24.0);
    float e = 1.0 - clamp(-d / bezel, 0.0, 1.0);
    float lensK = clamp(min(hs.x, hs.y) / 40.0, 0.45, 1.0);   // маленьким плиткам — мягче

    vec2 toLight = normalize(vec2(-0.3, -1.0));
    float facing = dot(n, toLight);

    // блик: тонкая линия по кромке и мягкое свечение вдоль скоса
    float line = smoothstep(-1.7, -0.5, d) * (1.0 - smoothstep(-0.5, 0.4, d));
    float spec = line * (0.22 + 1.1 * pow(max(facing, 0.0), 2.0) + 0.55 * pow(max(-facing, 0.0), 3.0));
    float glow = pow(e, 3.0) * (0.05 + 0.16 * max(facing, 0.0)) + pow(e, 8.0) * 0.06;

    if (hasWall > 0.5) {
        vec2 sp = origin + qt_TexCoord0 * area;
        // смещение: у кромки фон берётся снаружи, к середине — на месте
        float m = 34.0 * lensK * pow(e, 2.6);
        vec2 off = n * m;
        float blur = frost * frost * 18.0 + frost * 4.0 + e * 1.5;
        vec3 col = backdrop(sp + off, blur);
        // дисперсия на скосе: красный и синий смещены чуть по-разному
        if (e > 0.02) {
            float lod = lodBias(blur);
            float cr = texture(source, wallUv(sp + off * 1.12), lod).r;
            float cb = texture(source, wallUv(sp + off * 0.88), lod).b;
            float k = smoothstep(0.15, 0.7, e) * 0.85;
            col.r = mix(col.r, cr, k);
            col.b = mix(col.b, cb, k);
        }
        // стекло чуть ярче и сочнее фона
        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(vec3(luma), col, 1.12) * 1.04 + 0.015;
        // тонировка темой и молочная дымка матовости
        col = mix(col, tint.rgb, tint.a);
        col = mix(col, vec3(1.0), frost * mix(0.06, 0.12, lightBg));
        col += vec3(spec * 0.85 + glow);
        fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * inside * strength * qt_Opacity;
    } else {
        float a = clamp(spec * 0.85 + glow * 0.9 + frost * 0.04, 0.0, 1.0) * mix(1.0, 0.8, lightBg);
        fragColor = vec4(a, a, a, a) * inside * strength * qt_Opacity;
    }
}
