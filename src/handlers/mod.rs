//! Протоколы Wayland, которые понимает оболочка: на каждый — обработчик
//! и delegate_*! от Smithay.

mod compositor;
pub mod xdg_shell;

use smithay::{
    backend::allocator::dmabuf::Dmabuf,
    delegate_cursor_shape, delegate_data_device, delegate_dmabuf, delegate_output, delegate_seat,
    input::{keyboard::LedState, pointer::CursorImageStatus, Seat, SeatHandler, SeatState},
    reexports::wayland_server::{protocol::wl_surface::WlSurface, Resource},
    wayland::{
        dmabuf::{DmabufGlobal, DmabufHandler, DmabufState, ImportNotifier},
        output::OutputHandler,
        tablet_manager::TabletSeatHandler,
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

    // программа под мышью просит курсор: фигуру по имени, свою картинку
    // или спрятать. В настоящей сессии рисуем сами, в окне отладки — сессия вокруг
    fn cursor_image(&mut self, _seat: &Seat<Self>, image: CursorImageStatus) {
        self.cursor_status = image;
    }

    fn led_state_changed(&mut self, _seat: &Seat<Self>, leds: LedState) {
        self.update_leds(leds);
    }

    // буфер обмена — у программы с фокусом клавиатуры
    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let dh = &self.display_handle;
        let client = focused.and_then(|s| dh.get_client(s.id()).ok());
        set_data_device_focus(dh, seat, client);
    }
}
delegate_seat!(Shell);

// --- cursor-shape-v1: курсор по имени («text», «pointer»), без своих картинок ---
impl TabletSeatHandler for Shell {}
delegate_cursor_shape!(Shell);

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

// --- linux-dmabuf: кадры программ прямо из видеопамяти (только настоящая сессия) ---
impl DmabufHandler for Shell {
    fn dmabuf_state(&mut self) -> &mut DmabufState {
        &mut self.dmabuf_state
    }

    fn dmabuf_imported(&mut self, _global: &DmabufGlobal, dmabuf: Dmabuf, notifier: ImportNotifier) {
        if self.import_dmabuf(&dmabuf) {
            let _ = notifier.successful::<Shell>();
        } else {
            notifier.failed();
        }
    }
}
delegate_dmabuf!(Shell);
