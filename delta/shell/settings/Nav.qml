pragma Singleton

import QtQuick
import Quickshell

// Состояние окна «Настроек»: открытый раздел, поиск, слой для диалогов,
// всплывающие подсказки. Разделы обращаются сюда, а не к окну напрямую.
Singleton {
    id: root

    property string current: "appearance"
    property string query: ""
    // разделы, которые уже открывали: их Loader остаётся живым
    property var visited: ({})

    // слой поверх всего окна — сюда диалоги переносят себя (parent)
    property Item overlay: null
    // последний открытый диалог — поверх остальных
    property int dialogSerial: 0

    // команда для раздела из IPC или из другого раздела:
    //   Nav.action("keyboard.add", "de") → раздел ловит onAction
    signal action(string name, string arg)
    // прокрутить открытый раздел (IPC, для снимков)
    signal scrollTo(real y)

    property string toastText: ""
    property int toastSerial: 0
    function toast(text) { toastText = text; toastSerial++; }

    function open(id) {
        const v = Object.assign({}, visited);
        v[id] = true;
        visited = v;
        current = id;
    }
}
