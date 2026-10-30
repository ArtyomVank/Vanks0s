import QtQuick
import Quickshell
import qs.common
import "../../wallpaper/media.js" as Media

// Обои за элементом — для шейдеров «жидкого стекла» (Sheen, Goo доков):
// texture — сами обои (у видеообоев — кадр-заставка), wallRect — где они
// лежат на экране, origin — где на экране левый верхний угол target.
// Место окна-панели на экране выводится из его якорей и отступов.
//     WallLens { id: lens; target: glass; active: Theme.liquid }
Item {
    id: root

    property Item target: parent
    property bool active: true

    readonly property string wallFile: {
        const f = Settings.get("wallpaper.path", "");
        if (!f) return "";
        return Media.isVideo(f) || Settings.get("wallpaper.video", false) === true ? Settings.get("wallpaper.poster", "") : f;
    }
    readonly property bool wanted: active && wallFile !== ""
    readonly property alias texture: wall
    readonly property bool ready: wanted && wall.status === Image.Ready && wall.implicitWidth > 0

    width: 0
    height: 0

    Image {
        id: wall
        visible: false
        source: root.wanted ? Media.fileUrl(root.wallFile) : ""
        sourceSize.width: 1600
        asynchronous: true
        mipmap: true
        cache: true
    }

    readonly property var win: QsWindow.window
    readonly property var scr: win ? win.screen : null
    // как кладёт обои wallpaper/Wallpaper.qml: «заполнить» или «вписать»
    readonly property vector4d wallRect: {
        if (!scr || !ready) return Qt.vector4d(0, 0, 1, 1);
        const W = scr.width, H = scr.height, iw = wall.implicitWidth, ih = wall.implicitHeight;
        const k = Settings.get("wallpaper.fill", "cover") === "contain" ? Math.min(W / iw, H / ih) : Math.max(W / iw, H / ih);
        return Qt.vector4d((W - iw * k) / 2, (H - ih * k) / 2, iw * k, ih * k);
    }

    property point origin
    function place() {
        if (!win || !scr || !ready || !target) return;
        const p = target.mapToItem(null, 0, 0);
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
        running: root.ready && (root.target?.visible ?? false)
        onTriggered: root.place()
    }
    Connections {
        target: root.target
        function onWidthChanged() { root.place(); }
        function onHeightChanged() { root.place(); }
    }
}
