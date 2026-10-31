pragma Singleton

import QtQuick
import Quickshell
import "i18n/en.js" as En
import "i18n/uk.js" as Uk
import "i18n/be.js" as Be
import "i18n/kk.js" as Kk
import "i18n/de.js" as De
import "i18n/fr.js" as Fr
import "i18n/es.js" as Es

// Язык интерфейса Delta: «ru» (по умолчанию), «en», «uk», «be», «kk», «de»,
// «fr» или «es». Строки в коде — по-русски, перевод ищется по самой строке:
//     Label { text: I18n.tr("Настройки") }
// Нет перевода — для uk, be, kk показываем по-русски, для остальных —
// по-английски, а нет и его — как есть. Привязки с I18n.tr пересчитываются
// сами, когда язык меняется (language.ui в settings.json).
// Словари — common/i18n/<язык>.js с одинаковыми ключами; новые строки
// добавляйте во все.
Singleton {
    id: root

    // name — самоназвание языка, hint — подпись в первой настройке,
    // layout — раскладка, которую стоит включить вместе с языком
    readonly property var languages: [
        { id: "ru", name: "Русский", hint: "Интерфейс на русском", locale: "ru_RU", layout: "ru" },
        { id: "en", name: "English", hint: "Interface in English", locale: "en_US", layout: "us" },
        { id: "uk", name: "Українська", hint: "Інтерфейс українською", locale: "uk_UA", layout: "ua" },
        { id: "be", name: "Беларуская", hint: "Інтэрфейс па-беларуску", locale: "be_BY", layout: "by" },
        { id: "kk", name: "Қазақша", hint: "Интерфейс қазақша", locale: "kk_KZ", layout: "kz" },
        { id: "de", name: "Deutsch", hint: "Oberfläche auf Deutsch", locale: "de_DE", layout: "de" },
        { id: "fr", name: "Français", hint: "Interface en français", locale: "fr_FR", layout: "fr" },
        { id: "es", name: "Español", hint: "Interfaz en español", locale: "es_ES", layout: "es" }
    ]
    readonly property var dicts: ({ en: En.strings, uk: Uk.strings, be: Be.strings, kk: Kk.strings, de: De.strings, fr: Fr.strings, es: Es.strings })
    // запасной словарь, если в своём строки нет
    readonly property var fallback: ({ de: "en", fr: "en", es: "en" })

    function info(id) {
        for (const l of languages) if (l.id === id) return l;
        return languages[0];
    }

    readonly property string lang: info(Settings.get("language.ui", "ru")).id
    readonly property bool en: lang === "en"
    readonly property bool ru: lang === "ru"
    // русский текст ближе, чем английский (описания в магазине и т. п.)
    readonly property bool ruText: ["ru", "uk", "be", "kk"].indexOf(lang) >= 0
    readonly property var current: info(lang)
    readonly property string locale: current.locale

    function tr(text) {
        if (ru) return text;
        let t = dicts[lang][text];
        if (t === undefined && fallback[lang]) t = dicts[fallback[lang]][text];
        return t === undefined ? text : t;
    }
}
