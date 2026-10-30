#version 440
// «Желе»: копия окна на сетке. Точка, за которую держат окно (grab), стоит
// на месте, остальные отстают тем сильнее, чем дальше от неё: смещения
// пяти «колец» по расстоянию (o1…o5) считает пружинами Jelly.qml, здесь
// они только плавно смешиваются. Сетка шире окна на рамку (border) и тень
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

vec2 ring(float i) {
    if (i < 0.5) return vec2(0.0);
    if (i < 1.5) return o12.xy;
    if (i < 2.5) return o12.zw;
    if (i < 3.5) return o34.xy;
    if (i < 4.5) return o34.zw;
    return o5.xy;
}

void main() {
    float pad = border + shade;
    vec2 local = qt_MultiTexCoord0 * (rect.zw + 2.0 * pad) - vec2(pad);
    coord = local / rect.zw;
    float r = clamp(length(local - grab) / max(reach, 1.0), 0.0, 1.0) * 5.0;
    float i = floor(min(r, 4.999));
    float f = smoothstep(0.0, 1.0, r - i);
    vec2 off = mix(ring(i), ring(i + 1.0), f);
    gl_Position = qt_Matrix * vec4(rect.xy + local + off, 0.0, 1.0);
}
