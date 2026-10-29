pragma Singleton

import QtQuick
import Quickshell
import "i18n/en.js" as En

// Язык интерфейса Delta: «ru» (по умолчанию) или «en». Строки в коде —
// по-русски, перевод ищется по самой строке:
//     Label { text: I18n.tr("Настройки") }
// Нет перевода — показываем как есть. Привязки с I18n.tr пересчитываются
// сами, когда язык меняется (language.ui в settings.json).
// Словарь — common/i18n/en.js; новые строки добавляйте туда.
Singleton {
    id: root

    readonly property string lang: Settings.get("language.ui", "ru") === "en" ? "en" : "ru"
    readonly property bool en: lang === "en"
    readonly property string locale: en ? "en_US" : "ru_RU"

    function tr(text) {
        if (!en) return text;
        const t = En.strings[text];
        return t === undefined ? text : t;
    }
}
