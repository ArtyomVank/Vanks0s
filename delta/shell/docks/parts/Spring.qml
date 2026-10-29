import QtQuick

// Пружина с затуханием — «желе» доков. value тянется к target и колышется
// вокруг него; kick(v) толкает (v — скорость, единиц value в секунду).
// Считается покадрово, пока не успокоится, — в покое не стоит ничего.
//     Spring { id: squash; stiffness: 320; damping: 11 }   …   squash.kick(-1.4)
QtObject {
    id: s

    property real target: 0
    property real value: 0
    property real velocity: 0
    property real stiffness: 260      // выше — колебания чаще
    property real damping: 14         // ниже — колышется дольше
    property real epsilon: 0.001      // меньше этого — уже покой
    readonly property bool settled: !frames.running

    function kick(v) { velocity += v; frames.start(); }
    // сразу поставить значение (без толчка), например при отключении эффекта
    function snap(v) { frames.stop(); value = v; velocity = 0; }

    onTargetChanged: frames.start()

    property FrameAnimation frames: FrameAnimation {
        onTriggered: {
            // длинный кадр (окно было скрыто) не должен «выстреливать»
            const dt = Math.min(frameTime, 1 / 30);
            // полунеявный Эйлер: устойчив и при редких кадрах
            const a = -s.stiffness * (s.value - s.target) - s.damping * s.velocity;
            s.velocity += a * dt;
            s.value += s.velocity * dt;
            if (Math.abs(s.velocity) < s.epsilon * 4 && Math.abs(s.value - s.target) < s.epsilon) {
                s.value = s.target;
                s.velocity = 0;
                stop();
            }
        }
    }
}
