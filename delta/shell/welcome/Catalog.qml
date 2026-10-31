pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import Quickshell
import Quickshell.Io

// Что предлагает помощник «Добро пожаловать»: библиотеки, драйверы под
// видеокарту этого компьютера и приложения. Здесь же — что уже стоит и что
// отмечено. Пункт: { id, icon, title, text, pkgs, aur?, on, steam? }.
//   pkgs  — пакеты Arch (ставит delta-setup install);
//   aur   — рецепты AUR (только драйвер NVIDIA 580, см. delta-setup);
//   on    — отмечен по умолчанию;
//   steam — нужен Vulkan для 32-битных игр (Steam, Wine): к нему добавятся
//           драйверы Vulkan этой видеокарты, иначе pacman выберет любой.
Singleton {
    id: root

    // [{ kind: nvidia|amd|intel|vm|other, device: число, name }]
    property var gpus: []
    property var kernels: []
    property bool multilib: false
    property bool detected: false
    // { "имя пакета": true } — установленные
    property var installed: ({})
    // { id: bool } — выбор пользователя поверх значения по умолчанию
    property var picked: ({})

    readonly property var primary: {
        const order = ["nvidia", "amd", "intel", "vm", "other"];
        return gpus.slice().sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind))[0] || null;
    }

    // ---------- библиотеки ----------
    readonly property var libs: [
        { id: "vulkan", icon: "layers", title: "Vulkan", on: true,
          text: I18n.tr("Основа современных игр и DXVK: через него Steam запускает игры для Windows"),
          pkgs: ["vulkan-icd-loader", "lib32-vulkan-icd-loader", "vulkan-tools"] },
        { id: "lib32", icon: "cpu", title: I18n.tr("32-битные библиотеки"), on: true,
          text: I18n.tr("Графика и звук для старых игр и самого Steam"),
          pkgs: ["lib32-mesa", "lib32-pipewire", "lib32-libpulse", "lib32-alsa-plugins"] },
        { id: "gamemode", icon: "rocket", title: "GameMode", on: true,
          text: I18n.tr("Пока идёт игра, процессор работает на полную, а фоновые задачи ждут"),
          pkgs: ["gamemode", "lib32-gamemode"] },
        { id: "codecs", icon: "video", title: I18n.tr("Кодеки"), on: true,
          text: I18n.tr("Видео и музыка в любых форматах — в играх, браузере и плеерах"),
          pkgs: ["gst-plugins-good", "gst-plugins-bad", "gst-plugins-ugly", "gst-libav"] },
        { id: "fonts", icon: "font", title: I18n.tr("Шрифты для игр"), on: true,
          text: I18n.tr("Без них в лаунчерах и играх вместо букв бывают квадратики"),
          pkgs: ["ttf-liberation", "noto-fonts-cjk"] },
        { id: "mangohud", icon: "gauge", title: "MangoHud", on: false,
          text: I18n.tr("Счётчик кадров, температура и загрузка поверх игры"),
          pkgs: ["mangohud", "lib32-mangohud"] },
        { id: "gamescope", icon: "monitor", title: "Gamescope", on: false,
          text: I18n.tr("Отдельный экран для игры: своё разрешение, FSR, ограничение кадров"),
          pkgs: ["gamescope"] },
        { id: "wine", icon: "windows", title: "Wine", on: false, steam: true,
          text: I18n.tr("Программы и игры для Windows вне Steam"),
          pkgs: ["wine", "winetricks"] }
    ]

    // ---------- драйверы ----------
    function headers() { return kernels.map(k => k + "-headers"); }

    readonly property var drivers: {
        const out = [];
        const seen = {};
        const add = it => { if (!seen[it.id]) { seen[it.id] = true; out.push(it); } };
        for (const g of gpus) {
            if (g.kind === "nvidia" && g.device >= 0x1e00) {
                // Turing (GTX 16xx, RTX 20xx) и новее — открытые модули NVIDIA
                add({ id: "nvidia", icon: "gpu", title: I18n.tr("Драйвер NVIDIA"), on: true,
                      text: I18n.tr("Официальный драйвер для ") + g.name + ": полный FPS, DLSS, видеоускорение",
                      pkgs: ["nvidia-open-dkms", "nvidia-utils", "lib32-nvidia-utils", "nvidia-settings"].concat(headers()) });
            } else if (g.kind === "nvidia" && g.device >= 0x1340) {
                // Maxwell и Pascal (GTX 900/1000): NVIDIA выпускает для них ветку 580
                // только в AUR — собираем из рецепта
                add({ id: "nvidia580", icon: "gpu", title: I18n.tr("Драйвер NVIDIA 580"), on: true,
                      text: I18n.tr("Последний драйвер для ") + g.name + ". В Arch его нет — соберём из AUR, это займёт несколько минут",
                      pkgs: headers(), aur: ["nvidia-580xx-utils", "lib32-nvidia-580xx-utils"],
                      check: ["nvidia-580xx-utils", "nvidia-580xx-dkms", "lib32-nvidia-580xx-utils"] });
                add({ id: "nouveau", icon: "gpu", title: I18n.tr("Открытый драйвер Nouveau"), on: false,
                      text: I18n.tr("Ставится сразу и работает без AUR, но в играх заметно медленнее"),
                      pkgs: ["mesa", "lib32-mesa", "vulkan-nouveau", "lib32-vulkan-nouveau"] });
            } else if (g.kind === "nvidia") {
                add({ id: "nouveau", icon: "gpu", title: I18n.tr("Открытый драйвер Nouveau"), on: true,
                      text: I18n.tr("Для ") + g.name + " NVIDIA больше не выпускает драйвер — только открытый",
                      pkgs: ["mesa", "lib32-mesa", "vulkan-nouveau", "lib32-vulkan-nouveau"] });
            } else if (g.kind === "amd") {
                add({ id: "amd", icon: "gpu", title: I18n.tr("Драйвер AMD"), on: true,
                      text: I18n.tr("Открытый драйвер для ") + g.name + ": Vulkan RADV, OpenGL и видеоускорение",
                      pkgs: ["mesa", "lib32-mesa", "vulkan-radeon", "lib32-vulkan-radeon"] });
            } else if (g.kind === "intel") {
                add({ id: "intel", icon: "gpu", title: I18n.tr("Драйвер Intel"), on: true,
                      text: I18n.tr("Vulkan и видеоускорение для ") + g.name,
                      pkgs: ["mesa", "lib32-mesa", "vulkan-intel", "lib32-vulkan-intel", "intel-media-driver"] });
            } else if (g.kind === "vm") {
                add({ id: "vm", icon: "monitor", title: I18n.tr("Графика виртуальной машины"), on: true,
                      text: I18n.tr("Программный Vulkan: игры пойдут медленно, но запустятся"),
                      pkgs: ["mesa", "lib32-mesa", "vulkan-swrast", "lib32-vulkan-swrast"] });
            }
        }
        add({ id: "zen", icon: "cpu", title: I18n.tr("Игровое ядро linux-zen"), on: true,
              text: I18n.tr("Меньше задержек в играх и под нагрузкой. Заработает после перезагрузки"),
              pkgs: ["linux-zen", "linux-zen-headers"] });
        add({ id: "firmware", icon: "disk", title: I18n.tr("Прошивки устройств"), on: true,
              text: I18n.tr("Wi-Fi, Bluetooth и звук на ноутбуках"),
              pkgs: ["linux-firmware", "sof-firmware"] });
        return out;
    }

    // Vulkan основной видеокарты — Steam и Wine требуют его явно
    readonly property var vulkanForGames: {
        const g = primary;
        if (!g) return [];
        if (g.kind === "nvidia" && g.device >= 0x1e00) return ["nvidia-utils", "lib32-nvidia-utils"];
        if (g.kind === "nvidia") return ["vulkan-nouveau", "lib32-vulkan-nouveau"];
        if (g.kind === "amd") return ["vulkan-radeon", "lib32-vulkan-radeon"];
        if (g.kind === "intel") return ["vulkan-intel", "lib32-vulkan-intel"];
        return ["vulkan-swrast", "lib32-vulkan-swrast"];
    }

    // ---------- приложения ----------
    readonly property var apps: [
        { id: "steam", icon: "gamepad", title: "Steam", on: true, steam: true,
          text: I18n.tr("Магазин игр и Proton — тысячи игр для Windows прямо в Vanks OS"),
          pkgs: ["steam"] },
        { id: "chromium", icon: "globe", title: "Chromium", on: true,
          text: I18n.tr("Быстрый браузер с синхронизацией закладок"),
          pkgs: ["chromium"] },
        { id: "discord", icon: "send", title: "Discord", on: false,
          text: I18n.tr("Голосовые каналы и чаты с друзьями"),
          pkgs: ["discord"] },
        { id: "obs", icon: "video", title: "OBS Studio", on: false,
          text: I18n.tr("Запись экрана и стримы"),
          pkgs: ["obs-studio"] },
        { id: "lutris", icon: "gamepad", title: "Lutris", on: false, steam: true,
          text: I18n.tr("Игры из Epic, GOG, Battle.net и эмуляторы в одном месте"),
          pkgs: ["lutris"] },
        { id: "telegram", icon: "send", title: "Telegram", on: false,
          text: I18n.tr("Мессенджер"),
          pkgs: ["telegram-desktop"] },
        { id: "vlc", icon: "play", title: "VLC", on: false,
          text: I18n.tr("Плеер, который открывает всё"),
          pkgs: ["vlc"] },
        { id: "resources", icon: "gauge", title: I18n.tr("Ресурсы"), on: false,
          text: I18n.tr("Загрузка процессора, видеокарты, памяти и диска, список процессов"),
          pkgs: ["resources"] }
    ]

    readonly property var tabs: [
        { id: "libs", title: I18n.tr("Библиотеки"), icon: "layers", items: libs },
        { id: "drivers", title: I18n.tr("Драйверы"), icon: "gpu", items: drivers },
        { id: "apps", title: I18n.tr("Приложения"), icon: "apps", items: apps }
    ]

    // ---------- состояние ----------
    function names(it) { return it.check || (it.pkgs || []).concat(it.aur || []); }
    function isInstalled(it) {
        const n = names(it);
        return n.length > 0 && n.every(p => installed[p] === true);
    }
    function isOn(it) {
        if (isInstalled(it)) return false;
        return picked[it.id] !== undefined ? picked[it.id] : it.on;
    }
    function toggle(it) {
        const p = Object.assign({}, picked);
        p[it.id] = !isOn(it);
        picked = p;
    }

    readonly property var chosen: {
        const all = libs.concat(drivers, apps);
        void picked; void installed;   // пересчитать при выборе и после установки
        return all.filter(it => isOn(it));
    }
    function count(tab) { return tab.items.filter(it => isOn(it)).length; }

    // { pkgs: [...], aur: [...] } — что передать delta-setup install
    function plan(items) {
        const pkgs = [], aur = [];
        const push = (arr, p) => { if (arr.indexOf(p) === -1) arr.push(p); };
        // драйвер 580 сам даёт Vulkan для 32-битных игр — nouveau тогда не нужен
        const nv580 = drivers.find(d => d.id === "nvidia580");
        const vk = nv580 && (isInstalled(nv580) || items.indexOf(nv580) !== -1) ? [] : vulkanForGames;
        for (const it of items) {
            for (const p of it.pkgs || []) push(pkgs, p);
            for (const a of it.aur || []) push(aur, a);
            if (it.steam) for (const p of vk) push(pkgs, p);
        }
        // уже стоящее pacman пропустит сам (--needed), но список короче и понятнее
        return { pkgs: pkgs.filter(p => installed[p] !== true), aur: aur };
    }

    function refresh() {
        detect.running = true;
    }
    function checkInstalled() {
        const all = libs.concat(drivers, apps).reduce((a, it) => a.concat(names(it)), []);
        query.command = ["sh", "-c", "pacman -Qq \"$@\" 2>/dev/null; exit 0", "sh"].concat(all.concat(vulkanForGames));
        query.running = true;
    }

    // «GP102 [GeForce GTX 1080 Ti]» из lspci → «NVIDIA GeForce GTX 1080 Ti»
    function pretty(kind, raw) {
        const brand = { nvidia: "NVIDIA", amd: "AMD", intel: "Intel" }[kind] || "";
        const m = /\[([^\]]+)\]\s*$/.exec(raw);
        const model = m ? m[1] : raw;
        if (!model) return brand || "видеокарта";
        return brand && model.indexOf(brand) !== 0 ? brand + " " + model : model;
    }

    // поддельная видеокарта для проверок: DELTA_WELCOME_GPU="amd:0x73bf:Radeon RX 6800"
    readonly property string fakeGpu: Quickshell.env("DELTA_WELCOME_GPU") || ""

    Process {
        id: detect
        running: true
        command: ["delta-setup", "detect"]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "gpu") g.push({ kind: f[1], device: parseInt(f[2], 16) || 0, name: root.pretty(f[1], f[3] || "") });
                    else if (f[0] === "kernel") root.kernels = f[1].trim().split(/\s+/).filter(k => k.length);
                    else if (f[0] === "multilib") root.multilib = f[1] === "on";
                }
                if (root.fakeGpu) {
                    const f = root.fakeGpu.split(":");
                    g.splice(0, g.length, { kind: f[0], device: parseInt(f[1], 16) || 0, name: root.pretty(f[0], f.slice(2).join(":")) });
                }
                root.gpus = g;
                root.detected = true;
                root.checkInstalled();
            }
        }
    }

    Process {
        id: query
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const n of text.split("\n")) if (n.trim()) m[n.trim()] = true;
                root.installed = m;
            }
        }
    }
}
