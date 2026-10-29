#version 440
// «Жидкость» доков и меню: капля, полоска края и тело, слитые вместе.
//
// Каждая фигура — функция расстояния (SDF) в пикселях элемента. Мягкий
// минимум (smin) сливает их так, что между краем и каплей тянется «шейка»,
// а капля растекается в тело без шва. Фигура с нулевым размером выключена.
// Вторая капля (drop2) — выпуклость «желе» под курсором у открытой панели.
// stroke — тонкая обводка по краю всей фигуры (у панели в покое), чтобы
// выпуклости и вмятины обводились вместе с телом, без отдельного Rectangle.
// Сглаживание края — по самому расстоянию (1 px), поэтому чётко на любом масштабе.
// После правки: tools/delta-shaders.sh (собирает .qsb).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;      // размер элемента, px
    vec4 band;      // полоска края: x, y, ширина, высота
    vec4 drop;      // капля: центр x, y, радиус x, радиус y
    vec4 body;      // тело: x, y, ширина, высота
    float bodyR;    // скругление тела
    float k;        // мягкость слияния, px
    vec4 fill;      // цвет (без премультипликации)
    float glow;     // свечение вокруг (0…1)
    vec4 drop2;     // вторая капля: центр x, y, радиус x, радиус y
    vec4 stroke;    // цвет обводки (без премультипликации), a = 0 — нет обводки
    float strokeW;  // толщина обводки, px
};

float sdBox(vec2 p, vec4 r, float rad) {
    if (r.z <= 0.5 || r.w <= 0.5) return 1e5;
    vec2 hs = r.zw * 0.5;
    rad = min(rad, min(hs.x, hs.y));
    vec2 q = abs(p - (r.xy + hs)) - hs + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

// эллипс — приближённо: растягиваем пространство, расстояние домножаем на меньший радиус
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

void main() {
    vec2 p = qt_TexCoord0 * area;
    float bandR = min(band.z, band.w) * 0.5;
    float d = smin(sdBox(p, band, bandR), sdEllipse(p, drop), k);
    d = smin(d, sdBox(p, body, bodyR), k);
    d = smin(d, sdEllipse(p, drop2), k);

    float a = clamp(0.5 - d, 0.0, 1.0);
    float halo = glow * exp(-max(d, 0.0) / 9.0) * (1.0 - a) * 0.55;
    float alpha = fill.a * a + halo;
    vec3 rgb = fill.rgb * alpha;
    // обводка: полоса strokeW px внутрь от края, поверх заливки
    float sa = stroke.a * (a - clamp(0.5 - (d + strokeW), 0.0, 1.0));
    rgb = rgb * (1.0 - sa) + stroke.rgb * sa;
    alpha = alpha * (1.0 - sa) + sa;
    fragColor = vec4(rgb, alpha) * qt_Opacity;
}
