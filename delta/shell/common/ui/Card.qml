import QtQuick
import QtQuick.Layouts
import qs.common

// Группа строк настроек с заголовком над ней. Строки разделены линией.
//     Card { title: "Экран"; SettingRow { … } SettingRow { … } }
ColumnLayout {
    id: root

    property string title
    default property alias rows: box.data

    spacing: 8
    Layout.fillWidth: true

    Label {
        visible: root.title.length > 0
        text: root.title
        // обычный регистр и чуть крупнее: группа читается как заголовок, а не как метка
        tone: 2
        font.weight: Font.DemiBold
        Layout.leftMargin: 6
        Layout.topMargin: 4
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: box.implicitHeight
        radius: Theme.radius - 4
        color: Theme.soft
        border.color: Theme.line
        border.width: 1

        ColumnLayout {
            id: box
            anchors { left: parent.left; right: parent.right }
            spacing: 0
        }

        // Строки, между которыми нужна линия. Repeater и скрытые строки — тоже
        // дети box (нулевой высоты), а строки Repeater стоят в children после
        // статичных — поэтому только видимые и по порядку y.
        readonly property var shownRows: {
            const out = [];
            for (let i = 0; i < box.children.length; i++) {
                const c = box.children[i];
                if (c.visible && c.height > 0) out.push(c);
            }
            return out.sort((a, b) => a.y - b.y);
        }

        // разделители между строками
        Repeater {
            model: Math.max(0, parent.shownRows.length - 1)
            delegate: Rectangle {
                required property int index
                x: 14
                width: parent.width - 28
                height: 1
                color: Theme.line
                y: {
                    const c = parent.shownRows[index];
                    return c ? c.y + c.height : 0;
                }
            }
        }
    }
}
