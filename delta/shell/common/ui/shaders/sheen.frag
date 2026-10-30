#version 440
// «Жидкое стекло» поверх подложки (Sheen.qml). Не плоская кромка, а толща:
//   • у края стекло скруглено, как линза: свет бликует на скосе, по самой
//     кромке — тонкий перелив радугой (дисперсия), под скосом — тень;
//   • источник света медленно ходит — блик переливается, как жидкость;
//   • матовость (frost): молочная дымка и зерно, как у матового стекла;
//   • капли: стекают вниз рывками (то держатся, то срываются), у каждой —
//     блик сверху, светлый серп снизу, тёмный ободок и влажный след.
// Цвет на выходе — с premultiplied alpha: белое светит, чёрное затеняет.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;          // размер, px
    float radius;       // скругление, px
    float strength;     // общая сила 0…1
    float frost;        // матовость 0…1
    float time;         // секунды
    float drops;        // 0 — без капель, 1 — с каплями
    float seed;         // у каждой панели свои капли
    float lightBg;      // 1 — светлая тема: тени слабее, блики мягче
};

float box(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float hash1(float n) { return fract(sin(n * 91.3458 + seed * 17.13) * 47453.5453); }

// одна капля: добавляет свет (x) и тень (y) в точке p
vec2 drop(vec2 p, float i, vec2 hs, float scale) {
    float sp = 0.10 + 0.12 * hash1(i * 3.1);              // как часто срывается
    float s = time * sp + hash1(i * 7.7) * 10.0;
    // рывками: стоит, потом быстро сползает на шаг
    float f = fract(s);
    float y01 = fract((floor(s) + smoothstep(0.55, 1.0, f)) * (0.17 + 0.1 * hash1(i * 5.3)) + hash1(i * 1.9));
    float r = scale * (0.6 + 0.6 * hash1(i * 2.3));
    vec2 c = vec2((hash1(i * 4.7) - 0.5) * 2.0 * (hs.x - r * 2.0),
                  mix(-hs.y - r * 3.0, hs.y + r * 3.0, y01));
    c.x += sin(y01 * 18.0 + i) * r * 0.35;                // путь чуть виляет
    vec2 d = p - c;
    // капля вытянута книзу, как под тяжестью
    vec2 e = d / vec2(r, r * (d.y > 0.0 ? 1.18 : 0.92));
    float l = length(e);
    float light = 0.0, shade = 0.0;
    if (l < 1.0) {
        float z = sqrt(1.0 - l * l);
        // блик сверху слева и светлый серп снизу (свет прошёл сквозь каплю)
        light += pow(max(0.0, 1.0 - length(e - vec2(-0.35, -0.45)) * 2.6), 2.0) * 0.95;
        light += smoothstep(0.35, 0.95, e.y) * smoothstep(1.0, 0.8, l) * 0.45;
        // тёмный ободок — край линзы
        shade += smoothstep(0.62, 1.0, l) * (1.0 - z) * 0.55;
        light += z * 0.05;
    }
    // мягкая тень под каплей
    shade += smoothstep(1.35, 1.0, l) * (1.0 - step(l, 1.0)) * 0.12;
    // влажный след выше капли: узкий, тает с расстоянием
    float trail = smoothstep(r * 0.28, 0.0, abs(d.x)) * step(d.y, 0.0) * exp(d.y / (r * 3.5));
    light += trail * 0.07;
    return vec2(light, shade);
}

void main() {
    vec2 hs = area * 0.5;
    vec2 p = qt_TexCoord0 * area - hs;
    float r = min(radius, min(hs.x, hs.y));
    float d = box(p, hs, r);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);

    // нормаль края (в плоскости)
    vec2 q = abs(p) - hs + r;
    vec2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    n *= vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);

    // скос-линза шириной w: профиль — четверть круга
    float w = clamp(min(hs.x, hs.y) * 0.32, 6.0, 22.0);
    float t = clamp(-d / w, 0.0, 1.0);                     // 0 — кромка, 1 — плоское стекло
    float slope = (1.0 - t) / max(0.05, sqrt(1.0 - (1.0 - t) * (1.0 - t)));
    vec3 N = normalize(vec3(n * min(slope, 6.0) * 0.55, 1.0));

    // свет медленно гуляет — блик переливается
    float a = -2.2 + 0.35 * sin(time * 0.23 + seed) + 0.15 * sin(time * 0.61);
    vec3 L = normalize(vec3(cos(a), sin(a), 0.85));
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(N, H), 0.0), 40.0);
    float back = pow(max(dot(N, normalize(vec3(-L.xy, 0.85) + vec3(0.0, 0.0, 1.0))), 0.0), 60.0) * 0.5;
    float fres = pow(1.0 - N.z, 1.5);

    float light = 0.0, shade = 0.0;
    light += (spec + back) * 0.9 * (1.0 - t * 0.6);
    light += fres * 0.20;
    // самая кромка: тонкая светлая линия
    light += smoothstep(-1.8, -0.6, d) * (1.0 - smoothstep(-0.6, 0.3, d)) * (0.28 + 0.5 * max(0.0, dot(n, normalize(vec2(L.x, L.y)))));
    // под скосом свет преломился — темнее (толща стекла)
    shade += smoothstep(0.55, 0.9, t) * (1.0 - smoothstep(0.9, 1.0, t)) * 0.10;
    // отблеск сверху на плоскости
    light += pow(1.0 - qt_TexCoord0.y, 5.0) * 0.07;

    // перелив по кромке: цвета радуги по направлению нормали
    vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (atan(n.y, n.x) / 6.2832 + time * 0.03 + vec3(0.0, 0.33, 0.67)));
    float disp = smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.25, 0.6, t)) * 0.10;

    // матовость: молочная дымка и мелкое зерно
    float grain = hash(floor(qt_TexCoord0 * area)) - 0.5;
    light += frost * (0.07 + 0.05 * grain);

    // капли
    if (drops > 0.5) {
        float scale = clamp(min(area.x, area.y) * 0.045, 4.0, 10.0);
        for (int i = 0; i < 5; i++) {
            vec2 k = drop(p, float(i) + 1.0, hs, scale);
            light += k.x;
            shade += k.y;
        }
    }

    shade *= mix(1.0, 0.5, lightBg);
    light *= mix(1.0, 0.75, lightBg);
    vec3 col = vec3(light) + rainbow * disp;
    float alpha = clamp(light + disp + shade, 0.0, 1.0);
    vec4 c = vec4(clamp(col, 0.0, 1.0), alpha) * strength * inside;
    fragColor = c * qt_Opacity;
}
