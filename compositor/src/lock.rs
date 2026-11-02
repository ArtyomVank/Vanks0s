//! ext-session-lock — блокировка экрана. Замок рисует Delta (Quickshell
//! WlSessionLock): пока экран заблокирован, на мониторах видна только его
//! поверхность, и ввод получает только она. Окна и панели не показываются.
//!
//! Программа замка упала, не сняв блокировку, — экран остаётся закрытым
//! (так требует протокол), но новая копия замка может взять его снова
//! (как misc:allow_session_lock_restore в Hyprland): delta-shell сам
//! перезапускает оболочку.

use std::{
    collections::HashSet,
    time::{Duration, Instant},
};

use smithay::{
    delegate_session_lock,
    output::Output,
    reexports::{
        wayland_protocols::ext::session_lock::v1::server::ext_session_lock_v1::ExtSessionLockV1,
        wayland_server::{
            protocol::{wl_output::WlOutput, wl_surface::WlSurface},
            Resource,
        },
    },
    utils::{Logical, Point, SERIAL_COUNTER},
    wayland::{
        compositor::{add_pre_commit_hook, with_states, BufferAssignment, SurfaceAttributes},
        session_lock::{LockSurface, SessionLockHandler, SessionLockManagerState, SessionLocker},
    },
};

use crate::Shell;

/// Как часто просить Delta снова взять замок, пока экран закрыт без него.
const LOCK_RETRY: Duration = Duration::from_secs(2);
/// Дольше любого перехода Delta (0,9 с и ещё 0,9 с до выключения)
const XRAY_LIMIT: Duration = Duration::from_secs(4);

/// Отметка на поверхности: она была замком.
struct WasLockSurface;

/// Обход ошибки Smithay 0.7, как guard_removed_layer: замок убирают так:
/// destroy, затем пустой commit (так делает Quickshell), а проверка Smithay не
/// смотрит, снята ли роль, и отключает программу за «пустой буфер». Живому
/// замку пустой буфер тоже ничего не даст: на экране останется прежний кадр.
pub fn guard_removed_lock(surface: &WlSurface) {
    add_pre_commit_hook::<Shell, _>(surface, |_, _, surface| {
        with_states(surface, |states| {
            if states.data_map.get::<WasLockSurface>().is_some() {
                let mut attrs = states.cached_state.get::<SurfaceAttributes>();
                let pending = attrs.pending();
                if matches!(pending.buffer, Some(BufferAssignment::Removed)) {
                    pending.buffer = None;
                }
            }
        });
    });
}

#[derive(Default)]
pub enum Lock {
    #[default]
    Unlocked,
    /// просят закрыть: подтвердим, когда каждый монитор нарисует закрытый кадр
    Pending { locker: SessionLocker, drawn: HashSet<String> },
    Locked { by: ExtSessionLockV1 },
}

/// Поверхность замка на мониторе.
pub struct LockSurfaceOn {
    pub output: String,
    pub surface: LockSurface,
}

impl Shell {
    pub fn is_locked(&self) -> bool {
        !matches!(self.lock, Lock::Unlocked)
    }

    /// Переход Delta: рабочий стол виден сквозь прозрачные места замка (как
    /// misc.session_lock_xray в Hyprland). Сам выключается через XRAY_LIMIT:
    /// упавшая оболочка не должна оставить стол открытым.
    pub fn set_lock_xray(&mut self, on: bool) {
        self.lock_xray = on.then(|| Instant::now() + XRAY_LIMIT);
    }

    pub fn lock_xray_active(&self) -> bool {
        self.lock_xray.is_some_and(|until| Instant::now() < until)
    }

    /// Поверхность замка на этом мониторе, если программа её уже дала.
    pub fn lock_surface(&self, output: &Output) -> Option<&LockSurface> {
        self.lock_surfaces.iter().find(|l| l.output == output.name() && l.surface.alive()).map(|l| &l.surface)
    }

    /// Монитор нарисовал кадр. Все нарисовали закрытым — сообщаем программе:
    /// «заблокировано», содержимое экрана уже не видно.
    pub fn lock_frame_drawn(&mut self, output: &Output) {
        let Lock::Pending { drawn, .. } = &mut self.lock else { return };
        drawn.insert(output.name());
        let all = self.space.outputs().all(|o| drawn.contains(&o.name()));
        if all {
            if let Lock::Pending { locker, .. } = std::mem::take(&mut self.lock) {
                let by = locker.ext_session_lock().clone();
                locker.lock();
                tracing::info!("экран заблокирован");
                self.lock = Lock::Locked { by };
            }
        }
    }

    /// Замок упал, экран остаётся закрытым. delta-shell поднимет новую копию
    /// Delta, но та не знает, что сессия была заблокирована, поэтому просим её
    /// взять замок снова. Копии ещё нет — команда просто не сработает, повторим.
    pub fn lock_watchdog(&mut self) {
        let Lock::Locked { by } = &self.lock else { return };
        if by.is_alive() || self.lock_retry.is_some_and(|t| t.elapsed() < LOCK_RETRY) {
            return;
        }
        self.lock_retry = Some(Instant::now());
        tracing::warn!("замок упал, экран закрыт: прошу Delta взять его снова");
        self.spawn("exec qs -p \"${DELTA_SHELL_DIR:-${DELTA_DATA:-/usr/share/delta}/shell}\" ipc call lock lock >/dev/null 2>&1");
    }

    /// Поверхность замка под точкой (только при блокировке).
    pub fn lock_surface_under(&self, pos: Point<f64, Logical>) -> Option<(WlSurface, Point<f64, Logical>)> {
        let output = self.space.outputs().find(|o| self.space.output_geometry(o).is_some_and(|g| g.to_f64().contains(pos)))?;
        let geo = self.space.output_geometry(output)?;
        let surface = self.lock_surface(output)?;
        Some((surface.wl_surface().clone(), geo.loc.to_f64()))
    }

    /// Клавиатура — замку на мониторе под мышью (или любому).
    fn focus_lock(&mut self) {
        let pos = self.seat.get_pointer().map(|p| p.current_location()).unwrap_or_default();
        let target = self
            .lock_surface_under(pos)
            .map(|(s, _)| s)
            .or_else(|| self.lock_surfaces.iter().find(|l| l.surface.alive()).map(|l| l.surface.wl_surface().clone()));
        if let (Some(kb), Some(surface)) = (self.seat.get_keyboard(), target) {
            kb.set_focus(self, Some(surface.into()), SERIAL_COUNTER.next_serial());
        }
    }

    /// Новый размер монитора — замку тоже.
    pub fn resize_lock_surfaces(&mut self) {
        for l in &self.lock_surfaces {
            let Some(output) = self.space.outputs().find(|o| o.name() == l.output) else { continue };
            let Some(size) = self.space.output_geometry(output).map(|g| g.size) else { continue };
            let size = (size.w as u32, size.h as u32).into();
            if l.surface.current_state().size != Some(size) {
                l.surface.with_pending_state(|s| s.size = Some(size));
                l.surface.send_configure();
            }
        }
    }
}

impl SessionLockHandler for Shell {
    fn lock_state(&mut self) -> &mut SessionLockManagerState {
        &mut self.session_lock_state
    }

    fn lock(&mut self, confirmation: SessionLocker) {
        // уже держит живая программа — второй замок не нужен (уйдёт finished)
        let held = match &self.lock {
            Lock::Locked { by } => by.is_alive(),
            Lock::Pending { locker, .. } => locker.ext_session_lock().is_alive(),
            Lock::Unlocked => false,
        };
        if held {
            tracing::warn!("второй замок отклонён");
            return;
        }
        let restore = self.is_locked();
        self.lock_surfaces.retain(|l| l.surface.alive());
        if restore {
            // прежний замок упал, экран и так закрыт — подтверждаем сразу
            tracing::info!("замок взят заново");
            let by = confirmation.ext_session_lock().clone();
            confirmation.lock();
            self.lock = Lock::Locked { by };
        } else if self.space.outputs().next().is_none() {
            // мониторов нет — закрывать нечего
            let by = confirmation.ext_session_lock().clone();
            confirmation.lock();
            self.lock = Lock::Locked { by };
        } else {
            self.lock = Lock::Pending { locker: confirmation, drawn: HashSet::new() };
        }
        // меню и поиск больше не видят ввода
        self.clear_focus_grabs();
        if let Some(kb) = self.seat.get_keyboard() {
            kb.set_focus(self, None, SERIAL_COUNTER.next_serial());
        }
    }

    fn unlock(&mut self) {
        tracing::info!("экран разблокирован");
        self.lock = Lock::Unlocked;
        self.lock_surfaces.clear();
        self.focus_top();
    }

    fn new_surface(&mut self, surface: LockSurface, output: WlOutput) {
        let Some(output) = Output::from_resource(&output) else { return };
        with_states(surface.wl_surface(), |states| {
            states.data_map.insert_if_missing_threadsafe(|| WasLockSurface);
        });
        if let Some(size) = self.space.output_geometry(&output).map(|g| g.size) {
            surface.with_pending_state(|s| s.size = Some((size.w as u32, size.h as u32).into()));
        }
        self.lock_surfaces.retain(|l| l.output != output.name() && l.surface.alive());
        self.lock_surfaces.push(LockSurfaceOn { output: output.name(), surface });
        // configure пришлёт Smithay; фокус — когда поверхность появится
        self.focus_lock();
    }
}
delegate_session_lock!(Shell);

impl Shell {
    /// После commit поверхности замка: первый кадр — даём ей клавиатуру.
    pub fn lock_commit(&mut self, surface: &WlSurface) -> bool {
        if !self.lock_surfaces.iter().any(|l| l.surface.wl_surface() == surface) {
            return false;
        }
        let focused = self.seat.get_keyboard().and_then(|k| k.current_focus());
        if focused.is_none() {
            self.focus_lock();
        }
        true
    }
}
