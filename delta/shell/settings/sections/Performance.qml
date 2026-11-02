pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings

// Производительность: как работает процессор. Эконом — без турбо и с бережным
// регулятором, баланс — частота за нагрузкой, производительность — все ядра всегда
// на максимальной частоте. Режим применяет и хранит delta-setup performance от
// root; он же повторяет режим при загрузке (служба delta-performance).
ColumnLayout {
    id: root

    property string title: I18n.tr("Производительность")
    property string icon: "gauge"
    property string keywords: "процессор частота ядра турбо эконом экономия баланс максимальная режим игры"
    spacing: 18

    property string mode: ""   // eco | balance | performance | unsupported
    property string pending: ""
    property var info: null    // [ядер, средняя, самая низкая, самая высокая], МГц

    readonly property var modes: [
        { value: "eco", icon: "battery", title: I18n.tr("Эконом"),
          text: I18n.tr("Без турбо, частота растёт неохотно. Тише вентиляторы и дольше батарея, но программы и игры работают медленнее.") },
        { value: "balance", icon: "gauge", title: I18n.tr("Баланс"),
          text: I18n.tr("Частота идёт за нагрузкой: в простое низкая, под нагрузкой максимальная. Подходит почти всегда.") },
        { value: "performance", icon: "rocket", title: I18n.tr("Производительность"),
          text: I18n.tr("Все ядра всегда на максимальной частоте, даже в простое. Меньше просадок в играх, но больше нагрев, шум и расход энергии.") }
    ]

    function refresh() {
        Exec.read(["delta-setup", "performance", "mode"], (code, out) => root.mode = code === 0 ? out.trim() : "unsupported");
    }
    function readInfo() {
        Exec.read(["delta-setup", "performance", "info"], (code, out) => {
            const v = out.trim().split(/\s+/).map(Number);
            root.info = code === 0 && v.length === 4 && v.every(x => isFinite(x)) ? v : null;
        });
    }
    function pick(value) {
        if (value === mode || pending) return;
        pending = value;
        Exec.run(["pkexec", "delta-setup", "performance", value], {
            label: I18n.tr("Режим производительности"),
            done: () => {
                // в пробном режиме команда не выполняется — показываем выбранное
                if (Exec.dryRun) root.mode = value;
                else root.refresh();
                root.pending = "";
                root.readInfo();
            }
        });
    }
    function ghz(mhz) { return (mhz / 1000).toFixed(2).replace(".", ",") + " " + I18n.tr("ГГц"); }

    Component.onCompleted: { refresh(); readInfo(); }
    Timer { interval: 2000; running: root.visible; repeat: true; onTriggered: root.readInfo() }

    Card {
        title: I18n.tr("Режим работы процессора")

        Label {
            visible: root.mode === "unsupported"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            tone: 3
            text: I18n.tr("Частотой этого процессора система не управляет")
        }

        RowLayout {
            visible: root.mode !== "unsupported"
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: root.modes
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool current: root.mode === modelData.value
                    readonly property bool busy: root.pending === modelData.value

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: tileBody.implicitHeight + 28
                    radius: Theme.radius - 4
                    color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                        : area.containsMouse ? Theme.soft2 : Theme.soft
                    border.width: 1
                    border.color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

                    ColumnLayout {
                        id: tileBody
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 8
                        Sym {
                            name: tile.modelData.icon
                            size: 24
                            color: tile.current ? Theme.accent : Theme.fg2
                        }
                        Label {
                            Layout.fillWidth: true
                            text: tile.modelData.title
                            font.weight: Font.DemiBold
                        }
                        Label {
                            Layout.fillWidth: true
                            text: tile.busy ? I18n.tr("Применяю…") : tile.modelData.text
                            wrapMode: Text.WordWrap
                            size: "small"
                            tone: 2
                        }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.pending
                        onClicked: root.pick(tile.modelData.value)
                    }
                }
            }
        }

        SettingRow {
            visible: root.info !== null
            icon: "cpu"
            title: I18n.tr("Частота сейчас: ") + (root.info ? root.ghz(root.info[1]) : "")
            subtitle: root.info
                ? I18n.tr("Ядер: ") + root.info[0] + " · " + I18n.tr("самое медленное: ") + root.ghz(root.info[2]) + " · " + I18n.tr("самое быстрое: ") + root.ghz(root.info[3])
                : ""
        }
    }
}
