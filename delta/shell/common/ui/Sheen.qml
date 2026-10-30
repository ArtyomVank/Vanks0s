import QtQuick
import Quickshell
import qs.common
import "../../wallpaper/media.js" as Media

// «Жидкое стекло» поверх подложки (shaders/sheen.frag): линза — в середине
// чистое стекло, у края фон изгибается, по кромке тонкий блик. Виден только
// в стиле «Жидкое стекло». Кладётся первым ребёнком подложки — тогда
// содержимое рисуется поверх.
//     Rectangle { radius: 18; color: Theme.glass; Sheen { radius: 18; refract: true } }
//
// refract — сам рисовать преломлённые обои (доки, виджеты: за ними обои).
// Лаунчеру и меню, которые бывают поверх окон, это не подходит: им фон даёт
// размытие Hyprland, а здесь рисуются только блик и свечение.
ShaderEffect {
    id: root

    property real radius: Theme.radius
    property real strength: 1
    property bool refract: false

    readonly property size area: Qt.size(width, height)
    readonly property real frost: Theme.frost
    readonly property real lightBg: Theme.light ? 1 : 0
    // тон стекла: прозрачное — едва тонировано, матовое — заметнее
    readonly property vector4d tint: Qt.vector4d(Theme.base.r, Theme.base.g, Theme.base.b, 0.12 + 0.28 * Theme.frost)

    // --- обои за стеклом ---
    // у видеообоев — их кадр-заставка (wallpaper.poster)
    readonly property string wallFile: {
        const f = Settings.get("wallpaper.path", "");
        if (!f) return "";
        return Media.isVideo(f) || Settings.get("wallpaper.video", false) === true ? Settings.get("wallpaper.poster", "") : f;
    }
    readonly property bool wanted: refract && Theme.liquid && wallFile !== ""
    Image {
        id: wall
        visible: false
        source: root.wanted ? Media.fileUrl(root.wallFile) : ""
        sourceSize.width: 1600
        asynchronous: true
        mipmap: true
        cache: true
    }
    property variant source: wall
    readonly property real hasWall: wanted && wall.status === Image.Ready && wall.implicitWidth > 0 ? 1 : 0

    readonly property var win: QsWindow.window
    readonly property var scr: win ? win.screen : null
    // обои на экране — как их кладёт wallpaper/Wallpaper.qml («заполнить» или «вписать»)
    readonly property vector4d wallRect: {
        if (!scr || hasWall < 0.5) return Qt.vector4d(0, 0, 1, 1);
        const W = scr.width, H = scr.height, iw = wall.implicitWidth, ih = wall.implicitHeight;
        const k = Settings.get("wallpaper.fill", "cover") === "contain" ? Math.min(W / iw, H / ih) : Math.max(W / iw, H / ih);
        return Qt.vector4d((W - iw * k) / 2, (H - ih * k) / 2, iw * k, ih * k);
    }
    // где стекло на экране: место в окне + место окна-панели на экране (по якорям)
    property point origin
    function place() {
        if (!win || !scr || hasWall < 0.5) return;
        const p = root.mapToItem(null, 0, 0);
        const a = win.anchors, m = win.margins;
        let ox = 0, oy = 0;
        if (a && m) {
            ox = a.left && a.right ? 0 : a.left ? m.left : a.right ? scr.width - win.width - m.right : (scr.width - win.width) / 2;
            oy = a.top && a.bottom ? 0 : a.top ? m.top : a.bottom ? scr.height - win.height - m.bottom : (scr.height - win.height) / 2;
        }
        const o = Qt.point(Math.round(ox + p.x), Math.round(oy + p.y));
        if (o.x !== origin.x || o.y !== origin.y) origin = o;
    }
    // панели ездят (доки, перетаскивание виджетов) — сверяем место несколько раз в секунду
    Timer {
        interval: 200
        repeat: true
        triggeredOnStart: true
        running: root.hasWall > 0.5 && root.visible
        onTriggered: root.place()
    }
    onWidthChanged: place()
    onHeightChanged: place()

    anchors.fill: parent
    visible: Theme.liquid && width > 2 && height > 2
    fragmentShader: Qt.resolvedUrl("shaders/sheen.frag.qsb")
}
