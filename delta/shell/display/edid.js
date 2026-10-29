.pragma library

// Разбор EDID: только то, что нужно разделу «Экран» — умеет ли монитор HDR.
//
// Hyprland в `hyprctl monitors -j` не сообщает, поддерживает ли монитор HDR,
// поэтому смотрим сам EDID (/sys/class/drm/card*-<порт>/edid): в расширении
// CTA-861 есть блок «HDR Static Metadata» со списком передаточных функций.
// HDR в Hyprland — это PQ (SMPTE ST 2084), поэтому «умеет HDR» = есть бит PQ.

// "00ffff…" → [0, 255, 255, …]; мусор и пробелы пропускаем
function bytes(hex) {
    const clean = String(hex || "").replace(/[^0-9a-fA-F]/g, "");
    const out = [];
    for (let i = 0; i + 1 < clean.length; i += 2) out.push(parseInt(clean.substr(i, 2), 16));
    return out;
}

// кодовые значения яркости из CTA-861.3
function maxLum(cv) { return 50 * Math.pow(2, cv / 32); }
function minLum(cv, max) { return max * Math.pow(cv / 255, 2) / 100; }

// → { valid, hdr, hlg, wideColor, maxLuminance, maxAvgLuminance, minLuminance }
function parse(hex) {
    const b = bytes(hex);
    const info = { valid: false, hdr: false, hlg: false, wideColor: false,
                   maxLuminance: 0, maxAvgLuminance: 0, minLuminance: 0 };
    const header = [0, 255, 255, 255, 255, 255, 255, 0];
    if (b.length < 128 || header.some((v, i) => b[i] !== v)) return info;
    info.valid = true;

    const ext = Math.min(b[126], Math.floor(b.length / 128) - 1);
    for (let e = 1; e <= ext; e++) {
        const o = e * 128;
        if (b[o] !== 0x02) continue;          // не CTA-861
        const dtd = b[o + 2];
        let p = o + 4;
        const end = o + Math.min(dtd >= 4 ? dtd : 4, 127);
        while (p < end) {
            const tag = b[p] >> 5, len = b[p] & 0x1f;
            if (len === 0) { p += 1; continue; }
            if (tag === 7 && len >= 2) {
                const xt = b[p + 1];
                if (xt === 0x05) {
                    // Colorimetry: бит 7 — BT.2020 RGB
                    info.wideColor = (b[p + 2] & 0x80) !== 0;
                } else if (xt === 0x06) {
                    const eotf = b[p + 2];
                    info.hdr = (eotf & 0x04) !== 0;
                    info.hlg = (eotf & 0x08) !== 0;
                    // необязательные поля яркости: есть, только если блок длиннее
                    if (len >= 4 && b[p + 4]) info.maxLuminance = Math.round(maxLum(b[p + 4]));
                    if (len >= 5 && b[p + 5]) info.maxAvgLuminance = Math.round(maxLum(b[p + 5]));
                    if (len >= 6 && b[p + 4]) info.minLuminance = Math.round(minLum(b[p + 6], maxLum(b[p + 4])) * 1000) / 1000;
                }
            }
            p += len + 1;
        }
    }
    return info;
}
