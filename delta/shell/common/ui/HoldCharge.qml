import QtQuick
import qs.common

// Кнопка «зажми и держи»: пока держат, fill растёт от 0 до 1 за holdTime;
// отпустили раньше — стекает обратно с пружинкой; дошла до 1 — completed().
// Рисует заливку Liquid, логика — здесь. Общая для «Начать» (oobe/HoldButton)
// и кнопок «Выключение» и «Перезагрузка» (lock/PowerPanel, lock/LockSurface).
//     HoldCharge { id: charge; onCompleted: … }
//     TapHandler { onPressedChanged: pressed ? charge.begin() : charge.cancel() }
Item {
    id: root

    property int holdTime: 1500
    property real fill: 0
    property bool done: false
    property string sound: "oobe-fill"
    readonly property real level: Math.max(0, Math.min(1, fill))
    readonly property bool active: fill > 0.002 && !done
    readonly property bool charging: charge.running
    signal completed()

    function begin() {
        if (done) return;
        drain.stop();
        charge.duration = Math.max(60, (1 - Math.max(0, fill)) * holdTime);
        charge.restart();
        if (sound.length) Sounds.hold(sound);
    }
    function cancel() {
        if (done || (!charge.running && fill <= 0)) return;
        charge.stop();
        Sounds.release();
        drain.restart();
    }
    // снова пустая (повторный запуск настройки, меню открыли заново)
    function reset() {
        charge.stop();
        drain.stop();
        done = false;
        fill = 0;
    }

    NumberAnimation {
        id: charge
        target: root; property: "fill"; to: 1
        easing.type: Easing.InOutSine
        onFinished: if (root.fill >= 0.999) { root.done = true; Sounds.release(); root.completed(); }
    }
    NumberAnimation { id: drain; target: root; property: "fill"; to: 0; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
}
