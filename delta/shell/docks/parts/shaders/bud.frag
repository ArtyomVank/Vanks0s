#version 440
// Острова верхнего дока в режиме плиток выходят из среднего каплей:
// средний остров (mid) и до четырёх боковых (s0…s3) — «пилюли», слитые мягким
// минимумом. Пока боковой рядом со средним, между ними тянется шейка; к концу
// выхода k падает до нуля, и фигура совпадает с обычными островами.
// Сам средний остров рисует его Rectangle (со своим бликом), поэтому внутри
// него шейдер ничего не кладёт — стекло не темнеет вдвое.
// После правки: tools/delta-shaders.sh (собирает .qsb).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;      // размер элемента, px
    vec4 mid;       // средний остров: x, y, ширина, высота
    vec4 s0;        // боковые острова (нулевой размер — нет острова)
    vec4 s1;
    vec4 s2;
    vec4 s3;
    float k;        // мягкость слияния, px
    vec4 fill;      // цвет (без премультипликации)
    vec4 stroke;    // цвет обводки, a = 0 — нет обводки
    float strokeW;
};

float pill(vec2 p, vec4 r) {
    if (r.z <= 0.5 || r.w <= 0.5) return 1e5;
    vec2 hs = r.zw * 0.5;
    float rad = min(hs.x, hs.y);
    vec2 q = abs(p - (r.xy + hs)) - hs + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

float smin(float a, float b, float kk) {
    if (kk <= 0.0) return min(a, b);
    float h = clamp(0.5 + 0.5 * (b - a) / kk, 0.0, 1.0);
    return mix(b, a, h) - kk * h * (1.0 - h);
}

void main() {
    vec2 p = qt_TexCoord0 * area;
    float dm = pill(p, mid);
    float d = smin(dm, pill(p, s0), k);
    d = smin(d, pill(p, s1), k);
    d = smin(d, pill(p, s2), k);
    d = smin(d, pill(p, s3), k);

    float a = clamp(0.5 - d, 0.0, 1.0);
    float alpha = fill.a * a;
    vec3 rgb = fill.rgb * alpha;
    float sa = stroke.a * (a - clamp(0.5 - (d + strokeW), 0.0, 1.0));
    rgb = rgb * (1.0 - sa) + stroke.rgb * sa;
    alpha = alpha * (1.0 - sa) + sa;
    fragColor = vec4(rgb, alpha) * (1.0 - clamp(0.5 - dm, 0.0, 1.0)) * qt_Opacity;
}
