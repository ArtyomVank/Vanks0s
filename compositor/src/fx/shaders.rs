//! Шейдеры эффектов. Программы поверхностей (CLIP, GLASS) и рамка (DECOR)
//! компилирует Smithay — ему `#version` не нужен; остальные (raw) — `gl.rs`.

/// Шапка программы поверхности: те же варианты, что у встроенной в Smithay.
macro_rules! tex_head {
    () => {
        r#"
//_DEFINES_
#if defined(EXTERNAL)
#extension GL_OES_EGL_image_external : require
#endif
precision highp float;
#if defined(EXTERNAL)
uniform samplerExternalOES tex;
#else
uniform sampler2D tex;
#endif
uniform float alpha;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
"#
    };
}

/// Углы — суперэллипс со степенью 2.4, как rounding_power у прежней Delta.
macro_rules! sdf_box {
    () => {
        r#"
float sdBox(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    vec2 m = max(q, 0.0);
    float corner = m.x + m.y > 0.0 ? pow(pow(m.x, 2.4) + pow(m.y, 2.4), 1.0 / 2.4) : 0.0;
    return corner + min(max(q.x, q.y), 0.0) - r;
}
"#
    };
}

/// Поверхность окна со скруглёнными углами: прямоугольник окна в координатах
/// кадра (gl_FragCoord), так что поворот монитора и обрезка буфера неважны.
pub const CLIP: &str = concat!(
    tex_head!(),
    sdf_box!(),
    r#"
uniform vec4 clip_rect;
uniform float clip_radius;

void main() {
    vec4 color = texture2D(tex, v_coords);
#if defined(NO_ALPHA)
    color = vec4(color.rgb, 1.0);
#endif
    vec2 c = 0.5 * (clip_rect.xy + clip_rect.zw);
    vec2 hs = 0.5 * (clip_rect.zw - clip_rect.xy);
    float d = sdBox(gl_FragCoord.xy - c, hs, clip_radius);
    color *= 1.0 - smoothstep(-0.6, 0.6, d);
    color *= alpha;
#if defined(DEBUG_FLAGS)
    if (tint == 1.0)
        color = vec4(0.0, 0.2, 0.0, 0.2) + color * 0.8;
#endif
    gl_FragColor = color;
}
"#
);

/// Панель оболочки: размытый фон там, где панель непрозрачнее `ignore_alpha`
/// (тень карточек и пустые места слоя не размываются). Жидкое стекло
/// (`lens` > 0): форма панели берётся из её же прозрачности — восемь проб
/// вокруг точки дают нормаль у края, фон там преломляется, край ловит блик.
pub const GLASS: &str = concat!(
    tex_head!(),
    r#"
uniform sampler2D blur_tex;
uniform vec4 blur_map;
uniform vec4 blur_clamp;
uniform vec2 tex_px;
uniform float ignore_alpha;
uniform float lens;
uniform float lens_reach;
uniform float y_sign;
uniform float saturation;

float shape(vec2 uv) {
    return smoothstep(ignore_alpha, ignore_alpha + 0.03, texture2D(tex, uv).a);
}

void main() {
    vec4 color = texture2D(tex, v_coords);
#if defined(NO_ALPHA)
    color = vec4(color.rgb, 1.0);
#endif
    float mask = smoothstep(ignore_alpha, ignore_alpha + 0.03, color.a);
    if (mask > 0.0) {
        vec2 n = vec2(0.0);
        float rim = 0.0;
        float edge = 0.0;
        if (lens > 0.0) {
            vec2 r = tex_px * lens_reach;
            float d = 0.7071;
            n += vec2( 1.0,  0.0) * shape(v_coords + vec2( r.x, 0.0));
            n += vec2(-1.0,  0.0) * shape(v_coords + vec2(-r.x, 0.0));
            n += vec2( 0.0,  1.0) * shape(v_coords + vec2(0.0,  r.y));
            n += vec2( 0.0, -1.0) * shape(v_coords + vec2(0.0, -r.y));
            n += vec2( d,  d) * shape(v_coords + vec2( r.x,  r.y) * d);
            n += vec2(-d,  d) * shape(v_coords + vec2(-r.x,  r.y) * d);
            n += vec2( d, -d) * shape(v_coords + vec2( r.x, -r.y) * d);
            n += vec2(-d, -d) * shape(v_coords + vec2(-r.x, -r.y) * d);
            n /= 4.0;
            float near = clamp(length(n), 0.0, 1.0);
            // ближе к краю — сильнее изгиб: линза, а не ровный сдвиг
            n *= near * near;
            // свет сверху слева: край под ним светлее, напротив — слабый отблеск
            float lit = dot(normalize(n + 1e-4), vec2(0.45, 0.89));
            rim = near * near * near * (0.70 * max(0.0, lit) + 0.38 * max(0.0, -lit));
            // толщина стекла: у кромки со стороны от света оно темнее
            edge = near * near * near * near * near * (1.0 - max(0.0, lit));
        }
        vec2 frag = gl_FragCoord.xy + vec2(n.x, n.y * y_sign) * lens;
        vec2 uv = clamp((frag - blur_map.xy) * blur_map.zw, blur_clamp.xy, blur_clamp.zw);
        vec3 back = texture2D(blur_tex, uv).rgb;
        float l = dot(back, vec3(0.2126, 0.7152, 0.0722));
        back = mix(vec3(l), back, saturation);
        if (lens > 0.0) {
            // как у Liquid Glass: яркий фон приглушён ради текста, тёмный — чуть светлее
            back *= mix(1.08, 0.86, smoothstep(0.45, 0.85, l));
            back *= 1.0 - 0.22 * edge;
        }
        back += rim;
        color = color + (1.0 - color.a) * vec4(back, 1.0) * mask;
    }
    color *= alpha;
#if defined(DEBUG_FLAGS)
    if (tint == 1.0)
        color = vec4(0.0, 0.2, 0.0, 0.2) + color * 0.8;
#endif
    gl_FragColor = color;
}
"#
);

/// Рамка и тень окна снаружи его прямоугольника.
pub const DECOR: &str = concat!(
    r#"
//_DEFINES_
precision highp float;
uniform vec2 size;
uniform float alpha;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
uniform vec2 win_size;
uniform float radius;
uniform float border;
uniform float shadow;
uniform vec4 border_color;
"#,
    sdf_box!(),
    r#"
void main() {
    vec2 p = v_coords * size - size * 0.5;
    float inner = sdBox(p, win_size * 0.5, radius);
    float outer = border > 0.0 ? sdBox(p, win_size * 0.5 + border, radius + border) : inner;
    float content = 1.0 - smoothstep(-0.6, 0.6, inner);
    float body = 1.0 - smoothstep(-0.6, 0.6, outer);
    vec4 b = vec4(border_color.rgb * border_color.a, border_color.a) * (body - content);
    float s = shadow > 0.0 ? pow(1.0 - clamp(outer / shadow, 0.0, 1.0), 3.0) * 0.33 : 0.0;
    vec4 color = (b + vec4(0.0, 0.0, 0.0, s) * (1.0 - body)) * alpha;
#if defined(DEBUG_FLAGS)
    if (tint == 1.0)
        color = vec4(0.0, 0.2, 0.0, 0.2) + color * 0.8;
#endif
    gl_FragColor = color;
}
"#
);

// ---- raw: рисуются напрямую через GL внутри кадра ----

pub const PASS_VERT: &str = r#"#version 100
attribute vec2 a_pos;
uniform vec2 uv_max;
varying vec2 v_uv;
void main() {
    v_uv = a_pos * uv_max;
    gl_Position = vec4(a_pos * 2.0 - 1.0, 0.0, 1.0);
}
"#;

/// Dual Kawase: быстрое размытие уменьшением и увеличением.
pub const BLUR_DOWN: &str = r#"#version 100
precision highp float;
uniform sampler2D tex;
uniform vec2 halfpixel;
uniform vec2 uv_max;
uniform float offset;
varying vec2 v_uv;
vec4 at(vec2 uv) { return texture2D(tex, clamp(uv, vec2(0.0), uv_max)); }
void main() {
    vec2 o = halfpixel * offset;
    vec4 sum = at(v_uv) * 4.0;
    sum += at(v_uv - o);
    sum += at(v_uv + o);
    sum += at(v_uv + vec2(o.x, -o.y));
    sum += at(v_uv - vec2(o.x, -o.y));
    gl_FragColor = sum / 8.0;
}
"#;

pub const BLUR_UP: &str = r#"#version 100
precision highp float;
uniform sampler2D tex;
uniform vec2 halfpixel;
uniform vec2 uv_max;
uniform float offset;
varying vec2 v_uv;
vec4 at(vec2 uv) { return texture2D(tex, clamp(uv, vec2(0.0), uv_max)); }
void main() {
    vec2 o = halfpixel * offset;
    vec4 sum = at(v_uv + vec2(-o.x * 2.0, 0.0));
    sum += at(v_uv + vec2(-o.x, o.y)) * 2.0;
    sum += at(v_uv + vec2(0.0, o.y * 2.0));
    sum += at(v_uv + vec2(o.x, o.y)) * 2.0;
    sum += at(v_uv + vec2(o.x * 2.0, 0.0));
    sum += at(v_uv + vec2(o.x, -o.y)) * 2.0;
    sum += at(v_uv + vec2(0.0, -o.y * 2.0));
    sum += at(v_uv + vec2(-o.x, -o.y)) * 2.0;
    gl_FragColor = sum / 12.0;
}
"#;

/// Вершины в координатах монитора через матрицу кадра.
pub const QUAD_VERT: &str = r#"#version 100
attribute vec2 a_pos;
uniform mat3 proj;
uniform vec4 rect;
varying vec2 v_px;
void main() {
    v_px = a_pos * rect.zw;
    vec3 p = proj * vec3(rect.xy + v_px, 1.0);
    gl_Position = vec4(p.xy, 0.0, 1.0);
}
"#;

/// Размытый фон под окном со скруглёнными углами.
pub const BACKDROP: &str = concat!(
    r#"#version 100
precision highp float;
uniform sampler2D blur_tex;
uniform vec4 blur_map;
uniform vec4 blur_clamp;
uniform vec4 rect;
uniform float radius;
uniform float saturation;
uniform float alpha;
varying vec2 v_px;
"#,
    sdf_box!(),
    r#"
void main() {
    float d = sdBox(v_px - rect.zw * 0.5, rect.zw * 0.5, radius);
    vec2 uv = clamp((gl_FragCoord.xy - blur_map.xy) * blur_map.zw, blur_clamp.xy, blur_clamp.zw);
    vec3 back = texture2D(blur_tex, uv).rgb;
    float l = dot(back, vec3(0.2126, 0.7152, 0.0722));
    gl_FragColor = vec4(mix(vec3(l), back, saturation), 1.0) * (1.0 - smoothstep(-0.6, 0.6, d)) * alpha;
}
"#
);

/// Снимок окна, вписанный в форму: растёт из точки (как окно приложений по
/// кнопке «Начать»), всплывает, плавно проявляется или едет к новому месту.
pub const REVEAL: &str = concat!(
    r#"#version 100
precision highp float;
uniform sampler2D tex;
uniform sampler2D blur_tex;
uniform vec4 blur_map;
uniform vec4 blur_clamp;
uniform float blur_on;
uniform vec4 rect;
uniform vec4 content;
uniform vec4 shape_c;
uniform vec4 win;
uniform float win_radius;
uniform float shape_r;
uniform vec4 ball;
uniform float content_alpha;
uniform float alpha;
varying vec2 v_px;
"#,
    sdf_box!(),
    r#"
void main() {
    vec2 uv = (v_px - content.xy) / content.zw;
    vec4 c = (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) ? vec4(0.0) : texture2D(tex, uv);
    float d = sdBox(v_px - shape_c.xy, shape_c.zw, shape_r);
    float cut = 1.0 - smoothstep(-0.6, 0.6, d);
    if (blur_on > 0.5) {
        float m = 1.0 - smoothstep(-0.6, 0.6, sdBox(v_px - win.xy, win.zw, win_radius));
        vec2 bu = clamp((gl_FragCoord.xy - blur_map.xy) * blur_map.zw, blur_clamp.xy, blur_clamp.zw);
        c = c + (1.0 - c.a) * vec4(texture2D(blur_tex, bu).rgb, 1.0) * m;
    }
    vec4 b = vec4(ball.rgb * ball.a, ball.a);
    gl_FragColor = mix(b, c, content_alpha) * cut * alpha;
}
"#
);

/// Окно собирается из плиток: каждая прилетает на своё место со своей
/// задержкой и поворотом, прогресс — пружина в вершинном шейдере.
pub const SHARDS_VERT: &str = r#"#version 100
attribute vec2 a_pos;
attribute vec4 a_tile;
uniform mat3 proj;
uniform vec2 origin;
uniform vec2 full;
uniform float t;
uniform float omega;
uniform float zeta;
varying vec2 v_uv;
varying float v_a;

float spring(float x) {
    if (x <= 0.0) return 0.0;
    float wd = omega * sqrt(1.0 - zeta * zeta);
    return 1.0 - exp(-zeta * omega * x) * (cos(wd * x) + zeta * omega / wd * sin(wd * x));
}

void main() {
    vec2 center = a_tile.xy;
    float seed = a_tile.z;
    float delay = a_tile.w;
    float x = t - delay;
    float p = spring(x);
    vec2 fromC = center - full * 0.5;
    float len = length(fromC) + 1.0;
    // разлёт от середины окна, плюс сдвиг у каждой плитки свой
    float a = seed * 6.2832;
    vec2 scatter = fromC / len * (90.0 + 0.32 * len) + vec2(cos(a), sin(a)) * (30.0 + 80.0 * seed);
    float angle = (1.0 - p) * (seed - 0.5) * 2.4;
    float scale = mix(0.35, 1.0, clamp(p, 0.0, 1.15));
    vec2 q = (a_pos - center) * scale;
    float cs = cos(angle), sn = sin(angle);
    q = vec2(q.x * cs - q.y * sn, q.x * sn + q.y * cs);
    vec2 pos = origin + center + scatter * (1.0 - p) + q;
    v_uv = a_pos / full;
    v_a = clamp(x * 9.0, 0.0, 1.0);
    vec3 v = proj * vec3(pos, 1.0);
    gl_Position = vec4(v.xy, 0.0, 1.0);
}
"#;

pub const SHARDS_FRAG: &str = r#"#version 100
precision highp float;
uniform sampler2D tex;
uniform float alpha;
varying vec2 v_uv;
varying float v_a;
void main() {
    gl_FragColor = texture2D(tex, v_uv) * v_a * alpha;
}
"#;

/// «Желе» на сетке: точка захвата на месте, пять колец отстают на смещения
/// o1…o5. Та же кривая, что была в оболочке (квадратичный B-сплайн).
pub const JELLY_VERT: &str = r#"#version 100
attribute vec2 a_pos;
uniform mat3 proj;
uniform vec4 rect;
uniform float pad;
uniform vec2 grab;
uniform float reach;
uniform vec4 o12;
uniform vec4 o34;
uniform vec2 o5;
varying vec2 v_local;

vec2 r1, r2, r3, r4, r5;
vec2 limit(vec2 d, float m) { float l = length(d); return l > m ? d * (m / l) : d; }
vec2 ring(float i) {
    if (i < -0.5) return -r1;
    if (i < 0.5) return vec2(0.0);
    if (i < 1.5) return r1;
    if (i < 2.5) return r2;
    if (i < 3.5) return r3;
    if (i < 4.5) return r4;
    return r5;
}

void main() {
    vec2 local = a_pos * (rect.zw + 2.0 * pad) - vec2(pad);
    float m = max(reach, 1.0) / 5.0 * 0.6;
    r1 = limit(o12.xy, m);
    r2 = r1 + limit(o12.zw - r1, m);
    r3 = r2 + limit(o34.xy - r2, m);
    r4 = r3 + limit(o34.zw - r3, m);
    r5 = r4 + limit(o5 - r4, m);
    float r = clamp(length(local - grab) / max(reach, 1.0), 0.0, 1.0) * 5.0;
    float k = floor(r + 0.5);
    float t = r + 0.5 - k;
    vec2 off = 0.5 * (1.0 - t) * (1.0 - t) * ring(k - 1.0)
             + (0.5 + t - t * t) * ring(k)
             + 0.5 * t * t * ring(min(k + 1.0, 5.0));
    v_local = local;
    vec3 p = proj * vec3(rect.xy + local + off, 1.0);
    gl_Position = vec4(p.xy, 0.0, 1.0);
}
"#;

pub const JELLY_FRAG: &str = concat!(
    r#"#version 100
precision highp float;
uniform sampler2D tex;
uniform sampler2D blur_tex;
uniform vec4 blur_map;
uniform vec4 blur_clamp;
uniform float blur_on;
uniform vec4 rect;
uniform float pad;
uniform float radius;
varying vec2 v_local;
"#,
    sdf_box!(),
    r#"
void main() {
    vec2 uv = (v_local + vec2(pad)) / (rect.zw + 2.0 * pad);
    vec4 c = texture2D(tex, uv);
    if (blur_on > 0.5) {
        float m = 1.0 - smoothstep(-0.6, 0.6, sdBox(v_local - rect.zw * 0.5, rect.zw * 0.5, radius));
        vec2 bu = clamp((gl_FragCoord.xy - blur_map.xy) * blur_map.zw, blur_clamp.xy, blur_clamp.zw);
        c = c + (1.0 - c.a) * vec4(texture2D(blur_tex, bu).rgb, 1.0) * m;
    }
    gl_FragColor = c;
}
"#
);

/// HDR, последний проход кадра. В рабочем пространстве значения закодированы
/// гаммой 2.2 и лежат в BT.709, 1.0 — белый обычной картинки, поэтому окна
/// смешиваются так же, как без HDR. Здесь: свет → BT.2020 → PQ.
pub const HDR_OUT: &str = concat!(
    tex_head!(),
    r#"
uniform float white;
vec3 pq(vec3 nits) {
    vec3 y = pow(max(nits, 0.0) / 10000.0, vec3(0.1593017578125));
    return pow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), vec3(78.84375));
}
void main() {
    vec3 c = texture2D(tex, v_coords).rgb;
    vec3 light = sign(c) * pow(abs(c), vec3(2.2));
    light = mat3(0.6274, 0.0691, 0.0164, 0.3293, 0.9195, 0.0880, 0.0433, 0.0113, 0.8956) * light;
    gl_FragColor = vec4(pq(light * white), 1.0);
}
"#
);

/// Поверхность, которая сама сказала, в каком она цвете: из её пространства в
/// рабочее. tf: 0 — гамма 2.2 и sRGB, 1 — PQ, 2 — линейный scRGB, 3 — BT.1886.
pub const COLOR_IN: &str = concat!(
    tex_head!(),
    r#"
uniform float tf;
uniform float white;
uniform mat3 to709;
vec3 from_pq(vec3 e) {
    vec3 p = pow(max(e, 0.0), vec3(1.0 / 78.84375));
    vec3 y = max(p - 0.8359375, 0.0) / (18.8515625 - 18.6875 * p);
    return 10000.0 * pow(y, vec3(1.0 / 0.1593017578125));
}
void main() {
    vec4 c = texture2D(tex, v_coords);
#if defined(NO_ALPHA)
    c.a = 1.0;
#endif
    vec3 e = c.a > 0.0 ? c.rgb / c.a : c.rgb;
    vec3 light;
    if (tf < 0.5) light = sign(e) * pow(abs(e), vec3(2.2));
    else if (tf < 1.5) light = from_pq(e) / white;
    else if (tf < 2.5) light = e * 80.0 / white;
    else light = pow(max(e, 0.0), vec3(2.4));
    light = to709 * light;
    vec3 o = sign(light) * pow(abs(light), vec3(1.0 / 2.2));
    gl_FragColor = vec4(o * c.a, c.a) * alpha;
}
"#
);
