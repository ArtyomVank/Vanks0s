import QtQuick
import QtQuick.Effects
import Quickshell
import qs.common
import qs.widgets.parts

// Часы. Стиль и цвет — у виджета (item.style / item.color), иначе общие
// clock.style / clock.color. Размер цифр — от размера виджета (как clockCq
// в концепте), поэтому при растягивании часы растут целиком.
Base {
    id: root

    readonly property string style: (item && item.style) || Settings.get("clock.style", "ios")
    readonly property string tint: (item && item.color) || Settings.get("clock.color", "white")
    readonly property bool stack: style === "stack"
    readonly property bool neon: style === "neon"
    readonly property bool serif: style === "serif"
    readonly property bool wide: style === "wide"
    readonly property bool outline: style === "outline"
    readonly property bool minimal: style === "minimal"
    // «Длинные», как в iOS 26: тонкие высокие цифры на всю высоту виджета
    // (рисуются линиями — widgets/parts/TallDigits.qml)
    readonly property bool tall: style === "tall"

    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property string hh: Qt.formatTime(clock.date, "hh")
    readonly property string mm: Qt.formatTime(clock.date, "mm")
    readonly property string dateText: {
        const s = Qt.locale(I18n.locale).toString(clock.date, "dddd, d MMMM");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    readonly property real fs: minimal ? Math.min(34 * ch, 13 * cw)
        : stack ? Math.min(38 * ch, 34 * cw)
        : style === "mono" ? Math.min(56 * ch, 19 * cw)
        : serif ? Math.min(58 * ch, 21 * cw)
        : wide ? Math.min(54 * ch, 20 * cw)
        : Math.min(60 * ch, 23 * cw)

    readonly property string timeText: hh + ":" + mm
    // «Длинные» вписываются в виджет: высота — всё место под датой, ширина
    // цифр — сколько влезает в ширину, но не больше ползунка «ширина цифр»
    // (item.tallWidth, иначе общая clock.tallWidth). Считаем по «00:00» —
    // самой широкой строке, чтобы часы не прыгали от минуты к минуте.
    readonly property real tallMax: Math.max(0.3, Math.min(1, Number((item && item.tallWidth) ?? Settings.get("clock.tallWidth", 0.62)) || 0.62))
    readonly property real tallAreaW: 92 * cw
    readonly property real tallAreaH: 84 * ch - dateLine.height - Math.max(4, 4 * ch)
    readonly property var tallLine: tallFace.fit("00:00", tallAreaW, tallAreaH, tallMax)
    // узкий высокий виджет: часы над минутами — цифры выходят крупнее
    // две строки и зазор 0.12 высоты между ними
    readonly property var tallTwo: tallFace.fit("00", tallAreaW, tallAreaH / 2.14, tallMax)
    readonly property bool tallStack: tallTwo.h > tallLine.h
    readonly property var tallFit: tallStack ? tallTwo : tallLine
    readonly property real tallWidth: tallFit.r
    readonly property real tallH: tallFit.h
    readonly property real tallGap: tallStack ? tallH * 0.12 : 0
    readonly property color tallColor: tint === "accent" ? Theme.accent : tint === "glass" ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(1, 1, 1, 0.9)

    Column {
        anchors.centerIn: parent
        // у «длинных» цифр линии толстые — дате нужен зазор, иначе она ложится на них
        spacing: root.tall ? Math.max(4, 4 * root.ch) : 0

        WText {
            id: dateLine
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.minimal
            text: root.dateText
            px: Math.min(11 * root.ch, 4.4 * root.cw)
            display: true
            font.weight: Font.DemiBold
            color: "#ffffff"
            opacity: 0.85
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: face.width
            height: face.height

            Item {
                id: face
                width: root.tall ? Math.max(tallFace.implicitWidth, root.tallStack ? tallFace2.implicitWidth : 0) : digits.implicitWidth
                height: root.tall ? tallFace.implicitHeight + (root.tallStack ? root.tallGap + tallFace2.implicitHeight : 0) : digits.implicitHeight

                TallDigits {
                    id: tallFace
                    visible: root.tall && root.tint !== "gradient"
                    x: (face.width - implicitWidth) / 2
                    text: root.tallStack ? root.hh : root.timeText
                    digitHeight: root.tallH
                    widthRatio: root.tallWidth
                    color: root.tallColor
                    layer.enabled: visible && root.tint !== "glass"
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 16
                        shadowBlur: 0.8
                        shadowColor: root.tint === "accent" ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.25)
                        shadowVerticalOffset: 2
                    }
                }

                TallDigits {
                    id: tallFace2
                    visible: tallFace.visible && root.tallStack
                    x: (face.width - implicitWidth) / 2
                    y: tallFace.implicitHeight + root.tallGap
                    text: root.mm
                    digitHeight: root.tallH
                    widthRatio: root.tallWidth
                    color: root.tallColor
                    layer.enabled: tallFace.layer.enabled && visible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 16
                        shadowBlur: 0.8
                        shadowColor: root.tint === "accent" ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.25)
                        shadowVerticalOffset: 2
                    }
                }

                Text {
                    id: digits
                    text: root.stack ? root.hh + "\n" + root.mm : root.hh + ":" + root.mm
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.serif ? Theme.pickFont(["Noto Serif", "DejaVu Serif", "Liberation Serif", "serif"])
                               : root.style === "mono" ? Theme.fontMono
                               : root.style === "thin" ? Theme.font : Theme.fontDisplay
                    font.pixelSize: Math.max(1, Math.round(root.fs))
                    font.weight: root.serif ? Font.Normal
                               : root.wide ? Font.Light
                               : root.style === "thin" ? Font.ExtraLight
                               : root.style === "mono" ? Font.Medium : root.neon ? Font.DemiBold : Font.Bold
                    font.letterSpacing: root.fs * (root.wide ? 0.075 : root.serif ? 0.005 : root.style === "mono" ? -0.04 : root.style === "thin" ? -0.02 : -0.035)
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: root.stack ? 0.88 : 1.0
                    color: root.outline ? "transparent"
                         : root.tint === "accent" ? Theme.accent
                         : root.tint === "glass" ? Qt.rgba(1, 1, 1, 0.14)
                         : Qt.rgba(1, 1, 1, 0.93)
                    style: root.outline || root.tint === "glass" ? Text.Outline : Text.Normal
                    styleColor: root.outline && root.tint === "accent" ? Theme.accent : Qt.rgba(1, 1, 1, 0.9)
                    // градиент рисуем маской ниже, сами цифры тогда не видны
                    visible: !root.tall && root.tint !== "gradient"

                    // тень или неоновое свечение (контуру тень не нужна)
                    layer.enabled: !root.outline && (root.tint === "white" || root.tint === "accent")
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: Math.max(8, Math.round(root.fs * (root.neon ? 0.35 : 0.22)))
                        shadowBlur: 1
                        shadowColor: root.neon ? (root.tint === "accent" ? Theme.accent : "#ffffff")
                                               : Qt.rgba(0, 0, 0, root.tint === "accent" ? 0.3 : 0.25)
                        shadowOpacity: root.neon ? 0.95 : 1
                        shadowVerticalOffset: root.neon ? 0 : root.fs * 0.03
                        shadowHorizontalOffset: 0
                    }
                }

                // «Градиент»: белый → акцент → голубой по форме цифр.
                // Маска и градиент — через ShaderEffectSource: так текстуры точно рисуются,
                // хотя сами элементы спрятаны.
                Loader {
                    anchors.fill: parent
                    active: root.tint === "gradient"
                    sourceComponent: Item {
                        Item {
                            id: mask
                            anchors.fill: parent
                            TallDigits {
                                visible: root.tall
                                x: tallFace.x
                                text: tallFace.text
                                digitHeight: root.tallH
                                widthRatio: root.tallWidth
                                color: "#ffffff"
                            }
                            TallDigits {
                                visible: root.tall && root.tallStack
                                x: tallFace2.x
                                y: tallFace2.y
                                text: root.mm
                                digitHeight: root.tallH
                                widthRatio: root.tallWidth
                                color: "#ffffff"
                            }
                            Text {
                                visible: !root.tall
                                text: digits.text
                                textFormat: Text.PlainText
                                horizontalAlignment: Text.AlignHCenter
                                font: digits.font
                                lineHeightMode: digits.lineHeightMode
                                lineHeight: digits.lineHeight
                                color: "#ffffff"
                            }
                        }
                        Rectangle {
                            id: grad
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.1; color: "#ffffff" }
                                GradientStop { position: 0.55; color: Theme.accent }
                                GradientStop { position: 0.95; color: "#2BC4F0" }
                            }
                        }
                        ShaderEffectSource { id: maskTex; anchors.fill: parent; sourceItem: mask; hideSource: true; visible: false }
                        ShaderEffectSource { id: gradTex; anchors.fill: parent; sourceItem: grad; hideSource: true; visible: false }
                        MultiEffect {
                            anchors.fill: parent
                            source: gradTex
                            maskEnabled: true
                            maskSource: maskTex
                            maskThresholdMin: 0.3
                            maskSpreadAtMin: 0.3
                        }
                    }
                }
            }
        }
    }
}
