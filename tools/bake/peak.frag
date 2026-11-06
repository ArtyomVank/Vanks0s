#version 440
// Запекание обоев «Вершина» (wallpaper/super/peak.jpg и peak-mask.png):
// гранитный пик в лучах рассвета, снег, долина. Тяжёлый — трассировка лучей
// по карте высот с тенями, поэтому считается один раз, а живыми обои делает
// лёгкий wallpaper/super/peak.frag. Пересобрать: tools/bake/bake.sh.
//   pass 0 — цвет; pass 1 — маски: R — небо, G — высота точки (рассвет
//   спускается с вершины), B — даль (туман и облака).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float pass;
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p, int oct) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 9; i++) {
        if (i >= oct) break;
        s += a * vnoise(p);
        p = mat2(1.6, 1.2, -1.2, 1.6) * p + vec2(3.1, 1.7);
        a *= 0.5;
    }
    return s;
}
// острые гребни и промоины
float ridged(vec2 p, int oct) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 9; i++) {
        if (i >= oct) break;
        float n = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
        s += a * n * n;
        p = mat2(1.7, 1.1, -1.1, 1.7) * p + vec2(5.3, 2.9);
        a *= 0.5;
    }
    return s;
}
float smax(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(a, b, h) + k * h * (1.0 - h);
}

// игла: конус с крутыми гранями, промоины сверху вниз
float needle(vec2 p, vec2 c, float H, float k, int oct) {
    vec2 d = p - c;
    // гранёная пирамида, а не гладкий конус: грани в нескольких направлениях
    float fac = max(max(abs(dot(d, vec2(0.95, 0.31))), abs(dot(d, vec2(-0.62, 0.78)))), dot(d, vec2(0.18, -0.98)));
    float r = mix(length(d * vec2(1.0, 1.3)), fac, 0.65);
    // промоины сверху вниз и контрфорсы
    float g = ridged(vec2(d.x * 3.0 + d.y * 1.3, r * 0.7 + c.x * 1.7), oct);
    float b = fbm(d * 1.4 + c, oct);
    return H - k * r + (g - 0.45) * 0.95 * smoothstep(0.0, 0.9, r) + (b - 0.5) * 0.6 * smoothstep(0.2, 1.5, r);
}

float terrain(vec2 p, int oct) {
    // главный пик и соседние иглы справа и слева
    float h = needle(p, vec2(0.0, 7.5), 7.0, 2.8, oct);
    h = smax(h, needle(p, vec2(2.0, 8.6), 4.2, 3.0, oct), 0.25);
    h = smax(h, needle(p, vec2(2.7, 9.0), 3.8, 3.1, oct), 0.2);
    h = smax(h, needle(p, vec2(3.4, 8.8), 3.3, 3.1, oct), 0.2);
    h = smax(h, needle(p, vec2(4.2, 9.6), 2.9, 2.8, oct), 0.2);
    h = smax(h, needle(p, vec2(5.2, 10.4), 2.6, 2.5, oct), 0.2);
    h = smax(h, needle(p, vec2(-1.7, 8.3), 3.9, 2.6, oct), 0.3);
    h = smax(h, needle(p, vec2(-3.2, 9.5), 3.0, 2.2, oct), 0.3);
    h = smax(h, needle(p, vec2(-5.0, 10.5), 2.4, 2.0, oct), 0.3);
    // массив под пиками
    float base = 2.4 * exp(-pow((p.y - 8.2) / 2.2, 2.0)) * (0.7 + 0.6 * fbm(p * 0.35, 3)) * (1.0 - 0.08 * max(p.x, 0.0))
               + 0.3 * ridged(p * 0.9, oct) - 0.4;
    h = smax(h, base, 0.6);
    // дальний хребет за пиками — в дымке до горизонта
    float far = (2.2 + 1.6 * ridged(vec2(p.x * 0.25, 1.3), 4)) * smoothstep(13.0, 19.0, p.y) + 0.4 * ridged(p * 0.5, oct) - 0.6;
    h = max(h, far);
    // гряда справа посередине
    float mid = 1.6 * exp(-pow((p.y - 6.0) / 1.4, 2.0)) * smoothstep(1.5, 4.5, p.x) * (0.6 + 0.6 * ridged(p * 0.7 + 2.0, oct));
    h = max(h, mid - 0.2);
    // долина с ледником
    float valley = -0.5 + 0.3 * fbm(p * 0.5, 3) + 0.1 * ridged(p * 2.0, oct);
    h = max(h, valley);
    // ближний хребет: поднимается влево, в снегу
    float fg = (1.5 - 0.22 * p.x) * exp(-pow((p.y - 1.6) / 1.0, 2.0)) * (0.6 + 0.5 * fbm(p * 0.8 + 3.0, oct))
             + 0.18 * ridged(p * 2.2 + 7.0, oct) * exp(-pow((p.y - 1.6) / 1.2, 2.0));
    h = max(h, fg - 0.35);
    return h;
}

const vec3 SUN = vec3(-0.88, 0.28, -0.25);

vec3 sky(vec3 rd) {
    float y = max(rd.y, 0.0);
    vec3 top = vec3(0.012, 0.045, 0.17);
    vec3 hor = vec3(0.26, 0.46, 0.70);
    vec3 col = mix(hor, top, pow(y, 0.55));
    // тёплая полоса у горизонта со стороны солнца
    float s = max(dot(normalize(vec3(rd.x, 0.0, rd.z)), normalize(vec3(SUN.x, 0.0, SUN.z))), 0.0);
    col += vec3(0.55, 0.28, 0.22) * pow(s, 3.0) * exp(-y * 9.0) * 0.6;
    return col;
}

float march(vec3 ro, vec3 rd, out vec3 pos) {
    float t = 0.05;
    for (int i = 0; i < 420; i++) {
        vec3 p = ro + rd * t;
        float h = terrain(p.xz, 6);
        float d = p.y - h;
        if (d < 0.0008 * t) { pos = p; return t; }
        if (t > 60.0) break;
        t += max(0.004, d * 0.3);
    }
    pos = ro + rd * t;
    return -1.0;
}

float shadow(vec3 p) {
    float s = 1.0, t = 0.03;
    for (int i = 0; i < 90; i++) {
        vec3 q = p + normalize(SUN) * t;
        float d = q.y - terrain(q.xz, 4);
        s = min(s, 12.0 * d / t);
        if (s < 0.0 || q.y > 7.0) break;
        t += max(0.02, d * 0.5);
    }
    return clamp(s, 0.0, 1.0);
}

vec3 normalBig(vec2 p, float t) {
    float e = 0.03 + 0.002 * t;
    float hx = terrain(p + vec2(e, 0.0), 3) - terrain(p - vec2(e, 0.0), 3);
    float hz = terrain(p + vec2(0.0, e), 3) - terrain(p - vec2(0.0, e), 3);
    return normalize(vec3(-hx, 2.0 * e, -hz));
}
vec3 normalAt(vec2 p, float t) {
    float e = 0.0015 + 0.0006 * t;
    float hx = terrain(p + vec2(e, 0.0), 8) - terrain(p - vec2(e, 0.0), 8);
    float hz = terrain(p + vec2(0.0, e), 8) - terrain(p - vec2(0.0, e), 8);
    return normalize(vec3(-hx, 2.0 * e, -hz));
}

void main() {
    vec2 q = qt_TexCoord0;
    vec2 uv = (q * 2.0 - 1.0) * vec2(res.x / res.y, -1.0);
    vec3 ro = vec3(-0.4, 1.9, -2.2);
    vec3 ta = vec3(0.4, 3.2, 7.5);
    vec3 fw = normalize(ta - ro);
    vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
    vec3 up = cross(fw, rt);
    vec3 rd = normalize(uv.x * rt + uv.y * up + 1.6 * fw);

    vec3 pos;
    float t = march(ro, rd, pos);
    if (pass > 0.5) {
        float skyMask = t < 0.0 ? 1.0 : 0.0;
        float height = t < 0.0 ? 1.0 : clamp(pos.y / 7.0, 0.0, 1.0);
        float far = t < 0.0 ? 1.0 : clamp(t / 25.0, 0.0, 1.0);
        fragColor = vec4(skyMask, height, far, 1.0);
        return;
    }

    vec3 L = normalize(SUN);
    vec3 col;
    if (t < 0.0) {
        col = sky(rd);
    } else {
        vec3 n = normalAt(pos.xz, t);
        // свет — по крупным граням (иначе мелкий рельеф делает всё ровно-бежевым),
        // мелкий рельеф только чуть добавляет
        vec3 nb = normalize(mix(n, normalBig(pos.xz, t), 0.7));
        // гранит: тёплый серый с прожилками; снег на пологом
        float v = fbm(pos.xz * 3.0 + pos.y * 2.0, 5);
        vec3 rock = mix(vec3(0.36, 0.30, 0.27), vec3(0.62, 0.54, 0.48), v);
        rock *= 0.85 + 0.3 * ridged(vec2(pos.x * 6.0 + pos.z * 2.0, pos.y * 1.5), 4);
        float snow = smoothstep(0.62, 0.86, nb.y + 0.35 * (fbm(pos.xz * 4.0, 4) - 0.5));
        snow *= 1.0 - smoothstep(4.6, 5.8, pos.y);
        vec3 alb = mix(rock, vec3(0.92, 0.93, 0.97), snow);

        float sh = shadow(pos + n * 0.01);
        float dif = pow(max(dot(nb, L), 0.0), 0.8) * sh;
        // солнце только встаёт: свет на вершинах, низ ещё в холодной тени
        dif *= mix(0.12, 1.0, smoothstep(0.7, 3.0, pos.y));
        vec3 sun = vec3(1.0, 0.40, 0.13) * 4.6;
        vec3 amb = vec3(0.09, 0.13, 0.30) * (0.55 + 0.45 * nb.y);
        // розовый отсвет неба на теневых гранях
        vec3 bounce = vec3(0.26, 0.11, 0.14) * max(dot(nb, -L * vec3(1.0, 0.0, 1.0)), 0.0) * 0.5;
        float ao = clamp(0.4 + 0.6 * (pos.y - terrain(pos.xz, 2) + 0.6), 0.4, 1.0);
        col = alb * (sun * dif + amb * ao + bounce);
        // дымка вдали
        float fog = 1.0 - exp(-max(t - 6.0, 0.0) * 0.06);
        col = mix(col, vec3(0.24, 0.36, 0.58), fog * 0.85);
        // дымка в низинах
        col = mix(col, vec3(0.62, 0.62, 0.78), (1.0 - smoothstep(0.1, 0.9, pos.y)) * 0.35 * smoothstep(5.0, 10.0, t));
    }
    // тон и гамма
    col = 1.0 - exp(-col * 0.85);
    col = pow(col, vec3(1.0 / 2.2));
    // гамма разбавляет рассветный оранжевый до бежевого — возвращаем насыщенность
    col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, t < 0.0 ? 1.2 : 1.75);
    col = clamp((col - 0.5) * 1.1 + 0.5, 0.0, 1.0);
    fragColor = vec4(col, 1.0);
}
