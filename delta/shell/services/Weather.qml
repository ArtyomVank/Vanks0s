pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Погода через Open-Meteo (без ключа). Город — weather.city, координаты ищем
// геокодером Open-Meteo. Ответ кешируется в Quickshell.cacheDir: после
// перезапуска оболочки погода видна сразу, а сеть дёргается не чаще раза
// в 20 минут и только пока погоду кто-то показывает (WeatherUser {}).
Singleton {
    id: root

    readonly property string city: (Settings.get("weather.city", "") || "").trim()
    readonly property string units: Settings.get("weather.units", "c") === "f" ? "f" : "c"
    readonly property string unitMark: "°"
    readonly property string windUnit: units === "f" ? "миль/ч" : "м/с"

    // --- состояние ---
    property int users: 0
    function acquire() { users++; }
    function release() { users = Math.max(0, users - 1); }

    property bool loading: false
    property string error: ""             // текст для человека или ""
    // { query, name, admin, country, lat, lon }
    property var place: null
    // { temp, feels, code, day, wind, humidity, text, icon }
    property var current: null
    // [{ hour: "14:00", temp, code, icon, rain }] — ближайшие 24 часа
    property var hourly: []
    // [{ name: "Пн", date: "28 окт.", max, min, code, icon, text, rain }] — 6 дней с сегодняшнего
    property var daily: []
    property real fetched: 0               // мс, когда пришёл прогноз

    readonly property bool hasData: current !== null && place !== null && place.query === city.toLowerCase()
    readonly property int refreshMs: 20 * 60 * 1000

    // --- коды WMO → текст и иконка ---
    function describe(code) {
        const c = Number(code);
        if (c === 0) return "Ясно";
        if (c === 1) return "Преимущественно ясно";
        if (c === 2) return "Переменная облачность";
        if (c === 3) return "Пасмурно";
        if (c === 45 || c === 48) return "Туман";
        if (c >= 51 && c <= 55) return "Морось";
        if (c === 56 || c === 57) return "Ледяная морось";
        if (c === 61) return "Небольшой дождь";
        if (c === 63) return "Дождь";
        if (c === 65) return "Сильный дождь";
        if (c === 66 || c === 67) return "Ледяной дождь";
        if (c === 71) return "Небольшой снег";
        if (c === 73) return "Снег";
        if (c === 75) return "Сильный снег";
        if (c === 77) return "Снежная крупа";
        if (c === 80) return "Небольшой ливень";
        if (c === 81) return "Ливень";
        if (c === 82) return "Сильный ливень";
        if (c === 85 || c === 86) return "Снегопад";
        if (c === 95) return "Гроза";
        if (c === 96 || c === 99) return "Гроза с градом";
        return "Нет данных";
    }
    function icon(code, day) {
        const c = Number(code);
        if (c <= 1) return day === false ? "moon" : "sun";
        if (c === 2) return day === false ? "cloud" : "cloud-sun";
        if (c === 3) return "cloud";
        if (c === 45 || c === 48) return "fog";
        if (c >= 71 && c <= 77 || c === 85 || c === 86) return "snow";
        if (c >= 95) return "storm";
        if (c >= 51) return "rain";
        return "cloud";
    }
    // солнце рисуем тёплым, как в концепте; остальное — цветом текста
    function iconColor(name, fallback) {
        return name === "sun" || name === "cloud-sun" ? "#FFC65A" : fallback;
    }
    function temp(v) {
        if (v === undefined || v === null || isNaN(v)) return "—";
        const r = Math.round(v);
        return (r > 0 ? "+" : r < 0 ? "−" : "") + Math.abs(r) + "°";
    }

    // --- сеть ---
    function get(url, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let data = null;
            if (xhr.status === 200) {
                try { data = JSON.parse(xhr.responseText); } catch (e) { data = null; }
            }
            done(data, xhr.status);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function refresh(force) {
        // без зрителей в сеть не ходим: догоним, когда погоду покажут
        if (loading || users <= 0) return;
        if (!city.length) {
            error = "";
            return;
        }
        if (!force && hasData && Date.now() - fetched < refreshMs && current.units === units) return;
        if (place && place.query === city.toLowerCase()) fetchForecast();
        else geocode();
    }

    function geocode() {
        loading = true;
        error = "";
        const q = city;
        get("https://geocoding-api.open-meteo.com/v1/search?count=1&language=ru&format=json&name=" + encodeURIComponent(q), (data, status) => {
            if (q !== root.city) { loading = false; refresh(true); return; }
            const r = data && data.results && data.results[0];
            if (!r) {
                loading = false;
                error = data ? "Город «" + q + "» не найден" : "Нет связи с сервером погоды";
                return;
            }
            place = { query: q.toLowerCase(), name: r.name, admin: r.admin1 || "", country: r.country || "", lat: r.latitude, lon: r.longitude };
            loading = false;
            fetchForecast();
        });
    }

    function fetchForecast() {
        if (!place) return;
        loading = true;
        const p = place, u = units;
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + p.lat + "&longitude=" + p.lon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto&forecast_days=6"
            + (u === "f" ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "&wind_speed_unit=ms");
        get(url, (data, status) => {
            loading = false;
            if (!data || !data.current) {
                error = "Нет связи с сервером погоды";
                return;
            }
            error = "";
            apply(data, u, Date.now());
            save(data, u);
        });
    }

    readonly property var dayNames: ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    readonly property var monthNames: ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."]

    function apply(d, u, when) {
        const c = d.current;
        current = {
            units: u,
            temp: c.temperature_2m, feels: c.apparent_temperature, humidity: c.relative_humidity_2m,
            wind: c.wind_speed_10m, code: c.weather_code, day: c.is_day === 1,
            text: describe(c.weather_code), icon: icon(c.weather_code, c.is_day === 1)
        };
        // почасовой прогноз — с текущего часа (время в ответе уже местное)
        const h = d.hourly || {};
        const times = h.time || [];
        const nowHour = (c.time || "").slice(0, 13);
        let start = times.findIndex(t => t.slice(0, 13) >= nowHour);
        if (start < 0) start = 0;
        const hrs = [];
        for (let i = start; i < Math.min(times.length, start + 24); i++)
            hrs.push({ hour: times[i].slice(11, 16), temp: h.temperature_2m[i], code: h.weather_code[i],
                       icon: icon(h.weather_code[i], h.is_day ? h.is_day[i] === 1 : true),
                       rain: h.precipitation_probability ? h.precipitation_probability[i] : null });
        hourly = hrs;
        const dl = d.daily || {};
        const days = [];
        for (let i = 0; i < (dl.time || []).length; i++) {
            const parts = dl.time[i].split("-").map(Number);
            const date = new Date(parts[0], parts[1] - 1, parts[2]);
            days.push({ name: i === 0 ? "Сегодня" : dayNames[date.getDay()],
                        date: parts[2] + " " + monthNames[parts[1] - 1],
                        max: dl.temperature_2m_max[i], min: dl.temperature_2m_min[i], code: dl.weather_code[i],
                        icon: icon(dl.weather_code[i], true), text: describe(dl.weather_code[i]),
                        rain: dl.precipitation_probability_max ? dl.precipitation_probability_max[i] : null });
        }
        daily = days;
        fetched = when;
    }

    // --- кеш на диске ---
    readonly property string cachePath: Quickshell.cacheDir + "/weather.json"

    function save(data, u) {
        cacheFile.setText(JSON.stringify({ place: place, units: u, fetched: Date.now(), data: data }));
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c && c.place && c.data) {
                    root.place = c.place;
                    root.apply(c.data, c.units || "c", c.fetched || 0);
                }
            } catch (e) {}
            root.refresh(false);
        }
        onLoadFailed: root.refresh(false)
    }

    // каталог кеша может ещё не существовать
    Process {
        running: true
        command: ["mkdir", "-p", Quickshell.cacheDir]
    }

    onCityChanged: { place = place && place.query === city.toLowerCase() ? place : null; refresh(true); }
    onUnitsChanged: refresh(true)
    onUsersChanged: if (users > 0) refresh(false)

    Timer {
        running: root.users > 0 && root.city.length > 0
        interval: 60 * 1000
        repeat: true
        onTriggered: root.refresh(false)
    }
}
