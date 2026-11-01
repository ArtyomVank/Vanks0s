use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Event, InputBackend, InputEvent, KeyState,
        KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent,
    },
    input::{
        keyboard::{FilterResult, Keysym, ModifiersState},
        pointer::{AxisFrame, ButtonEvent, Focus, GrabStartData, MotionEvent},
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::SERIAL_COUNTER,
};

use crate::{config, grabs::MoveSurfaceGrab, state::Shell};

/// левая кнопка мыши (linux/input-event-codes.h)
const BTN_LEFT: u32 = 0x110;

/// Сочетания оболочки. Ищутся по латинской клавише, так что работают и в
/// русской раскладке (Super+Й — это Super+Q).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Terminal,
    CloseWindow,
    Quit,
}

fn binding(mods: &ModifiersState, sym: Keysym) -> Option<Action> {
    if !mods.logo {
        return None;
    }
    match sym {
        Keysym::Return | Keysym::KP_Enter => Some(Action::Terminal),
        Keysym::q | Keysym::Q => Some(Action::CloseWindow),
        Keysym::e | Keysym::E if mods.shift => Some(Action::Quit),
        _ => None,
    }
}

impl Shell {
    pub fn process_input_event<I: InputBackend>(&mut self, event: InputEvent<I>) {
        match event {
            InputEvent::Keyboard { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let time = Event::time_msec(&event);
                let pressed = event.state() == KeyState::Pressed;
                let action = self.seat.get_keyboard().unwrap().input::<Action, _>(
                    self,
                    event.key_code(),
                    event.state(),
                    serial,
                    time,
                    |_, mods, handle| match binding(mods, handle.raw_latin_sym_or_raw_current_sym().unwrap_or(Keysym::NoSymbol)) {
                        // нажатие — действие, отпускание той же клавиши программе тоже не нужно
                        Some(a) if pressed => FilterResult::Intercept(a),
                        _ => FilterResult::Forward,
                    },
                );
                if let Some(action) = action {
                    self.run_action(action);
                }
            }
            InputEvent::PointerMotion { .. } => {}
            InputEvent::PointerMotionAbsolute { event, .. } => {
                let Some(output) = self.space.outputs().next() else { return };
                let output_geo = self.space.output_geometry(output).unwrap();
                let pos = event.position_transformed(output_geo.size) + output_geo.loc.to_f64();
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                let under = self.surface_under(pos);
                pointer.motion(self, under, &MotionEvent { location: pos, serial, time: event.time_msec() });
                pointer.frame(self);
            }
            InputEvent::PointerButton { event, .. } => {
                let pointer = self.seat.get_pointer().unwrap();
                let keyboard = self.seat.get_keyboard().unwrap();
                let serial = SERIAL_COUNTER.next_serial();
                let button = event.button_code();
                let button_state = event.state();

                if button_state == ButtonState::Pressed && !pointer.is_grabbed() {
                    let location = pointer.current_location();
                    if let Some((window, _)) = self.space.element_under(location).map(|(w, l)| (w.clone(), l)) {
                        // щелчок по окну: оно впереди всех и получает клавиатуру
                        self.focus_window(&window, serial);
                        // Super + левая кнопка: тащим окно за любое место
                        if button == BTN_LEFT && keyboard.modifier_state().logo {
                            let initial_window_location = self.space.element_location(&window).unwrap();
                            let start_data = GrabStartData { focus: None, button, location };
                            let grab = MoveSurfaceGrab { start_data, window, initial_window_location };
                            pointer.set_grab(self, grab, serial, Focus::Clear);
                            return;
                        }
                    } else {
                        // щелчок по пустому столу — ни одно окно не активно
                        self.space.elements().for_each(|w| {
                            w.set_activated(false);
                            if let Some(t) = w.toplevel() {
                                t.send_pending_configure();
                            }
                        });
                        keyboard.set_focus(self, Option::<WlSurface>::None, serial);
                    }
                }

                pointer.button(self, &ButtonEvent { button, state: button_state, serial, time: event.time_msec() });
                pointer.frame(self);
            }
            InputEvent::PointerAxis { event, .. } => {
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
            _ => {}
        }
    }

    fn run_action(&mut self, action: Action) {
        tracing::debug!(?action, "сочетание");
        match action {
            Action::Terminal => self.spawn(&config::terminal()),
            Action::CloseWindow => {
                if let Some(t) = self.focused_window().and_then(|w| w.toplevel().cloned()) {
                    t.send_close();
                }
            }
            Action::Quit => self.loop_signal.stop(),
        }
    }
}
