pragma Singleton

import QtQuick
import Quickshell

// Состояние окна «Настроек»: открытый раздел, поиск, слой для диалогов,
// всплывающие подсказки. Разделы обращаются сюда, а не к окну напрямую.
Singleton {
    id: root

    // "home" — главная с папками
    property string current: "home"
    property string query: ""
    // поиск: найденное (Registry.search) и выбранное стрелками; searching —
    // справа показан список найденного, а не раздел
    readonly property var results: query.trim().length ? Registry.search(query) : []
    property bool searching: false
    property int pick: 0
    onQueryChanged: { searching = query.trim().length > 0; pick = 0; }
    // открыть найденное: раздел, а в нём прокрутить к строке и подсветить её
    // card — найдена сама карточка; inCard — карточка, в которой строка
    signal reveal(string section, string key, bool card, string inCard)
    function openResult(r) {
        if (!r) return;
        open(r.sec);
        if (r.key) reveal(r.sec, r.key, r.kind === "card", r.card || "");
    }
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
    // раздел просит закрыть окно (например, «Рекомендации» открывают помощник)
    signal closeRequested()

    property string toastText: ""
    property int toastSerial: 0
    function toast(text) { toastText = text; toastSerial++; }

    // раскрытые папки боковой панели: { system: true, … }
    property var openFolders: ({})
    function setFolder(id, on) {
        if ((openFolders[id] === true) === on) return;
        const f = Object.assign({}, openFolders);
        f[id] = on;
        openFolders = f;
    }

    function open(id) {
        const v = Object.assign({}, visited);
        v[id] = true;
        visited = v;
        current = id;
        searching = false;
    }
}
