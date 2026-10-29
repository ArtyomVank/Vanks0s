import QtQuick
import QtQuick.Effects
import qs.common

// Фон экрана блокировки: свои обои (lock.wallpaper) или обои рабочего стола,
// размытые и притемнённые.
//
// Размытие считается один раз с уменьшенной копии картинки, а анимируется
// только прозрачность слоёв — так переходы дешёвые даже на 4K.
//   blurred — 0…1: насколько видна размытая копия (1 — экран блокировки)
//   sharp   — 0…1: насколько видны чёткие обои (0 — сквозь них виден рабочий стол)
Item {
    id: root

    // своя картинка экрана блокировки, иначе — обои рабочего стола
    readonly property string own: Settings.get("lock.wallpaper", "") || ""
    property string file: own || Settings.get("wallpaper.path", "")
    property string fill: Settings.get("wallpaper.fill", "cover")
    property real blurred: 1
    property real sharp: 1

    // видеообои здесь не крутим: берём их кадр-заставку (его пишет wallpaper/Wallpaper.qml)
    readonly property bool video: /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(file)
    readonly property string image: video ? Settings.get("wallpaper.poster", "") : file

    Item {
        anchors.fill: parent
        opacity: root.sharp

        // без обоев — тот же градиент, что у wallpaper/Wallpaper.qml
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.darker(Theme.accent, 1.6) }
                GradientStop { position: 0.55; color: Theme.base }
                GradientStop { position: 1; color: Qt.darker(Theme.base, 1.4) }
            }
        }

        Image {
            id: sharpImg
            anchors.fill: parent
            source: root.image ? "file://" + root.image : ""
            asynchronous: true
            cache: false
            fillMode: root.fill === "contain" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            sourceSize: Qt.size(root.width, root.height)
        }
    }

    // уменьшенная копия: размытию не нужны детали, а памяти и работы в 9 раз меньше
    Item {
        id: smallBox
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.textureSize: Qt.size(Math.max(1, width / 3), Math.max(1, height / 3))
        Rectangle {
            anchors.fill: parent
            visible: small.status !== Image.Ready
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.darker(Theme.accent, 1.6) }
                GradientStop { position: 0.55; color: Theme.base }
                GradientStop { position: 1; color: Qt.darker(Theme.base, 1.4) }
            }
        }
        Image {
            id: small
            anchors.fill: parent
            source: sharpImg.source
            cache: false
            asynchronous: true
            fillMode: sharpImg.fillMode
            sourceSize: Qt.size(Math.max(1, root.width / 3), Math.max(1, root.height / 3))
        }
    }

    MultiEffect {
        anchors.fill: parent
        opacity: root.blurred
        visible: opacity > 0
        source: smallBox
        blurEnabled: true
        blur: 1
        blurMax: 48
        blurMultiplier: 0.6
        saturation: 0.15
        // края размытия не должны светлеть
        autoPaddingEnabled: false
    }

    // притемнение, как .lk-blur в концепте: rgba(8, 6, 18, .32)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(8 / 255, 6 / 255, 18 / 255, 0.32)
        opacity: root.blurred
    }
}
