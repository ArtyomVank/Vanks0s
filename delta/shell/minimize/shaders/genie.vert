#version 440
// «Джинн»: снимок окна перетекает в значок дока.
//
// Сетка (GridMesh) натянута на снимок. Считаем в «каноническом» виде, где док
// снизу (ось along — к доку), и поворачиваем обратно в конце.
//   1. Между окном и значком встаёт воронка: её бока — S-образная кривая
//      (smoothstep) от ширины окна у его дальнего края до ширины значка.
//   2. Окно скользит по воронке к значку, ускоряясь; ряды у дока стартуют
//      чуть раньше. Ширина каждой точки берётся из воронки на её ТЕКУЩЕЙ
//      высоте — поэтому бока окна изгибаются, а не сужаются трапецией.
// progress: 0 — окно, 1 — значок. После правки: tools/delta-shaders.sh.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 coord;
layout(location = 1) out float squeeze;   // 0 — ширина окна, 1 — ширина значка

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float edge;     // где док: 0 снизу, 1 сверху, 2 слева, 3 справа
    vec4 src;       // x, y, ширина, высота окна (в координатах элемента)
    vec4 dst;       // то же для значка
};

// в канонический вид (док снизу) и обратно
vec2 toC(vec2 p) {
    if (edge < 0.5) return p;
    if (edge < 1.5) return vec2(p.x, -p.y);
    if (edge < 2.5) return vec2(p.y, -p.x);
    return vec2(p.y, p.x);
}
vec2 fromC(vec2 c) {
    if (edge < 0.5) return c;
    if (edge < 1.5) return vec2(c.x, -c.y);
    if (edge < 2.5) return vec2(-c.y, c.x);
    return vec2(c.y, c.x);
}
// прямоугольник в каноническом виде: (левый, верхний, правый, нижний)
vec4 rectC(vec4 r) {
    vec2 a = toC(r.xy), b = toC(r.xy + r.zw);
    return vec4(min(a, b), max(a, b));
}

void main() {
    vec2 uv = qt_MultiTexCoord0;
    vec4 s = rectC(src);
    vec4 d = rectC(dst);
    vec2 c0 = toC(src.xy + uv * src.zw);   // точка в окне
    vec2 c1 = toC(dst.xy + uv * dst.zw);   // та же точка в значке

    // насколько ряд близок к доку (1 — край окна у дока)
    float row = clamp((c0.y - s.y) / max(1.0, s.w - s.y), 0.0, 1.0);
    // доля поперёк окна
    float across = clamp((c0.x - s.x) / max(1.0, s.z - s.x), 0.0, 1.0);

    // 1. воронка формируется; дальний край окна при этом чуть «наклоняется» к доку
    float funnel = smoothstep(0.0, 0.40, progress);
    // 2. скольжение: ряды у дока стартуют заметно раньше и с ускорением —
    //    окно вытягивается, будто его засасывает
    float sl = clamp((progress - 0.08 - 0.34 * (1.0 - row)) / 0.62, 0.0, 1.0);
    sl = sl * sl * (3.0 - 2.0 * sl);
    sl = mix(sl, sl * sl, 0.5);
    float y = mix(c0.y, c1.y, sl);
    // в начале дальний край чуть подтягивается (окно не стоит столбом)
    y += (1.0 - row) * (d.y - s.y) * 0.05 * funnel * (1.0 - sl);

    // ширина воронки на текущей высоте точки: горлышко сужается раньше,
    // бока выгибаются S-кривой
    float span = max(1.0, d.y - s.y);
    float f = clamp((y - s.y) / span, 0.0, 1.0);
    float w = smoothstep(0.0, 1.0, pow(f, 0.72)) * funnel;
    float left = mix(s.x, d.x, w);
    float right = mix(s.z, d.z, w);
    float x = mix(left, right, across);
    // лёгкое покачивание горлышка в середине пути
    x += sin(progress * 6.2832) * (1.0 - progress) * 6.0 * w * (1.0 - w) * 4.0;

    squeeze = w;
    coord = uv;
    gl_Position = qt_Matrix * vec4(fromC(vec2(x, y)), 0.0, 1.0);
}
