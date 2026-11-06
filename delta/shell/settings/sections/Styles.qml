pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Стили и темы — три уровня оформления (см. Theme.qml):
//   «Стиль» — интерфейс (Theme.uiStyles): Delta и «Акрил»;
//   «Тема»  — материал панелей (Theme.styles): Delta, акриловое и жидкое
//             стекло, GNOME, Material You, Nothing;
//   «Цвет»  — цветокор (Theme.themes): оттенок поверхностей и акцент, в том
//             числе свои цвета пользователя.
ColumnLayout {
    id: root

    property string title: I18n.tr("Стили и темы")
    property string icon: "swatch"
    property string keywords: "стиль интерфейс тема материал акрил delta жидкое стекло акриловое material you gnome nothing цвет цветокор тёмная светлая свой цвет"
    spacing: 18

    // --- стиль: интерфейс ---
    Card {
        title: I18n.tr("Стиль")
        subtitle: I18n.tr("Как устроен интерфейс: панели, кнопки, ползунки")

        Item {
            Layout.fillWidth: true
            implicitHeight: uiRow.implicitHeight + 24
            RowLayout {
                id: uiRow
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 12
                Repeater {
                    model: Theme.uiStyles
                    delegate: StyleCard {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 250
                        kind: "style"
                        styleId: modelData.id
                        onClicked: Theme.applyUi(styleId)
                    }
                }
            }
        }
    }

    // --- тема: материал панелей ---
    Card {
        title: I18n.tr("Тема")
        subtitle: I18n.tr("Из чего сделаны панели: стекло, акрил, сплошной цвет")

        Item {
            Layout.fillWidth: true
            implicitHeight: matGrid.implicitHeight + 24
            GridLayout {
                id: matGrid
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                columns: 3
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: Theme.styles
                    delegate: StyleCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        kind: "theme"
                        styleId: modelData.id
                        onClicked: Theme.applyStyle(styleId)
                    }
                }
            }
        }
        SettingRow {
            visible: Theme.style === "delta"
            icon: "palette"
            title: I18n.tr("Подсветка")
            subtitle: I18n.tr("Текст светится цветом оформления или плитки под текстом подкрашены им")
            Chips {
                model: [{ value: "off", label: I18n.tr("Выкл") }, { value: "text", label: I18n.tr("Текст") }, { value: "tiles", label: I18n.tr("Плитки") }]
                current: Theme.highlight
                onPicked: v => Settings.set("appearance.highlight", v)
            }
        }
    }

    // --- цвет: цветокор ---
    Card {
        title: I18n.tr("Цвет")
        subtitle: I18n.tr("Оттенок панелей и акцент — для любого стиля и темы")

        Item {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight + 24
            GridLayout {
                id: grid
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                columns: 8
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: Theme.themes
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool sel: Theme.current.id === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 74
                        radius: 14
                        color: hov.hovered ? Theme.soft2 : "transparent"
                        border.width: 2
                        border.color: sel ? Theme.accent : Theme.line
                        Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
                            height: 38
                            radius: 9
                            color: Qt.rgba(tile.modelData.rgb[0] / 255, tile.modelData.rgb[1] / 255, tile.modelData.rgb[2] / 255, 1)
                            border.color: Qt.rgba(0.5, 0.5, 0.55, 0.35)
                            Rectangle { width: 12; height: 12; radius: 6; color: tile.modelData.accent || Theme.accent; anchors { right: parent.right; bottom: parent.bottom; margins: 6 } }
                            Sym { visible: tile.sel; anchors.centerIn: parent; name: "check"; size: 16; color: tile.modelData.light ? "#17131F" : "#ffffff" }
                        }
                        Label {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 6; bottomMargin: 7 }
                            text: tile.modelData.name
                            size: "caption"
                            font.weight: Font.Bold
                        }
                        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.pickTheme(tile.modelData) }

                        // своя тема: при наведении — изменить и удалить
                        Row {
                            visible: tile.modelData.custom === true && hov.hovered
                            anchors { right: parent.right; top: parent.top; margins: 3 }
                            spacing: 3
                            z: 2
                            Repeater {
                                model: [{ icon: "edit", act: "edit" }, { icon: "close", act: "del" }]
                                delegate: Rectangle {
                                    id: mini
                                    required property var modelData
                                    width: 20; height: 20; radius: 10
                                    color: mini.modelData.act === "del" ? "#E5484D" : Theme.inv
                                    border.color: Theme.line
                                    Sym { anchors.centerIn: parent; name: mini.modelData.icon; size: 11; color: mini.modelData.act === "del" ? "#ffffff" : Theme.fg }
                                    TapHandler {
                                        onTapped: mini.modelData.act === "del" ? root.deleteTheme(tile.modelData.id) : themeDlg.openFor(tile.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // создать свой цвет
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: 14
                    color: addHov.hovered ? Theme.soft2 : "transparent"
                    border.width: 2
                    border.color: Theme.line
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 30; height: 30; radius: 15
                            color: Theme.soft2
                            Sym { anchors.centerIn: parent; name: "plus"; size: 16 }
                        }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.tr("Свой цвет"); size: "caption"; font.weight: Font.Bold }
                    }
                    HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: themeDlg.openFor(null) }
                }
            }
        }
    }

    // --- цвета: выбор, свои (в настройках — appearance.theme и customThemes) ---
    function pickTheme(t) {
        Settings.set("appearance.theme", t.id);
        // у готовых сочетаний и своих тем — свой акцент и стекло
        if (t.accent) Settings.set("appearance.accent", t.accent);
        if (t.glass !== undefined) Settings.set("appearance.glass", t.glass);
    }
    function hexOf(rgb) { return "#" + rgb.map(c => Math.round(c).toString(16).padStart(2, "0")).join("").toUpperCase(); }
    function rgbOf(hex) { const c = Qt.color(hex); return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]; }
    function saveTheme(t) {
        const list = Theme.customThemes.map(x => ({ id: x.id, name: x.name, rgb: x.rgb, light: x.light, accent: x.accent, glass: x.glass }));
        const i = list.findIndex(x => x.id === t.id);
        if (i >= 0) list[i] = t; else list.push(t);
        Settings.set("appearance.customThemes", list);
        pickTheme(t);
    }
    function deleteTheme(id) {
        const list = Theme.customThemes.filter(x => x.id !== id).map(x => ({ id: x.id, name: x.name, rgb: x.rgb, light: x.light, accent: x.accent, glass: x.glass }));
        Settings.set("appearance.customThemes", list);
        if (Theme.current.id === id) Settings.set("appearance.theme", "graphite");
        Nav.toast("Цвет удалён");
    }

    Dialog {
        id: themeDlg
        title: editId ? "Изменить цвет" : "Свой цвет"
        subtitle: I18n.tr("Выберите цвет панелей и акцент — превью покажет, как это будет выглядеть")
        cardWidth: 460

        property string editId: ""
        property string base: "#1C2230"
        property string accentHex: "#7C5CFF"
        property real glass: 0.7
        readonly property bool isLight: Theme.luminance(Qt.color(base)) > 0.5
        readonly property color glassColor: { const c = Qt.color(base); return Qt.rgba(c.r, c.g, c.b, glass); }
        readonly property color ink: isLight ? "#17131F" : "#ECE9F7"

        function openFor(t) {
            editId = t ? t.id : "";
            base = t ? root.hexOf(t.rgb) : root.hexOf(Theme.current.rgb);
            accentHex = t && t.accent ? t.accent : String(Theme.accent).toUpperCase();
            glass = t && t.glass !== undefined ? t.glass : Theme.opacity;
            nameF.text = t ? t.name : "";
            open();
            nameF.focusInput();
        }
        function save() {
            const name = nameF.text.trim() || "Мой цвет";
            root.saveTheme({ id: editId || "custom-" + Date.now().toString(36), name: name, rgb: root.rgbOf(base),
                             light: isLight, accent: accentHex, glass: Math.round(glass * 100) / 100 });
            close();
        }

        // превью: кусочек обоев, док и кнопка в этих цветах
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 120
            radius: 16
            clip: true
            gradient: Gradient {
                GradientStop { position: 0; color: "#3A4A6B" }
                GradientStop { position: 1; color: "#C98A6B" }
            }
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                width: 250; height: 50; radius: 25
                color: themeDlg.glassColor
                border.color: themeDlg.isLight ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(1, 1, 1, 0.1)
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 30; height: 30; radius: 9
                            color: index === 0 ? themeDlg.accentHex : Qt.rgba(themeDlg.ink.r, themeDlg.ink.g, themeDlg.ink.b, 0.16)
                        }
                    }
                }
            }
            Rectangle {
                anchors { left: parent.left; top: parent.top; margins: 14 }
                width: 150; height: 40; radius: 12
                color: themeDlg.glassColor
                Label { anchors.centerIn: parent; text: I18n.tr("Привет!"); color: themeDlg.ink; font.weight: Font.DemiBold }
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; margins: 14 }
                width: 90; height: 32; radius: 16
                color: themeDlg.accentHex
                Label { anchors.centerIn: parent; text: I18n.tr("Кнопка"); color: Theme.onColor(Qt.color(themeDlg.accentHex)); size: "small"; font.weight: Font.DemiBold }
            }
        }

        Field { id: nameF; Layout.fillWidth: true; icon: "palette"; placeholder: I18n.tr("Название, например «Моя ночь»"); maxLength: 24; onAccepted: themeDlg.save() }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: [{ key: "base", label: I18n.tr("Панели") }, { key: "accent", label: I18n.tr("Акцент") }]
                delegate: Rectangle {
                    id: pick
                    required property var modelData
                    readonly property string hex: modelData.key === "base" ? themeDlg.base : themeDlg.accentHex
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: pickHov.hovered ? Theme.soft2 : Theme.soft
                    border.color: Theme.line
                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 10
                        Rectangle { implicitWidth: 28; implicitHeight: 28; radius: 14; color: pick.hex; border.color: Qt.rgba(0.5, 0.5, 0.55, 0.4) }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: pick.modelData.label; font.weight: Font.DemiBold }
                            Label { Layout.fillWidth: true; text: pick.hex; size: "caption"; tone: 3 }
                        }
                    }
                    HoverHandler { id: pickHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            themeColor.target = pick.modelData.key;
                            themeColor.title = pick.modelData.key === "base" ? "Цвет панелей" : "Акцент";
                            themeColor.subtitle = pick.modelData.key === "base" ? "Доки, меню и окна" : "Кнопки, выделение, рамка окна";
                            themeColor.openWith(pick.hex);
                        }
                    }
                }
            }
        }

        SliderRow {
            Layout.fillWidth: true
            icon: "eye"
            title: I18n.tr("Прозрачность панелей")
            from: 0.3; to: 1; step: 0.01
            value: themeDlg.glass
            format: v => Math.round(v * 100) + " %"
            onCommit: v => themeDlg.glass = v
        }

        buttons: [
            Btn { text: I18n.tr("Отмена"); onClicked: themeDlg.close() },
            Btn { text: themeDlg.editId ? "Сохранить" : "Создать цвет"; kind: "accent"; onClicked: themeDlg.save() }
        ]
    }
    ColorDialog {
        id: themeColor
        property string target: "base"
        onPicked: hex => { if (target === "base") themeDlg.base = hex; else themeDlg.accentHex = hex; }
    }


    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "appearance.newTheme" || name === "styles.newTheme") themeDlg.openFor(null);
        }
    }
}
