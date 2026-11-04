use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Event, GestureBeginEvent, GestureEndEvent,
        GesturePinchUpdateEvent as _, GestureSwipeUpdateEvent as _, InputBackend, InputEvent, KeyState,
        KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent, PointerMotionEvent,
    },
    input::{
        keyboard::{FilterResult, Keysym, ModifiersState},
        pointer::{
            AxisFrame, ButtonEvent, Focus, GestureHoldBeginEvent, GestureHoldEndEvent, GesturePinchBeginEvent,
            GesturePinchEndEvent, GesturePinchUpdateEvent, GestureSwipeBeginEvent, GestureSwipeEndEvent,
            GestureSwipeUpdateEvent, GrabStartData, MotionEvent, RelativeMotionEvent,
        },
    },
    utils::{Logical, Point, Rectangle, SERIAL_COUNTER},
    wayland::pointer_constraints::{with_pointer_constraint, PointerConstraint},
};

use smithay::wayland::shell::wlr_layer::Layer;

use crate::{
    config,
    grabs::{resize_grab::ResizeEdge, MoveSurfaceGrab, ResizeSurfaceGrab},
    state::Shell,
};

/// левая кнопка мыши (linux/input-event-codes.h)
const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
/// смахивание тремя пальцами на столько точек — соседний стол (как hl.gesture в Delta)
const SWIPE_DISTANCE: f64 = 120.0;

/// Сочетания оболочки — те же, что у Delta в hyprland.lua, чтобы руки не
/// переучивать. Ищутся по латинской клавише, так что работают и в русской
/// раскладке (Super+Й — это Super+Q). «Глобальные» уходят в Delta
/// (hyprland_global_shortcuts_v1), остальное делает оболочка.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    Terminal,
    CloseWindow,
    Quit,
    /// Ctrl+Alt+F1…F12 — другая консоль (только в настоящей сессии)
    Vt(i32),
    /// Ctrl+Alt+Shift+H — выключить HDR, если монитор с ним погас
    HdrOff,
    /// сочетание Delta: «delta:lock», «delta:volume-up»…
    Global(&'static str),
    Exec(&'static str),
    OpenHome,
    Workspace(i32),
    MoveToWorkspace(i32),
}

impl Action {
    /// Что можно при заблокированном экране. Выход из сессии — нельзя: это был
    /// бы обход замка, если сессию запустили из консоли.
    fn allowed_when_locked(&self) -> bool {
        match self {
            Action::Vt(_) | Action::Exec(_) | Action::HdrOff => true,
            Action::Global(name) => matches!(
                *name,
                "delta:volume-up"
                    | "delta:volume-down"
                    | "delta:volume-mute"
                    | "delta:mic-mute"
                    | "delta:brightness-up"
                    | "delta:brightness-down"
            ),
            _ => false,
        }
    }
}

/// sym — латинская клавиша (для сочетаний), modified — что даёт xkb с учётом
/// модификаторов (для Ctrl+Alt+Fn это XF86Switch_VT_n).
fn binding(mods: &ModifiersState, sym: Keysym, modified: Keysym) -> Option<Action> {
    let vt = modified.raw().wrapping_sub(Keysym::XF86_Switch_VT_1.raw());
    if vt < 12 {
        return Some(Action::Vt(vt as i32 + 1));
    }
    // аварийный выход, если оболочка «зависла» для программ: Ctrl+Alt+Backspace
    if mods.ctrl && mods.alt && sym == Keysym::BackSpace {
        return Some(Action::Quit);
    }
    if mods.ctrl && mods.alt && mods.shift && (sym == Keysym::h || sym == Keysym::H) {
        return Some(Action::HdrOff);
    }
    // мультимедийные клавиши — без Super, и на экране блокировки тоже
    let media = match sym {
        Keysym::XF86_AudioRaiseVolume => Some(Action::Global("delta:volume-up")),
        Keysym::XF86_AudioLowerVolume => Some(Action::Global("delta:volume-down")),
        Keysym::XF86_AudioMute => Some(Action::Global("delta:volume-mute")),
        Keysym::XF86_AudioMicMute => Some(Action::Global("delta:mic-mute")),
        Keysym::XF86_MonBrightnessUp => Some(Action::Global("delta:brightness-up")),
        Keysym::XF86_MonBrightnessDown => Some(Action::Global("delta:brightness-down")),
        Keysym::XF86_AudioNext => Some(Action::Exec("playerctl next")),
        Keysym::XF86_AudioPrev => Some(Action::Exec("playerctl previous")),
        Keysym::XF86_AudioPlay | Keysym::XF86_AudioPause => Some(Action::Exec("playerctl play-pause")),
        Keysym::Print => Some(Action::Global("delta:screenshot")),
        _ => None,
    };
    if media.is_some() {
        return media;
    }
    if !mods.logo {
        return None;
    }
    // Super+1…9, 0 — столы 1…10; с Shift — перенести туда окно
    let digit = match sym.raw() {
        r if (Keysym::_1.raw()..=Keysym::_9.raw()).contains(&r) => Some((r - Keysym::_1.raw()) as i32 + 1),
        r if r == Keysym::_0.raw() => Some(10),
        _ => None,
    };
    if let Some(n) = digit {
        return Some(if mods.shift { Action::MoveToWorkspace(n) } else { Action::Workspace(n) });
    }
    match sym {
        Keysym::Return | Keysym::KP_Enter => Some(Action::Terminal),
        Keysym::q | Keysym::Q => Some(Action::CloseWindow),
        Keysym::e | Keysym::E if mods.shift => Some(Action::Quit),
        Keysym::e | Keysym::E => Some(Action::OpenHome),
        Keysym::s | Keysym::S => Some(Action::Global("delta:wallpapers")),
        Keysym::n | Keysym::N => Some(Action::Global("delta:notifications")),
        Keysym::w | Keysym::W => Some(Action::Global("delta:widgets")),
        Keysym::i | Keysym::I => Some(Action::Global("delta:settings")),
        Keysym::l | Keysym::L => Some(Action::Global("delta:lock")),
        Keysym::Escape => Some(Action::Global("delta:power")),
        Keysym::h | Keysym::H => Some(Action::Global("delta:minimize")),
        Keysym::f | Keysym::F => Some(Action::Global("delta:fullscreen")),
        _ => None,
    }
}

fn is_super(sym: Keysym) -> bool {
    sym == Keysym::Super_L || sym == Keysym::Super_R
}

impl Shell {
    pub fn process_input_event<I: InputBackend>(&mut self, event: InputEvent<I>) {
        // любое действие за клавиатурой или мышью — не простой (IdleMonitor Delta)
        if matches!(
            event,
            InputEvent::Keyboard { .. }
                | InputEvent::PointerMotion { .. }
                | InputEvent::PointerMotionAbsolute { .. }
                | InputEvent::PointerButton { .. }
                | InputEvent::PointerAxis { .. }
        ) {
            self.idle_notify.activity();
        }
        match event {
            InputEvent::Keyboard { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let time = Event::time_msec(&event);
                let pressed = event.state() == KeyState::Pressed;
                let locked = self.is_locked();
                let action = self.seat.get_keyboard().unwrap().input::<Action, _>(
                    self,
                    event.key_code(),
                    event.state(),
                    serial,
                    time,
                    |shell, mods, handle| {
                        let sym = handle.raw_latin_sym_or_raw_current_sym().unwrap_or(Keysym::NoSymbol);
                        // экран заблокирован: только консоли и громкость, остальное — замку
                        if locked {
                            shell.super_alone = false;
                            return match binding(mods, sym, handle.modified_sym()) {
                                Some(a) if pressed && a.allowed_when_locked() => FilterResult::Intercept(a),
                                _ => FilterResult::Forward,
                            };
                        }
                        // Super сам по себе (нажали и отпустили) — меню приложений Delta
                        if is_super(handle.modified_sym()) || is_super(sym) {
                            if pressed {
                                shell.super_alone = true;
                            } else if std::mem::take(&mut shell.super_alone) {
                                return FilterResult::Intercept(Action::Global("delta:launcher-key"));
                            }
                            return FilterResult::Forward;
                        }
                        if pressed {
                            shell.super_alone = false;
                        }
                        match binding(mods, sym, handle.modified_sym()) {
                            // нажатие — действие, отпускание той же клавиши программе тоже не нужно
                            Some(a) if pressed => FilterResult::Intercept(a),
                            _ => FilterResult::Forward,
                        }
                    },
                );
                if let Some(action) = action {
                    self.run_action(action);
                }
                // Alt+Shift сменил раскладку — Delta покажет новую
                self.layout_maybe_changed();
            }
            // мышь и тачпад в настоящей сессии: сдвиг, а не точка
            InputEvent::PointerMotion { event, .. } => {
                self.pointer_motion_relative(event.delta(), event.delta_unaccel(), event.time(), event.time_msec());
            }
            // окно отладки, планшет, виртуальная машина: точка на экране
            InputEvent::PointerMotionAbsolute { event, .. } => {
                let Some(output) = self.space.outputs().next() else { return };
                let output_geo = self.space.output_geometry(output).unwrap();
                let pos = event.position_transformed(output_geo.size) + output_geo.loc.to_f64();
                self.pointer_moved(pos, event.time_msec());
            }
            InputEvent::PointerButton { event, .. } => {
                let pointer = self.seat.get_pointer().unwrap();
                let keyboard = self.seat.get_keyboard().unwrap();
                let serial = SERIAL_COUNTER.next_serial();
                let button = event.button_code();
                let button_state = event.state();

                if button_state == ButtonState::Pressed {
                    self.super_alone = false;
                }
                let location = pointer.current_location();
                // экран заблокирован: щелчок и клавиатура — только замку
                if self.is_locked() {
                    if button_state == ButtonState::Pressed {
                        if let Some((surface, _)) = self.lock_surface_under(location) {
                            keyboard.set_focus(self, Some(surface.into()), serial);
                        }
                    }
                    pointer.button(self, &ButtonEvent { button, state: button_state, serial, time: event.time_msec() });
                    pointer.frame(self);
                    return;
                }
                // щелчок мимо меню Delta с захватом — меню закрывается
                if button_state == ButtonState::Pressed {
                    let under = self.surface_under(location).map(|(s, _)| s);
                    self.focus_grab_click(under.as_ref());
                }
                let top_layer = self.layer_surface_under(location, &[Layer::Overlay, Layer::Top]);
                let bottom_layer = || self.layer_surface_under(location, &[Layer::Bottom, Layer::Background]);
                if button_state == ButtonState::Pressed && !pointer.is_grabbed() && top_layer.is_some() {
                    // щелчок по панели Delta: клавиатура — ей, если она её берёт
                    let (_, _, layer) = top_layer.unwrap();
                    if layer.can_receive_keyboard_focus() {
                        keyboard.set_focus(self, Some(layer.wl_surface().clone().into()), serial);
                    }
                } else if button_state == ButtonState::Pressed && !pointer.is_grabbed() {
                    let under = self.space.element_under(location).map(|(w, _)| w.clone());
                    // меню X11 (Steam и другие): фокус остаётся у окна меню. Иначе окно
                    // теряет фокус, закрывает меню, и щелчок по пункту пропадает
                    let x11_menu = under.as_ref().is_some_and(|w| w.x11_surface().is_some_and(|x| x.is_override_redirect()));
                    if x11_menu {
                    } else if let Some(window) = under {
                        // щелчок по окну: оно впереди всех и получает клавиатуру
                        self.focus_window(&window, serial);
                        // Super + левая кнопка: тащим окно за любое место
                        if button == BTN_LEFT && keyboard.modifier_state().logo {
                            let initial_window_location = self.space.element_location(&window).unwrap();
                            let start_data = GrabStartData { focus: None, button, location };
                            let grab = MoveSurfaceGrab::new(start_data, window, initial_window_location);
                            pointer.set_grab(self, grab, serial, Focus::Clear);
                            return;
                        }
                        // Super + правая кнопка: размер за ближайший угол
                        if button == BTN_RIGHT && keyboard.modifier_state().logo {
                            let loc = self.space.element_location(&window).unwrap();
                            let size = window.geometry().size;
                            let mut edges = ResizeEdge::empty();
                            edges |= if location.x < loc.x as f64 + size.w as f64 / 2.0 { ResizeEdge::LEFT } else { ResizeEdge::RIGHT };
                            edges |= if location.y < loc.y as f64 + size.h as f64 / 2.0 { ResizeEdge::TOP } else { ResizeEdge::BOTTOM };
                            let start_data = GrabStartData { focus: None, button, location };
                            let grab = ResizeSurfaceGrab::start(start_data, window, edges, Rectangle::new(loc, size));
                            pointer.set_grab(self, grab, serial, Focus::Clear);
                            return;
                        }
                    } else if let Some((_, _, layer)) = bottom_layer().filter(|(_, _, l)| l.can_receive_keyboard_focus()) {
                        // виджеты Delta на столе
                        keyboard.set_focus(self, Some(layer.wl_surface().clone().into()), serial);
                    } else {
                        // щелчок по пустому столу — ни одно окно не активно
                        self.space.elements().for_each(|w| {
                            w.set_activated(false);
                            if let Some(t) = w.toplevel() {
                                t.send_pending_configure();
                            }
                        });
                        keyboard.set_focus(self, None, serial);
                    }
                }

                pointer.button(self, &ButtonEvent { button, state: button_state, serial, time: event.time_msec() });
                pointer.frame(self);
            }
            InputEvent::PointerAxis { event, .. } => {
                // Super + колесо — соседний занятый стол (как в Delta)
                let logo = !self.is_locked() && self.seat.get_keyboard().map(|k| k.modifier_state().logo).unwrap_or(false);
                if logo {
                    if let Some(v) = event.amount_v120(Axis::Vertical).or(event.amount(Axis::Vertical)).filter(|v| *v != 0.0) {
                        self.super_alone = false;
                        if let Some(id) = self.resolve_ws(if v > 0.0 { "e+1" } else { "e-1" }) {
                            self.switch_workspace(id);
                        }
                        return;
                    }
                }
                let source = event.source();
                let horizontal = event
                    .amount(Axis::Horizontal)
                    .unwrap_or_else(|| event.amount_v120(Axis::Horizontal).unwrap_or(0.0) * 15.0 / 120.);
                let vertical = event
                    .amount(Axis::Vertical)
                    .unwrap_or_else(|| event.amount_v120(Axis::Vertical).unwrap_or(0.0) * 15.0 / 120.);

                let mut frame = AxisFrame::new(event.time_msec()).source(source);
                if horizontal != 0.0 {
                    frame = frame.value(Axis::Horizontal, horizontal);
                    if let Some(d) = event.amount_v120(Axis::Horizontal) {
                        frame = frame.v120(Axis::Horizontal, d as i32);
                    }
                }
                if vertical != 0.0 {
                    frame = frame.value(Axis::Vertical, vertical);
                    if let Some(d) = event.amount_v120(Axis::Vertical) {
                        frame = frame.v120(Axis::Vertical, d as i32);
                    }
                }
                if source == AxisSource::Finger {
                    if event.amount(Axis::Horizontal) == Some(0.0) {
                        frame = frame.stop(Axis::Horizontal);
                    }
                    if event.amount(Axis::Vertical) == Some(0.0) {
                        frame = frame.stop(Axis::Vertical);
                    }
                }
                let pointer = self.seat.get_pointer().unwrap();
                pointer.axis(self, frame);
                pointer.frame(self);
            }
            InputEvent::GestureSwipeBegin { event, .. } => {
                // три пальца — столы, остальное программе
                if event.fingers() == 3 && !self.is_locked() {
                    self.swipe = Some(0.0);
                    return;
                }
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_swipe_begin(self, &GestureSwipeBeginEvent { serial, time: event.time_msec(), fingers: event.fingers() });
            }
            InputEvent::GestureSwipeUpdate { event, .. } => {
                if let Some(dx) = self.swipe.as_mut() {
                    *dx += event.delta().x;
                    return;
                }
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_swipe_update(self, &GestureSwipeUpdateEvent { time: event.time_msec(), delta: event.delta() });
            }
            InputEvent::GestureSwipeEnd { event, .. } => {
                if let Some(dx) = self.swipe.take() {
                    if !event.cancelled() && dx.abs() >= SWIPE_DISTANCE {
                        // пальцы влево — следующий стол, как перелистывание
                        if let Some(id) = self.resolve_ws(if dx < 0.0 { "e+1" } else { "e-1" }) {
                            self.switch_workspace(id);
                        }
                    }
                    return;
                }
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_swipe_end(self, &GestureSwipeEndEvent { serial, time: event.time_msec(), cancelled: event.cancelled() });
            }
            InputEvent::GesturePinchBegin { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_pinch_begin(self, &GesturePinchBeginEvent { serial, time: event.time_msec(), fingers: event.fingers() });
            }
            InputEvent::GesturePinchUpdate { event, .. } => {
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_pinch_update(
                    self,
                    &GesturePinchUpdateEvent { time: event.time_msec(), delta: event.delta(), scale: event.scale(), rotation: event.rotation() },
                );
            }
            InputEvent::GesturePinchEnd { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_pinch_end(self, &GesturePinchEndEvent { serial, time: event.time_msec(), cancelled: event.cancelled() });
            }
            InputEvent::GestureHoldBegin { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_hold_begin(self, &GestureHoldBeginEvent { serial, time: event.time_msec(), fingers: event.fingers() });
            }
            InputEvent::GestureHoldEnd { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                pointer.gesture_hold_end(self, &GestureHoldEndEvent { serial, time: event.time_msec(), cancelled: event.cancelled() });
            }
            _ => {}
        }
    }

    /// Сдвиг мыши: сначала программе как есть (игры с захватом смотрят только
    /// на него), затем курсор — если его не держит захват.
    fn pointer_motion_relative(&mut self, delta: Point<f64, Logical>, delta_unaccel: Point<f64, Logical>, utime: u64, time: u32) {
        let pointer = self.seat.get_pointer().unwrap();
        let pos = pointer.current_location();
        let under = self.surface_under(pos);

        let mut locked = false;
        let mut confined = None;
        if let Some((surface, origin)) = &under {
            with_pointer_constraint(surface, &pointer, |c| {
                let Some(c) = c.filter(|c| c.is_active()) else { return };
                // курсор вышел из области захвата — захват не действует
                if !c.region().is_none_or(|r| r.contains((pos - *origin).to_i32_round())) {
                    return;
                }
                match &*c {
                    PointerConstraint::Locked(_) => locked = true,
                    PointerConstraint::Confined(_) => confined = Some((surface.clone(), *origin, c.region().cloned())),
                }
            });
        }

        pointer.relative_motion(self, under, &RelativeMotionEvent { delta, delta_unaccel, utime });
        if locked {
            pointer.frame(self);
            return;
        }

        let new = self.clamp_to_outputs(pos + delta);
        if let Some((surface, origin, region)) = confined {
            // курсор остаётся внутри области: шаг наружу не делаем
            let inside = self.surface_under(new).is_some_and(|(s, _)| s == surface)
                && region.is_none_or(|r| r.contains((new - origin).to_i32_round()));
            if !inside {
                pointer.frame(self);
                return;
            }
        }
        self.pointer_moved(new, time);
    }

    fn pointer_moved(&mut self, pos: Point<f64, Logical>, time: u32) {
        let serial = SERIAL_COUNTER.next_serial();
        let pointer = self.seat.get_pointer().unwrap();
        let under = self.surface_under(pos);
        pointer.motion(self, under.clone(), &MotionEvent { location: pos, serial, time });
        pointer.frame(self);

        // курсор вошёл в область захвата — захват начинает действовать
        if let Some((surface, origin)) = under {
            with_pointer_constraint(&surface, &pointer, |c| {
                if let Some(c) = c.filter(|c| !c.is_active()) {
                    if c.region().is_none_or(|r| r.contains((pos - origin).to_i32_round())) {
                        c.activate();
                    }
                }
            });
        }
    }

    fn run_action(&mut self, action: Action) {
        tracing::debug!(?action, "сочетание");
        match action {
            Action::Global(name) => {
                self.trigger_global(name, true);
                self.trigger_global(name, false);
            }
            Action::Exec(cmd) => self.spawn(cmd),
            Action::OpenHome => self.spawn("xdg-open \"$HOME\""),
            Action::Workspace(n) => self.switch_workspace(n),
            Action::MoveToWorkspace(n) => {
                if let Some(w) = self.focused_window() {
                    self.move_to_workspace(&w, n, true);
                }
            }
            Action::Terminal => self.spawn(&config::terminal()),
            Action::CloseWindow => {
                if let Some(w) = self.focused_window() {
                    crate::workspaces::close(&w);
                }
            }
            Action::Quit => self.loop_signal.stop(),
            Action::Vt(vt) => self.change_vt(vt),
            Action::HdrOff => self.hdr_emergency_off(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hdr_off_chord() {
        let mods = ModifiersState { ctrl: true, alt: true, shift: true, ..Default::default() };
        assert!(matches!(binding(&mods, Keysym::h, Keysym::H), Some(Action::HdrOff)));
        assert!(Action::HdrOff.allowed_when_locked());
    }
}
