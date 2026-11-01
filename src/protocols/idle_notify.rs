//! ext-idle-notify — простой: Delta (Quickshell IdleMonitor) просит сообщить,
//! когда за клавиатурой и мышью никого не было N секунд, и гасит экран или
//! блокирует его. Своя реализация, а не из Smithay: там цикл событий обязан
//! работать с тем же типом, что и Wayland, а у нас это CalloopData.
//!
//! Простой проверяется раз в секунду; точнее и не нужно.

use std::time::{Duration, Instant};

use smithay::reexports::{
    calloop::{
        timer::{TimeoutAction, Timer},
        LoopHandle,
    },
    wayland_protocols::ext::idle_notify::v1::server::{
        ext_idle_notification_v1::{self, ExtIdleNotificationV1},
        ext_idle_notifier_v1::{self, ExtIdleNotifierV1},
    },
    wayland_server::{backend::ClientId, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New},
};

use crate::{CalloopData, Shell};

const TICK: Duration = Duration::from_secs(1);

struct Note {
    resource: ExtIdleNotificationV1,
    timeout: Duration,
    /// false — считать простоем, даже если программа просит не считать (v2)
    respects_inhibitors: bool,
    since: Instant,
    idle: bool,
}

#[derive(Default)]
pub struct IdleNotifyState {
    notes: Vec<Note>,
    inhibited: bool,
}

impl IdleNotifyState {
    pub fn new(dh: &DisplayHandle, handle: &LoopHandle<'static, CalloopData>) -> Self {
        dh.create_global::<Shell, ExtIdleNotifierV1, _>(2, ());
        let timer = handle.insert_source(Timer::from_duration(TICK), |_, _, data| {
            data.state.idle_notify.tick();
            TimeoutAction::ToDuration(TICK)
        });
        if let Err(e) = timer {
            tracing::warn!("таймер простоя: {e}");
        }
        Self::default()
    }

    /// Кто-то за клавиатурой или мышью.
    pub fn activity(&mut self) {
        let now = Instant::now();
        for note in &mut self.notes {
            note.since = now;
            if std::mem::take(&mut note.idle) {
                note.resource.resumed();
            }
        }
    }

    /// Программа запретила простой или сняла запрет: отсчёт начинается заново.
    pub fn set_inhibited(&mut self, inhibited: bool) {
        if self.inhibited == inhibited {
            return;
        }
        self.inhibited = inhibited;
        let now = Instant::now();
        for note in self.notes.iter_mut().filter(|n| n.respects_inhibitors) {
            note.since = now;
            if inhibited && std::mem::take(&mut note.idle) {
                note.resource.resumed();
            }
        }
    }

    fn tick(&mut self) {
        for note in &mut self.notes {
            if !note.idle && !(self.inhibited && note.respects_inhibitors) && note.since.elapsed() >= note.timeout {
                note.idle = true;
                note.resource.idled();
            }
        }
    }
}

impl GlobalDispatch<ExtIdleNotifierV1, ()> for Shell {
    fn bind(
        _state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<ExtIdleNotifierV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ExtIdleNotifierV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        _notifier: &ExtIdleNotifierV1,
        request: ext_idle_notifier_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let (id, timeout, respects_inhibitors) = match request {
            ext_idle_notifier_v1::Request::GetIdleNotification { id, timeout, .. } => (id, timeout, true),
            ext_idle_notifier_v1::Request::GetInputIdleNotification { id, timeout, .. } => (id, timeout, false),
            _ => return,
        };
        let resource = data_init.init(id, ());
        state.idle_notify.notes.push(Note {
            resource,
            timeout: Duration::from_millis(timeout.into()),
            respects_inhibitors,
            since: Instant::now(),
            idle: false,
        });
    }
}

impl Dispatch<ExtIdleNotificationV1, ()> for Shell {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtIdleNotificationV1,
        _request: ext_idle_notification_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &ExtIdleNotificationV1, _data: &()) {
        state.idle_notify.notes.retain(|n| &n.resource != resource);
    }
}
