pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.launcher.parts

// Рабочие столы: сетка столов с числом окон, нажатие — перейти.
// В Lua-режиме Hyprland диспетчеры — это выражения hl.dsp.*, а не «workspace 2».
Item {
    id: root

    implicitWidth: 320
    implicitHeight: col.implicitHeight
    signal close()

    readonly property int current: Hyprland.focusedWorkspace?.id ?? 1
    // обычные столы (у именованных и спецстолов id отрицательный)
    readonly property var real: Hyprland.workspaces.values.filter(w => w.id > 0)
    readonly property var ids: {
        let max = 4;
        for (const w of real) max = Math.max(max, w.id);
        const out = [];
        for (let i = 1; i <= max; i++) out.push(i);
        return out;
    }
    readonly property var counts: {
        const c = {};
        for (const t of Hyprland.toplevels.values) {
            const id = t.workspace?.id ?? 0;
            if (id > 0) c[id] = (c[id] || 0) + 1;
        }
        return c;
    }

    function dispatch(lua, legacy) {
        Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
    }
    function go(id) {
        dispatch("hl.dsp.focus({ workspace = " + id + " })", "workspace " + id);
        root.close();
    }
    function windows(n) {
        if (!n) return "Пусто";
        const m10 = n % 10, m100 = n % 100;
        const w = m10 === 1 && m100 !== 11 ? "окно" : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? "окна" : "окон";
        return n + " " + w;
    }

    onVisibleChanged: if (visible) { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        MenuTitle { text: I18n.tr("Рабочие столы") }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: root.ids
                delegate: MenuRow {
                    required property int modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    active: modelData === root.current
                    title: I18n.tr("Стол ") + modelData
                    subtitle: root.windows(root.counts[modelData] || 0)
                    onClicked: root.go(modelData)
                }
            }
        }

        Btn {
            Layout.alignment: Qt.AlignLeft
            kind: "ghost"
            icon: "plus"
            text: I18n.tr("Новый рабочий стол")
            implicitHeight: 32
            onClicked: { root.dispatch("hl.dsp.focus({ workspace = \"empty\" })", "workspace empty"); root.close(); }
        }
    }
}
