import QtQuick
import Quickshell
import Quickshell.Wayland

// Невидимая полоска, которая только резервирует место под док
// (exclusive zone), чтобы окна не заходили под постоянно видимый док.
// Сами доки рисуются в окнах без резервирования — так их координаты
// не зависят от соседних панелей.
PanelWindow {
    property string edge: "top"
    property int zone: 0
    readonly property bool vertical: edge === "left" || edge === "right"

    WlrLayershell.namespace: "delta-dock-zone"
    WlrLayershell.layer: WlrLayer.Bottom
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: zone
    anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
    implicitHeight: vertical ? 0 : 1
    implicitWidth: vertical ? 1 : 0
    color: "transparent"
    mask: Region {}
}
