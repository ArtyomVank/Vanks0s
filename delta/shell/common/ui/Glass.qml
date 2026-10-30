import QtQuick
import qs.common

// Стеклянная подложка: цвет темы с прозрачностью из настроек, тонкая рамка.
// Размытие под ней делает Hyprland (layer_rule для delta-*). В стиле
// «Жидкое стекло» поверх — светлая кромка (Sheen).
//     Glass { strong: true; radius: Theme.radius }
Rectangle {
    // strong — плотнее (меню, окна поверх обоев)
    property bool strong: false

    color: strong ? Theme.glass2 : Theme.glass
    radius: Theme.radius
    border.color: Theme.line
    border.width: 1

    Sheen { radius: parent.radius }
}
