import QtQuick
import qs.common
import qs.common.ui
import qs.widgets.parts

// Таймер: кнопки 1/5/10/25 минут, кольцо убывает по мере отсчёта, нажатие
// по кольцу — пауза и продолжение. В конце — сигнал и вспышка кольца.
Base {
    id: root

    property real total: 0          // мс
    property real endAt: 0          // когда кончится (идёт)
    property real rest: 0           // сколько осталось (на паузе)
    property real now: Date.now()
    readonly property bool running: endAt > 0
    readonly property bool paused: !running && rest > 0
    readonly property bool idle: !running && !paused
    readonly property real remain: running ? Math.max(0, endAt - now) : rest
    property bool rang: false

    readonly property var presets: width > height * 1.5 ? [1, 5, 10, 25] : [1, 5, 10]

    function start(min) {
        total = min * 60000;
        endAt = Date.now() + total;
        rest = 0;
        rang = false;
        Sounds.play("pop");
    }
    function toggle() {
        if (running) { rest = remain; endAt = 0; Sounds.play("tick"); }
        else if (paused) { endAt = Date.now() + rest; rest = 0; Sounds.play("tick"); }
        else start(5);
    }
    function reset() { endAt = 0; rest = 0; total = 0; Sounds.play("oobe-back"); }
    function more() {
        if (running) endAt += 60000; else rest += 60000;
        total += 60000;
        Sounds.play("tick");
    }

    Timer {
        interval: 250
        repeat: true
        running: root.running
        onTriggered: {
            root.now = Date.now();
            if (root.remain <= 0) {
                root.endAt = 0;
                root.rest = 0;
                root.rang = true;
                flash.restart();
                Sounds.play("alarm-clock-elapsed", 0);
                ShellState.island({ kind: "timer", icon: "clock", title: I18n.tr("Таймер"), text: I18n.tr("Время вышло"), color: "#F09A2B", ms: 5000 });
            }
        }
    }

    function clock(ms) {
        const s = Math.ceil(ms / 1000), m = Math.floor(s / 60), h = Math.floor(m / 60);
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m % 60) + ":" + two(s % 60) : two(m) + ":" + two(s % 60);
    }

    WCaption { id: cap; cm: root.cm; text: I18n.tr("Таймер"); color: root.pal.c2; width: parent.width }

    Ring {
        id: ring
        anchors { horizontalCenter: parent.horizontalCenter; top: cap.bottom; topMargin: 2 * root.cm; bottom: chips.top; bottomMargin: 3 * root.cm }
        width: height
        value: root.idle ? (root.rang ? 100 : 0) : root.remain / Math.max(1, root.total) * 100
        color: root.paused ? root.pal.c3 : Theme.accent
        track: root.pal.track

        WText {
            anchors.centerIn: parent
            text: root.idle ? (root.rang ? I18n.tr("Готово") : "5:00") : root.clock(root.remain)
            px: (root.rang && root.idle ? 0.17 : 0.22) * ring.height
            display: true
            color: root.pal.c1
            opacity: root.idle && !root.rang ? 0.6 : 1
        }
        // пауза мигает
        SequentialAnimation on opacity {
            running: root.paused
            loops: Animation.Infinite
            onRunningChanged: if (!running) ring.opacity = 1
            NumberAnimation { to: 0.45; duration: 600 * Theme.anim.k; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 600 * Theme.anim.k; easing.type: Easing.InOutSine }
        }
        // вспышка, когда время вышло
        Rectangle {
            id: glow
            anchors.centerIn: parent
            width: parent.width; height: width
            radius: width / 2
            color: "transparent"
            border.width: parent.width * 0.06
            border.color: Theme.accent
            opacity: 0
        }
        ParallelAnimation {
            id: flash
            loops: 3
            NumberAnimation { target: glow; property: "opacity"; from: 0.9; to: 0; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: glow; property: "scale"; from: 1; to: 1.35; duration: 700; easing.type: Easing.OutCubic }
        }
        TapHandler { enabled: !root.editing; onTapped: root.toggle() }
        HoverHandler { enabled: !root.editing; cursorShape: Qt.PointingHandCursor }
    }

    // кнопки: пресеты, пока таймер стоит; «+1» и «сброс», пока идёт
    Row {
        id: chips
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        spacing: 3 * root.cm
        readonly property real h: Math.max(14, 13 * root.cm)

        component Chip: Rectangle {
            id: chip
            property string label
            property bool strong: false
            signal clicked()
            height: chips.h
            width: Math.max(height * 1.4, lbl.implicitWidth + height * 0.7)
            radius: height / 2
            color: strong ? Theme.accent : root.pal.track
            scale: tap.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 120 * Theme.anim.k; easing.type: Easing.OutBack } }
            WText {
                id: lbl
                anchors.centerIn: parent
                text: chip.label
                px: chip.height * 0.5
                font.weight: Font.DemiBold
                color: chip.strong ? "#ffffff" : root.pal.c1
            }
            TapHandler { id: tap; enabled: !root.editing; onTapped: chip.clicked() }
            HoverHandler { enabled: !root.editing; cursorShape: Qt.PointingHandCursor }
        }

        Repeater {
            model: root.idle ? root.presets : []
            delegate: Chip {
                required property int modelData
                label: modelData + (root.presets.length > 3 ? " " + I18n.tr("мин") : "")
                onClicked: root.start(modelData)
            }
        }
        Chip { visible: !root.idle; label: "+1"; onClicked: root.more() }
        Chip { visible: !root.idle; label: I18n.tr("Сброс"); strong: true; onClicked: root.reset() }
    }
}
