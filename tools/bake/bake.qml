//@ pragma AppId delta-bake
import QtQuick
import Quickshell
import Quickshell.Wayland

// Запекание тяжёлого шейдера в картинку (tools/bake/bake.sh):
//     BAKE_FRAG=peak.frag.qsb BAKE_OUT=/tmp/peak BAKE_SIZE="2560 1440" qs -p bake.qml
// Пишет <BAKE_OUT>.png (pass 0) и <BAKE_OUT>-mask.png (pass 1) и выходит.
ShellRoot {
    id: root
    readonly property var size: (Quickshell.env("BAKE_SIZE") || "2560 1440").split(" ").map(Number)
    readonly property string out: Quickshell.env("BAKE_OUT") || "/tmp/bake"
    property int done: 0

    PanelWindow {
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "delta-bake"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 64
        implicitHeight: 64
        color: "black"

        Repeater {
            model: 2
            delegate: ShaderEffect {
                id: fx
                required property int index
                width: root.size[0]
                height: root.size[1]
                visible: false
                property vector2d res: Qt.vector2d(width, height)
                property real pass: index
                fragmentShader: Quickshell.env("BAKE_FRAG")
                Timer {
                    interval: 1500 + fx.index * 4000
                    running: true
                    onTriggered: fx.grabToImage(r => {
                        r.saveToFile(root.out + (fx.index ? "-mask" : "") + ".png");
                        console.info("baked " + fx.index);
                        if (++root.done === 2) Qt.quit();
                    })
                }
            }
        }
    }
}
