// Основа — пример smallvil из Smithay v0.7.0 (MIT, © Smithay contributors), см. NOTICE.

use std::time::{Duration, Instant};

use super::snap::Zone;
use crate::{
    workspaces::{self, Mode},
    Shell,
};
use smithay::{
    desktop::Window,
    input::pointer::{
        AxisFrame, ButtonEvent, GestureHoldBeginEvent, GestureHoldEndEvent, GesturePinchBeginEvent,
        GesturePinchEndEvent, GesturePinchUpdateEvent, GestureSwipeBeginEvent, GestureSwipeEndEvent,
        GestureSwipeUpdateEvent, GrabStartData as PointerGrabStartData, MotionEvent, PointerGrab,
        PointerInnerHandle, RelativeMotionEvent,
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::{Logical, Point, Rectangle, Size},
};

/// Сдвиг, после которого щелчок становится перетаскиванием.
const MOVE_THRESHOLD: f64 = 3.0;
/// Развёрнутое окно отрывается от места не сразу, как в GNOME.
const UNMAXIMIZE_THRESHOLD: f64 = 14.0;
/// Как часто писать состояние для Delta: 250 раз в секунду хватает и на 240 Гц.
const WRITE_EVERY: Duration = Duration::from_millis(4);

pub struct MoveSurfaceGrab {
    start_data: PointerGrabStartData<Shell>,
    window: Window,
    initial_window_location: Point<i32, Logical>,
    moving: bool,
    /// где держат окно, от его левого верхнего угла
    grip: Point<i32, Logical>,
    zone: Option<Zone>,
    monitor: String,
    last_write: Option<Instant>,
}

impl MoveSurfaceGrab {
    pub fn new(start_data: PointerGrabStartData<Shell>, window: Window, initial_window_location: Point<i32, Logical>) -> Self {
        let grip = (start_data.location - initial_window_location.to_f64()).to_i32_round();
        Self { start_data, window, initial_window_location, moving: false, grip, zone: None, monitor: String::new(), last_write: None }
    }

    /// Окно сдвинули: прежний размер — если оно развёрнуто или прижато к краю.
    /// false — пока рано или нельзя. Мышь заперта на время захвата, поэтому
    /// режим меняем уже после этого вызова (insert_idle).
    fn begin(&mut self, data: &mut Shell, delta: Point<f64, Logical>) -> bool {
        let size = self.window.geometry().size;
        let (mode, snapped, restore) = {
            let d = workspaces::data(&self.window);
            (d.mode, d.snapped, d.restore)
        };
        let old = match mode {
            Mode::Fullscreen => return false,
            Mode::Maximized => {
                if delta.x.abs() + delta.y.abs() < UNMAXIMIZE_THRESHOLD {
                    return false;
                }
                let window = self.window.clone();
                data.loop_handle.insert_idle(move |d| d.state.set_mode(&window, Mode::Maximized));
                Some(restore.map(|r| r.size).unwrap_or(Size::from(((size.w * 3) / 5, (size.h * 7) / 10))))
            }
            Mode::Normal => {
                if let Some(old) = snapped {
                    workspaces::data(&self.window).snapped = None;
                    data.resize_window(&self.window, old);
                }
                snapped
            }
        };
        // окно стало другого размера: курсор держит ту же долю его ширины
        if let Some(old) = old {
            self.grip.x = self.grip.x * old.w / size.w.max(1);
            self.grip.y = if mode == Mode::Maximized { self.grip.y } else { self.grip.y * old.h / size.h.max(1) };
            self.initial_window_location = (self.start_data.location - self.grip.to_f64()).to_i32_round();
            // отпустят сразу — окно останется под курсором, а не на старом месте
            if mode == Mode::Maximized {
                workspaces::data(&self.window).restore = Some(Rectangle::new(self.initial_window_location, old));
            }
        }
        true
    }
}

impl PointerGrab<Shell> for MoveSurfaceGrab {
    fn motion(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        _focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &MotionEvent,
    ) {
        // While the grab is active, no client has pointer focus
        handle.motion(data, None, event);

        let delta = event.location - self.start_data.location;
        let first = !self.moving;
        if first {
            if delta.x.abs() + delta.y.abs() < MOVE_THRESHOLD || !self.begin(data, delta) {
                return;
            }
            self.moving = true;
        }
        let new_location = (self.initial_window_location.to_f64() + delta).to_i32_round();
        data.move_window(&self.window, new_location);

        let (output, zone) = data.snap_zone(event.location);
        if let Some(output) = output {
            self.monitor = output.name();
        }
        let zone_changed = zone != self.zone;
        self.zone = zone;
        let due = self.last_write.is_none_or(|t| t.elapsed() >= WRITE_EVERY);
        if first || zone_changed || due {
            self.last_write = Some(Instant::now());
            let state = if first { "begin" } else { "move" };
            data.write_drag(state, &self.window, &self.monitor, self.grip, self.zone.as_ref());
        }
    }

    fn relative_motion(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &RelativeMotionEvent,
    ) {
        handle.relative_motion(data, focus, event);
    }

    fn button(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &ButtonEvent,
    ) {
        handle.button(data, event);

        // The button is a button code as defined in the
        // Linux kernel's linux/input-event-codes.h header file, e.g. BTN_LEFT.
        const BTN_LEFT: u32 = 0x110;

        if !handle.current_pressed().contains(&BTN_LEFT) {
            // No more buttons are pressed, release the grab.
            handle.unset_grab(self, data, event.serial, event.time, true);
            if self.moving {
                let (window, monitor, grip, zone) = (self.window.clone(), self.monitor.clone(), self.grip, self.zone.take());
                data.loop_handle.insert_idle(move |d| d.state.finish_drag(&window, &monitor, grip, zone));
            }
        }
    }

    fn axis(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        details: AxisFrame,
    ) {
        handle.axis(data, details)
    }

    fn frame(&mut self, data: &mut Shell, handle: &mut PointerInnerHandle<'_, Shell>) {
        handle.frame(data);
    }

    fn gesture_swipe_begin(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GestureSwipeBeginEvent,
    ) {
        handle.gesture_swipe_begin(data, event)
    }

    fn gesture_swipe_update(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GestureSwipeUpdateEvent,
    ) {
        handle.gesture_swipe_update(data, event)
    }

    fn gesture_swipe_end(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GestureSwipeEndEvent,
    ) {
        handle.gesture_swipe_end(data, event)
    }

    fn gesture_pinch_begin(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GesturePinchBeginEvent,
    ) {
        handle.gesture_pinch_begin(data, event)
    }

    fn gesture_pinch_update(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GesturePinchUpdateEvent,
    ) {
        handle.gesture_pinch_update(data, event)
    }

    fn gesture_pinch_end(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GesturePinchEndEvent,
    ) {
        handle.gesture_pinch_end(data, event)
    }

    fn gesture_hold_begin(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GestureHoldBeginEvent,
    ) {
        handle.gesture_hold_begin(data, event)
    }

    fn gesture_hold_end(
        &mut self,
        data: &mut Shell,
        handle: &mut PointerInnerHandle<'_, Shell>,
        event: &GestureHoldEndEvent,
    ) {
        handle.gesture_hold_end(data, event)
    }

    fn start_data(&self) -> &PointerGrabStartData<Shell> {
        &self.start_data
    }

    fn unset(&mut self, _data: &mut Shell) {}
}
