import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг 5: звуки и движение — анимации окон, «желе» при перетаскивании, «джинн».
Page {
    id: root

    icon: "sliders"
    title: I18n.tr("Звуки и движение")
    subtitle: I18n.tr("Vanks OS отзывается звуком и живыми анимациями. Если хочется тише и спокойнее — выключите.")

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        implicitHeight: rows.implicitHeight + 8
        height: implicitHeight
        radius: 18
        color: Theme.soft
        border.width: 1
        border.color: Theme.line
        ColumnLayout {
            id: rows
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 0
            SettingRow {
                icon: "volume"
                title: I18n.tr("Звуки системы")
                subtitle: I18n.tr("Уведомления, громкость, блокировка, снимки экрана")
                Toggle {
                    checked: Settings.get("sounds.enabled", true) !== false
                    onToggled: v => { Settings.set("sounds.enabled", v); if (v) Qt.callLater(() => Sounds.play("oobe-select", 0)); }
                }
            }
            SettingRow {
                icon: "sliders"
                title: I18n.tr("Анимации")
                subtitle: I18n.tr("Плавное появление окон и переходы")
                Toggle { checked: Settings.get("windows.animations", true) !== false; onToggled: v => { Settings.set("windows.animations", v); Sounds.play("pop", 60); } }
            }
            SettingRow {
                icon: "cursor"
                title: I18n.tr("Желе при перемещении окон")
                subtitle: I18n.tr("Окно пружинит за курсором, когда его тащат")
                Toggle { checked: Number(Settings.get("windows.jelly", 0.5)) > 0; onToggled: v => { Settings.set("windows.jelly", v ? 0.5 : 0); Sounds.play("pop", 60); } }
            }
            SettingRow {
                icon: "minus"
                title: I18n.tr("Эффект «джинн»")
                subtitle: I18n.tr("Свёрнутое окно втягивается в док")
                Toggle { checked: Settings.get("windows.genie", true) !== false; onToggled: v => { Settings.set("windows.genie", v); Sounds.play("swoosh", 60); } }
            }
        }
    }
}
