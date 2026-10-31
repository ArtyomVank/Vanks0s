pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.common

// История уведомлений и всплывающие карточки.
//
// items — живые объекты Notification (новые первыми). Пока уведомление в
// истории, оно «отслеживается» сервером; когда его закрывают (мы или
// приложение), Quickshell уничтожает объект, и он уходит из списка.
// popups — записи для карточек { key, n, … }: данные скопированы, чтобы
// карточка могла доиграть исчезновение и после закрытия уведомления.
Singleton {
    id: root

    property var items: []
    property var times: ({})
    property var popups: []
    property int unread: 0
    property int seq: 0
    readonly property int maxItems: 60
    readonly property int maxPopups: 3

    readonly property bool dnd: ShellState.dnd

    function iconFor(n) {
        if (!n) return "";
        const icon = n.appIcon || "";
        if (icon.startsWith("/") ) return "file://" + icon;
        if (icon.indexOf("://") !== -1) return icon;
        if (icon) return Quickshell.iconPath(icon, true);
        const e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
        return e ? Quickshell.iconPath(e.icon, true) : "";
    }
    function imageFor(n) {
        const img = n?.image || "";
        return img.startsWith("/") ? "file://" + img : img;
    }

    function add(n) {
        n.tracked = true;
        const t = Object.assign({}, times);
        t[n.id] = Date.now();
        times = t;
        const fresh = items.indexOf(n) === -1;
        let list = [n].concat(items.filter(x => x !== n));
        // старые сверх лимита закрываем как истёкшие
        while (list.length > maxItems) list.pop().expire();
        items = list;
        if (fresh) n.closed.connect(() => root.forget(n));
        if (!n.transient || n.urgency === NotificationUrgency.Critical) unread++;
        if (!dnd || n.urgency === NotificationUrgency.Critical) popup(n);
        // «Не беспокоить»: карточки нет — только тихий взгляд в острове дока
        else if (!n.transient) ShellState.island({ kind: "notify", image: iconFor(n), icon: "bell",
                                                   title: n.appName || I18n.tr("Уведомление"), text: n.summary || "" });
        publish();
    }

    function forget(n) {
        items = items.filter(x => x !== n);
        publish();
    }

    function popup(n) {
        // уже на экране (замена уведомления) — карточка сама обновится и перезапустит таймер
        if (popups.some(p => p.n === n)) return;
        seq++;
        popups = [{ key: "p" + seq, n: n }].concat(popups);
        Sounds.play(n.urgency === NotificationUrgency.Critical ? "dialog-warning" : "message-new-instant", 400);
    }
    // карточка доиграла исчезновение; временные (transient) в истории не держим
    function dropPopup(key) {
        const rec = popups.find(p => p.key === key);
        popups = popups.filter(p => p.key !== key);
        if (rec && rec.n && rec.n.transient) rec.n.expire();
    }

    function dismiss(n) { if (n) n.dismiss(); }
    function clear() {
        for (const n of items.slice()) if (n) n.dismiss();
        items = [];
        unread = 0;
        publish();
    }
    function markRead() { unread = 0; }

    // для виджета на экране блокировки
    function publish() {
        ShellState.notifications = items.slice(0, 20).map(n => ({
            id: n.id, app: n.appName, appIcon: iconFor(n), summary: n.summary, body: n.body, time: times[n.id] || Date.now()
        }));
    }

    function ago(ms) {
        const s = Math.max(0, (Date.now() - ms) / 1000);
        if (s < 60) return "сейчас";
        if (s < 3600) return Math.floor(s / 60) + " мин назад";
        if (s < 86400) return Math.floor(s / 3600) + " ч назад";
        return Qt.formatDate(new Date(ms), "d MMM");
    }
}
