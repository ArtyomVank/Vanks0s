use smithay::{
    backend::renderer::utils::on_commit_buffer_handler,
    delegate_compositor, delegate_drm_syncobj, delegate_shm,
    xwayland::XWaylandClientData,
    reexports::{
        calloop::Interest,
        wayland_server::{
            protocol::{wl_buffer, wl_surface::WlSurface},
            Client, Resource,
        },
    },
    wayland::{
        buffer::BufferHandler,
        compositor::{
            add_blocker, add_pre_commit_hook, get_parent, is_sync_subsurface, with_states, BufferAssignment, CompositorClientState,
            CompositorHandler, CompositorState, SurfaceAttributes,
        },
        dmabuf::get_dmabuf,
        drm_syncobj::{DrmSyncobjCachedState, DrmSyncobjHandler, DrmSyncobjState},
        shm::{ShmHandler, ShmState},
    },
};

use super::{layer_shell, xdg_shell};
use crate::{grabs::resize_grab, state::ClientState, CalloopData, Shell};

impl CompositorHandler for Shell {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        // Xwayland тоже программа Wayland, но со своими данными
        if let Some(x) = client.get_data::<XWaylandClientData>() {
            return &x.compositor_state;
        }
        &client.get_data::<ClientState>().unwrap().compositor_state
    }

    fn new_surface(&mut self, surface: &WlSurface) {
        layer_shell::guard_removed_layer(surface);
        crate::lock::guard_removed_lock(surface);
        wait_for_buffer(surface);
    }

    /// Программа прислала новый кадр поверхности.
    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
        self.fx.scene.increment();
        if !is_sync_subsurface(surface) {
            let mut root = surface.clone();
            while let Some(parent) = get_parent(&root) {
                root = parent;
            }
            if let Some(window) = self.window_for_surface(&root) {
                window.on_commit();
            }
        }
        xdg_shell::handle_commit(self, surface);
        layer_shell::handle_commit(self, surface);
        self.lock_commit(surface);
        resize_grab::handle_commit(&mut self.space, surface);
    }
}

/// Кадр программы применяется, только когда видеокарта его дорисовала. Иначе
/// на экран попадает недорисованный буфер: на NVIDIA неявной синхронизации нет,
/// и при запуске, когда видеокарта занята, это видно как мусор на панелях до
/// следующего кадра (например, пока не сдвинешь мышь).
fn wait_for_buffer(surface: &WlSurface) {
    add_pre_commit_hook::<Shell, _>(surface, |state, _, surface| {
        let (acquire, dmabuf) = with_states(surface, |states| {
            let acquire = states.cached_state.get::<DrmSyncobjCachedState>().pending().acquire_point.clone();
            let mut attrs = states.cached_state.get::<SurfaceAttributes>();
            let dmabuf = match attrs.pending().buffer.as_ref() {
                Some(BufferAssignment::NewBuffer(buffer)) => get_dmabuf(buffer).cloned().ok(),
                _ => None,
            };
            (acquire, dmabuf)
        });
        let Some(dmabuf) = dmabuf else { return };
        let Some(client) = surface.client() else { return };
        let wake = move |data: &mut CalloopData| {
            let dh = data.display_handle.clone();
            data.state.client_compositor_state(&client).blocker_cleared(&mut data.state, &dh);
        };
        // явная синхронизация, если программа её использует; иначе — неявная у dmabuf
        if let Some(Ok((blocker, source))) = acquire.as_ref().map(|p| p.generate_blocker()) {
            let wake = wake.clone();
            let inserted = state.loop_handle.insert_source(source, move |_, _, data| {
                wake(data);
                Ok(())
            });
            if inserted.is_ok() {
                add_blocker(surface, blocker);
                return;
            }
        }
        if let Ok((blocker, source)) = dmabuf.generate_blocker(Interest::READ) {
            let inserted = state.loop_handle.insert_source(source, move |_, _, data| {
                wake(data);
                Ok(())
            });
            if inserted.is_ok() {
                add_blocker(surface, blocker);
            }
        }
    });
}

impl DrmSyncobjHandler for Shell {
    fn drm_syncobj_state(&mut self) -> Option<&mut DrmSyncobjState> {
        self.syncobj_state.as_mut()
    }
}

impl BufferHandler for Shell {
    fn buffer_destroyed(&mut self, _buffer: &wl_buffer::WlBuffer) {}
}

impl ShmHandler for Shell {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

delegate_compositor!(Shell);
delegate_shm!(Shell);
delegate_drm_syncobj!(Shell);
