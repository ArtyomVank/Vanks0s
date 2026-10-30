import QtQuick
import Quickshell
import Quickshell.Hyprland

// Глобальные сочетания Delta. Hyprland отправляет их как "delta:<имя>"
// (см. hl.dsp.global в hyprland.lua). Модули подписываются на сигналы:
//     Shortcuts { onLauncher: launcher.toggle() }
Scope {
    id: root

    signal launcher()
    signal wallpapers()
    signal notifications()
    signal widgets()
    signal settings()
    signal lock()
    signal power()
    signal minimize()
    signal fullscreen()
    signal screenshot()
    signal volume(string action)
    signal brightness(string action)

    component Key: GlobalShortcut { appid: "delta" }

    Key { name: "launcher";        description: "Окно приложений";        onPressed: root.launcher() }
    // одиночный Super — бинд на отпускание, а global в нём шлёт «отпущено»
    Key { name: "launcher-key";    description: "Окно приложений (Super)"; onReleased: root.launcher() }
    Key { name: "wallpapers";      description: "Выбор обоев";            onPressed: root.wallpapers() }
    Key { name: "notifications";   description: "Центр уведомлений";      onPressed: root.notifications() }
    Key { name: "widgets";         description: "Редактор виджетов";      onPressed: root.widgets() }
    Key { name: "settings";        description: "Настройки";              onPressed: root.settings() }
    Key { name: "lock";            description: "Заблокировать экран";    onPressed: root.lock() }
    Key { name: "power";           description: "Меню питания";           onPressed: root.power() }
    Key { name: "minimize";        description: "Свернуть окно";          onPressed: root.minimize() }
    Key { name: "fullscreen";      description: "Развернуть окно";        onPressed: root.fullscreen() }
    Key { name: "screenshot";      description: "Снимок экрана";          onPressed: root.screenshot() }
    Key { name: "volume-up";       description: "Громче";                 onPressed: root.volume("up") }
    Key { name: "volume-down";     description: "Тише";                   onPressed: root.volume("down") }
    Key { name: "volume-mute";     description: "Выключить звук";         onPressed: root.volume("mute") }
    Key { name: "mic-mute";        description: "Выключить микрофон";     onPressed: root.volume("mic") }
    Key { name: "brightness-up";   description: "Ярче";                   onPressed: root.brightness("up") }
    Key { name: "brightness-down"; description: "Темнее";                 onPressed: root.brightness("down") }
}
