import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.common

// Обложка трека. Без картинки — градиент из акцента, как .art в концепте.
//     Cover { width: 64; height: 64; radius: 16; source: player.trackArtUrl }
Item {
    id: root

    property string source
    property real radius: width * 0.25

    Shape {
        anchors.fill: parent
        visible: img.status !== Image.Ready
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.width * 0.3; centerY: root.height * 0.25
                focalX: root.width * 0.3; focalY: root.height * 0.25
                centerRadius: Math.max(root.width, root.height) * 1.05
                focalRadius: 0
                GradientStop { position: 0; color: "#2BC4F0" }
                GradientStop { position: 0.55; color: Theme.accent }
                GradientStop { position: 1; color: "#2A1B66" }
            }
            PathRectangle { width: root.width; height: root.height; radius: root.radius }
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(256, 256)
    }
    // скругление картинки маской; текстуры — через ShaderEffectSource
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
    }
    ShaderEffectSource { id: imgTex; anchors.fill: parent; sourceItem: img; hideSource: true; visible: false }
    ShaderEffectSource { id: maskTex; anchors.fill: parent; sourceItem: mask; hideSource: true; visible: false }
    MultiEffect {
        anchors.fill: parent
        visible: img.status === Image.Ready
        source: imgTex
        maskEnabled: true
        maskSource: maskTex
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
