pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects

// Vanks Setup — окно в стиле Delta: тёмное стекло, фиолетовый акцент.
// Шаги: версия → куда → устройство или папка → запись. Данные и работа —
// backend (gui/__init__.py), здесь только вид.
ApplicationWindow {
    id: win
    width: 940
    height: 640
    minimumWidth: 780
    minimumHeight: 560
    visible: true
    title: "Vanks Setup"
    color: "#0F0D16"

    readonly property color accent: "#7C5CFF"
    readonly property color accent2: "#2BC4F0"
    readonly property color fg: "#F2F0F8"
    readonly property color fg2: Qt.rgba(1, 1, 1, 0.72)
    readonly property color fg3: Qt.rgba(1, 1, 1, 0.5)
    readonly property color glass: Qt.rgba(1, 1, 1, 0.055)
    readonly property color line: Qt.rgba(1, 1, 1, 0.1)
    readonly property color danger: "#FF6B7A"
    // шрифт как у Delta: первый установленный из списка
    font.family: {
        const have = Qt.fontFamilies();
        for (const f of ["Inter", "Segoe UI Variable Text", "Segoe UI", "Adwaita Sans", "Noto Sans", "Cantarell", "Liberation Sans"])
            if (have.indexOf(f) >= 0) return f;
        return Qt.application.font.family;
    }
    font.pixelSize: 14

    // шаг: 0 версия · 1 куда · 2 устройство · 3 запись
    property int step: startStep
    property string kind: startKind || "usb"
    property string target: ""
    readonly property var ver: backend.versions[backend.index] || null
    readonly property bool working: backend.state === "busy" || backend.state === "done" || backend.state === "failed"
    onWorkingChanged: if (working) step = 3

    // ---------- фон: мягкие пятна света ----------
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
        Rectangle { x: -120; y: -160; width: 520; height: 520; radius: 260; color: win.accent; opacity: 0.32 }
        Rectangle { x: win.width - 380; y: win.height - 300; width: 480; height: 480; radius: 240; color: win.accent2; opacity: 0.16 }
        Rectangle { x: win.width * 0.45; y: -220; width: 360; height: 360; radius: 180; color: "#E0567F"; opacity: 0.12 }
    }

    // ---------- общие детали ----------
    component Ico: Image {
        property string name
        property real size: 20
        source: icons[name] || ""
        sourceSize: Qt.size(size * 2, size * 2)
        width: size
        height: size
        smooth: true
    }
    component Txt: Text {
        color: win.fg
        font.family: win.font.family
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }
    component Btn: Rectangle {
        id: btn
        property string text
        property string icon
        property bool primary: false
        property bool danger: false
        property bool active: true
        signal clicked()
        implicitWidth: row.implicitWidth + 36
        implicitHeight: 42
        radius: 21
        opacity: active ? 1 : 0.4
        color: danger ? Qt.rgba(1, 0.42, 0.48, mouse.pressed ? 0.35 : mouse.containsMouse ? 0.28 : 0.2)
            : primary ? (mouse.pressed ? Qt.darker(win.accent, 1.2) : mouse.containsMouse ? Qt.lighter(win.accent, 1.1) : win.accent)
            : Qt.rgba(1, 1, 1, mouse.pressed ? 0.16 : mouse.containsMouse ? 0.12 : 0.08)
        border.width: primary ? 0 : 1
        border.color: win.line
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: mouse.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Ico { visible: btn.icon.length > 0; name: btn.icon; size: 16 }
            Txt { text: btn.text; font.weight: Font.DemiBold; color: btn.danger ? win.danger : win.fg }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: btn.active
            onClicked: btn.clicked()
        }
    }
    component Glass: Rectangle {
        radius: 18
        color: win.glass
        border.width: 1
        border.color: win.line
    }
    // карточка выбора: подсвечивается, когда выбрана
    component Choice: Rectangle {
        id: ch
        property bool selected: false
        signal picked()
        radius: 18
        color: selected ? Qt.rgba(0.49, 0.36, 1, 0.16) : Qt.rgba(1, 1, 1, cm.containsMouse ? 0.08 : 0.055)
        border.width: selected ? 2 : 1
        border.color: selected ? win.accent : win.line
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.picked() }
    }
    component Switch2: Rectangle {
        id: sw
        property bool checked
        signal toggled(bool value)
        implicitWidth: 46
        implicitHeight: 26
        radius: 13
        color: checked ? win.accent : Qt.rgba(1, 1, 1, 0.16)
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 20; height: 20; radius: 10
            y: 3
            x: sw.checked ? sw.width - width - 3 : 3
            color: "white"
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled(!sw.checked) }
    }

    // ---------- слева: логотип и шаги ----------
    Item {
        id: side
        width: 230
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }

        ColumnLayout {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 6
            RowLayout {
                spacing: 12
                Image { source: logoData; sourceSize: Qt.size(88, 88); Layout.preferredWidth: 44; Layout.preferredHeight: 44 }
                ColumnLayout {
                    spacing: 0
                    Txt { text: "Vanks Setup"; font.pixelSize: 18; font.weight: Font.Bold }
                    Txt { text: "версия " + backend.appVersion; color: win.fg3; font.pixelSize: 12 }
                }
            }
            Item { Layout.preferredHeight: 26 }
            Repeater {
                model: ["Версия", "Куда записать", win.kind === "folder" ? "Папка" : "Устройство", "Запись"]
                delegate: RowLayout {
                    id: st
                    required property string modelData
                    required property int index
                    readonly property bool now: win.step === index
                    readonly property bool past: win.step > index
                    spacing: 12
                    Layout.preferredHeight: 40
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: st.now ? win.accent : st.past ? Qt.rgba(0.49, 0.36, 1, 0.3) : Qt.rgba(1, 1, 1, 0.08)
                        border.width: st.now ? 0 : 1
                        border.color: win.line
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Ico { anchors.centerIn: parent; visible: st.past; name: "check"; size: 14 }
                        Txt { anchors.centerIn: parent; visible: !st.past; text: st.index + 1; font.pixelSize: 13; font.weight: Font.Bold }
                    }
                    Txt { text: st.modelData; color: st.now ? win.fg : win.fg3; font.weight: st.now ? Font.DemiBold : Font.Normal }
                }
            }
        }
        Txt {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28 }
            text: "Образ скачивается с GitHub и проверяется по sha256. Недокачанное продолжится при следующем запуске."
            color: win.fg3
            font.pixelSize: 12
        }
    }

    // ---------- справа: страницы ----------
    Glass {
        id: panel
        anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 18; leftMargin: 0 }
        radius: 26
        color: Qt.rgba(0.08, 0.07, 0.12, 0.72)

        // настройки
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 18 }
            width: 38; height: 38; radius: 19
            visible: !win.working
            color: Qt.rgba(1, 1, 1, gearMouse.containsMouse ? 0.12 : 0.06)
            Ico { anchors.centerIn: parent; name: "settings"; size: 18 }
            MouseArea { id: gearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settings.open() }
        }

        StackLayout {
            id: pages
            anchors { fill: parent; margins: 34; topMargin: 30 }
            currentIndex: win.step

            // ===== 0. версия =====
            ColumnLayout {
                spacing: 16
                Txt { text: "Какую версию поставить?"; font.pixelSize: 26; font.weight: Font.Bold }
                Txt {
                    Layout.fillWidth: true
                    Layout.rightMargin: 40
                    color: win.fg2
                    text: "Все версии оболочки Delta из релизов GitHub. Самая новая выбрана сама — можно взять любую."
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    BusyIndicator { anchors.centerIn: parent; running: backend.state === "loading"; visible: running }
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width * 0.8
                        visible: backend.state === "error"
                        spacing: 14
                        Ico { Layout.alignment: Qt.AlignHCenter; name: "warning"; size: 34 }
                        Txt { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: backend.error; color: win.fg2 }
                        Btn { Layout.alignment: Qt.AlignHCenter; text: "Повторить"; icon: "refresh"; onClicked: backend.load() }
                    }
                    ListView {
                        anchors.fill: parent
                        visible: backend.state !== "loading" && backend.state !== "error"
                        clip: true
                        spacing: 10
                        model: backend.versions
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Choice {
                            id: vc
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 78
                            selected: backend.index === index
                            onPicked: backend.choose(index)
                            RowLayout {
                                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                                spacing: 14
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        spacing: 10
                                        Txt { text: "Delta " + vc.modelData.version; font.pixelSize: 17; font.weight: Font.Bold }
                                        Rectangle {
                                            visible: vc.modelData.latest
                                            implicitWidth: nl.implicitWidth + 16; implicitHeight: 22; radius: 11
                                            color: win.accent
                                            Txt { id: nl; anchors.centerIn: parent; text: "Новая"; font.pixelSize: 12; font.weight: Font.Bold }
                                        }
                                        Rectangle {
                                            visible: vc.modelData.pre
                                            implicitWidth: pl.implicitWidth + 16; implicitHeight: 22; radius: 11
                                            color: Qt.rgba(1, 0.6, 0.2, 0.25)
                                            Txt { id: pl; anchors.centerIn: parent; text: "Предварительная"; font.pixelSize: 12 }
                                        }
                                    }
                                    Txt {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                        color: win.fg3
                                        font.pixelSize: 13
                                        text: vc.modelData.title + " · " + vc.modelData.date + " · "
                                            + (vc.modelData.own ? "образ " + vc.modelData.imageSize
                                               : vc.modelData.image ? "образ из " + vc.modelData.imageTag + ", оболочка поверх" : "образа нет")
                                    }
                                }
                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: vc.selected ? win.accent : "transparent"
                                    border.width: vc.selected ? 0 : 2
                                    border.color: Qt.rgba(1, 1, 1, 0.3)
                                    Ico { anchors.centerIn: parent; visible: vc.selected; name: "check"; size: 13 }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Txt {
                        Layout.fillWidth: true
                        color: win.fg3
                        font.pixelSize: 13
                        text: win.ver && win.ver.image ? "Скачается " + win.ver.imageSize + " · " + win.ver.image : ""
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                    }
                    Btn { text: "Далее"; primary: true; active: !!win.ver && !!win.ver.image; onClicked: win.step = 1 }
                }
            }

            // ===== 1. куда =====
            ColumnLayout {
                spacing: 16
                Txt { text: "Куда записать?"; font.pixelSize: 26; font.weight: Font.Bold }
                Txt { Layout.fillWidth: true; Layout.rightMargin: 40; color: win.fg2; text: "Delta " + (win.ver ? win.ver.version : "") + " — образ системы и выбранная оболочка." }
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: backend.allowDisks ? 3 : 2
                    columnSpacing: 14
                    Repeater {
                        model: [
                            { id: "folder", icon: "folder", title: "В папку", note: "Сохранить образ на этом компьютере. Записать флешку можно потом — Ventoy, Rufus, dd." },
                            { id: "usb", icon: "usb", title: "На флешку", note: "Загрузочная флешка сразу. С неё можно установить систему. Нужно от 8 ГБ." },
                            { id: "disk", icon: "disk", title: "На диск", note: "Другой диск компьютера целиком. Всё на нём будет стёрто. Системный не показывается." }
                        ].filter(t => t.id !== "disk" || backend.allowDisks)
                        delegate: Choice {
                            id: tc
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 220
                            selected: win.kind === modelData.id
                            onPicked: win.kind = modelData.id
                            ColumnLayout {
                                anchors { fill: parent; margins: 22 }
                                spacing: 10
                                Rectangle {
                                    width: 54; height: 54; radius: 16
                                    color: tc.selected ? win.accent : Qt.rgba(1, 1, 1, 0.08)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Ico { anchors.centerIn: parent; name: tc.modelData.icon; size: 26 }
                                }
                                Txt { text: tc.modelData.title; font.pixelSize: 18; font.weight: Font.Bold }
                                Txt { Layout.fillWidth: true; text: tc.modelData.note; color: win.fg2; font.pixelSize: 13 }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Btn { text: "Назад"; icon: "chevron-left"; onClicked: win.step = 0 }
                    Item { Layout.fillWidth: true }
                    Btn {
                        text: "Далее"; primary: true
                        onClicked: {
                            if (win.kind === "folder") win.target = win.target.startsWith("/") || win.target.indexOf(":") === 1 ? win.target : backend.downloads;
                            else { win.target = ""; backend.refreshDisks(win.kind === "disk"); }
                            win.step = 2;
                        }
                    }
                }
            }

            // ===== 2. устройство или папка =====
            ColumnLayout {
                spacing: 16
                Txt { text: win.kind === "folder" ? "Куда сохранить образ?" : win.kind === "usb" ? "Какая флешка?" : "Какой диск?"; font.pixelSize: 26; font.weight: Font.Bold }
                Txt {
                    Layout.fillWidth: true; Layout.rightMargin: 40; color: win.fg2
                    text: win.kind === "folder" ? "Рядом с образом ляжет папка vankos с выбранной оболочкой — для Ventoy скопируйте её в корень флешки."
                        : "Всё, что на нём есть, будет удалено. Если места больше образа, после него появится раздел VANKOS с выбранной оболочкой."
                }

                // папка
                Glass {
                    visible: win.kind === "folder"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 12 }
                        spacing: 12
                        Ico { name: "folder"; size: 22 }
                        Txt { Layout.fillWidth: true; text: win.target; elide: Text.ElideMiddle; wrapMode: Text.NoWrap }
                        Btn { text: "Выбрать…"; onClicked: { const p = backend.pickFolder(win.target); if (p) win.target = p; } }
                    }
                }

                // устройства
                Item {
                    visible: win.kind !== "folder"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Timer { interval: 2500; repeat: true; running: win.step === 2 && win.kind !== "folder"; onTriggered: backend.refreshDisks(win.kind === "disk") }
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: backend.disks.length === 0
                        spacing: 12
                        Ico { Layout.alignment: Qt.AlignHCenter; name: win.kind === "usb" ? "usb" : "disk"; size: 40; opacity: 0.6 }
                        Txt { Layout.alignment: Qt.AlignHCenter; text: win.kind === "usb" ? "Вставьте флешку — она появится здесь" : "Подходящих дисков нет"; color: win.fg2 }
                    }
                    ListView {
                        anchors.fill: parent
                        clip: true
                        spacing: 10
                        model: backend.disks
                        delegate: Choice {
                            id: dc
                            required property var modelData
                            width: ListView.view.width
                            height: 70
                            selected: win.target === modelData.path
                            opacity: modelData.fits ? 1 : 0.45
                            onPicked: if (modelData.fits) win.target = modelData.path
                            RowLayout {
                                anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                                spacing: 14
                                Ico { name: dc.modelData.removable ? "usb" : "disk"; size: 26 }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Txt { text: dc.modelData.name; font.weight: Font.DemiBold }
                                    Txt { text: dc.modelData.size + " · " + dc.modelData.path + (dc.modelData.fits ? "" : " · мало места"); color: win.fg3; font.pixelSize: 13 }
                                }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: win.kind === "folder" }
                RowLayout {
                    Layout.fillWidth: true
                    Btn { text: "Назад"; icon: "chevron-left"; onClicked: win.step = 1 }
                    Item { Layout.fillWidth: true }
                    Btn {
                        text: win.kind === "folder" ? "Скачать" : "Записать"
                        icon: "download"
                        primary: true
                        active: win.target.length > 0
                        onClicked: win.kind === "folder" ? backend.start(win.kind, win.target) : confirm.open()
                    }
                }
            }

            // ===== 3. запись =====
            Item {
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 480)
                    spacing: 18
                    visible: backend.state === "busy"

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: ({ download: "Скачиваю образ", verify: "Проверяю образ", write: win.kind === "folder" ? "Собираю образ" : "Записываю",
                                 check: "Сверяю записанное", extra: "Кладу выбранную оболочку" })[backend.stage] || "Готовлюсь"
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: backend.total > 1 ? Math.floor(backend.done / backend.total * 100) + " %" : ""
                        font.pixelSize: 54
                        font.weight: Font.Bold
                        color: win.fg
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 10
                        radius: 5
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Rectangle {
                            height: parent.height
                            radius: 5
                            width: parent.width * (backend.total > 0 ? Math.min(1, backend.done / backend.total) : 0)
                            Behavior on width { NumberAnimation { duration: 250 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: win.accent }
                                GradientStop { position: 1; color: win.accent2 }
                            }
                        }
                    }
                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        color: win.fg3
                        function h(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " ГБ" : (b / 1048576).toFixed(0) + " МБ"; }
                        text: backend.total > 1 ? h(backend.done) + " из " + h(backend.total) + (backend.speed > 0 ? " · " + h(backend.speed) + "/с" : "") : ""
                    }
                    Btn { Layout.alignment: Qt.AlignHCenter; text: "Отмена"; onClicked: backend.cancel() }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 480)
                    spacing: 16
                    visible: backend.state === "done" || backend.state === "failed"
                    readonly property bool ok: backend.state === "done"
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 84; height: 84; radius: 42
                        color: parent.ok ? Qt.rgba(0.25, 0.7, 0.48, 0.25) : Qt.rgba(1, 0.42, 0.48, 0.22)
                        Ico { anchors.centerIn: parent; name: parent.parent.ok ? "check" : "warning"; size: 40 }
                        scale: visible ? 1 : 0.6
                        Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    }
                    Txt { Layout.alignment: Qt.AlignHCenter; text: parent.ok ? "Готово" : "Не получилось"; font.pixelSize: 26; font.weight: Font.Bold }
                    Txt {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        color: win.fg2
                        text: parent.ok ? backend.result + (win.kind === "folder" ? "" : "\nЗагрузитесь с неё: меню загрузки при включении — обычно F12, F8 или Esc.")
                                        : backend.error
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        Btn { visible: parent.parent.ok && win.kind === "folder"; text: "Открыть папку"; icon: "folder"; onClicked: backend.openPath(win.target) }
                        Btn { text: parent.parent.ok ? "Ещё раз" : "Назад"; onClicked: { backend.reset(); win.step = parent.parent.ok ? 0 : 2; } }
                        Btn { visible: parent.parent.ok; text: "Закрыть"; primary: true; onClicked: Qt.quit() }
                    }
                }
            }
        }
    }

    // ---------- подтверждение стирания ----------
    Popup {
        id: confirm
        anchors.centerIn: parent
        width: 440
        modal: true
        padding: 26
        readonly property var disk: backend.disks.find(d => d.path === win.target) || null
        background: Rectangle { radius: 22; color: "#1C1928"; border.width: 1; border.color: win.line }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
        contentItem: ColumnLayout {
            spacing: 14
            Ico { name: "warning"; size: 30 }
            Txt { text: "Стереть «" + (confirm.disk ? confirm.disk.name : "") + "»?"; font.pixelSize: 20; font.weight: Font.Bold }
            Txt {
                Layout.fillWidth: true
                color: win.fg2
                text: "Все данные на " + (confirm.disk ? confirm.disk.size + " (" + confirm.disk.path + ")" : "устройстве")
                      + " будут удалены без возможности вернуть. Дальше система может спросить пароль администратора."
            }
            RowLayout {
                Layout.topMargin: 6
                Item { Layout.fillWidth: true }
                Btn { text: "Отмена"; onClicked: confirm.close() }
                Btn { text: "Стереть и записать"; danger: true; onClicked: { confirm.close(); backend.start(win.kind, win.target); } }
            }
        }
    }

    // ---------- настройки ----------
    Popup {
        id: settings
        anchors.centerIn: parent
        width: 480
        modal: true
        padding: 26
        background: Rectangle { radius: 22; color: "#1C1928"; border.width: 1; border.color: win.line }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
        contentItem: ColumnLayout {
            spacing: 16
            RowLayout {
                Txt { Layout.fillWidth: true; text: "Настройки"; font.pixelSize: 20; font.weight: Font.Bold }
                Rectangle {
                    width: 32; height: 32; radius: 16; color: Qt.rgba(1, 1, 1, 0.08)
                    Ico { anchors.centerIn: parent; name: "close"; size: 14 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: settings.close() }
                }
            }
            RowLayout {
                spacing: 14
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Txt { text: "Разрешить запись на диски"; font.weight: Font.DemiBold }
                    Txt { Layout.fillWidth: true; text: "Появится «На диск»: образ запишется на другой диск компьютера целиком. Системный диск не показывается."; color: win.fg3; font.pixelSize: 13 }
                }
                Switch2 { checked: backend.allowDisks; onToggled: v => { backend.allowDisks = v; if (!v && win.kind === "disk") win.kind = "usb"; } }
            }
            RowLayout {
                spacing: 14
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Txt { text: "Предварительные версии"; font.weight: Font.DemiBold }
                    Txt { Layout.fillWidth: true; text: "Показывать в списке и тестовые сборки"; color: win.fg3; font.pixelSize: 13 }
                }
                Switch2 { checked: backend.prerelease; onToggled: v => backend.prerelease = v }
            }
            ColumnLayout {
                spacing: 2
                Txt { text: "Загрузки"; font.weight: Font.DemiBold }
                Txt { Layout.fillWidth: true; text: backend.cachePath; color: win.fg3; font.pixelSize: 13; wrapMode: Text.WrapAnywhere }
            }
        }
    }
}
