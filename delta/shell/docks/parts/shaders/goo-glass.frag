#version 440
// «Жидкость» доков в стиле «Жидкое стекло» (Goo с glass): та же фигура, что
// в goo.frag (полоска, капля, тело, выпуклость — слиты мягким минимумом), но
// залита не цветом, а линзой, как sheen.frag: в середине чистые обои, у края
// фон изгибается (берётся снаружи), на скосе дисперсия, по кромке тонкий
// блик. Нормаль края — из градиента расстояния, поэтому стекло повторяет
// форму и при нажатии, и при выпуклости под курсором, и при появлении.
// Цвет fill (акцент капли → тон стекла) ложится поверх линзы с его альфой.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;
    vec4 band;
    vec4 drop;
    vec4 body;
    float bodyR;
    float k;
    vec4 fill;
    float glow;
    vec4 drop2;
    vec4 stroke;
    float strokeW;
    // стекло
    float frost;        // матовость 0…1
    float lightBg;      // 1 — светлая тема
    float hasWall;      // 1 — обои загружены
    vec2 origin;        // левый верхний угол элемента на экране, px
    vec4 wallRect;      // где на экране обои
    float bezel;        // ширина скоса, px
};

layout(binding = 1) uniform sampler2D source;

float sdBox(vec2 p, vec4 r, float rad) {
    if (r.z <= 0.5 || r.w <= 0.5) return 1e5;
    vec2 hs = r.zw * 0.5;
    rad = min(rad, min(hs.x, hs.y));
    vec2 q = abs(p - (r.xy + hs)) - hs + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}
float sdEllipse(vec2 p, vec4 d) {
    if (d.z <= 0.5 || d.w <= 0.5) return 1e5;
    vec2 q = (p - d.xy) / d.zw;
    return (length(q) - 1.0) * min(d.z, d.w);
}
float smin(float a, float b, float kk) {
    if (kk <= 0.0) return min(a, b);
    float h = clamp(0.5 + 0.5 * (b - a) / kk, 0.0, 1.0);
    return mix(b, a, h) - kk * h * (1.0 - h);
}
float shape(vec2 p) {
    float bandR = min(band.z, band.w) * 0.5;
    float d = smin(sdBox(p, band, bandR), sdEllipse(p, drop), k);
    d = smin(d, sdBox(p, body, bodyR), k);
    return smin(d, sdEllipse(p, drop2), k);
}

vec2 wallUv(vec2 sp) { return clamp((sp - wallRect.xy) / wallRect.zw, vec2(0.001), vec2(0.999)); }
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
    vec2 p = qt_TexCoord0 * area;
    float d = shape(p);
    float a = clamp(0.5 - d, 0.0, 1.0);
    float halo = glow * exp(-max(d, 0.0) / 9.0) * (1.0 - a) * 0.55;
    if (a <= 0.0) {
        fragColor = vec4(fill.rgb * halo, halo) * qt_Opacity;
        return;
    }

    // нормаль наружу — по градиенту расстояния
    float h = 1.0;
    vec2 g = vec2(shape(p + vec2(h, 0.0)) - shape(p - vec2(h, 0.0)),
                  shape(p + vec2(0.0, h)) - shape(p - vec2(0.0, h)));
    vec2 n = length(g) > 1e-4 ? normalize(g) : vec2(0.0, -1.0);
    float e = 1.0 - clamp(-d / max(4.0, bezel), 0.0, 1.0);

    vec2 toLight = normalize(vec2(-0.3, -1.0));
    float facing = dot(n, toLight);
    float line = smoothstep(-1.7, -0.5, d) * (1.0 - smoothstep(-0.5, 0.4, d));
    float spec = line * (0.22 + 1.1 * pow(max(facing, 0.0), 2.0) + 0.55 * pow(max(-facing, 0.0), 3.0));
    float sheen = pow(e, 3.0) * (0.05 + 0.16 * max(facing, 0.0)) + pow(e, 8.0) * 0.06;

    vec3 col;
    float alpha;
    if (hasWall > 0.5) {
        vec2 sp = origin + p;
        float lensK = clamp(bezel / 20.0, 0.45, 1.0);
        vec2 off = n * 34.0 * lensK * pow(e, 2.6);
        float blur = frost * frost * 18.0 + frost * 4.0 + e * 1.5;
        col = backdrop(sp + off, blur);
        if (e > 0.02) {
            float lod = lodBias(blur);
            float kk = smoothstep(0.15, 0.7, e) * 0.85;
            col.r = mix(col.r, texture(source, wallUv(sp + off * 1.12), lod).r, kk);
            col.b = mix(col.b, texture(source, wallUv(sp + off * 0.88), lod).b, kk);
        }
        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(vec3(luma), col, 1.12) * 1.04 + 0.015;
        col = mix(col, fill.rgb, fill.a);
        col = mix(col, vec3(1.0), frost * mix(0.06, 0.12, lightBg));
        col += vec3(spec * 0.85 + sheen);
        alpha = 1.0;
    } else {
        // обоев нет: тонированное стекло (под ним — размытие Hyprland) и блик
        float l = spec * 0.85 + sheen * 0.9;
        alpha = fill.a + l * (1.0 - fill.a);
        col = (fill.rgb * fill.a + vec3(l)) / max(alpha, 1e-3);
    }
    col = clamp(col, 0.0, 1.0);

    // обводка (режим правки): полоса strokeW px внутрь от края
    float sa = stroke.a * (1.0 - clamp(0.5 - (d + strokeW), 0.0, 1.0));
    col = mix(col, stroke.rgb, sa);
    alpha = max(alpha, sa);

    float outA = alpha * a;
    fragColor = vec4(col * outA + fill.rgb * halo, outA + halo) * qt_Opacity;
}
