#version 440
// Снимок окна для «джинна»; у самого значка гаснет, чтобы не было шва.

layout(location = 0) in vec2 coord;
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
    float fade = 1.0 - smoothstep(0.86, 1.0, progress);
    fragColor = texture(source, coord) * qt_Opacity * fade;
}
