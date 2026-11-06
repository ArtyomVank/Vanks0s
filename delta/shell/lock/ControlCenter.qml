pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.display
import qs.services

// Центр управления стиля «Акрил» (Theme.round) — меню кнопки питания верхнего
// дока (menus/PowerMenu.qml). Сверху дата, аптайм и заряд, карандаш — правка.
// Блоки (power.cc.blocks — порядок и какие видны; power.cc.sizes — какие
// в половину ширины: { id: "half" }, две половинки подряд встают рядом):
//   media         музыка и вертикальные ползунки света и звука;
//   music         только музыка;
//   sliders       только ползунки света и звука;
//   net           Wi-Fi и Bluetooth — широкие кнопки, нажатие открывает их меню;
//   toggles       круглые кнопки (power.cc.toggles — какие и в каком порядке);
//   vpn           подключения VPN (services/Vpn.qml);
//   notifications последние уведомления.
// Внизу всегда — кнопки питания: перезагрузку и выключение нужно зажать.
ColumnLayout {
    id: root

    signal close()
    property var screen: null

    implicitWidth: 400
    spacing: 12

    property bool editing: false
    property string confirm: ""

    // ---------- блоки ----------
    readonly property var blockCatalog: ({
        media: { name: "Музыка, свет и звук", icon: "music" },
        music: { name: "Музыка", icon: "play" },
        sliders: { name: "Свет и звук", icon: "sliders" },
        net: { name: "Wi-Fi и Bluetooth", icon: "wifi" },
        toggles: { name: "Быстрые кнопки", icon: "grid" },
        vpn: { name: "VPN", icon: "vpn" },
        notifications: { name: "Уведомления", icon: "bell" }
    })
    readonly property var blockOrder: ["media", "music", "sliders", "net", "toggles", "vpn", "notifications"]
    readonly property var blocks: {
        const b = Settings.get("power.cc.blocks", null);
        return Array.isArray(b) ? b.filter(id => blockCatalog[id] !== undefined) : ["media", "net", "toggles", "notifications"];
    }
    readonly property var hiddenBlocks: blockOrder.filter(id => blocks.indexOf(id) === -1)
    function moveBlock(id, d) {
        const list = blocks.slice();
        const i = list.indexOf(id), j = i + d;
        if (i < 0 || j < 0 || j >= list.length) return;
        list.splice(i, 1);
        list.splice(j, 0, id);
        Settings.set("power.cc.blocks", list);
    }
    function removeBlock(id) { Settings.set("power.cc.blocks", blocks.filter(x => x !== id)); }
    function addBlock(id) { Settings.set("power.cc.blocks", blocks.concat([id])); }
    // половина ширины — всем, кроме «Музыки, света и звука»: им тесно
    readonly property var sizes: Settings.get("power.cc.sizes", null) ?? ({})
    function isHalf(id) { return id !== "media" && sizes[id] === "half"; }
    function toggleSize(id) {
        const s = Object.assign({}, sizes);
        if (isHalf(id)) delete s[id]; else s[id] = "half";
        Settings.set("power.cc.sizes", s);
    }

    // ---------- круглые кнопки ----------
    readonly property var toggleOrder: ["dnd", "night", "vpn", "hdr", "mic", "airplane", "screenshot", "performance"]
    readonly property var toggles: {
        const t = Settings.get("power.cc.toggles", null);
        return (Array.isArray(t) ? t : ["dnd", "night", "vpn", "hdr", "mic", "screenshot", "performance"])
            .filter(id => toggleOrder.indexOf(id) !== -1);
    }
    function removeToggle(id) { Settings.set("power.cc.toggles", toggles.filter(x => x !== id)); }
    function addToggle(id) { Settings.set("power.cc.toggles", toggles.concat([id])); }

    readonly property bool dnd: Settings.get("notifications.dnd", ShellState.dnd) === true
    readonly property PwNode mic: Pipewire.defaultAudioSource
    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.mic, root.sink] }
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool airplane: !Networking.wifiEnabled && !(btAdapter?.enabled ?? false)

    function toggleName(id) {
        return ({ dnd: "Не беспокоить", night: "Ночной свет", vpn: "VPN", hdr: "HDR в играх", mic: "Микрофон",
                  airplane: "В самолёте", screenshot: "Скриншот", performance: "Мощность" })[id] || id;
    }
    function toggleIcon(id) {
        if (id === "mic") return root.mic?.audio?.muted ? "mic-off" : "mic";
        if (id === "dnd") return "bell-off";
        return ({ night: "night-light", vpn: "vpn", hdr: "hdr", airplane: "airplane", screenshot: "screenshot", performance: "gauge" })[id] || "info";
    }
    function toggleOn(id) {
        switch (id) {
        case "dnd": return root.dnd;
        case "night": return NightLight.enabled;
        case "vpn": return Vpn.active;
        case "hdr": return Settings.get("display.autoHdr", false) === true;
        case "mic": return root.mic !== null && root.mic.audio !== null && !root.mic.audio.muted;
        case "airplane": return root.airplane;
        }
        return false;
    }
    // подпись под кнопкой VPN — имя подключения, если оно одно
    function toggleCaption(id) {
        if (id === "vpn" && !root.editing && Vpn.active && Vpn.activeName) return Vpn.activeName;
        return I18n.tr(toggleName(id));
    }
    function press(id) {
        switch (id) {
        case "dnd":
            Settings.set("notifications.dnd", !root.dnd);
            ShellState.dnd = !root.dnd;
            break;
        case "night": NightLight.toggle(); break;
        case "vpn": {
            // одно своё подключение — переключаем его; иначе — включённое выключаем,
            // а если ничего не включено — поднимаем первое
            const own = Vpn.own;
            const on = own.find(c => c.active);
            if (on) Vpn.toggle(on.uuid);
            else if (own.length) Vpn.toggle(own[0].uuid);
            else if (!Vpn.active) { root.close(); ShellState.openSettings("network"); }
            break;
        }
        case "hdr": Displays.setAutoHdr(!toggleOn("hdr")); break;
        case "mic": if (root.mic?.audio) root.mic.audio.muted = !root.mic.audio.muted; break;
        case "airplane": {
            const on = !root.airplane;
            Networking.wifiEnabled = !on;
            if (root.btAdapter) root.btAdapter.enabled = !on;
            break;
        }
        case "screenshot":
            // как Print (shell.qml), но сначала даём меню закрыться
            root.close();
            Quickshell.execDetached(["sh", "-c", 'sleep 0.35; g=$(slurp) && grim -g "$g" - | wl-copy -t image/png && delta-shell ipc call fx flash' + Sounds.shell("camera-shutter")]);
            break;
        case "performance": root.close(); ShellState.openSettings("performance"); break;
        }
    }

    // пока меню открыто, список VPN обновляется
    Binding { target: Vpn; property: "watch"; value: root.visible; when: root.visible; restoreMode: Binding.RestoreValue }

    // ---------- шапка: дата, аптайм, заряд ----------
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var weekdays: ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    readonly property var months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property string dateText: {
        const d = clock.date;
        if (I18n.ru) return weekdays[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()];
        const s = Qt.locale(I18n.locale).toString(d, "dddd, d MMMM");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    FileView { id: uptimeFile; path: "/proc/uptime" }
    readonly property string uptime: {
        clock.date;
        const sec = Number(String(uptimeFile.text() || "0").split(" ")[0]) || 0;
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60);
        return h + ":" + String(m).padStart(2, "0");
    }
    onVisibleChanged: if (visible) uptimeFile.reload()
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat !== null && bat.ready && bat.isLaptopBattery && bat.isPresent
    readonly property int percent: bat ? Math.round(bat.percentage > 1 ? bat.percentage : bat.percentage * 100) : 0
    readonly property string subText: {
        const parts = [I18n.tr("аптайм") + " " + uptime];
        if (hasBattery) {
            parts.push(percent + "%");
            const t = bat.timeToEmpty;
            if (t > 0) parts.push(Math.floor(t / 3600) + " " + I18n.tr("ч") + " " + Math.floor(t % 3600 / 60) + " " + I18n.tr("мин"));
        }
        return parts.join(" · ");
    }

    // ---------- общие кусочки ----------
    // круглая кнопка-значок в шапке
    component RoundIcon: Rectangle {
        id: ri
        property string icon
        property bool accent: false
        signal clicked()
        implicitWidth: 38; implicitHeight: 38
        radius: height / 2
        color: accent ? Theme.accent : riHov.hovered ? Theme.soft2 : Theme.soft
        scale: riTap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
        Sym { anchors.centerIn: parent; name: ri.icon; size: 18; color: ri.accent ? Theme.onAccent : Theme.fg }
        HoverHandler { id: riHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: riTap; onTapped: ri.clicked() }
    }

    // плитка блока: мягкая подложка
    component Tile: Rectangle {
        radius: Math.max(14, Theme.radius - 4)
        color: Theme.soft
        border.width: Theme.acrylic ? 0 : 1
        border.color: Theme.line
        Contour { radius: parent.radius; strength: 0.55 }
    }

    // вертикальный ползунок-капсула: заливка снизу, значок внизу
    component VSlider: ClippingRectangle {
        id: vs
        property real value: 0
        property string icon
        signal moved(real v)
        Layout.preferredWidth: 62
        Layout.fillHeight: true
        radius: 26
        color: Theme.soft2
        readonly property color fillColor: Theme.light ? Theme.accent : Qt.rgba(1, 0.97, 0.93, 0.94)
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.max(vs.width * 0.8, vs.height * Math.max(0, Math.min(1, vs.value)))
            color: vs.fillColor
            Behavior on height { enabled: !vsDrag.pressed; NumberAnimation { duration: Theme.anim.fast } }
        }
        Sym {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
            name: vs.icon
            size: 20
            color: Theme.light ? Theme.onAccent : "#2A1D10"
        }
        MouseArea {
            id: vsDrag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function upd(y) { vs.moved(Math.max(0, Math.min(1, 1 - y / height))); }
            onPressed: m => upd(m.y)
            onPositionChanged: m => { if (pressed) upd(m.y); }
            onWheel: w => vs.moved(Math.max(0, Math.min(1, vs.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    // горизонтальный ползунок-капсула: заливка слева, значок и подпись внутри
    component HSlider: ClippingRectangle {
        id: hs
        property real value: 0
        property string icon
        property string title
        signal moved(real v)
        radius: height / 2
        color: Theme.soft2
        readonly property color fillColor: Theme.light ? Theme.accent : Qt.rgba(1, 0.97, 0.93, 0.94)
        readonly property real shown: Math.max(height, width * Math.max(0, Math.min(1, value)))
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: hs.shown
            color: hs.fillColor
            Behavior on width { enabled: !hsDrag.pressed; NumberAnimation { duration: Theme.anim.fast } }
        }
        Sym {
            id: hsIcon
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            name: hs.icon
            size: 20
            color: Theme.light ? Theme.onAccent : "#2A1D10"
        }
        Label {
            anchors { left: hsIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: hs.title
            size: "small"
            font.weight: Font.Bold
            // поверх заливки — тёмная, на пустой части — обычная
            color: hs.shown > x + width ? (Theme.light ? Theme.onAccent : "#2A1D10") : Theme.fg
        }
        Label {
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            text: Math.round(Math.max(0, Math.min(1, hs.value)) * 100) + "%"
            num: true
            size: "small"
            tone: 2
        }
        MouseArea {
            id: hsDrag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function upd(x) { hs.moved(Math.max(0, Math.min(1, x / width))); }
            onPressed: m => upd(m.x)
            onPositionChanged: m => { if (pressed) upd(m.x); }
            onWheel: w => hs.moved(Math.max(0, Math.min(1, hs.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    // плитка музыки: обложка, название, прогресс, кнопки
    component PlayerTile: Tile {
        id: mb
        readonly property var players: Mpris.players.values
        readonly property MprisPlayer player: players.find(p => p.isPlaying) || players[0] || null
        readonly property bool playing: player !== null && player.isPlaying

        Timer {
            running: mb.playing && root.visible && (mb.player?.positionSupported ?? false)
            interval: 1000
            repeat: true
            onTriggered: mb.player.positionChanged()
        }
        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 8
            RowLayout {
                spacing: 10
                ClippingRectangle {
                    implicitWidth: 42; implicitHeight: 42; radius: 21
                    color: Theme.soft2
                    Image {
                        anchors.fill: parent
                        source: mb.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(84, 84)
                        visible: status === Image.Ready
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        visible: !(mb.player?.trackArtUrl)
                        width: 12; height: 12; radius: 6
                        color: Theme.accent
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: mb.player ? (mb.player.trackTitle || mb.player.identity || I18n.tr("Без названия")) : I18n.tr("Ничего не играет"); size: "small"; font.weight: Font.Bold }
                    Label { Layout.fillWidth: true; text: mb.player ? (mb.player.trackArtist || mb.player.identity || "") : I18n.tr("Включите музыку"); size: "caption"; tone: 3 }
                }
            }
            Item { Layout.fillHeight: true }
            // светящаяся полоса прогресса
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 5
                radius: 2.5
                color: Theme.soft2
                Rectangle {
                    id: prog
                    height: parent.height
                    radius: parent.radius
                    width: mb.player && mb.player.lengthSupported && mb.player.length > 0
                        ? parent.width * Math.min(1, mb.player.position / mb.player.length) : 0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.tint(0.3) }
                        GradientStop { position: 1; color: Theme.accent }
                    }
                }
                RectangularShadow {
                    visible: Theme.acrylic && prog.width > 4
                    x: prog.width - 8; y: -4
                    width: 14; height: 13; radius: 6.5
                    blur: 10
                    color: Theme.tint(0.8)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: ["prev", "play", "next"]
                    delegate: Item {
                        id: mc
                        required property string modelData
                        readonly property bool main: modelData === "play"
                        Layout.fillWidth: true
                        implicitHeight: 42
                        Rectangle {
                            anchors.centerIn: parent
                            width: mc.main ? 42 : 34; height: width; radius: width / 2
                            color: mc.main ? (Theme.light ? Theme.accent : "#FFF6EA") : mcHov.hovered ? Theme.soft2 : "transparent"
                            opacity: mb.player ? 1 : 0.4
                            scale: mcTap.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                            Sym {
                                anchors.centerIn: parent
                                name: mc.main ? (mb.playing ? "pause" : "play") : mc.modelData
                                size: mc.main ? 18 : 16
                                color: mc.main ? (Theme.light ? Theme.onAccent : "#2A1D10") : Theme.fg
                            }
                            HoverHandler { id: mcHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                id: mcTap
                                enabled: mb.player !== null
                                onTapped: mc.main ? mb.player.togglePlaying() : mc.modelData === "prev" ? mb.player.previous() : mb.player.next()
                            }
                        }
                    }
                }
            }
        }
    }

    // широкая кнопка: Wi-Fi, Bluetooth, VPN
    component WideChip: Rectangle {
        id: wc
        property string icon
        property string title
        property string sub
        property bool on: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 64
        radius: 32
        color: on ? Theme.tint(Theme.light ? 0.9 : 0.82) : wcHov.hovered ? Theme.soft2 : Theme.soft
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
        scale: wcTap.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
        RectangularShadow {
            z: -1
            anchors.fill: parent
            visible: Theme.acrylic && wc.on
            radius: parent.radius
            blur: 18
            color: Theme.tint(0.35)
        }
        Rectangle {
            id: wcIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width: 44; height: 44; radius: 22
            color: wc.on ? Qt.rgba(0, 0, 0, 0.14) : Theme.soft2
            Sym { anchors.centerIn: parent; name: wc.icon; size: 20; color: wc.on ? Theme.onAccent : Theme.fg }
        }
        Column {
            anchors { left: wcIcon.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            Label { width: parent.width; text: wc.title; size: "small"; font.weight: Font.Bold; color: wc.on ? Theme.onAccent : Theme.fg }
            Label { width: parent.width; text: wc.sub; num: true; size: "caption"; color: wc.on ? Theme.onAccent : Theme.fg3; opacity: wc.on ? 0.75 : 1 }
        }
        HoverHandler { id: wcHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: wcTap; onTapped: wc.clicked() }
    }

    // ---------- шапка ----------
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: root.dateText; size: "title"; font.weight: Font.ExtraBold }
            Label { Layout.fillWidth: true; text: root.subText; num: true; size: "caption"; tone: 3 }
        }
        RoundIcon {
            icon: root.editing ? "check" : "edit"
            accent: root.editing
            onClicked: root.editing = !root.editing
        }
        RoundIcon {
            visible: !root.editing
            icon: "settings"
            onClicked: { root.close(); ShellState.openSettings("power"); }
        }
    }

    // ---------- блоки ----------
    // две колонки: целый блок занимает обе, половинки встают рядом
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 12
    Repeater {
        model: root.blocks
        delegate: ColumnLayout {
            id: blk
            required property string modelData
            required property int index
            readonly property bool half: root.isHalf(modelData)
            Layout.columnSpan: half ? 1 : 2
            Layout.fillWidth: true
            Layout.preferredWidth: half ? 1 : 2
            Layout.alignment: Qt.AlignTop
            spacing: 6
            // VPN без подключений вне правки не показываем
            visible: root.editing || modelData !== "vpn" || Vpn.available

            // полоска правки: название, выше/ниже, убрать
            Rectangle {
                visible: root.editing
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 17
                color: Theme.tint(0.14)
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 4 }
                    spacing: 4
                    Sym { name: root.blockCatalog[blk.modelData].icon; size: 16; color: Theme.accent }
                    // у половинки места на название нет — только значок
                    Label { visible: !blk.half; Layout.fillWidth: true; text: I18n.tr(root.blockCatalog[blk.modelData].name); size: "small"; font.weight: Font.Bold }
                    Item { visible: blk.half; Layout.fillWidth: true }
                    // половинка двигается влево-вправо, целый блок — вверх-вниз;
                    // act 2 — размер (у «Музыки, света и звука» его нет)
                    Repeater {
                        model: [{ icon: blk.half ? "chevron-left" : "chevron-up", act: -1 },
                                { icon: blk.half ? "chevron-right" : "chevron-down", act: 1 }]
                            .concat(blk.modelData === "media" ? [] : [{ icon: blk.half ? "maximize" : "restore", act: 2 }])
                            .concat([{ icon: "close", act: 0 }])
                        delegate: Rectangle {
                            id: eb
                            required property var modelData
                            readonly property bool can: modelData.act === 0 || modelData.act === 2
                                || (modelData.act < 0 ? blk.index > 0 : blk.index < root.blocks.length - 1)
                            width: 28; height: 28; radius: 14
                            opacity: can ? 1 : 0.3
                            color: ebHov.hovered && can ? Theme.soft2 : "transparent"
                            Sym { anchors.centerIn: parent; name: eb.modelData.icon; size: 14 }
                            HoverHandler { id: ebHov; cursorShape: eb.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler {
                                enabled: eb.can
                                onTapped: eb.modelData.act === 0 ? root.removeBlock(blk.modelData)
                                    : eb.modelData.act === 2 ? root.toggleSize(blk.modelData)
                                    : root.moveBlock(blk.modelData, eb.modelData.act)
                            }
                        }
                    }
                }
            }
            Loader {
                // блоки читают parent.half — узкий вид
                readonly property bool half: blk.half
                Layout.fillWidth: true
                sourceComponent: blk.modelData === "media" ? mediaBlock
                    : blk.modelData === "music" ? musicBlock
                    : blk.modelData === "sliders" ? slidersBlock
                    : blk.modelData === "net" ? netBlock
                    : blk.modelData === "toggles" ? togglesBlock
                    : blk.modelData === "vpn" ? vpnBlock
                    : notifBlock
            }
        }
    }
    }

    // правка: блоки, которых сейчас нет
    ColumnLayout {
        visible: root.editing && root.hiddenBlocks.length > 0
        Layout.fillWidth: true
        spacing: 6
        Label { text: I18n.tr("Добавить"); size: "small"; tone: 3; font.weight: Font.Bold }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.hiddenBlocks
                delegate: Rectangle {
                    id: hb
                    required property string modelData
                    width: hbRow.implicitWidth + 24; height: 34; radius: 17
                    color: hbHov.hovered ? Theme.soft2 : Theme.soft
                    border.color: Theme.line
                    Row {
                        id: hbRow
                        anchors.centerIn: parent
                        spacing: 6
                        Sym { anchors.verticalCenter: parent.verticalCenter; name: "plus"; size: 14; color: Theme.accent }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(root.blockCatalog[hb.modelData].name); size: "small"; font.weight: Font.DemiBold }
                    }
                    HoverHandler { id: hbHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.addBlock(hb.modelData) }
                }
            }
        }
    }

    // ---------- кнопки питания ----------
    RowLayout {
        visible: root.confirm === "" && !root.editing
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 8
        Repeater {
            model: ["lock", "logout", "suspend", "hibernate", "reboot", "poweroff"]
                .filter(a => a !== "hibernate" || PowerActions.canHibernate)
            delegate: ColumnLayout {
                id: pb
                required property string modelData
                readonly property bool danger: modelData === "poweroff"
                readonly property bool hold: PowerActions.needsHold(modelData)
                readonly property string glyph: modelData === "suspend" ? "sleep" : modelData === "reboot" ? "restart"
                    : modelData === "poweroff" ? "power" : modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 5
                ClippingRectangle {
                    id: pbc
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 50; implicitHeight: 50
                    radius: 25
                    color: pbHov.hovered ? Theme.soft2 : Theme.soft
                    scale: (pbTap.pressed ? 0.92 : 1) + charge.level * 0.06
                    Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                    HoldCharge {
                        id: charge
                        holdTime: 1200
                        onCompleted: { root.close(); PowerActions.run(pb.modelData); refill.start(); }
                    }
                    Timer { id: refill; interval: 700; onTriggered: charge.reset() }
                    Liquid {
                        anchors.fill: parent
                        level: charge.level
                        still: charge.done
                        color: pb.danger ? "#e5484d" : Theme.accent
                        waveHeight: 3
                    }
                    Sym {
                        anchors.centerIn: parent
                        name: pb.glyph
                        size: 20
                        color: charge.level > 0.5 ? (pb.danger ? "#ffffff" : Theme.onAccent) : pb.danger ? "#ff6b6b" : Theme.fg
                    }
                    HoverHandler { id: pbHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: pbTap
                        onPressedChanged: if (pb.hold) { if (pressed) charge.begin(); else charge.cancel(); }
                        onTapped: {
                            if (pb.hold) return;
                            if (PowerActions.needsConfirm(pb.modelData)) root.confirm = pb.modelData;
                            else { root.close(); PowerActions.run(pb.modelData); }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: pb.hold && (charge.active || pbTap.pressed) ? I18n.tr("Держите") : I18n.tr(PowerActions.labels[pb.modelData])
                    size: "caption"
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 9
                    tone: 2
                }
            }
        }
    }

    // подтверждение выхода
    Tile {
        visible: root.confirm !== ""
        Layout.fillWidth: true
        implicitHeight: confirmCol.implicitHeight + 28
        ColumnLayout {
            id: confirmCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
            spacing: 10
            Label { text: I18n.tr("Выйти из системы?"); size: "title"; Layout.fillWidth: true }
            Label { text: I18n.tr("Все программы будут закрыты."); size: "small"; tone: 3; Layout.fillWidth: true }
            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignRight
                Btn { text: I18n.tr("Отмена"); onClicked: root.confirm = "" }
                Btn { text: I18n.tr(PowerActions.labels[root.confirm] || ""); kind: "accent"; onClicked: { root.close(); PowerActions.run(root.confirm); } }
            }
        }
    }

    // ================= блоки =================

    // --- музыка, свет и звук ---
    Component {
        id: mediaBlock
        Item {
            implicitHeight: 178
            RowLayout {
                anchors.fill: parent
                spacing: 10
                PlayerTile { Layout.fillWidth: true; Layout.fillHeight: true }
                VSlider {
                    visible: Brightness.available
                    icon: "sun"
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }
                VSlider {
                    icon: root.sink?.audio?.muted ? "volume-mute" : "volume"
                    value: root.sink?.audio?.volume ?? 0
                    onMoved: v => { if (root.sink?.audio) root.sink.audio.volume = v; }
                }
            }
        }
    }

    // --- только музыка ---
    Component {
        id: musicBlock
        PlayerTile { implicitHeight: parent?.half ? 178 : 150 }
    }

    // --- только свет и звук: половинка — столбики, целый — полосы ---
    Component {
        id: slidersBlock
        GridLayout {
            readonly property bool half: parent?.half ?? false
            columns: half ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10
            Repeater {
                model: Brightness.available ? ["light", "sound"] : ["sound"]
                delegate: Loader {
                    id: sl
                    required property string modelData
                    readonly property bool light: modelData === "light"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: parent.half ? 178 : 56
                    sourceComponent: parent.half ? vert : horiz
                    Component {
                        id: vert
                        VSlider {
                            icon: sl.light ? "sun" : root.sink?.audio?.muted ? "volume-mute" : "volume"
                            value: sl.light ? Brightness.value : root.sink?.audio?.volume ?? 0
                            onMoved: v => sl.set(v)
                        }
                    }
                    Component {
                        id: horiz
                        HSlider {
                            icon: sl.light ? "sun" : root.sink?.audio?.muted ? "volume-mute" : "volume"
                            title: sl.light ? I18n.tr("Яркость") : I18n.tr("Громкость")
                            value: sl.light ? Brightness.value : root.sink?.audio?.volume ?? 0
                            onMoved: v => sl.set(v)
                        }
                    }
                    function set(v) {
                        if (light) Brightness.set(v);
                        else if (root.sink?.audio) root.sink.audio.volume = v;
                    }
                }
            }
        }
    }

    // --- Wi-Fi и Bluetooth ---
    Component {
        id: netBlock
        // половинка — кнопки друг под другом
        GridLayout {
            id: nb
            columns: parent?.half ? 1 : 2
            columnSpacing: 10
            rowSpacing: 10
            readonly property var devices: Networking.devices.values
            readonly property var wifiDev: devices.find(d => d.type === DeviceType.Wifi) ?? null
            readonly property bool wired: devices.some(d => d.type === DeviceType.Wired && d.connected)
            readonly property var net: wifiDev && Networking.wifiEnabled ? (wifiDev.networks.values.find(n => n.connected) ?? null) : null
            readonly property var btDev: (root.btAdapter?.devices?.values ?? []).find(d => d.connected) ?? null

            WideChip {
                icon: nb.net ? "wifi" : nb.wired ? "ethernet" : "wifi-off"
                title: nb.net ? nb.net.name : nb.wired ? I18n.tr("Кабель") : "Wi-Fi"
                sub: nb.net ? I18n.tr("Подключено") : nb.wired ? I18n.tr("Подключено") : Networking.wifiEnabled ? I18n.tr("Не подключено") : I18n.tr("Выключен")
                on: nb.net !== null || nb.wired
                onClicked: if (root.screen) ShellState.openMenu("wifi", root.screen)
            }
            WideChip {
                icon: "bluetooth"
                title: nb.btDev ? (nb.btDev.name || nb.btDev.deviceName || "Bluetooth") : "Bluetooth"
                sub: nb.btDev ? (nb.btDev.batteryAvailable ? Math.round(nb.btDev.battery * 100) + "%" : I18n.tr("Подключено"))
                    : root.btAdapter === null ? I18n.tr("Нет адаптера") : root.btAdapter.enabled ? I18n.tr("Включён") : I18n.tr("Выключен")
                on: nb.btDev !== null
                onClicked: if (root.screen) ShellState.openMenu("bluetooth", root.screen)
            }
        }
    }

    // --- круглые кнопки ---
    Component {
        id: togglesBlock
        GridLayout {
            columns: parent?.half ? 2 : 4
            columnSpacing: 6
            rowSpacing: 8
            Repeater {
                // в правке — ещё и те, которых нет (бледные, с «+»)
                model: root.editing ? root.toggles.concat(root.toggleOrder.filter(t => root.toggles.indexOf(t) === -1)) : root.toggles
                delegate: Item {
                    id: tg
                    required property string modelData
                    readonly property bool extra: root.toggles.indexOf(modelData) === -1
                    readonly property bool on: !root.editing && root.toggleOn(modelData)
                    // HDR — только если есть HDR-монитор
                    visible: root.editing || modelData !== "hdr" || Displays.anyHdr
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 88
                    opacity: extra ? 0.5 : 1

                    RectangularShadow {
                        anchors.fill: circ
                        visible: Theme.acrylic && tg.on
                        radius: circ.radius
                        blur: 18
                        color: Theme.tint(0.5)
                    }
                    Rectangle {
                        id: circ
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 58; height: 58; radius: 29
                        color: tg.on ? Theme.accent : tgHov.hovered ? Theme.soft2 : Theme.soft
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        scale: tgTap.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                        Sym { anchors.centerIn: parent; name: root.toggleIcon(tg.modelData); size: 22; color: tg.on ? Theme.onAccent : Theme.fg }
                        // правка: убрать или добавить
                        Rectangle {
                            visible: root.editing
                            anchors { right: parent.right; top: parent.top; rightMargin: -3; topMargin: -3 }
                            width: 22; height: 22; radius: 11
                            color: tg.extra ? Theme.accent : "#E5484D"
                            Sym { anchors.centerIn: parent; name: tg.extra ? "plus" : "minus"; size: 13; color: tg.extra ? Theme.onAccent : "#ffffff" }
                        }
                    }
                    Label {
                        anchors { top: circ.bottom; topMargin: 6; left: parent.left; right: parent.right }
                        horizontalAlignment: Text.AlignHCenter
                        text: root.toggleCaption(tg.modelData)
                        size: "caption"
                        tone: 2
                    }
                    HoverHandler { id: tgHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: tgTap
                        onTapped: {
                            if (!root.editing) root.press(tg.modelData);
                            else if (tg.extra) root.addToggle(tg.modelData);
                            else root.removeToggle(tg.modelData);
                        }
                    }
                }
            }
        }
    }

    // --- VPN ---
    Component {
        id: vpnBlock
        ColumnLayout {
            spacing: 8
            Repeater {
                model: Vpn.connections
                delegate: Tile {
                    id: vr
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 58
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 14 }
                        spacing: 10
                        Rectangle {
                            implicitWidth: 38; implicitHeight: 38; radius: 19
                            color: vr.modelData.active ? Theme.accent : Theme.soft2
                            Sym { anchors.centerIn: parent; name: "vpn"; size: 18; color: vr.modelData.active ? Theme.onAccent : Theme.fg }
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: vr.modelData.name; size: "small"; font.weight: Font.Bold }
                            Label {
                                Layout.fillWidth: true
                                text: !vr.modelData.own ? I18n.tr("Включён в своей программе")
                                    : Vpn.busy === vr.modelData.uuid ? I18n.tr("Подключение…")
                                    : vr.modelData.active ? I18n.tr("Подключено") : I18n.tr("Отключено")
                                size: "caption"; tone: 3
                            }
                        }
                        Toggle {
                            visible: vr.modelData.own
                            checked: vr.modelData.active
                            enabled: Vpn.busy === ""
                            onToggled: Vpn.toggle(vr.modelData.uuid)
                        }
                    }
                }
            }
            Tile {
                visible: Vpn.connections.length === 0
                Layout.fillWidth: true
                implicitHeight: 58
                Label {
                    anchors { fill: parent; margins: 14 }
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    text: I18n.tr("VPN не найден. Добавьте подключение в NetworkManager или включите VPN в своей программе.")
                    size: "caption"; tone: 3
                }
            }
        }
    }

    // --- уведомления ---
    Component {
        id: notifBlock
        ColumnLayout {
            spacing: 8
            readonly property var recent: root.dnd ? [] : (ShellState.notifications || []).slice(0, 3)
            Repeater {
                model: parent.recent
                delegate: Tile {
                    id: nt
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: Math.max(62, ntCol.implicitHeight + 22)
                    ClippingRectangle {
                        id: ntIcon
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 38; height: 38; radius: 12
                        color: Theme.accent
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.25) }
                                GradientStop { position: 1; color: Theme.accent }
                            }
                        }
                        Image {
                            id: ntImg
                            anchors.fill: parent
                            anchors.margins: 7
                            source: nt.modelData.appIcon || ""
                            sourceSize: Qt.size(48, 48)
                            visible: status === Image.Ready
                        }
                        Sym { anchors.centerIn: parent; visible: !ntImg.visible; name: "bell"; size: 18; color: Theme.onAccent }
                    }
                    ColumnLayout {
                        id: ntCol
                        anchors { left: ntIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: nt.modelData.summary || nt.modelData.app || ""; size: "small"; font.weight: Font.Bold }
                            Label {
                                num: true
                                text: {
                                    const m = Math.floor((clock.date.getTime() - (nt.modelData.time || 0)) / 60000);
                                    return m < 1 ? I18n.tr("сейчас") : m < 60 ? m + " " + I18n.tr("мин") : Qt.formatTime(new Date(nt.modelData.time), "HH:mm");
                                }
                                size: "caption"; tone: 3
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: String(nt.modelData.body || "").replace(/<[^>]*>/g, "")
                            textFormat: Text.PlainText
                            size: "caption"; tone: 2
                        }
                    }
                }
            }
            Tile {
                visible: parent.recent.length === 0
                Layout.fillWidth: true
                implicitHeight: 46
                Label {
                    anchors.centerIn: parent
                    text: root.dnd ? I18n.tr("Не беспокоить — уведомления скрыты") : I18n.tr("Новых уведомлений нет")
                    size: "small"; tone: 3
                }
            }
        }
    }

    Component.onCompleted: { PowerActions.refresh(); Vpn.refresh(); }
}
