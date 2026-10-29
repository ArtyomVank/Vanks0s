import QtQuick
import QtQuick.Shapes
import qs.common
import qs.common.ui

// Колокольчик «без звука», как переключатель режима в iOS: при выключении
// звука колокольчик вздрагивает и его перечёркивает косая черта, при
// включении черта втягивается обратно, а колокольчик звенит.
//     MuteBell { size: 18; muted: sink.audio.muted; cutColor: Theme.glass2 }
Item {
    id: root

    property bool muted: false
    property int size: 18
    property color color: Theme.fg
    // цвет под значком: черта «вырезает» в колокольчике просвет этого цвета
    property color cutColor: Theme.glass2

    implicitWidth: size
    implicitHeight: size

    // 0 — черты нет, 1 — перечёркнут
    property real slash: muted ? 1 : 0
    Behavior on slash { enabled: !root.instant; NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

    // звон — при каждой смене (и туда, и обратно)
    onMutedChanged: if (!instant) ring.restart()
    // сразу поставить состояние, без анимации (дальше — смена с анимацией)
    property bool instant: false
    function snapTo(m) { instant = true; muted = m; instant = false; }

    Item {
        id: bell
        anchors.fill: parent
        transformOrigin: Item.Top
        Sym { anchors.fill: parent; name: "bell"; size: root.size; color: root.color }
    }
    SequentialAnimation {
        id: ring
        NumberAnimation { target: bell; property: "rotation"; to: -20; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: bell; property: "rotation"; to: 16; duration: 130; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bell; property: "rotation"; to: -11; duration: 120; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bell; property: "rotation"; to: 6; duration: 110; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bell; property: "rotation"; to: 0; duration: 140; easing.type: Easing.OutQuad }
    }

    // косая черта из левого верхнего угла в правый нижний; под ней — просвет
    Shape {
        id: cut
        anchors.fill: parent
        visible: root.slash > 0.01
        preferredRendererType: Shape.CurveRenderer
        readonly property real p: root.size * 0.12
        ShapePath {
            strokeColor: root.cutColor
            strokeWidth: root.size * 0.24
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            startX: cut.p; startY: cut.p
            PathLine { x: cut.p + (root.size - 2 * cut.p) * root.slash; y: cut.p + (root.size - 2 * cut.p) * root.slash }
        }
        ShapePath {
            strokeColor: root.color
            strokeWidth: Math.max(1.4, root.size * 0.1)
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            startX: cut.p; startY: cut.p
            PathLine { x: cut.p + (root.size - 2 * cut.p) * root.slash; y: cut.p + (root.size - 2 * cut.p) * root.slash }
        }
    }
}
