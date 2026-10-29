#version 440
// Первая настройка: капли стекаются с краёв экрана к центру и разливаются
// стеклом на весь экран (card — весь экран), по стеклу медленно плывёт сияние
// акцента. progress 0 — капли за краями, 1 — экран залит.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float time;
    float radius;
    float dimAmount;
    vec2 res;
    vec4 card;      // x, y, w, h в пикселях
    vec4 glass;     // цвет карточки
    vec4 accent;
    vec4 dim;       // затемнение фона
};

float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
float hash(float n) { return fract(sin(n) * 43758.5453); }

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 c = card.xy + card.zw * 0.5;

    float grow = smoothstep(0.30, 1.0, progress);
    vec2 hb = card.zw * 0.5 * grow;
    float d = sdBox(px - c, hb, min(radius, min(hb.x, hb.y)));

    // капли: стартуют за краем экрана по своему лучу из центра
    float tint = 0.0;
    for (int i = 0; i < 16; i++) {
        float fi = float(i);
        float a = fi / 16.0 * 6.28318 + hash(fi) * 0.5;
        vec2 dir = vec2(cos(a), sin(a));
        vec2 tEdge = (res * 0.5 + 120.0) / max(abs(dir), vec2(1e-3));
        vec2 start = res * 0.5 + dir * min(tEdge.x, tEdge.y);
        float delay = hash(fi + 7.0) * 0.28;
        float k = clamp((progress - delay) / (0.82 - delay), 0.0, 1.0);
        k = k * k * (3.0 - 2.0 * k);
        vec2 wob = vec2(sin(time * 1.3 + fi), cos(time * 1.1 + fi * 1.7)) * 26.0 * (1.0 - k);
        vec2 p = mix(start, c, k) + wob;
        float r = mix(70.0 + hash(fi + 3.0) * 90.0, 6.0, k);
        float bd = length(px - p) - r;
        tint += exp(-max(bd, 0.0) / 60.0) * (1.0 - k);
        d = smin(d, bd, 110.0 * (1.0 - 0.5 * grow));
    }

    float fill = 1.0 - smoothstep(-1.2, 1.2, d);
    // карточка: стекло с лёгким переливом акцента у краёв и в каплях
    float edge = exp(-abs(d) / 5.0);
    vec2 uv = (px - c) / max(card.zw, vec2(1.0));
    float sheen = 0.5 + 0.5 * sin(time * 0.7 + uv.x * 3.0 - uv.y * 2.0);
    // сияние: два мягких пятна акцента медленно гуляют по экрану
    vec2 q = px / res;
    vec2 a1 = vec2(0.25 + 0.12 * sin(time * 0.21), 0.30 + 0.10 * cos(time * 0.17));
    vec2 a2 = vec2(0.78 + 0.10 * cos(time * 0.19), 0.72 + 0.12 * sin(time * 0.23));
    float aur = exp(-dot(q - a1, q - a1) * 6.0) + 0.8 * exp(-dot(q - a2, q - a2) * 5.0);
    vec3 cc = mix(glass.rgb, accent.rgb, 0.06 + 0.20 * clamp(tint, 0.0, 1.0) + 0.04 * sheen + 0.22 * aur * grow);
    vec4 cardC = vec4(cc, 1.0) * glass.a;

    // фон: затемнение и мягкое сияние вокруг карточки
    float halo = exp(-max(d, 0.0) / 220.0) * 0.30 * progress;
    vec4 back = vec4(dim.rgb, 1.0) * dim.a * dimAmount + vec4(accent.rgb, 1.0) * halo * 0.5;

    vec4 col = back * (1.0 - fill) + cardC * fill;
    col += vec4(accent.rgb, 1.0) * edge * (0.55 + 0.25 * sheen) * smoothstep(0.0, 0.2, progress);
    fragColor = col * qt_Opacity;
}
