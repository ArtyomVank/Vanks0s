pragma Singleton

import QtQuick
import Quickshell

// Общее состояние оболочки — через него модули узнают друг о друге,
// не импортируя чужие файлы. Пишет тот, кто владеет состоянием (см. CONTRACTS.md).
Singleton {
    id: root

    // --- окна оболочки (одновременно открыто не больше одного) ---
    // "" | "launcher" | "wallpapers" | "power" | "notifications"
    property string overlay: ""
    function toggleOverlay(name) {
        if (overlay !== name && recentlyDismissed(name)) return;
        overlay = overlay === name ? "" : name;
    }
    function closeOverlay() { overlay = ""; }

    // Нажатие мимо окна (HyprlandFocusGrab) закрывает его раньше, чем до
    // кнопки дока доходит сам клик, — и кнопка открыла бы окно снова.
    // Закрытие захватом отмечаем, и такой клик просто ничего не открывает.
    property var dismissedAt: ({})
    function noteDismiss(name) {
        const d = Object.assign({}, dismissedAt);
        d[name] = Date.now();
        dismissedAt = d;
    }
    function recentlyDismissed(name) { return Date.now() - (dismissedAt[name] || 0) < 300; }

    // Окно приложений выдвигает оба дока (как в концепте).
    readonly property bool docksForced: overlay === "launcher"

    // --- меню модулей верхнего дока ---
    // id модуля, чьё меню открыто ("wifi", "sound", …), и монитор, где оно открыто
    property string menu: ""
    property var menuScreen: null
    // когда открыли текущее меню: второй щелчок двойного нажатия не должен его закрыть
    property real menuOpenedAt: 0
    function openMenu(id, screen) {
        if (menu !== id && recentlyDismissed("menu:" + id)) return;
        if (menu !== id) menuOpenedAt = Date.now();
        menu = id; menuScreen = screen;
    }
    function menuJustOpened() { return Date.now() - menuOpenedAt < 450; }
    function closeMenu() { menu = ""; menuScreen = null; }

    // --- меню рабочего стола (правый щелчок по обоям) ---
    // { screen, x, y } — где щёлкнули, в координатах экрана; null — закрыто
    property var desktopMenu: null
    function openDesktopMenu(screen, x, y) {
        if (overlay !== "") closeOverlay();
        closeMenu();
        desktopMenu = { screen: screen, x: x, y: y };
    }
    function closeDesktopMenu() { desktopMenu = null; }

    // --- «Настройки» (отдельный процесс) ---
    // Открывать через openSettings: окно выходит каплей из верхнего дока
    // (window/SettingsGhost.qml). from — прямоугольник на экране, откуда течёт
    // капля ({ x, y, w, h }), или null — середина верхнего дока.
    signal settingsRequested(string section, var from)
    function openSettings(section, from) { settingsRequested(section || "", from || null); }

    // --- плитка, из которой вытекает капля (docks/parts/Blob.qml) ---
    // Пока капля не оторвалась (и когда возвращается), плитка дока тянется
    // за ней: pull 0…1. Ключ — "<экран>/<что>": "@launcher", "@add",
    // ключ значка приложения, "top:<модуль>".
    property string pullKey: ""
    property real pull: 0
    // откуда течёт капля (координаты экрана) и её радиус: край острова дока
    // в этом месте вздувается каплей того же размера, и капля отрывается от него
    property point pullPoint: Qt.point(0, 0)
    property real pullR: 0
    // какие острова готовы рисовать каплю сами: "<экран>/top" | "<экран>/apps" → true.
    // Тогда всплывающая карточка не рисует каплю, пока та держится за край.
    property var islandReady: ({})

    // --- режимы ---
    property bool widgetEditing: false     // редактор виджетов рабочего стола (Super+W)
    property bool lockEditing: false       // редактор виджетов экрана блокировки
    property bool dockEditing: false       // перестановка модулей верхнего дока
    property bool locked: false            // экран заблокирован (пишет lock/)
    property bool unlocking: false         // идёт анимация разблокировки (пишет lock/)

    // --- данные, которые публикуют модули ---
    // notify/: последние уведомления для виджета на экране блокировки
    //   [{ id, app, appIcon, summary, body, time }]
    property var notifications: []
    property bool dnd: false
    // docks/: геометрия доков для «шарика из дока» и анимации сворачивания
    //   { "<имя экрана>": { top: {x, y, w, h, edge}, apps: {x, y, w, h, edge} } }
    property var dockGeometry: ({})
    // docks/: положение значка приложения в доке по классу окна
    //   { "<класс>": { screen, x, y, size } }
    property var appIconGeometry: ({})
}
