import QtQuick
import qs.common

// Текст «печатается» по буквам с тихими щелчками (звук tick). Сам ничего не
// рисует — отдаёт text для Label; play() начинает заново. Поменялся full,
// пока не печатаем (язык, число найденного), — показываем его сразу.
//     Typewriter { id: tw; full: I18n.tr("Всё готово") }
//     Label { text: tw.text }   …   tw.play()
Timer {
    id: root

    property string full
    property int count: full.length
    // щелчок на каждую n-ю букву: на каждую — трещит
    property int every: 2
    property bool sound: true
    readonly property string text: full.slice(0, count)
    readonly property bool typing: running

    interval: 28
    repeat: true

    function play(delay) {
        count = 0;
        interval = delay > 0 ? delay : 28;
        restart();
    }
    onFullChanged: if (!running) count = full.length
    onTriggered: {
        interval = 28;
        // пробелы проскакиваем — ритм ровнее
        count = Math.min(full.length, count + (full.charAt(count) === " " ? 2 : 1));
        if (sound && count % every === 1) Sounds.play("tick", 45);
        if (count >= full.length) stop();
    }
}
