#version 440
// «Желе»: копия окна на сетке. Точка, за которую держат окно (grab), стоит
// на месте, остальные отстают тем сильнее, чем дальше от неё: смещения
// пяти «колец» по расстоянию (o1…o5) считает пружинами Jelly.qml, здесь
// через них проводится гладкая кривая (квадратичный B-сплайн): у smoothstep
// внутри каждого кольца была ступенька, и при сильном рывке окно гнулось
// лесенкой; кривая Катмулла — Рома перелетала и складывала окно у точки
// захвата, а B-сплайн не выходит за значения соседних колец. Сетка шире окна на рамку (border) и тень
// (shade) с каждой стороны — Hyprland рисует их снаружи окна, и копия тоже;
// тень гнётся вместе с окном и не отстаёт от него.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 coord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 rect;          // окно без рамки: x, y, ширина, высота (в координатах слоя)
    vec2 grab;          // точка захвата от левого верхнего угла, px
    float reach;        // расстояние до самого дальнего угла, px
    float radius;       // скругление углов, px
    float border;       // рамка, px
    float shade;        // тень за рамкой, px
    vec4 borderColor;
    vec4 o12;           // смещения колец 1 и 2
    vec4 o34;           // 3 и 4
    vec4 o5;            // 5 (xy)
};

// Соседние кольца расходятся не больше чем на 0,6 ширины кольца: при резком
// рывке пружины отстают на сотни пикселей, и без этого сетка у точки захвата
// заворачивалась бы складкой. (Без массивов: Qt берёт и старый GLSL.)
vec2 r1, r2, r3, r4, r5;
vec2 limit(vec2 d, float m) { float l = length(d); return l > m ? d * (m / l) : d; }
void fillRings(float m) {
    r1 = limit(o12.xy, m);
    r2 = r1 + limit(o12.zw - r1, m);
    r3 = r2 + limit(o34.xy - r2, m);
    r4 = r3 + limit(o34.zw - r3, m);
    r5 = r4 + limit(o5.xy - r4, m);
}
vec2 ring(float i) {
    // «−1» — отражение первого кольца: точка захвата остаётся ровно на месте
    if (i < -0.5) return -r1;
    if (i < 0.5) return vec2(0.0);
    if (i < 1.5) return r1;
    if (i < 2.5) return r2;
    if (i < 3.5) return r3;
    if (i < 4.5) return r4;
    return r5;
}

void main() {
    float pad = border + shade;
    vec2 local = qt_MultiTexCoord0 * (rect.zw + 2.0 * pad) - vec2(pad);
    coord = local / rect.zw;
    fillRings(max(reach, 1.0) / 5.0 * 0.6);
    float r = clamp(length(local - grab) / max(reach, 1.0), 0.0, 1.0) * 5.0;
    float k = floor(r + 0.5);
    float t = r + 0.5 - k;
    vec2 off = 0.5 * (1.0 - t) * (1.0 - t) * ring(k - 1.0)
             + (0.5 + t - t * t) * ring(k)
             + 0.5 * t * t * ring(min(k + 1.0, 5.0));
    gl_Position = qt_Matrix * vec4(rect.xy + local + off, 0.0, 1.0);
}
