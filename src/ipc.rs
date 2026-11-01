//! IPC как у Hyprland — чтобы Delta (Quickshell.Hyprland и hyprctl) работала
//! поверх Vanks Shell без единой правки.
//!
//!   $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock   запрос → ответ
//!   $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock  события «имя>>данные\n»
//!
//! Запрос: «[флаги/]команда аргументы», флаг j — ответ в JSON; «[[BATCH]]a;b» —
//! несколько сразу. Делаем то, чем пользуется Delta, остальное — «unknown request».
//! Своё, родное API оболочки появится рядом; это — слой совместимости.

use std::{
    collections::HashMap,
    io::{Read, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    time::Duration,
};

use serde_json::{json, Value};
use smithay::{
    desktop::layer_map_for_output,
    reexports::{
        calloop::{generic::Generic, Interest, Mode as CMode, PostAction},
        wayland_server::Resource,
    },
};

use crate::{
    workspaces::{class_title, data, output_description, ws_name, Mode, SPECIAL},
    Shell,
};

/// Версия Hyprland, за которую мы себя выдаём (Delta рассчитана на 0.57 с Lua).
const HYPR_VERSION: &str = "0.57.0";

pub struct Ipc {
    pub signature: String,
    pub dir: PathBuf,
    events: Vec<UnixStream>,
    /// раскладка, о которой Delta уже знает (activelayout)
    pub last_layout: String,
}

impl Drop for Ipc {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

impl Shell {
    pub fn init_ipc(&mut self) -> std::io::Result<()> {
        let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
        let time = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs();
        let signature = format!("vanks_{time}_{}", std::process::id());
        let dir = runtime.join("hypr").join(&signature);
        std::fs::create_dir_all(&dir)?;

        let requests = UnixListener::bind(dir.join(".socket.sock"))?;
        let events = UnixListener::bind(dir.join(".socket2.sock"))?;
        requests.set_nonblocking(true)?;
        events.set_nonblocking(true)?;

        self.loop_handle
            .insert_source(Generic::new(requests, Interest::READ, CMode::Level), |_, listener, data| {
                while let Ok((stream, _)) = listener.accept() {
                    let _ = stream.set_nonblocking(true);
                    let source = Generic::new(stream, Interest::READ, CMode::Level);
                    let mut buf = Vec::new();
                    let r = data.state.loop_handle.insert_source(source, move |_, stream, data| {
                        let mut s: &UnixStream = stream;
                        let mut chunk = [0u8; 4096];
                        loop {
                            match s.read(&mut chunk) {
                                Ok(0) => break,
                                Ok(n) => buf.extend_from_slice(&chunk[..n]),
                                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                                Err(_) => return Ok(PostAction::Remove),
                            }
                        }
                        if buf.is_empty() {
                            return Ok(PostAction::Remove);
                        }
                        let request = String::from_utf8_lossy(&buf).to_string();
                        let reply = data.state.ipc_request(&request);
                        let _ = s.set_nonblocking(false);
                        let _ = s.set_write_timeout(Some(Duration::from_millis(500)));
                        let _ = s.write_all(reply.as_bytes());
                        let _ = s.shutdown(std::net::Shutdown::Both);
                        Ok(PostAction::Remove)
                    });
                    if let Err(e) = r {
                        tracing::warn!("ipc: {e}");
                    }
                }
                Ok(PostAction::Continue)
            })
            .map_err(|e| std::io::Error::other(e.to_string()))?;

        self.loop_handle
            .insert_source(Generic::new(events, Interest::READ, CMode::Level), |_, listener, data| {
                while let Ok((stream, _)) = listener.accept() {
                    let _ = stream.set_nonblocking(true);
                    if let Some(ipc) = data.state.ipc.as_mut() {
                        ipc.events.push(stream);
                    }
                }
                Ok(PostAction::Continue)
            })
            .map_err(|e| std::io::Error::other(e.to_string()))?;

        tracing::info!(signature, "IPC как у Hyprland");
        self.ipc = Some(Ipc { signature, dir, events: Vec::new(), last_layout: String::new() });
        Ok(())
    }

    /// Событие всем, кто слушает .socket2.sock.
    pub fn ipc_event(&mut self, name: &str, payload: &str) {
        let Some(ipc) = self.ipc.as_mut() else { return };
        if ipc.events.is_empty() {
            return;
        }
        let line = format!("{name}>>{payload}\n");
        tracing::debug!(event = line.trim_end(), "ipc");
        ipc.events.retain_mut(|s| match s.write_all(line.as_bytes()) {
            Ok(()) => true,
            // слушатель не успевает — подождём чуть-чуть, иначе отпустим
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                let _ = s.set_nonblocking(false);
                let _ = s.set_write_timeout(Some(Duration::from_millis(50)));
                let ok = s.write_all(line.as_bytes()).is_ok();
                let _ = s.set_nonblocking(true);
                ok
            }
            Err(_) => false,
        });
    }

    pub fn ipc_request(&mut self, request: &str) -> String {
        let request = request.trim_end_matches(['\0', '\n']);
        tracing::debug!(request, "ipc");
        if let Some(batch) = request.strip_prefix("[[BATCH]]") {
            return batch
                .split(';')
                .filter(|c| !c.trim().is_empty())
                .map(|c| self.ipc_one(c.trim()))
                .collect::<Vec<_>>()
                .join("\n\n");
        }
        self.ipc_one(request)
    }

    fn ipc_one(&mut self, request: &str) -> String {
        // «j/monitors» — флаги до косой черты (без пробелов перед ней)
        let (flags, command) = match request.split_once('/') {
            Some((f, rest)) if !f.contains(' ') && f.chars().all(|c| "jrac*[]".contains(c)) => (f, rest),
            _ => ("", request),
        };
        let json = flags.contains('j');
        let (cmd, args) = command.split_once(' ').unwrap_or((command, ""));
        let args = args.trim();

        let value = match cmd {
            "status" => Some(json!({ "configProvider": "lua", "version": HYPR_VERSION, "compositor": "Vanks Shell" })),
            "version" => Some(json!({
                "branch": "vanks-shell",
                "commit": env!("CARGO_PKG_VERSION"),
                "version": HYPR_VERSION,
                "dirty": false,
                "commit_message": "Vanks Shell",
                "commit_date": "",
                "tag": format!("v{HYPR_VERSION}"),
                "commits": "0",
                "buildAquamarine": "",
                "flags": [],
            })),
            "monitors" => Some(self.monitors_json(args == "all")),
            "workspaces" => Some(Value::Array(self.workspaces_json())),
            "activeworkspace" => {
                let id = self.focused_ws();
                Some(self.workspaces_json().into_iter().find(|w| w["id"] == id).unwrap_or(json!({})))
            }
            "clients" => Some(Value::Array(self.windows.clone().iter().map(|w| self.client_json(w)).collect())),
            "activewindow" => Some(self.focused_window().map(|w| self.client_json(&w)).unwrap_or(json!({}))),
            "devices" => Some(self.devices_json()),
            "layers" => Some(self.layers_json()),
            "cursorpos" => {
                let p = self.seat.get_pointer().map(|p| p.current_location()).unwrap_or_default();
                Some(json!({ "x": p.x as i32, "y": p.y as i32 }))
            }
            "instances" => Some(json!([{ "instance": self.ipc.as_ref().map(|i| i.signature.clone()), "pid": std::process::id(), "wl_socket": self.socket_name.to_string_lossy() }])),
            "configerrors" => Some(json!([""])),
            "binds" | "globalshortcuts" | "animations" => Some(json!([])),
            "getoption" => Some(json!({ "option": args, "int": 0, "set": false })),
            "splash" => return "Vanks Shell".into(),
            "dispatch" => return self.dispatch(args),
            // delta-apply после записи settings.json зовёт hyprctl reload
            "reload" => {
                self.settings = crate::settings::Settings::load();
                self.reload_monitors();
                return "ok".into();
            }
            // из Lua понимаем только мониторы: раздел «Экран» применяет их на лету
            "eval" => {
                let rules = crate::monitors::parse_lua(args);
                return match self.apply_monitor_rules(&rules) {
                    Ok(()) => "ok".into(),
                    Err(e) => format!("error: {e}"),
                };
            }
            // настройки оболочки берутся из Delta напрямую; keyword — «ок»
            "keyword" | "seterror" | "notify" | "dismissnotify" | "plugin" => return "ok".into(),
            "setcursor" => {
                let mut it = args.split_whitespace();
                if let (Some(theme), Some(size)) = (it.next(), it.next().and_then(|s| s.parse().ok())) {
                    self.cursor = crate::cursor::Cursor::with_theme(theme, size);
                }
                return "ok".into();
            }
            "switchxkblayout" => {
                let target = args.split_whitespace().nth(1).unwrap_or("next");
                self.switch_layout(target);
                return "ok".into();
            }
            _ => None,
        };
        match value {
            Some(v) if json => serde_json::to_string_pretty(&v).unwrap_or_default(),
            Some(v) => plain(&v),
            None => "unknown request".into(),
        }
    }

    fn monitors_json(&self, all: bool) -> Value {
        let focused = self.focused_output_name();
        let mut outputs: Vec<_> = self.space.outputs().cloned().collect();
        if all {
            outputs.extend(self.disabled_outputs());
        }
        let list: Vec<Value> = outputs
            .iter()
            .enumerate()
            .map(|(i, o)| {
                let geo = self.space.output_geometry(o).unwrap_or_default();
                let mode = o.current_mode();
                let size = mode.map(|m| m.size).unwrap_or_default();
                let zone = layer_map_for_output(o).non_exclusive_zone();
                let reserved = [zone.loc.x, zone.loc.y, geo.size.w - zone.size.w - zone.loc.x, geo.size.h - zone.size.h - zone.loc.y];
                let ws = self.active_ws(&o.name());
                let p = o.physical_properties();
                let modes: Vec<String> = o
                    .modes()
                    .iter()
                    .map(|m| format!("{}x{}@{:.2}Hz", m.size.w, m.size.h, m.refresh as f64 / 1000.0))
                    .collect();
                json!({
                    "id": i,
                    "name": o.name(),
                    "description": output_description(o),
                    "make": p.make,
                    "model": p.model,
                    "serial": o.user_data().get::<crate::workspaces::OutputSerial>().map(|s| s.0.as_str()).unwrap_or(""),
                    "width": size.w,
                    "height": size.h,
                    "physicalWidth": p.size.w,
                    "physicalHeight": p.size.h,
                    "refreshRate": mode.map(|m| m.refresh as f64 / 1000.0).unwrap_or(60.0),
                    "x": geo.loc.x,
                    "y": geo.loc.y,
                    "activeWorkspace": { "id": ws, "name": ws_name(ws) },
                    "specialWorkspace": if self.workspaces.special_shown && o.name() == focused {
                        json!({ "id": SPECIAL, "name": ws_name(SPECIAL) })
                    } else {
                        json!({ "id": 0, "name": "" })
                    },
                    "reserved": reserved,
                    "scale": o.current_scale().fractional_scale(),
                    "transform": if self.udev.is_some() { crate::monitors::transform_number(o.current_transform()) } else { 0 },
                    "focused": o.name() == focused,
                    "dpmsStatus": true,
                    "vrr": false,
                    "solitary": "0",
                    "activelyTearing": false,
                    "directScanoutTo": "0",
                    "disabled": self.space.output_geometry(o).is_none(),
                    "currentFormat": "XRGB8888",
                    "mirrorOf": "none",
                    "availableModes": modes,
                })
            })
            .collect();
        Value::Array(list)
    }

    fn workspaces_json(&self) -> Vec<Value> {
        let outputs: Vec<String> = self.space.outputs().map(|o| o.name()).collect();
        let mut counts: HashMap<i32, (usize, bool, Option<(u64, String)>)> = HashMap::new();
        for w in &self.windows {
            let d = data(w);
            let e = counts.entry(d.workspace).or_default();
            e.0 += 1;
            e.1 |= d.mode != Mode::Normal;
            e.2 = Some((d.address, class_title(w).1));
        }
        self.workspaces
            .known
            .iter()
            .map(|&id| {
                let monitor = self.workspaces.monitor_of.get(&id).cloned().unwrap_or_default();
                let (n, full, last) = counts.get(&id).cloned().unwrap_or_default();
                let (addr, title) = last.unwrap_or_default();
                json!({
                    "id": id,
                    "name": ws_name(id),
                    "monitor": monitor,
                    "monitorID": outputs.iter().position(|o| *o == monitor).unwrap_or(0),
                    "windows": n,
                    "hasfullscreen": full,
                    "lastwindow": format!("0x{addr:x}"),
                    "lastwindowtitle": title,
                    "ispersistent": false,
                })
            })
            .collect()
    }

    fn client_json(&self, window: &smithay::desktop::Window) -> Value {
        let (class, title) = class_title(window);
        // раньше data(): is_visible сам берёт запись окна
        let hidden = !self.is_visible(window);
        let d = data(window);
        let loc = self.space.element_location(window).unwrap_or(d.loc);
        let size = window.geometry().size;
        let monitor = self
            .workspaces
            .monitor_of
            .get(&d.workspace)
            .and_then(|m| self.space.outputs().position(|o| o.name() == *m))
            .unwrap_or(0);
        let pid = match window.x11_surface() {
            Some(x11) => x11.pid().map(|p| p as i32).unwrap_or(-1),
            None => window
                .toplevel()
                .and_then(|t| self.display_handle.get_client(t.wl_surface().id()).ok())
                .and_then(|c| c.get_credentials(&self.display_handle).ok())
                .map(|c| c.pid)
                .unwrap_or(-1),
        };
        let focus_order = self.windows.iter().rev().position(|w| w == window).unwrap_or(0);
        json!({
            "address": format!("0x{:x}", d.address),
            "mapped": true,
            "hidden": hidden,
            "at": [loc.x, loc.y],
            "size": [size.w, size.h],
            "workspace": { "id": d.workspace, "name": ws_name(d.workspace) },
            "floating": true,
            "pseudo": false,
            "monitor": monitor,
            "class": class,
            "title": title,
            "initialClass": class,
            "initialTitle": title,
            "pid": pid,
            "xwayland": window.is_x11(),
            "pinned": d.pinned,
            "fullscreen": match d.mode { Mode::Normal => 0, Mode::Maximized => 1, Mode::Fullscreen => 2 },
            "fullscreenClient": 0,
            "grouped": [],
            "tags": [],
            "swallowing": "0x0",
            "focusHistoryID": focus_order,
            "inhibitingIdle": false,
            "xdgTag": "",
            "xdgDescription": "",
            "contentType": "none",
        })
    }

    fn devices_json(&mut self) -> Value {
        let (layout, layouts) = self.layout_names();
        let input = &self.settings.input;
        json!({
            "mice": [],
            "keyboards": [{
                "address": "0x1",
                "name": "vanks-keyboard",
                "rules": "",
                "model": "",
                "layout": input.xkb_layout(),
                "variant": "",
                "options": input.switch_keys,
                "active_keymap": layout,
                "active_layout_index": layouts.iter().position(|l| *l == layout).unwrap_or(0),
                "capsLock": false,
                "numLock": false,
                "main": true,
            }],
            "tablets": [],
            "touch": [],
            "switches": [],
        })
    }

    fn layers_json(&self) -> Value {
        let mut out = serde_json::Map::new();
        for o in self.space.outputs() {
            let map = layer_map_for_output(o);
            let mut levels = serde_json::Map::new();
            for (i, level) in ["background", "bottom", "top", "overlay"].iter().enumerate() {
                let wl = [
                    smithay::wayland::shell::wlr_layer::Layer::Background,
                    smithay::wayland::shell::wlr_layer::Layer::Bottom,
                    smithay::wayland::shell::wlr_layer::Layer::Top,
                    smithay::wayland::shell::wlr_layer::Layer::Overlay,
                ][i];
                let items: Vec<Value> = map
                    .layers_on(wl)
                    .map(|l| {
                        let g = map.layer_geometry(l).unwrap_or_default();
                        json!({ "address": "0x0", "x": g.loc.x, "y": g.loc.y, "w": g.size.w, "h": g.size.h, "namespace": l.namespace(), "pid": -1 })
                    })
                    .collect();
                levels.insert(i.to_string(), Value::Array(items));
                let _ = level;
            }
            out.insert(o.name(), json!({ "levels": levels }));
        }
        Value::Object(out)
    }

    /// Текущая раскладка и все раскладки — по-человечески («Russian»).
    pub fn layout_names(&mut self) -> (String, Vec<String>) {
        let Some(kb) = self.seat.get_keyboard() else { return Default::default() };
        kb.with_xkb_state(self, |ctx| {
            let xkb = ctx.xkb().lock().unwrap();
            let names: Vec<String> = xkb.layouts().map(|l| xkb.layout_name(l).to_string()).collect();
            (xkb.layout_name(xkb.active_layout()).to_string(), names)
        })
    }

    /// hyprctl switchxkblayout all next|prev|N.
    pub fn switch_layout(&mut self, target: &str) {
        let Some(kb) = self.seat.get_keyboard() else { return };
        kb.with_xkb_state(self, |mut ctx| {
            let (cur, n) = {
                let xkb = ctx.xkb().lock().unwrap();
                (xkb.active_layout().0, xkb.layouts().count() as u32)
            };
            if n == 0 {
                return;
            }
            let next = match target {
                "next" => (cur + 1) % n,
                "prev" => (cur + n - 1) % n,
                i => i.parse::<u32>().unwrap_or(cur).min(n - 1),
            };
            ctx.set_layout(smithay::input::keyboard::Layout(next));
        });
        self.layout_maybe_changed();
    }

    /// Раскладка сменилась (Alt+Shift, switchxkblayout) — событие для Delta.
    pub fn layout_maybe_changed(&mut self) {
        let (layout, _) = self.layout_names();
        let Some(ipc) = self.ipc.as_mut() else { return };
        if ipc.last_layout != layout {
            let first = ipc.last_layout.is_empty();
            ipc.last_layout = layout.clone();
            if !first {
                self.ipc_event("activelayout", &format!("vanks-keyboard,{layout}"));
            }
        }
    }
}

/// Ответ без флага j — коротко, по строке на объект.
fn plain(v: &Value) -> String {
    match v {
        Value::Array(a) => a.iter().map(plain).collect::<Vec<_>>().join("\n\n"),
        Value::Object(o) => o.iter().map(|(k, v)| format!("{k}: {}", plain(v))).collect::<Vec<_>>().join("\n\t"),
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}
