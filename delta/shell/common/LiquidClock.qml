pragma Singleton

import QtQuick
import Quickshell

// Общие часы «жидкого стекла»: по ним стекают капли и переливается блик
// (common/ui/Sheen). Идут с частотой экрана, только пока стиль «Жидкое
// стекло» и на экране есть хоть одна такая панель. Капли — appearance.drops.
Singleton {
    id: root

    property int users: 0
    readonly property bool drops: Settings.get("appearance.drops", true) !== false
    property real time: 0

    FrameAnimation {
        running: Theme.liquid && root.users > 0
        // после долгой паузы (сон, другой стиль) не прыгаем вперёд
        onTriggered: root.time = (root.time + Math.min(0.05, frameTime)) % 3600
    }
}
