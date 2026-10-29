import QtQuick

// «Я смотрю на показатели»: пока active, SystemStats опрашивает датчики.
//     StatsUser { active: root.visible; gpu: true }
// gpu — нужны данные видеокарты (для NVIDIA это запуск nvidia-smi),
// disk — нужен диск (df раз в 30 с).
QtObject {
    id: root

    property bool active: true
    property bool gpu: false
    property bool disk: false

    // что именно сейчас «взято» — чтобы отдать ровно столько же
    property var held: null

    function sync() {
        if (held) SystemStats.release(held.gpu, held.disk);
        held = active ? { gpu: gpu, disk: disk } : null;
        if (held) SystemStats.acquire(held.gpu, held.disk);
    }

    onActiveChanged: sync()
    onGpuChanged: sync()
    onDiskChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (held) SystemStats.release(held.gpu, held.disk)
}
