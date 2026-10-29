import QtQuick

// Подпись виджета сверху («ПРОЦЕССОР»), как .wlabel в концепте.
//     WCaption { cm: root.cm; text: "Погода"; color: pal.c2 }
WText {
    property real cm: 1

    px: 6.5 * cm
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6 * px / 13
}
