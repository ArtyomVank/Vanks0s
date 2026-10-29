pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Корень модуля сворачивания: слой «джинна» на каждом мониторе и IPC.
//   delta-shell ipc call minimize active | toggle <адрес>
Scope {
    Variants {
        model: Quickshell.screens
        delegate: Genie {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "minimize"

        function active(): void { Minimizer.minimizeActive(); }
        function toggle(address: string): void {
            const h = Minimizer.byAddress(address);
            if (h) Minimizer.toggle(h);
        }
        function list(): string {
            return JSON.stringify(Hyprland.toplevels.values.filter(h => Minimizer.isMinimized(h))
                .map(h => ({ address: Minimizer.norm(h.address), app: h.wayland?.appId ?? "", title: h.title })));
        }
    }
}
