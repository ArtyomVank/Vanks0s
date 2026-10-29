#version 440
// Выход из первой настройки: всё исчезает от центра к краям, по краю дыры
// бежит светящееся кольцо и чуть преломляет то, что ещё осталось.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float hole;     // 0 — всё на месте, 1 — исчезло целиком
    vec2 res;
    vec4 ring;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 c = res * 0.5;
    float maxR = length(c) + 160.0;
    float R = hole * maxR;
    vec2 v = px - c;
    float dist = length(v);
    float d = dist - R;
    vec2 n = dist > 0.0 ? v / dist : vec2(0.0);
    // преломление у кольца: тянем картинку наружу
    vec2 off = n * exp(-abs(d) / 50.0) * 28.0 * step(0.0005, hole);
    vec4 s = texture(source, (px + off) / res);
    float keep = smoothstep(-40.0, 30.0, d);
    float glow = exp(-abs(d) / 26.0) * step(0.0005, hole) * (1.0 - smoothstep(0.75, 1.0, hole));
    fragColor = (s * keep + vec4(ring.rgb, 1.0) * ring.a * glow) * qt_Opacity;
}
