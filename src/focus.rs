//! Кто получает клавиатуру: поверхность Wayland или окно X11. Окну X11 ещё надо
//! сказать о фокусе по протоколу X — это умеет KeyboardTarget самого X11Surface.

use std::borrow::Cow;

use smithay::{
    backend::input::KeyState,
    desktop::PopupKind,
    input::{
        keyboard::{KeyboardTarget, KeysymHandle, ModifiersState},
        Seat,
    },
    reexports::wayland_server::{protocol::wl_surface::WlSurface, Resource},
    utils::{IsAlive, Serial},
    wayland::seat::WaylandFocus,
    xwayland::X11Surface,
};

use crate::Shell;

#[derive(Debug, Clone, PartialEq)]
pub enum KeyFocus {
    Surface(WlSurface),
    X11(X11Surface),
}

impl KeyFocus {
    pub fn surface(&self) -> Option<WlSurface> {
        self.wl_surface().map(Cow::into_owned)
    }

    /// Та же программа и та же поверхность.
    pub fn is(&self, surface: &WlSurface) -> bool {
        self.wl_surface().as_deref() == Some(surface)
    }
}

impl From<WlSurface> for KeyFocus {
    fn from(s: WlSurface) -> Self {
        KeyFocus::Surface(s)
    }
}

impl From<PopupKind> for KeyFocus {
    fn from(p: PopupKind) -> Self {
        KeyFocus::Surface(p.wl_surface().clone())
    }
}

// захват всплывающего меню передаёт корень меню мыши. Меню бывают только у
// окон Wayland и панелей, у X11 они свои, поэтому X11 сюда не доходит
impl From<KeyFocus> for WlSurface {
    fn from(f: KeyFocus) -> Self {
        f.surface().expect("корень меню — поверхность Wayland")
    }
}

impl IsAlive for KeyFocus {
    fn alive(&self) -> bool {
        match self {
            KeyFocus::Surface(s) => s.is_alive(),
            KeyFocus::X11(x) => x.alive(),
        }
    }
}

impl WaylandFocus for KeyFocus {
    fn wl_surface(&self) -> Option<Cow<'_, WlSurface>> {
        match self {
            KeyFocus::Surface(s) => Some(Cow::Borrowed(s)),
            KeyFocus::X11(x) => x.wl_surface().map(Cow::Owned),
        }
    }
}

impl KeyboardTarget<Shell> for KeyFocus {
    fn enter(&self, seat: &Seat<Shell>, data: &mut Shell, keys: Vec<KeysymHandle<'_>>, serial: Serial) {
        match self {
            KeyFocus::Surface(s) => KeyboardTarget::enter(s, seat, data, keys, serial),
            KeyFocus::X11(x) => KeyboardTarget::enter(x, seat, data, keys, serial),
        }
    }

    fn leave(&self, seat: &Seat<Shell>, data: &mut Shell, serial: Serial) {
        match self {
            KeyFocus::Surface(s) => KeyboardTarget::leave(s, seat, data, serial),
            KeyFocus::X11(x) => KeyboardTarget::leave(x, seat, data, serial),
        }
    }

    fn key(&self, seat: &Seat<Shell>, data: &mut Shell, key: KeysymHandle<'_>, state: KeyState, serial: Serial, time: u32) {
        match self {
            KeyFocus::Surface(s) => KeyboardTarget::key(s, seat, data, key, state, serial, time),
            KeyFocus::X11(x) => KeyboardTarget::key(x, seat, data, key, state, serial, time),
        }
    }

    fn modifiers(&self, seat: &Seat<Shell>, data: &mut Shell, modifiers: ModifiersState, serial: Serial) {
        match self {
            KeyFocus::Surface(s) => KeyboardTarget::modifiers(s, seat, data, modifiers, serial),
            KeyFocus::X11(x) => KeyboardTarget::modifiers(x, seat, data, modifiers, serial),
        }
    }
}
