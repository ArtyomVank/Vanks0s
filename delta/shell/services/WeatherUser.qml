import QtQuick

// «Я показываю погоду»: пока active, Weather обновляет прогноз (раз в 20 мин).
//     WeatherUser { active: root.visible }
QtObject {
    id: root

    property bool active: true
    property bool held: false

    function sync() {
        if (held === active) return;
        held = active;
        if (held) Weather.acquire(); else Weather.release();
    }

    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (held) Weather.release()
}
