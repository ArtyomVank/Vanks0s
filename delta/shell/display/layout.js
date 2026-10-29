.pragma library

// Геометрия раздела «Экран»: режимы, допустимые масштабы, раскладка мониторов.
// Чистые функции без QML, чтобы их можно было проверить отдельно.
//
// Координаты раскладки — логические пиксели Hyprland: размер режима, делённый
// на масштаб, а при повороте на 90/270° ширина и высота меняются местами.

// "1920x1080@200.00Hz" → { w, h, hz }
function parseMode(s) {
    const m = /^(\d+)x(\d+)(?:@([\d.]+))?/.exec(String(s || ""));
    return m ? { w: parseInt(m[1]), h: parseInt(m[2]), hz: m[3] ? parseFloat(m[3]) : 60 } : null;
}

// строка для правила монитора; частота с двумя знаками, как в availableModes
function modeString(mode) {
    return mode.w + "x" + mode.h + "@" + Number(mode.hz).toFixed(2);
}

// уникальные разрешения по убыванию площади, затем ширины
function resolutions(modes) {
    const seen = {}, out = [];
    for (const m of modes) {
        const k = m.w + "x" + m.h;
        if (!seen[k]) { seen[k] = true; out.push({ w: m.w, h: m.h }); }
    }
    return out.sort((a, b) => (b.w * b.h - a.w * a.h) || (b.w - a.w));
}

// частоты для разрешения, по убыванию
function rates(modes, w, h) {
    return modes.filter(m => m.w === w && m.h === h).map(m => m.hz)
                .filter((v, i, a) => a.indexOf(v) === i).sort((a, b) => b - a);
}

// режим из списка, ближайший к нужному (частоты 59.94/60 — разные режимы)
function nearestMode(modes, w, h, hz) {
    const same = modes.filter(m => m.w === w && m.h === h);
    if (same.length === 0) return null;
    return same.reduce((best, m) => Math.abs(m.hz - hz) < Math.abs(best.hz - hz) ? m : best);
}

function hzLabel(hz) {
    const r = Math.round(hz * 100) / 100;
    return (Math.abs(r - Math.round(r)) < 0.005 ? String(Math.round(r)) : r.toFixed(2)) + " Гц";
}

// Масштабы, которые Hyprland принимает без округления: дробный масштаб в
// Wayland кратен 1/120, а логический размер должен получиться целым.
// Оставляем «читаемые» значения: целые проценты и трети (133 %, 167 %).
function validScales(w, h) {
    const out = [];
    for (let n = 120; n <= 360; n++) {
        if ((w * 120) % n !== 0 || (h * 120) % n !== 0) continue;
        if (n % 6 !== 0 && n % 40 !== 0) continue;
        out.push(n / 120);
    }
    // на больших экранах вариантов слишком много: оставляем кратные 5 % и трети
    if (out.length > 14)
        return out.filter(s => Math.abs(s * 20 - Math.round(s * 20)) < 1e-6 || Math.abs(s * 3 - Math.round(s * 3)) < 1e-6);
    return out;
}

function scaleLabel(s) { return Math.round(s * 100) + " %"; }

// ближайший допустимый масштаб
function nearestScale(scales, s) {
    if (scales.length === 0) return 1;
    return scales.reduce((best, v) => Math.abs(v - s) < Math.abs(best - s) ? v : best);
}

// масштаб для Lua/JSON: 4/3 → 1.333333 (Hyprland сам подтянет к 1/120)
function scaleValue(s) { return Math.round(s * 1e6) / 1e6; }

// логический размер монитора с учётом масштаба и поворота
function logicalSize(cfg) {
    let w = Math.round(cfg.mode.w / cfg.scale), h = Math.round(cfg.mode.h / cfg.scale);
    if (cfg.transform % 2 === 1) { const t = w; w = h; h = t; }
    return { w: w, h: h };
}

// --- раскладка -----------------------------------------------------------
// rect: { name, x, y, w, h }

function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

// мониторы касаются стороной (а не только углом)
function touches(a, b) {
    const vert = (a.x + a.w === b.x || b.x + b.w === a.x) && a.y < b.y + b.h && b.y < a.y + a.h;
    const horz = (a.y + a.h === b.y || b.y + b.h === a.y) && a.x < b.x + b.w && b.x < a.x + a.w;
    return vert || horz;
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

// Выравнивание по краям и центру соседа, если близко (snap — в логических px).
function align(p, size, start, len, snap) {
    const opts = [start, start + len - size, start + Math.round((len - size) / 2)];
    let best = p, d = snap + 1;
    for (const o of opts) if (Math.abs(o - p) < d) { d = Math.abs(o - p); best = o; }
    return best;
}

// Куда поставить прямоугольник r, который бросили в (px, py): вплотную к одному
// из соседей стороной, без наложений, как можно ближе к месту броска.
// Соседи должны перекрываться хотя бы на четверть меньшей стороны —
// иначе курсор не перейдёт с монитора на монитор.
function place(r, px, py, others, snap) {
    if (others.length === 0) return { x: 0, y: 0 };
    let best = null, bestD = Infinity;
    function consider(x, y) {
        const c = { x: x, y: y, w: r.w, h: r.h };
        for (const o of others) if (overlaps(c, o)) return;
        const d = (x - px) * (x - px) + (y - py) * (y - py);
        if (d < bestD) { bestD = d; best = { x: x, y: y }; }
    }
    for (const o of others) {
        const mh = Math.max(1, Math.round(Math.min(r.h, o.h) / 4));
        const mw = Math.max(1, Math.round(Math.min(r.w, o.w) / 4));
        let y = align(clamp(py, o.y - r.h + mh, o.y + o.h - mh), r.h, o.y, o.h, snap);
        consider(o.x + o.w, y);
        consider(o.x - r.w, y);
        let x = align(clamp(px, o.x - r.w + mw, o.x + o.w - mw), r.w, o.x, o.w, snap);
        consider(x, o.y + o.h);
        consider(x, o.y - r.h);
    }
    if (best) return best;
    // всё занято (не должно случаться) — справа от всех
    const right = Math.max.apply(null, others.map(o => o.x + o.w));
    const top = Math.min.apply(null, others.map(o => o.y));
    return { x: right, y: top };
}

// Сдвинуть всё так, чтобы левый верхний угол раскладки был в (0, 0).
function normalize(rects) {
    if (rects.length === 0) return rects;
    const mx = Math.min.apply(null, rects.map(r => r.x));
    const my = Math.min.apply(null, rects.map(r => r.y));
    return rects.map(r => ({ name: r.name, x: r.x - mx, y: r.y - my, w: r.w, h: r.h }));
}

// Привести раскладку в порядок: без наложений и разрывов. `fixed` остаётся на
// месте, остальные по очереди (от ближних к дальним) приставляются к уже
// расставленным, если перекрываются или висят отдельно.
function fixup(rects, fixed, snap) {
    if (rects.length <= 1) return normalize(rects.map(r => Object.assign({}, r, { x: 0, y: 0 })));
    const first = rects.find(r => r.name === fixed) || rects[0];
    const cx = first.x + first.w / 2, cy = first.y + first.h / 2;
    const rest = rects.filter(r => r !== first).sort((a, b) =>
        Math.hypot(a.x + a.w / 2 - cx, a.y + a.h / 2 - cy) - Math.hypot(b.x + b.w / 2 - cx, b.y + b.h / 2 - cy));
    const done = [Object.assign({}, first)];
    for (const r of rest) {
        const c = Object.assign({}, r);
        const ok = !done.some(o => overlaps(c, o)) && done.some(o => touches(c, o));
        if (!ok) {
            const p = place(c, c.x, c.y, done, snap);
            c.x = p.x; c.y = p.y;
        }
        done.push(c);
    }
    return normalize(done);
}

// Монитор `name` бросили в (px, py): поставить к соседям, остальное поправить.
function drop(rects, name, px, py, snap) {
    const r = rects.find(o => o.name === name);
    if (!r) return rects;
    const others = rects.filter(o => o.name !== name);
    const p = place(r, Math.round(px), Math.round(py), others, snap);
    const moved = rects.map(o => o.name === name ? Object.assign({}, o, { x: p.x, y: p.y }) : Object.assign({}, o));
    // если монитор был «мостом» между другими, они могли оторваться — fixup
    // от перемещённого их приставит
    return fixup(moved, name, snap);
}

// Размер монитора поменялся (режим, масштаб, поворот): соседей справа и снизу
// сдвигаем на разницу, потом убираем наложения и разрывы.
function resized(rects, name, oldW, oldH) {
    const r = rects.find(o => o.name === name);
    if (!r) return rects;
    const dw = r.w - oldW, dh = r.h - oldH;
    const moved = rects.map(o => {
        if (o.name === name) return Object.assign({}, o);
        const c = Object.assign({}, o);
        if (o.x >= r.x + oldW) c.x += dw;
        if (o.y >= r.y + oldH) c.y += dh;
        return c;
    });
    return fixup(moved, name, 0);
}
