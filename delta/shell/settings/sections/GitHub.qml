pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// GitHub: где живёт Vanks OS. Репозиторий берём из того же update.conf, что и
// delta-update (DELTA_REPO), — значит, здесь показан ровно тот проект, откуда
// приходят обновления. Последний выпуск — из API GitHub (только чтение).
// Ссылки открывает браузер по умолчанию; в пробном режиме — только журнал.
ColumnLayout {
    id: root

    property string title: "GitHub"
    property string icon: "github"
    property string keywords: "репозиторий исходники выпуск релиз ошибка сообщить проблема github iso скачать"
    spacing: 18

    property string repo: ""
    property bool loaded: false
    property var release: null        // { tag, name, date, url, iso }
    property string releaseError: ""
    property string installed: ""

    readonly property string base: repo ? "https://github.com/" + repo : ""

    function open(url, label) {
        Exec.run(["xdg-open", url], { label: label });
    }

    function day(iso) {
        return iso ? new Date(iso).toLocaleDateString(Qt.locale("ru_RU"), "d MMMM yyyy") : "";
    }

    function refresh() {
        // /etc перекрывает системный файл; в проверках файл лежит рядом с оболочкой
        Exec.read(["sh", "-c",
            "DELTA_REPO=; for f in \"$1/../update.conf\" \"$1/../defaults/update.conf\" /etc/delta/update.conf; do " +
            "[ -f \"$f\" ] && . \"$f\"; done; printf '%s' \"$DELTA_REPO\"", "sh", Quickshell.shellDir], (code, out) => {
            root.repo = out.trim();
            root.loaded = true;
            if (root.repo) root.fetchRelease();
        });
        Exec.read(["sh", "-c", "pacman -Q delta 2>/dev/null | cut -d' ' -f2"], (code, out) => root.installed = out.trim());
    }

    function fetchRelease() {
        releaseError = "";
        Exec.read(["sh", "-c",
            "curl -fsSL --max-time 15 -H 'Accept: application/vnd.github+json' \"https://api.github.com/repos/$1/releases/latest\" | " +
            "jq -c '{ tag: .tag_name, name: .name, date: .published_at, url: .html_url, iso: ([.assets[]? | select(.name | test(\"\\\\.iso\"))] | length > 0) }'",
            "sh", repo], (code, out) => {
            try { root.release = JSON.parse(out); }
            catch (e) { root.release = null; root.releaseError = "Не удалось связаться с GitHub — нет интернета?"; }
        });
    }

    Component.onCompleted: refresh()

    // --- шапка ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 128
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line
        RowLayout {
            anchors { fill: parent; margins: 22 }
            spacing: 20
            Rectangle {
                implicitWidth: 76; implicitHeight: 76; radius: 22
                color: Theme.soft2
                Sym { anchors.centerIn: parent; name: "github"; size: 38 }
            }
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: I18n.tr("Vanks OS на GitHub"); size: "h1"; Layout.fillWidth: true }
                Label {
                    text: root.repo ? "github.com/" + root.repo : root.loaded ? "Репозиторий не указан" : "…"
                    tone: 2
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Label { text: I18n.tr("Отсюда приходят обновления Delta"); tone: 3; size: "small"; visible: root.repo !== "" }
            }
            Btn { text: I18n.tr("Открыть"); icon: "link"; kind: "accent"; enabled: root.repo !== ""; onClicked: root.open(root.base, "Открыть репозиторий") }
        }
    }

    Card {
        title: I18n.tr("Последний выпуск")
        visible: root.repo !== ""
        SettingRow {
            icon: "rocket"
            title: root.release ? (root.release.name || root.release.tag) : root.releaseError ? "Нет связи" : "Проверяю…"
            subtitle: root.release
                ? "Вышел " + root.day(root.release.date) + (root.installed ? " · у вас Delta " + root.installed.replace(/-\d+$/, "") : "")
                : root.releaseError
            RowLayout {
                spacing: 8
                Btn { text: I18n.tr("Повторить"); icon: "refresh"; visible: root.releaseError !== ""; onClicked: root.fetchRelease() }
                Btn { text: I18n.tr("Что нового"); visible: root.release !== null; onClicked: root.open(root.release.url, "Открыть выпуск " + root.release.tag) }
            }
        }
        SettingRow {
            icon: "disk"
            title: I18n.tr("Образ для флешки")
            subtitle: I18n.tr("Чтобы поставить Vanks OS на другой компьютер")
            visible: root.release !== null && root.release.iso === true
            Btn { text: I18n.tr("Скачать ISO"); icon: "download"; onClicked: root.open(root.release.url, "Скачать ISO") }
        }
    }

    Card {
        title: I18n.tr("Помочь проекту")
        visible: root.repo !== ""
        Rows {
            SettingRow {
                icon: "warning"
                title: I18n.tr("Что-то сломалось?")
                subtitle: I18n.tr("Расскажите, что случилось, — разберёмся")
                Btn { text: I18n.tr("Сообщить"); onClicked: root.open(root.base + "/issues/new", "Сообщить о проблеме") }
            }
            SettingRow {
                icon: "file"
                title: I18n.tr("Исходный код")
                subtitle: I18n.tr("Всё открыто: оболочка, установщик, сборка образа")
                Btn { text: I18n.tr("Смотреть"); onClicked: root.open(root.base, "Открыть исходный код") }
            }
            SettingRow {
                icon: "download"
                title: I18n.tr("Все выпуски")
                subtitle: I18n.tr("Прошлые версии и списки изменений")
                Btn { text: I18n.tr("Открыть"); onClicked: root.open(root.base + "/releases", "Открыть выпуски") }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.loaded && root.repo === ""
        wrapMode: Text.WordWrap
        tone: 3
        text: "Укажите репозиторий в /etc/delta/update.conf (DELTA_REPO=\"владелец/имя\") — тогда здесь появятся ссылки, а Delta начнёт получать обновления."
    }
}
