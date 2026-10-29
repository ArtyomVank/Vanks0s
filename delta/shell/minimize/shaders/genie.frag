#version 440
// Снимок окна для «джинна»: в горлышке воронки окно светлеет и тает, у самого
// значка гаснет полностью, чтобы не было шва.

layout(location = 0) in vec2 coord;
layout(location = 1) in float squeeze;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float edge;
    vec4 src;
    vec4 dst;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, coord);
    // чем уже, тем светлее — блик в горлышке
    float glow = smoothstep(0.55, 1.0, squeeze) * 0.18;
    c.rgb = min(c.rgb + glow * c.a, vec3(c.a));
    // часть, уже ушедшая в значок, тает; в конце — всё
    float fade = (1.0 - smoothstep(0.88, 1.0, squeeze) * smoothstep(0.35, 0.8, progress) * 0.85)
               * (1.0 - smoothstep(0.84, 1.0, progress));
    fragColor = c * qt_Opacity * fade;
}
