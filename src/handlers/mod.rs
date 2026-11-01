//! Протоколы Wayland, которые понимает оболочка: на каждый — обработчик
//! и delegate_*! от Smithay.

mod compositor;
pub mod xdg_shell;

use smithay::{
    delegate_data_device, delegate_output, delegate_seat,
    input::{Seat, SeatHandler, SeatState},
    reexports::wayland_server::{protocol::wl_surface::WlSurface, Resource},
    wayland::{
        output::OutputHandler,
        selection::{
            data_device::{set_data_device_focus, ClientDndGrabHandler, DataDeviceHandler, DataDeviceState, ServerDndGrabHandler},
            SelectionHandler,
        },
    },
};

use crate::Shell;

// --- wl_seat: клавиатура, мышь, касания ---
impl SeatHandler for Shell {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Shell> {
        &mut self.seat_state
    }

    // курсор рисует сессия вокруг (окно отладки); свой — вместе с DRM
    fn cursor_image(&mut self, _seat: &Seat<Self>, _image: smithay::input::pointer::CursorImageStatus) {}

    // буфер обмена — у программы с фокусом клавиатуры
    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let dh = &self.display_handle;
        let client = focused.and_then(|s| dh.get_client(s.id()).ok());
        set_data_device_focus(dh, seat, client);
    }
}
delegate_seat!(Shell);

// --- буфер обмена и перетаскивание между программами ---
impl SelectionHandler for Shell {
    type SelectionUserData = ();
}
impl DataDeviceHandler for Shell {
    fn data_device_state(&self) -> &DataDeviceState {
        &self.data_device_state
    }
}
impl ClientDndGrabHandler for Shell {}
impl ServerDndGrabHandler for Shell {}
delegate_data_device!(Shell);

// --- выходы (мониторы) и xdg-output ---
impl OutputHandler for Shell {}
delegate_output!(Shell);
