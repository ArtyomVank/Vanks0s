import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Последний шаг: «Всё готово» и кнопка «Начать», которую нужно зажать.
Page {
    id: root

    signal started(point at)
    property alias button: hold

    icon: "rocket"
    title: I18n.tr("Всё готово")
    subtitle: I18n.tr("Остальное — драйверы, игры и приложения — предложит помощник сразу после входа. Настройки всегда в верхнем доке.")

    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        Item { Layout.fillHeight: true }
        HoldButton {
            id: hold
            Layout.alignment: Qt.AlignHCenter
            onCompleted: root.started(hold.mapToItem(null, hold.width / 2, hold.height / 2))
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: hold.done ? I18n.tr("Поехали!") : hold.fill > 0.02 ? I18n.tr("Не отпускайте…") : I18n.tr("Зажмите кнопку, чтобы начать")
            tone: 3
        }
        Item { Layout.fillHeight: true }
    }
}
