pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Клавиатура: раскладки (input.layouts), сочетание переключения, повтор
// и список сочетаний Delta. Всё из input.* применяет delta-apply.
ColumnLayout {
    id: root

    property string title: "Клавиатура"
    property string icon: "keyboard"
    property string keywords: "раскладка язык переключение повтор задержка сочетания горячие клавиши xkb"
    spacing: 18

    readonly property var i: Settings.s.input || ({})
    readonly property var layouts: (i.layouts || ["us", "ru"]).filter(l => typeof l === "string")
    // все раскладки из xkb: [{ value, label, sub }]
    property var xkb: []

    // xkb даёт английские названия — частые переводим
    readonly property var ruNames: ({
        us: "Английская (США)", gb: "Английская (Великобритания)", ru: "Русская", ua: "Украинская",
        by: "Белорусская", kz: "Казахская", de: "Немецкая", fr: "Французская", es: "Испанская",
        it: "Итальянская", pl: "Польская", cz: "Чешская", tr: "Турецкая", jp: "Японская",
        cn: "Китайская", kr: "Корейская", il: "Иврит", ara: "Арабская", gr: "Греческая",
        pt: "Португальская", br: "Португальская (Бразилия)", fi: "Финская", se: "Шведская",
        no: "Норвежская", dk: "Датская", nl: "Нидерландская", hu: "Венгерская", ro: "Румынская",
        bg: "Болгарская", rs: "Сербская", ge: "Грузинская", am: "Армянская", az: "Азербайджанская",
        uz: "Узбекская", tj: "Таджикская", kg: "Киргизская", lt: "Литовская", lv: "Латышская",
        ee: "Эстонская", in: "Индийская", th: "Тайская", vn: "Вьетнамская", ir: "Персидская"
    })
    function nameOf(code) {
        if (ruNames[code]) return ruNames[code];
        const x = xkb.find(l => l.value === code);
        return x ? x.label : code;
    }

    function setLayouts(list) { Settings.set("input.layouts", list); }
    function move(idx, d) {
        const l = layouts.slice();
        const j = idx + d;
        if (j < 0 || j >= l.length) return;
        [l[idx], l[j]] = [l[j], l[idx]];
        setLayouts(l);
    }
    function remove(idx) {
        if (layouts.length <= 1) return;
        const l = layouts.slice();
        l.splice(idx, 1);
        setLayouts(l);
    }
    function add(code) {
        if (!code || layouts.indexOf(code) !== -1) return;
        setLayouts(layouts.concat([code]));
        Nav.toast("Добавлена раскладка: " + nameOf(code));
    }

    Card {
        title: "Раскладки"
        Rows {

            Repeater {
                model: root.layouts
                delegate: SettingRow {
                    id: lrow
                    required property string modelData
                    required property int index
                    title: root.nameOf(modelData)
                    subtitle: (index === 0 ? "основная · " : "") + modelData
                    icon: "keyboard"
                    Row {
                        spacing: 6
                        Btn { icon: "chevron-up"; iconSize: 16; implicitHeight: 32; enabled: lrow.index > 0; onClicked: root.move(lrow.index, -1) }
                        Btn { icon: "chevron-down"; iconSize: 16; implicitHeight: 32; enabled: lrow.index < root.layouts.length - 1; onClicked: root.move(lrow.index, 1) }
                        Btn { icon: "trash"; iconSize: 16; implicitHeight: 32; kind: "danger"; enabled: root.layouts.length > 1; onClicked: root.remove(lrow.index) }
                    }
                }
            }
            SettingRow {
                icon: "plus"
                title: "Добавить раскладку"
                subtitle: "Раскладки переключаются в этом порядке"
                Btn { text: "Добавить…"; icon: "plus"; onClicked: picker.openWith() }
            }
        }
    }

    Card {
        title: "Переключение и повтор"
        SettingRow {
            icon: "globe"
            title: "Сочетание для смены раскладки"
            wide: true
            Chips {
                model: [
                    { value: "grp:alt_shift_toggle", label: "Alt + Shift" },
                    { value: "grp:win_space_toggle", label: "Super + Пробел" },
                    { value: "grp:ctrl_shift_toggle", label: "Ctrl + Shift" },
                    { value: "grp:caps_toggle", label: "Caps Lock" }
                ]
                current: root.i.switchKeys ?? "grp:alt_shift_toggle"
                onPicked: v => Settings.set("input.switchKeys", v)
            }
        }
        SliderRow {
            icon: "clock"
            title: "Задержка перед повтором"
            from: 150; to: 1000; step: 10; unit: " мс"
            value: root.i.repeatDelay ?? 300
            onCommit: v => Settings.set("input.repeatDelay", Math.round(v))
        }
        SliderRow {
            icon: "refresh"
            title: "Скорость повтора"
            from: 5; to: 80; step: 1
            format: v => Math.round(v) + "/с"
            value: root.i.repeatRate ?? 30
            onCommit: v => Settings.set("input.repeatRate", Math.round(v))
        }
        SettingRow {
            icon: "edit"
            title: "Проверить"
            wide: true
            Field { placeholder: "Зажмите клавишу, чтобы проверить повтор" }
        }
    }

    Card {
        title: "Сочетания Delta"
        Rows {
            Repeater {
                model: [
                    { k: ["Super"], t: "Окно приложений" },
                    { k: ["Super", "S"], t: "Выбор обоев" },
                    { k: ["Super", "N"], t: "Центр уведомлений" },
                    { k: ["Super", "W"], t: "Редактор виджетов" },
                    { k: ["Super", "I"], t: "Настройки" },
                    { k: ["Super", "L"], t: "Заблокировать экран" },
                    { k: ["Super", "Esc"], t: "Меню питания" },
                    { k: ["Super", "Enter"], t: "Терминал" },
                    { k: ["Super", "E"], t: "Файлы" },
                    { k: ["Super", "Q"], t: "Закрыть окно" },
                    { k: ["Super", "H"], t: "Свернуть окно" },
                    { k: ["Super", "F"], t: "Во весь экран" },
                    { k: ["Super", "V"], t: "Плавающее окно" },
                    { k: ["Super", "1…0"], t: "Рабочий стол 1–10" },
                    { k: ["Super", "Shift", "1…0"], t: "Перенести окно на стол" },
                    { k: ["Print"], t: "Снимок экрана" }
                ]
                delegate: SettingRow {
                    id: krow
                    required property var modelData
                    title: modelData.t
                    KeyCaps { keys: krow.modelData.k }
                }
            }
            SettingRow {
                icon: "info"
                title: "Переназначение сочетаний"
                subtitle: "скоро"
            }
        }
    }

    Picker {
        id: picker
        title: "Добавить раскладку"
        searchHint: "Язык или код: немецкая, de"
        model: root.xkb.filter(l => root.layouts.indexOf(l.value) === -1)
        onPicked: v => root.add(v)
    }

    // ! layout из evdev.lst: «  us              English (US)»
    Process {
        running: true
        command: ["sh", "-c", "awk '/^! layout/{p=1;next} /^!/{p=0} p && NF' /usr/share/X11/xkb/rules/evdev.lst"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const m = line.match(/^\s+(\S+)\s+(.+)$/);
                    // delta-apply принимает только коды раскладок без вариантов
                    if (!m || !/^[a-z]{2,8}$/.test(m[1])) continue;
                    const ru = root.ruNames[m[1]];
                    out.push({ value: m[1], label: ru || m[2], sub: ru ? m[2] + " · " + m[1] : m[1], keywords: m[2] });
                }
                root.xkb = out.sort((a, b) => a.label.localeCompare(b.label));
            }
        }
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "keyboard.add") { if (arg) root.add(arg); else picker.openWith(); }
            else if (name === "keyboard.pick") picker.openWith(arg);
            else if (name === "keyboard.remove") root.remove(root.layouts.indexOf(arg));
            else if (name === "keyboard.up") root.move(root.layouts.indexOf(arg), -1);
        }
    }
}
