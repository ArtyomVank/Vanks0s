pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// VPN через NetworkManager: подключения типов vpn и wireguard можно включать
// и выключать (nmcli connection up/down). Туннели сторонних программ
// (AmneziaVPN, Happ, incy… — NetworkManager видит их как tun) только
// показываются: выключает их сама программа.
//
//   Vpn.connections   [{ name, uuid, type, active, own }] — own: можно переключать
//   Vpn.active        включён хоть один VPN
//   Vpn.activeName    имя включённого (первого)
//   Vpn.toggle(uuid)  включить или выключить своё подключение
//   Vpn.watch         пока true — список обновляется раз в 4 секунды
//
// Во вложенной сессии и в пробном режиме переключение только рисуется.
Singleton {
    id: root

    readonly property bool dryRun: (Quickshell.env("DELTA_NESTED") || "") !== "" || Quickshell.env("DELTA_DRY_RUN") === "1"
    property var connections: []
    property bool watch: false
    property string busy: ""
    // пробный режим: что «включено» понарошку
    property var fake: ({})

    readonly property var own: connections.filter(c => c.own)
    readonly property bool active: connections.some(c => c.active)
    readonly property string activeName: (connections.find(c => c.active) || {}).name || ""
    readonly property bool available: connections.length > 0

    function refresh() { if (!list.running) list.running = true; }

    function toggle(uuid) {
        const c = connections.find(x => x.uuid === uuid);
        if (!c || !c.own || busy) return;
        if (dryRun) {
            const f = Object.assign({}, fake);
            f[uuid] = !c.active;
            fake = f;
            console.log("DRY: nmcli connection " + (c.active ? "down" : "up") + " uuid " + uuid);
            parse(lastText);
            return;
        }
        busy = uuid;
        sw.command = ["nmcli", "connection", c.active ? "down" : "up", "uuid", uuid];
        sw.running = true;
    }

    // nmcli -t экранирует «:» внутри полей как «\:»
    function split(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (ch === ":") { out.push(cur); cur = ""; continue; }
            cur += ch;
        }
        out.push(cur);
        return out;
    }
    property string lastText: ""
    function parse(text) {
        lastText = text;
        const out = [];
        for (const line of text.split("\n")) {
            if (!line) continue;
            const f = split(line);
            if (f.length < 4) continue;
            const type = f[2];
            const own = type === "vpn" || type === "wireguard";
            if (!own && type !== "tun") continue;
            // чужой tun показываем, только пока он поднят
            let on = f[3] === "yes";
            if (!own && !on) continue;
            if (dryRun && own && root.fake[f[1]] !== undefined) on = root.fake[f[1]];
            out.push({ name: f[0], uuid: f[1], type: type, active: on, own: own });
        }
        // свои — первыми, включённые — выше
        out.sort((a, b) => (b.own - a.own) || (b.active - a.active) || a.name.localeCompare(b.name));
        connections = out;
    }

    Process {
        id: list
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Process {
        id: sw
        stderr: StdioCollector { id: swErr }
        onExited: code => {
            if (code !== 0) console.warn("[delta] vpn: " + swErr.text.trim());
            root.busy = "";
            root.refresh();
        }
    }
    Timer {
        interval: 4000
        repeat: true
        running: root.watch
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
