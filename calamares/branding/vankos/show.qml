// Vanks OS — заставка на время установки (Calamares slideshow, API 2).
// Только QtQuick 2.0: совместимо и с Qt5-, и с Qt6-сборками Calamares.
import QtQuick 2.0

Item {
    id: root
    width: 800
    height: 520
    clip: true

    function onActivate() { pulse.running = true; fade.running = true }
    function onLeave()    { pulse.running = false; fade.running = false }

    // Фон: лёгкий градиент поверх обоев брендинга.
    Image {
        anchors.fill: parent
        source: "wallpaper.png"
        fillMode: Image.PreserveAspectCrop
        opacity: 0.5
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0E0C15" }
            GradientStop { position: 1.0; color: "#12101B" }
        }
        opacity: 0.55
    }

    // Пульсирующий акцентный круг.
    Rectangle {
        id: halo
        width: 320; height: 320
        radius: 160
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        color: "transparent"
        border.width: 2
        border.color: "#7C5CFF"
        opacity: 0.35

        SequentialAnimation on scale {
            id: pulse
            running: false
            loops: Animation.Infinite
            NumberAnimation { to: 1.06; duration: 1600; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.00; duration: 1600; easing.type: Easing.InOutQuad }
        }
    }

    Image {
        source: "logo.png"
        width: 128; height: 128
        anchors.centerIn: halo
        fillMode: Image.PreserveAspectFit
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 60
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Устанавливаем Vanks OS"
            color: "#F2F0FA"
            font.pixelSize: 26
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Почти всё уже в оперативной памяти — можно налить кофе"
            color: "#A79FC4"
            font.pixelSize: 14
        }
    }

    // Циклическая смена подсказок.
    Text {
        id: tip
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        color: "#6E688A"
        font.pixelSize: 12

        property var tips: [
            "GNOME и Hyprland ставятся из локального репозитория — интернет не обязателен",
            "Система загружается в RAM, поэтому флешку можно вынуть после загрузки",
            "Vanks OS — это Arch Linux: pacman, AUR и rolling release",
            "Выбранный рабочий стол можно поменять позже: оба набора есть в репозитории"
        ]
        property int index: 0
        text: tips[index]

        Timer {
            interval: 5200
            running: true
            repeat: true
            onTriggered: {
                tip.index = (tip.index + 1) % tip.tips.length
                fade.restart()
            }
        }

        SequentialAnimation {
            id: fade
            running: true
            NumberAnimation { target: tip; property: "opacity"; to: 0.0; duration: 260 }
            NumberAnimation { target: tip; property: "opacity"; to: 1.0; duration: 380 }
        }
    }
}
