pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Каталог виджетов: имена, размеры в ячейках, режимы — как VS_W / VS_LW в концепте.
//   def/min/max — [ширина, высота] в ячейках;
//   modes — [id, подпись, минимальная ширина, минимальная высота];
//   presets — размеры для кнопок «размер» в панели редактора.
Singleton {
    id: root

    readonly property var desktop: ({
        clock:    { name: "Часы", short: "Часы", icon: "clock", def: [7, 3], min: [3, 2], max: [13, 5], modes: [],
                    presets: [[4, 2], [7, 3], [10, 4]] },
        weather:  { name: "Погода", short: "Погода", icon: "cloud-sun", def: [2, 2], min: [2, 2], max: [6, 4],
                    modes: [["compact", "Компакт", 2, 2], ["wide", "Подробно", 4, 2]] },
        music:    { name: "Музыка", short: "Музыка", icon: "music", def: [2, 2], min: [2, 2], max: [6, 3],
                    modes: [["short", "Короткий", 2, 2], ["long", "Длинный", 4, 2]] },
        pc:       { name: "Показатели ПК", short: "ПК", icon: "monitor", def: [4, 2], min: [4, 2], max: [6, 4],
                    modes: [["wavy", "Волнистые", 4, 2], ["straight", "Прямые", 4, 2], ["list", "Список", 4, 2]], gpu: true },
        cpu:      { name: "Нагрузка процессора", short: "Процессор", icon: "cpu", def: [2, 2], min: [2, 2], max: [6, 4],
                    modes: [["wavy", "Волнистое", 2, 2], ["straight", "Прямое", 2, 2]] },
        ram:      { name: "Оперативная память", short: "ОЗУ", icon: "memory", def: [2, 2], min: [2, 2], max: [6, 4],
                    modes: [["wavy", "Волнистое", 2, 2], ["straight", "Прямое", 2, 2]] },
        gpu:      { name: "Нагрузка видеокарты", short: "Видеокарта", icon: "gpu", def: [2, 2], min: [2, 2], max: [6, 4],
                    modes: [["wavy", "Волнистое", 2, 2], ["straight", "Прямое", 2, 2]], gpu: true },
        gtemp:    { name: "Температура видеокарты", short: "Темп. видеокарты", icon: "thermometer", def: [2, 2], min: [2, 2], max: [4, 4],
                    modes: [["wavy", "Волнистое", 2, 2], ["straight", "Прямое", 2, 2]], gpu: true },
        ctemp:    { name: "Температура процессора", short: "Темп. процессора", icon: "thermometer", def: [2, 2], min: [2, 2], max: [4, 4],
                    modes: [["wavy", "Волнистое", 2, 2], ["straight", "Прямое", 2, 2]] },
        disk:     { name: "Диск", short: "Диск", icon: "disk", def: [2, 2], min: [2, 2], max: [4, 3],
                    modes: [["wavy", "Волнистое", 2, 2], ["straight", "Прямое", 2, 2]], disk: true },
        calendar: { name: "Календарь", short: "Календарь", icon: "calendar", def: [2, 2], min: [2, 2], max: [5, 4],
                    modes: [["day", "День", 2, 2], ["month", "Месяц", 3, 3]] },
        battery:  { name: "Батарея", short: "Батарея", icon: "battery", def: [2, 2], min: [2, 2], max: [4, 3],
                    modes: [], needsBattery: true },
        bars:     { name: "Полосы (спектр звука)", short: "Полосы", icon: "waveform", def: [8, 2], min: [3, 1], max: [13, 4],
                    modes: [], presets: [[4, 1], [8, 2], [12, 3]] },
        analog:   { name: "Часы со стрелками", short: "Стрелки", icon: "clock", def: [2, 2], min: [2, 2], max: [5, 5],
                    modes: [["plain", "Циферблат", 2, 2], ["date", "С датой", 2, 2]], presets: [[2, 2], [3, 3], [4, 4]] },
        net:      { name: "Скорость сети", short: "Сеть", icon: "wifi", def: [3, 2], min: [2, 2], max: [6, 4],
                    modes: [["graph", "График", 3, 2], ["numbers", "Числа", 2, 2]] },
        timer:    { name: "Таймер", short: "Таймер", icon: "clock", def: [2, 2], min: [2, 2], max: [4, 4],
                    modes: [], presets: [[2, 2], [3, 2], [3, 3]] },
        sun:      { name: "Восход и закат", short: "Солнце", icon: "sun", def: [3, 2], min: [2, 2], max: [6, 3],
                    modes: [], presets: [[2, 2], [3, 2], [4, 2]] }
    })
    readonly property var desktopOrder: ["clock", "analog", "weather", "sun", "music", "bars", "timer", "net", "pc", "gtemp", "ctemp", "cpu", "ram", "gpu", "disk", "calendar", "battery"]

    readonly property var lock: ({
        clock:    { name: "Часы", icon: "clock", def: [7, 3], min: [3, 2], max: [13, 4], modes: [] },
        analog:   { name: "Часы со стрелками", icon: "clock", def: [2, 2], min: [2, 2], max: [4, 4],
                    modes: [["plain", "Циферблат", 2, 2], ["date", "С датой", 2, 2]] },
        notifs:   { name: "Уведомления", icon: "bell", def: [4, 3], min: [2, 1], max: [10, 7],
                    modes: [["stack", "Стопкой", 3, 2], ["list", "Списком", 3, 2], ["count", "Числом", 2, 1]] },
        weather:  { name: "Погода", icon: "cloud-sun", def: [2, 1], min: [2, 1], max: [4, 3],
                    modes: [["row", "Строка", 2, 1], ["block", "Блок", 3, 2]] },
        calendar: { name: "Календарь", icon: "calendar", def: [2, 1], min: [2, 1], max: [5, 3],
                    modes: [["day", "День", 2, 1], ["month", "Месяц", 3, 2]] },
        music:    { name: "Музыка", icon: "music", def: [3, 1], min: [3, 1], max: [5, 2],
                    modes: [["short", "Короткий", 3, 1], ["wide", "Широкий", 4, 2]] },
        cpu:      { name: "Процессор", icon: "cpu", def: [2, 1], min: [2, 1], max: [4, 2],
                    modes: [["number", "Число", 2, 1], ["ring", "Кольцо", 2, 2]] },
        ram:      { name: "Память", icon: "memory", def: [2, 1], min: [2, 1], max: [4, 2],
                    modes: [["number", "Число", 2, 1], ["bar", "Полоса", 2, 2]] },
        battery:  { name: "Батарея", icon: "battery", def: [2, 1], min: [2, 1], max: [4, 2],
                    modes: [["number", "Число", 2, 1], ["ring", "Кольцо", 2, 2]], needsBattery: true }
    })
    readonly property var lockOrder: ["clock", "analog", "notifs", "weather", "calendar", "music", "cpu", "ram", "battery"]

    readonly property var clockStyles: [
        { value: "ios", label: "iOS" }, { value: "thin", label: "Тонкие" }, { value: "mono", label: "Моно" },
        { value: "neon", label: "Неон" }, { value: "stack", label: "Столбиком" },
        { value: "serif", label: "С засечками" }, { value: "wide", label: "Разрядка" },
        { value: "outline", label: "Контур" }, { value: "minimal", label: "Минимум" },
        { value: "tall", label: "Длинные" }
    ]
    readonly property var clockColors: [
        { value: "white", label: "Белые" }, { value: "accent", label: "Акцент" },
        { value: "gradient", label: "Градиент" }, { value: "glass", label: "Стекло" }
    ]

    readonly property var tallKinds: [
        { value: "line", label: "Линии" }, { value: "hollow", label: "Пустые внутри" }, { value: "column", label: "В столбик" }
    ]
    // Настройка часов: у виджета (item[key]), иначе общая (fallback). Битые
    // значения (старые версии писали в color число) не считаются.
    function clockValue(item, key, fallback) {
        const v = item ? item[key] : undefined;
        const list = key === "style" ? clockStyles : key === "color" ? clockColors : key === "tallKind" ? tallKinds : null;
        const ok = x => x !== undefined && x !== null && x !== "" && (list ? list.some(o => o.value === x) : isFinite(Number(x)));
        return ok(v) ? v : ok(fallback) ? fallback : list ? list[0].value : fallback;
    }

    // батарея есть только у ноутбуков: без неё виджет не показываем и не предлагаем
    readonly property bool hasBattery: {
        const d = UPower.displayDevice;
        return d !== null && d.isLaptopBattery && d.isPresent;
    }

    function table(layer) { return layer === "lock" ? lock : desktop; }
    function order(layer) { return layer === "lock" ? lockOrder : desktopOrder; }
    function info(layer, id) { return table(layer)[id] || null; }
    function available(layer, id) {
        const t = info(layer, id);
        return t !== null && (!t.needsBattery || hasBattery);
    }
    function defaultMode(layer, id) {
        const t = info(layer, id);
        return t && t.modes.length ? t.modes[0][0] : "";
    }

    // мин/макс с учётом режима: «Подробно» у погоды не бывает меньше 4×2
    function limits(layer, id, mode) {
        const t = info(layer, id);
        if (!t) return { min: [1, 1], max: [1, 1] };
        const min = t.min.slice();
        const m = t.modes.find(x => x[0] === mode);
        if (m) { min[0] = Math.max(min[0], m[2]); min[1] = Math.max(min[1], m[3]); }
        return { min: min, max: t.max };
    }

    // варианты размеров для панели редактора (без повторов, в пределах min/max)
    function presets(layer, id, mode) {
        const t = info(layer, id), lim = limits(layer, id, mode);
        if (!t) return [];
        const clamp = s => [Math.max(lim.min[0], Math.min(lim.max[0], s[0])), Math.max(lim.min[1], Math.min(lim.max[1], s[1]))];
        const opts = t.presets ? t.presets.map(clamp)
            : layer === "lock" ? [lim.min, [Math.min(lim.max[0], lim.min[0] + 1), lim.min[1]], lim.max]
            : [lim.min, [Math.min(lim.max[0], Math.max(lim.min[0], 4)), Math.max(lim.min[1], 2)], [Math.min(lim.max[0], 4), Math.min(lim.max[1], 3)]];
        const seen = {}, out = [];
        for (const o of opts) {
            const k = o[0] + "×" + o[1];
            if (seen[k]) continue;
            seen[k] = true;
            out.push({ value: k, label: k, w: o[0], h: o[1] });
        }
        return out;
    }
}
