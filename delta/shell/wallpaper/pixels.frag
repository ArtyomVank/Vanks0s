#version 440
// Смена обоев «по пикселям» (Wallpaper.qml): новая картинка проступает
// поверх старой квадратиками в случайном порядке. Квадратик появляется
// крупным пикселем (цвет из его середины) с лёгкой вспышкой и через
// мгновение становится резким. Квадратики расходятся волной от origin —
// там, где был курсор (Wallpaper.qml), — с небольшим разбросом.
// После правки: tools/delta-shaders.sh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;          // размер, px
    float cell;         // сторона квадратика, px
    float progress;     // 0 — старые обои, 1 — новые целиком
    vec2 origin;        // откуда идёт волна, 0…1 (курсор; иначе середина)
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 px = qt_TexCoord0 * area;
    vec2 id = floor(px / cell);
    vec2 centre = (id + 0.5) * cell / area;
    // очередь квадратика: волна от origin (до самого дальнего угла — 1) и разброс
    vec2 aspect = vec2(area.x / area.y, 1.0);
    float far = length(max(origin, 1.0 - origin) * aspect);
    float d = length((centre - origin) * aspect) / max(far, 0.001);
    float order = clamp(hash(id) * 0.4 + d * 0.6, 0.0, 1.0);
    float t = progress * 1.35 - order;          // > 0 — квадратик уже идёт
    float shown = smoothstep(0.0, 0.08, t);
    float sharp = smoothstep(0.1, 0.32, t);
    if (shown <= 0.0) { fragColor = vec4(0.0); return; }
    vec4 blocky = texture(source, centre);
    vec4 fine = texture(source, qt_TexCoord0);
    vec4 c = mix(blocky, fine, sharp);
    // вспышка только что появившегося квадратика
    float flash = (1.0 - sharp) * shown * 0.18;
    c.rgb += flash * c.a;
    fragColor = c * shown * qt_Opacity;
}
