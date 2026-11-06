import QtQuick
import qs.common

// Плитка выбора стиля или темы: маленькая сцена — обои, верхняя панель, окно
// и док, ниже название и пояснение. Нужна «Стилям и темам» и первой настройке.
//   kind "theme" — тема (материал, Theme.styles): сцена в этом материале,
//                  раскладка — текущего стиля;
//   kind "style" — стиль (интерфейс, Theme.uiStyles): раскладка этого стиля,
//                  материал — тот, что будет после выбора.
//     StyleCard { kind: "theme"; styleId: "liquid"; onClicked: Theme.applyStyle(styleId) }
Rectangle {
    id: root

    property string kind: "theme"
    property string styleId: "delta"
    readonly property bool isUi: kind === "style"
    readonly property var info: isUi ? (Theme.uiStyles.find(x => x.id === styleId) || Theme.uiStyles[0])
                                     : (Theme.styles.find(x => x.id === styleId) || Theme.styles[0])
    readonly property bool sel: isUi ? Theme.ui === styleId : Theme.style === styleId
    readonly property string mat: !isUi ? styleId
        : Theme.uiStyles.some(x => x.theme === Theme.style) ? info.theme : Theme.style
    // раскладка «Акрила»: три острова сверху, круглые кнопки
    readonly property bool islands: (isUi ? styleId : Theme.ui) === "acrylic"
    readonly property bool flat: mat === "gnome"
    readonly property bool liquid: mat === "liquid"
    readonly property bool material: mat === "material"
    readonly property bool nothing: mat === "nothing"
    readonly property bool acrylic: mat === "acrylic"
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
    readonly property color panel: nothing ? (Theme.light ? "#F2F2F2" : "#0B0B0C")
        : flat ? (Theme.light ? "#FAFAFB" : "#242428")
        : material ? Theme.materialBase
        : acrylic ? Qt.rgba(Theme.base.r * 0.8 + 0.04, Theme.base.g * 0.8 + 0.03, Theme.base.b * 0.8 + 0.02, 0.48)
        : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, liquid ? 0.36 : 0.66)
    readonly property real r: flat ? 5 : liquid ? 10 : material ? 14 : nothing ? 9 : acrylic ? 13 : 7

    Rectangle {
        id: scene
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        height: Math.max(90, root.height - 66)
        radius: 10
        clip: true
        // «обои»: разноцветные пятна — на них видно, прозрачна ли панель;
        // у Nothing — чёрное поле в точку
        Grid {
            visible: root.nothing
            z: 1
            anchors.fill: parent
            anchors.margins: 4
            columns: Math.floor(width / 9)
            spacing: 6
            Repeater {
                model: root.nothing ? 120 : 0
                delegate: Rectangle { width: 3; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.22) }
            }
        }
        gradient: root.nothing ? null : root.acrylic ? acrylGrad : sceneGrad
        Gradient {
            id: acrylGrad
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: "#22343A" }
            GradientStop { position: 0.55; color: "#3E3328" }
            GradientStop { position: 1; color: "#B0702E" }
        }
        color: "#000000"
        Gradient {
            id: sceneGrad
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#3B2A8F" }
            GradientStop { position: 0.5; color: Theme.accent }
            GradientStop { position: 1; color: "#E0567F" }
        }
        Rectangle { visible: !root.nothing; x: parent.width * 0.55; y: -20; width: 70; height: 70; radius: 35; color: "#FFD166"; opacity: 0.85 }
        Rectangle { visible: !root.nothing; x: 10; y: 60; width: 60; height: 60; radius: 30; color: "#2BC4F0"; opacity: 0.8 }

        // верхняя панель «Акрила»: три островка
        Repeater {
            model: root.islands ? [[6, 0.26], [0.37, 0.26], [0.70, 0.30]] : []
            delegate: Rectangle {
                required property var modelData
                z: 2
                x: modelData[0] > 1 ? modelData[0] : scene.width * modelData[0]
                y: 5
                width: scene.width * modelData[1] - (modelData[0] > 1 ? 6 : 0)
                height: 11
                radius: 5.5
                color: root.flat ? "#000000" : root.panel
                Sheen { radius: parent.radius; liquid: root.liquid; acrylic: root.acrylic }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 3; width: 5; height: 5; radius: 2.5; color: Theme.accent }
            }
        }
        // верхняя панель: у GNOME — сплошная чёрная полоса во всю ширину
        Rectangle {
            visible: !root.islands
            z: 2
            x: root.flat ? 0 : 6; y: root.flat ? 0 : 5
            width: parent.width - 2 * x; height: root.flat ? 11 : 10
            radius: root.flat ? 0 : height / 2
            color: root.flat ? "#000000" : root.panel
            Sheen { radius: parent.radius; liquid: root.liquid; acrylic: root.acrylic }
        }
        // окно
        Rectangle {
            x: parent.width * 0.2; y: 24
            width: parent.width * 0.6; height: 54
            radius: root.r
            z: 2
            color: root.flat ? (Theme.light ? "#FFFFFF" : "#303034") : root.panel
            border.width: root.material ? 0 : 1
            border.color: root.liquid ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, root.flat ? 0.06 : root.nothing ? 0.22 : 0.12)
            Sheen { radius: parent.radius; liquid: root.liquid; acrylic: root.acrylic }
            Rectangle { x: 8; y: 9; width: parent.width * 0.45; height: 5; radius: 2.5; color: Theme.fg; opacity: 0.7 }
            Rectangle { x: 8; y: 19; width: parent.width * 0.7; height: 4; radius: 2; color: Theme.fg; opacity: 0.35 }
            Rectangle { x: 8; y: 27; width: parent.width * 0.6; height: 4; radius: 2; color: Theme.fg; opacity: 0.35 }
            Rectangle { visible: !root.islands; anchors { right: parent.right; bottom: parent.bottom; margins: 7 } width: 26; height: 10; radius: 5; color: root.material ? Theme.materialAccent : root.nothing ? "#D71921" : Theme.accent }
            Row {
                visible: root.islands
                anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                spacing: 4
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: 13; height: 13; radius: 6.5
                        color: index === 0 ? (root.nothing ? "#D71921" : root.material ? Theme.materialAccent : Theme.accent) : index === 1 ? "#FFF6EA" : Qt.rgba(1, 1, 1, 0.16)
                    }
                }
            }
        }
        // док
        Rectangle {
            z: 2
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
            width: 84; height: 18
            radius: root.flat ? 6 : root.acrylic ? 9 : 9
            color: root.panel
            Sheen { radius: parent.radius; liquid: root.liquid; acrylic: root.acrylic }
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
