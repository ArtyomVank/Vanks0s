import QtQuick
import qs.common

// Плитка выбора стиля оформления (Theme.styles): маленькая сцена — обои,
// верхняя панель, окно и док в этом стиле, ниже название и пояснение.
// Нужна «Оформлению» и первой настройке.
//     StyleCard { styleId: "liquid"; onClicked: Theme.applyStyle(styleId) }
Rectangle {
    id: root

    property string styleId: "delta"
    readonly property var info: Theme.styles.find(x => x.id === styleId) || Theme.styles[0]
    readonly property bool sel: Theme.style === styleId
    readonly property bool flat: styleId === "gnome"
    readonly property bool liquid: styleId === "liquid"
    readonly property bool material: styleId === "material"
    signal clicked()

    implicitWidth: 200
    implicitHeight: 172
    radius: 16
    color: hov.hovered ? Theme.soft2 : Theme.soft
    border.width: 2
    border.color: sel ? Theme.accent : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }
    scale: tap.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 140 * Theme.anim.k; easing.type: Easing.OutBack } }

    // панели сцены: цвет и прозрачность — как у стиля
    // (Material You — сплошные, в оттенке обоев, крупно скруглённые)
    readonly property color panel: flat ? (Theme.light ? "#FAFAFB" : "#242428")
        : material ? Theme.materialBase
        : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, liquid ? 0.36 : 0.66)
    readonly property real r: flat ? 5 : liquid ? 10 : material ? 14 : 7

    Rectangle {
        id: scene
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        height: Math.max(90, root.height - 66)
        radius: 10
        clip: true
        // «обои»: разноцветные пятна — на них видно, прозрачна ли панель
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#3B2A8F" }
            GradientStop { position: 0.5; color: Theme.accent }
            GradientStop { position: 1; color: "#E0567F" }
        }
        Rectangle { x: parent.width * 0.55; y: -20; width: 70; height: 70; radius: 35; color: "#FFD166"; opacity: 0.85 }
        Rectangle { x: 10; y: 60; width: 60; height: 60; radius: 30; color: "#2BC4F0"; opacity: 0.8 }

        // верхняя панель: у GNOME — сплошная чёрная полоса во всю ширину
        Rectangle {
            x: root.flat ? 0 : 6; y: root.flat ? 0 : 5
            width: parent.width - 2 * x; height: root.flat ? 11 : 10
            radius: root.flat ? 0 : height / 2
            color: root.flat ? "#000000" : root.panel
            Sheen { radius: parent.radius; visible: root.liquid }
        }
        // окно
        Rectangle {
            x: parent.width * 0.2; y: 24
            width: parent.width * 0.6; height: 54
            radius: root.r
            color: root.flat ? (Theme.light ? "#FFFFFF" : "#303034") : root.panel
            border.width: root.material ? 0 : 1
            border.color: root.liquid ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, root.flat ? 0.06 : 0.12)
            Sheen { radius: parent.radius; visible: root.liquid }
            Rectangle { x: 8; y: 9; width: parent.width * 0.45; height: 5; radius: 2.5; color: Theme.fg; opacity: 0.7 }
            Rectangle { x: 8; y: 19; width: parent.width * 0.7; height: 4; radius: 2; color: Theme.fg; opacity: 0.35 }
            Rectangle { x: 8; y: 27; width: parent.width * 0.6; height: 4; radius: 2; color: Theme.fg; opacity: 0.35 }
            Rectangle { anchors { right: parent.right; bottom: parent.bottom; margins: 7 } width: 26; height: 10; radius: 5; color: root.material ? Theme.materialAccent : Theme.accent }
        }
        // док
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
            width: 84; height: 18
            radius: root.flat ? 6 : 9
            color: root.panel
            Sheen { radius: parent.radius; visible: root.liquid }
            Row {
                anchors.centerIn: parent
                spacing: 5
                Repeater {
                    model: ["#7C5CFF", "#3FB37A", "#F09A2B", "#2BC4F0"]
                    delegate: Rectangle { required property string modelData; width: 11; height: 11; radius: root.flat ? 3 : 5.5; color: modelData }
                }
            }
        }
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: scene.bottom; topMargin: 8; leftMargin: 12; rightMargin: 10 }
        spacing: 2
        Row {
            spacing: 6
            Label { text: I18n.tr(root.info.name); font.weight: Font.Bold }
            Sym { visible: root.sel; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 14; color: Theme.accent }
        }
        Label { width: parent.width; text: I18n.tr(root.info.note); size: "caption"; tone: 3; elide: Text.ElideRight }
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: root.clicked() }
}
