.pragma library

// Восход и закат для расписания ночного света (алгоритм из «Almanac for
// Computers», точность ~1–2 минуты — для ночного света более чем достаточно).
// Работает без сети: координаты берём из настроек или из zone1970.tab по
// часовому поясу.

const RAD = Math.PI / 180;

function norm(v, m) { return ((v % m) + m) % m; }

// UTC-час события для дня года n; null — солнце в этот день не встаёт/не садится
function utcHour(n, lat, lon, rising) {
    const zenith = 90.833;
    const lngHour = lon / 15;
    const t = n + ((rising ? 6 : 18) - lngHour) / 24;
    const M = 0.9856 * t - 3.289;
    const L = norm(M + 1.916 * Math.sin(M * RAD) + 0.020 * Math.sin(2 * M * RAD) + 282.634, 360);
    let RA = norm(Math.atan(0.91764 * Math.tan(L * RAD)) / RAD, 360);
    RA = (RA + Math.floor(L / 90) * 90 - Math.floor(RA / 90) * 90) / 15;
    const sinDec = 0.39782 * Math.sin(L * RAD);
    const cosDec = Math.cos(Math.asin(sinDec));
    const cosH = (Math.cos(zenith * RAD) - sinDec * Math.sin(lat * RAD)) / (cosDec * Math.cos(lat * RAD));
    if (cosH > 1 || cosH < -1) return null;
    const H = (rising ? 360 - Math.acos(cosH) / RAD : Math.acos(cosH) / RAD) / 15;
    const T = H + RA - 0.06571 * t - 6.622;
    return norm(T - lngHour, 24);
}

// → { sunrise: Date, sunset: Date } для местной даты `date`, или null у полюсов
function times(date, lat, lon) {
    const start = new Date(date.getFullYear(), 0, 0);
    const n = Math.floor((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - start) / 86400000);
    function at(rising) {
        const h = utcHour(n, lat, lon, rising);
        if (h === null) return null;
        let d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) + h * 3600000);
        // восточнее Гринвича UTC-дата события может быть вчерашней: подгоняем
        // к нужной местной дате
        const want = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        const got = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        if (got < want) d = new Date(d.getTime() + 86400000);
        else if (got > want) d = new Date(d.getTime() - 86400000);
        return d;
    }
    const r = at(true), s = at(false);
    return r && s ? { sunrise: r, sunset: s } : null;
}

// "+4310+13156" или "+431000+1315600" (zone1970.tab) → { lat, lon }
function parseIso6709(s) {
    const m = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(String(s || ""));
    if (!m) return null;
    const lat = (parseInt(m[2]) + parseInt(m[3]) / 60 + (m[4] ? parseInt(m[4]) / 3600 : 0)) * (m[1] === "-" ? -1 : 1);
    const lon = (parseInt(m[6]) + parseInt(m[7]) / 60 + (m[8] ? parseInt(m[8]) / 3600 : 0)) * (m[5] === "-" ? -1 : 1);
    return { lat: lat, lon: lon };
}

// координаты часового пояса из текста zone1970.tab
function zoneCoords(tab, zone) {
    for (const line of String(tab).split("\n")) {
        if (line.startsWith("#")) continue;
        const f = line.split("\t");
        if (f.length >= 3 && f[2] === zone) return parseIso6709(f[1]);
    }
    return null;
}

// "21:30" → минуты от полуночи, null при ошибке
function parseTime(s) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(s || "").trim());
    if (!m) return null;
    const h = parseInt(m[1]), mi = parseInt(m[2]);
    return h < 24 && mi < 60 ? h * 60 + mi : null;
}

function fmt(minutes) {
    const h = Math.floor(minutes / 60) % 24, m = minutes % 60;
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

function minutesOf(d) { return d.getHours() * 60 + d.getMinutes(); }

// Включён ли ночной свет сейчас: интервал [from, to) может переходить через полночь.
function inWindow(now, from, to) {
    if (from === to) return false;
    return from < to ? (now >= from && now < to) : (now >= from || now < to);
}
