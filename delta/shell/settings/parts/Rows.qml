import QtQuick
import QtQuick.Layouts
import qs.common

// Строки из Repeater внутри Card. Card рисует разделители между своими
// детьми по порядку, а Repeater и скрытые строки — тоже дети (нулевой высоты),
// поэтому линии съезжают. Rows — один ребёнок для Card, а линии рисует сам,
// только между видимыми строками.
//     Card { Rows { Repeater { model: …; delegate: SettingRow { … } } } SettingRow { … } }
// (Кандидат в common/ui: та же логика пригодилась бы самой Card.)
Item {
    id: root

    default property alias rows: box.data

    Layout.fillWidth: true
    implicitHeight: box.implicitHeight

    readonly property var shownRows: {
        const out = [];
        for (let i = 0; i < box.children.length; i++) {
            const c = box.children[i];
            if (c.visible && c.height > 0) out.push(c);
        }
        // строки Repeater идут в children после статичных — порядок по y
        return out.sort((a, b) => a.y - b.y);
    }

    ColumnLayout {
        id: box
        anchors { left: parent.left; right: parent.right }
        spacing: 0
    }

    Repeater {
        model: Math.max(0, root.shownRows.length - 1)
        delegate: Rectangle {
            required property int index
            x: 14
            width: root.width - 28
            height: 1
            color: Theme.line
            y: {
                const c = root.shownRows[index];
                return c ? c.y + c.height : 0;
            }
        }
    }
}
