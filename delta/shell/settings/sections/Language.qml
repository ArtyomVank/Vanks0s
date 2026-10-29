pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Язык и регион: язык системы (LANG) и форматы (LC_TIME, LC_NUMERIC,
// LC_MONETARY, LC_MEASUREMENT, LC_PAPER) через localectl — localed спросит
// пароль через polkit; в проверках только журнал. Применяется после
// повторного входа.
ColumnLayout {
    id: root

    property string title: I18n.tr("Язык и регион")
    property string icon: "globe"
    property string keywords: "язык локаль регион форматы дата числа валюта единицы"
    spacing: 18

    property var status: ({})       // { LANG: "ru_RU.UTF-8", LC_TIME: … }
    property var locales: []
    property bool changed: false

    readonly property string lang: status.LANG || "C.UTF-8"
    readonly property string formats: status.LC_TIME || lang
    readonly property var fmtKeys: ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER"]

    function cap(s) { return s.length ? s[0].toUpperCase() + s.slice(1) : s; }
    function nameOf(loc) {
        const base = String(loc).split(".")[0];
        if (base === "C" || base === "POSIX") return "Без языка (C)";
        const l = Qt.locale(base);
        const lang = l.nativeLanguageName || base;
        const terr = l.nativeTerritoryName || "";
        return cap(lang) + (terr ? " (" + terr + ")" : "");
    }

    function refresh() {
        Exec.read(["localectl", "status"], (code, out) => {
            const o = {};
            const re = /(LANG|LC_[A-Z]+|LANGUAGE)=(\S+)/g;
            let m;
            while ((m = re.exec(out)) !== null) o[m[1]] = m[2];
            root.status = o;
        });
    }
    Component.onCompleted: {
        refresh();
        Exec.read(["localectl", "list-locales"], (code, out) => {
            root.locales = out.split("\n").filter(l => l.length).map(l => ({ value: l, label: root.nameOf(l), sub: l }));
        });
    }

    function apply(newLang, newFormats) {
        const args = ["localectl", "set-locale", "LANG=" + newLang];
        if (newFormats !== newLang) for (const k of fmtKeys) args.push(k + "=" + newFormats);
        Exec.run(args, {
            label: I18n.tr("язык ") + newLang + (newFormats !== newLang ? ", форматы " + newFormats : ""),
            done: code => {
                if (code !== 0) { Nav.toast("Не удалось изменить язык"); return; }
                root.changed = true;
                if (Exec.dryRun) {
                    // показываем выбор, как будто localed его принял
                    const o = { LANG: newLang };
                    if (newFormats !== newLang) for (const k of root.fmtKeys) o[k] = newFormats;
                    root.status = o;
                } else root.refresh();
            }
        });
    }

    readonly property var fmtLocale: Qt.locale(formats.split(".")[0])
    readonly property date sample: new Date(2026, 9, 28, 14, 30)

    Card {
        title: I18n.tr("Язык")
        Rows {
            SettingRow {
                icon: "globe"
                title: I18n.tr("Язык системы")
                subtitle: I18n.tr("На этом языке говорят программы")
                Select { text: root.nameOf(root.lang); onClicked: langPicker.openWith() }
            }
            SettingRow {
                icon: "calendar"
                title: I18n.tr("Форматы")
                subtitle: I18n.tr("Как писать даты, числа и деньги")
                Select { text: root.nameOf(root.formats); onClicked: fmtPicker.openWith() }
            }
            SettingRow {
                visible: root.changed
                icon: "warning"
                title: I18n.tr("Изменения вступят в силу после повторного входа")
            }
        }
    }

    Card {
        title: I18n.tr("Как это выглядит")
        SettingRow { icon: "calendar"; title: I18n.tr("Дата"); Label { text: root.sample.toLocaleDateString(root.fmtLocale, Locale.LongFormat); tone: 2 } }
        SettingRow { icon: "clock"; title: I18n.tr("Время"); Label { text: root.sample.toLocaleTimeString(root.fmtLocale, Locale.ShortFormat); tone: 2 } }
        SettingRow { icon: "grid"; title: I18n.tr("Числа"); Label { text: Number(1234567.89).toLocaleString(root.fmtLocale, "f", 2); tone: 2 } }
        SettingRow { icon: "palette"; title: I18n.tr("Валюта"); Label { text: Number(1990).toLocaleCurrencyString(root.fmtLocale); tone: 2 } }
        SettingRow {
            icon: "scale"; title: I18n.tr("Единицы")
            Label { text: root.fmtLocale.measurementSystem === Locale.MetricSystem ? "метрические (км, кг, °C)" : "имперские (мили, фунты, °F)"; tone: 2 }
        }
        SettingRow {
            icon: "calendar"; title: I18n.tr("Первый день недели")
            Label { text: Qt.locale("ru_RU").dayName(root.fmtLocale.firstDayOfWeek % 7, Locale.LongFormat); tone: 2 }
        }
    }

    Card {
        SettingRow {
            icon: "info"
            title: I18n.tr("Нет нужного языка?")
            subtitle: I18n.tr("Здесь языки, которые уже есть в системе")
        }
    }

    Picker {
        id: langPicker
        title: I18n.tr("Язык системы")
        searchHint: "Язык: русский, english"
        model: root.locales
        current: root.lang
        onPicked: v => root.apply(v, root.formats === root.lang ? v : root.formats)
    }
    Picker {
        id: fmtPicker
        title: I18n.tr("Форматы")
        searchHint: "Регион"
        model: root.locales
        current: root.formats
        onPicked: v => root.apply(root.lang, v)
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "language.lang") { if (arg) root.apply(arg, root.formats); else langPicker.openWith(); }
            else if (name === "language.formats") { if (arg) root.apply(root.lang, arg); else fmtPicker.openWith(); }
        }
    }
}
