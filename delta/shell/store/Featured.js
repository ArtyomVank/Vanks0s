.pragma library

// Подборка на главной магазина: разделы и приложения. pkg — пакет Arch
// (pacman), fp — id на Flathub; есть оба — источник выбирают на странице
// приложения (по умолчанию Arch: быстрее и общие библиотеки с системой).
// Название и описание — свои (title, text) или из каталога Flathub.

var sections = [
    { id: "popular", title: "Популярное", icon: "rocket", items: [
        { title: "Steam", pkg: "steam", fp: "com.valvesoftware.Steam", text: "Магазин игр и Proton — игры для Windows прямо в Vanks OS" },
        { title: "Discord", pkg: "discord", fp: "com.discordapp.Discord", text: "Голосовые каналы и чаты с друзьями" },
        { title: "Telegram", pkg: "telegram-desktop", fp: "org.telegram.desktop", text: "Быстрый мессенджер с каналами и звонками" },
        { title: "Chromium", pkg: "chromium", fp: "org.chromium.Chromium", text: "Быстрый браузер с синхронизацией закладок" },
        { title: "Firefox", pkg: "firefox", fp: "org.mozilla.firefox", text: "Свободный браузер, который бережёт приватность" },
        { title: "OBS Studio", pkg: "obs-studio", fp: "com.obsproject.Studio", text: "Запись экрана и стримы" },
        { title: "VLC", pkg: "vlc", fp: "org.videolan.VLC", text: "Плеер, который открывает всё" },
        { title: "Spotify", fp: "com.spotify.Client", text: "Музыка и подкасты" }
    ] },
    { id: "games", title: "Игры", icon: "gamepad", items: [
        { title: "Lutris", pkg: "lutris", fp: "net.lutris.Lutris", text: "Игры из Epic, GOG, Battle.net и эмуляторы в одном месте" },
        { title: "Heroic", fp: "com.heroicgameslauncher.hgl", text: "Игры Epic, GOG и Amazon без их лаунчеров" },
        { title: "Bottles", fp: "com.usebottles.bottles", text: "Программы Windows в отдельных «бутылках»" },
        { title: "Prism Launcher", pkg: "prismlauncher", fp: "org.prismlauncher.PrismLauncher", text: "Minecraft: версии, моды и сборки" },
        { title: "RetroArch", pkg: "retroarch", fp: "org.libretro.RetroArch", text: "Эмуляторы старых приставок в одном окне" },
        { title: "ProtonPlus", fp: "com.vysp3r.ProtonPlus", text: "Свежие Proton и Wine для Steam, Lutris и Heroic" },
        { title: "Sober", fp: "org.vinegarhq.Sober", text: "Roblox для Linux" }
    ] },
    { id: "work", title: "Работа и учёба", icon: "file", items: [
        { title: "LibreOffice", pkg: "libreoffice-fresh", fp: "org.libreoffice.LibreOffice", text: "Документы, таблицы и презентации, открывает файлы Office" },
        { title: "ONLYOFFICE", fp: "org.onlyoffice.desktopeditors", text: "Офис, похожий на Microsoft Office" },
        { title: "Obsidian", fp: "md.obsidian.Obsidian", text: "Заметки и база знаний в Markdown" },
        { title: "Thunderbird", pkg: "thunderbird", fp: "org.mozilla.thunderbird", text: "Почта, календарь и контакты" },
        { title: "LocalSend", fp: "org.localsend.localsend_app", text: "Файлы на телефон и другие компьютеры по Wi-Fi" },
        { title: "qBittorrent", pkg: "qbittorrent", fp: "org.qbittorrent.qBittorrent", text: "Торрент-клиент без рекламы" }
    ] },
    { id: "create", title: "Творчество", icon: "palette", items: [
        { title: "GIMP", pkg: "gimp", fp: "org.gimp.GIMP", text: "Обработка фотографий и рисование" },
        { title: "Krita", pkg: "krita", fp: "org.kde.krita", text: "Цифровая живопись и иллюстрации" },
        { title: "Inkscape", pkg: "inkscape", fp: "org.inkscape.Inkscape", text: "Векторная графика" },
        { title: "Blender", pkg: "blender", fp: "org.blender.Blender", text: "3D-моделирование, анимация и монтаж" },
        { title: "Kdenlive", pkg: "kdenlive", fp: "org.kde.kdenlive", text: "Видеоредактор" },
        { title: "Audacity", pkg: "audacity", fp: "org.audacityteam.Audacity", text: "Запись и обработка звука" }
    ] },
    { id: "media", title: "Музыка и видео", icon: "music", items: [
        { title: "mpv", pkg: "mpv", fp: "io.mpv.Mpv", text: "Лёгкий плеер для любых видео" },
        { title: "Amberol", fp: "io.bassi.Amberol", text: "Простой музыкальный плеер" },
        { title: "Shortwave", fp: "de.haeckerfelix.Shortwave", text: "Интернет-радио со всего мира" },
        { title: "Easy Effects", pkg: "easyeffects", fp: "com.github.wwmm.easyeffects", text: "Эквалайзер и эффекты для звука системы" }
    ] },
    { id: "dev", title: "Разработка", icon: "terminal", items: [
        { title: "Visual Studio Code", fp: "com.visualstudio.code", text: "Редактор кода от Microsoft" },
        { title: "Code - OSS", pkg: "code", text: "Свободная сборка VS Code из Arch" },
        { title: "Zed", pkg: "zed", fp: "dev.zed.Zed", text: "Очень быстрый редактор кода" },
        { title: "Godot", pkg: "godot", fp: "org.godotengine.Godot", text: "Движок для своих игр" }
    ] },
    { id: "system", title: "Система", icon: "settings", items: [
        { title: "Ресурсы", pkg: "resources", fp: "net.nokyan.Resources", text: "Загрузка процессора, видеокарты, памяти и диска" },
        { title: "Mission Center", fp: "io.missioncenter.MissionCenter", text: "Диспетчер задач и мониторинг" },
        { title: "Flatseal", fp: "com.github.tchx84.Flatseal", text: "Права приложений Flatpak" },
        { title: "GParted", pkg: "gparted", icon: "gparted", text: "Разделы дисков" },
        { title: "Timeshift", pkg: "timeshift", icon: "timeshift", text: "Снимки системы: откат после неудачного обновления" }
    ] }
];

function allFlatpaks() {
    var out = [];
    for (var i = 0; i < sections.length; i++)
        for (var j = 0; j < sections[i].items.length; j++)
            if (sections[i].items[j].fp) out.push(sections[i].items[j].fp);
    return out;
}
