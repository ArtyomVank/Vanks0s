import QtQuick
import QtQuick.Effects
import Quickshell
import qs.common
// с квалификатором: в widgets/parts есть свои Field и Cover
import qs.widgets.parts as WParts

// Большие часы экрана блокировки — стили и цвета как в концепте.
//   style: ios · thin · mono · neon · stack · serif · wide · outline · minimal · tall
//   tint:  white · accent · gradient · glass
//     BigClock { style: "neon"; tint: "accent"; size: 152 }
// size — кегль цифр для стиля ios, остальные стили пересчитываются от него.
Item {
    id: root

    property string style: "ios"
    property string tint: "white"
    // неизвестное значение (старый settings.json) — белые
    readonly property string t: ["white", "accent", "gradient", "glass"].indexOf(tint) !== -1 ? tint : "white"
    property real size: 152
    // ширина цифр «Длинных» часов — доля высоты
    property real tallWidth: 0.62
    property bool showDate: true
    property color textColor: "#ffffff"   // цвет даты (на обоях всегда светлый)

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property string hh: Qt.formatTime(now, "HH")
    readonly property string mm: Qt.formatTime(now, "mm")
    readonly property string dateText: {
        const s = Qt.locale("ru_RU").toString(now, "dddd, d MMMM");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    // параметры стиля (как clockOf() в концепте)
    readonly property bool stack: style === "stack"
    readonly property bool glow: style === "neon"
    readonly property bool serif: style === "serif"
    readonly property bool wide: style === "wide"
    readonly property bool outline: style === "outline"
    readonly property bool minimal: style === "minimal"
    // «Длинные», как в iOS 26: тонкие высокие цифры, нарисованные линиями
    // (widgets/parts/TallDigits.qml)
    readonly property bool tall: style === "tall"
    readonly property real px: minimal ? size * 0.58
        : style === "mono" ? size * 0.84
        : stack ? size * 0.74
        : serif ? size * 0.92
        : wide ? size * 0.86
        : size
    readonly property string family: serif ? Theme.pickFont(["Noto Serif", "DejaVu Serif", "Liberation Serif", "serif"])
        : style === "mono" ? Theme.fontMono
        : style === "thin" ? Theme.pickFont(["Manrope", "Inter", Theme.font]) : Theme.fontDisplay
    readonly property int weight: serif ? Font.Normal
        : wide ? Font.Light
        : style === "thin" ? Font.ExtraLight
        : style === "mono" ? Font.Medium : style === "neon" ? Font.DemiBold : Font.Bold
    readonly property real spacing: px * (wide ? 0.075 : serif ? 0.005 : style === "mono" ? -0.04 : style === "thin" ? -0.02 : -0.035)

    readonly property color faceColor: tint === "accent" ? Theme.accent
        : tint === "glass" ? Qt.rgba(1, 1, 1, 0.14)
        : tint === "gradient" ? "#ffffff" : Qt.rgba(1, 1, 1, 0.93)
    // тень для обычных стилей, свечение для неона
    readonly property color shadowColor: glow ? (tint === "accent" ? Theme.accent : "#ffffff") : Qt.rgba(0, 0, 0, 0.3)

    implicitWidth: Math.max(tall ? tallBox.width : face.width, date.implicitWidth)
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.px * 0.02

        Text {
            id: date
            visible: root.showDate && !root.minimal
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            color: root.textColor
            opacity: 0.88
            font.family: Theme.fontDisplay
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(root.size * 0.15)
        }

        // «Длинные»: цифры-линии с тенью, градиент — по их маске
        Item {
            id: tallBox
            visible: root.tall
            anchors.horizontalCenter: parent.horizontalCenter
            width: tallFace.implicitWidth
            height: tallFace.implicitHeight

            WParts.TallDigits {
                id: tallFace
                text: root.hh + ":" + root.mm
                digitHeight: root.size * 1.3
                widthRatio: root.tallWidth
                color: root.t === "accent" ? Theme.accent : root.t === "glass" ? Qt.rgba(1, 1, 1, 0.38) : "#ffffff"
                opacity: root.t === "white" ? 0.92 : 1
                visible: root.t === "glass"
                layer.enabled: true
            }
            Rectangle {
                id: tallGrad
                anchors.fill: tallFace
                visible: false
                layer.enabled: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.1; color: "#ffffff" }
                    GradientStop { position: 0.55; color: Theme.accent }
                    GradientStop { position: 0.95; color: Theme.accents[1] }
                }
            }
            MultiEffect {
                anchors.fill: tallFace
                visible: root.t === "gradient"
                source: tallGrad
                maskEnabled: true
                maskSource: tallFace
            }
            MultiEffect {
                anchors.fill: tallFace
                visible: root.t === "white" || root.t === "accent"
                source: tallFace
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.3)
                shadowBlur: 0.8
                shadowVerticalOffset: 3
                blurMax: 24
            }
        }

        Item {
            visible: !root.tall
            anchors.horizontalCenter: parent.horizontalCenter
            width: face.width
            height: face.height

            Item {
                id: face
                width: digits.implicitWidth
                height: digits.implicitHeight * (root.stack ? 0.94 : 0.86)

                Text {
                    id: digits
                    anchors.centerIn: parent
                    text: root.stack ? root.hh + "\n" + root.mm : root.hh + ":" + root.mm
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: root.stack ? 0.86 : 1
                    color: root.outline ? "transparent" : root.faceColor
                    style: root.outline || root.t === "glass" ? Text.Outline : Text.Normal
                    styleColor: root.outline && root.t === "accent" ? Theme.accent : Qt.rgba(1, 1, 1, 0.9)
                    font.family: root.family
                    font.weight: root.weight
                    font.pixelSize: Math.round(root.px)
                    font.letterSpacing: root.spacing
                    font.features: { "tnum": 1 }
                    // стекло и контур рисуются как есть; остальное — через эффекты ниже
                    // (тень/свечение или градиент по маске из самих цифр)
                    visible: root.t === "glass" || root.outline
                    // слой всегда: эффекты ниже берут цифры как текстуру, а включение
                    // слоя на лету MultiEffect не подхватывает (градиент пропадал)
                    layer.enabled: true
                }

                // градиент 120°: белый → акцент → голубой
                Rectangle {
                    id: grad
                    anchors.fill: digits
                    visible: false
                    layer.enabled: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.1; color: "#ffffff" }
                        GradientStop { position: 0.55; color: Theme.accent }
                        GradientStop { position: 0.95; color: Theme.accents[1] }
                    }
                }
                MultiEffect {
                    anchors.fill: digits
                    visible: root.t === "gradient"
                    source: grad
                    maskEnabled: true
                    maskSource: digits
                }

                // цифры с тенью или неоновым свечением
                MultiEffect {
                    anchors.fill: digits
                    visible: !root.outline && (root.t === "white" || root.t === "accent")
                    source: digits
                    shadowEnabled: true
                    shadowColor: root.shadowColor
                    shadowBlur: 1
                    shadowScale: root.glow ? 1.02 : 1
                    shadowVerticalOffset: root.glow ? 0 : 4
                    shadowOpacity: root.glow ? 0.9 : 0.6
                    blurMax: root.glow ? 48 : 32
                }
            }
        }
    }
}
