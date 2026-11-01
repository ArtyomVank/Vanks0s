//! Окна и рабочие столы — в том же устройстве, что у Hyprland, чтобы Delta
//! видела привычную картину: у окна есть адрес (0x…) и номер стола; у
//! монитора — активный стол; свёрнутые окна Delta прячет на особый стол
//! «special:minimized».
//!
//! В Space лежат только видимые окна; остальные — в `Shell::windows` со своим
//! местом и возвращаются при переключении стола.

use std::{
    cell::{RefCell, RefMut},
    collections::{BTreeSet, HashMap},
};

use smithay::{
    desktop::Window,
    output::Output,
    reexports::wayland_protocols::xdg::shell::server::xdg_toplevel,
    utils::{Logical, Point, Rectangle, SERIAL_COUNTER},
    wayland::{compositor::with_states, shell::xdg::XdgToplevelSurfaceData},
};

use crate::Shell;

/// Особый стол Delta для свёрнутых окон (номер — как у Hyprland).
pub const SPECIAL: i32 = -98;
pub const SPECIAL_NAME: &str = "special:minimized";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Mode {
    #[default]
    Normal,
    /// развёрнуто на место без панелей (Hyprland fullscreen 1)
    Maximized,
    /// весь монитор (Hyprland fullscreen 0)
    Fullscreen,
}

/// Свои данные окна (в user_data).
#[derive(Debug, Default)]
pub struct WinData {
    pub address: u64,
    pub workspace: i32,
    /// где окно стояло, пока оно не на экране
    pub loc: Point<i32, Logical>,
    pub mode: Mode,
    /// место и размер до «развернуть» / «во весь экран»
    pub restore: Option<Rectangle<i32, Logical>>,
}

pub fn data(window: &Window) -> RefMut<'_, WinData> {
    window.user_data().get_or_insert(|| RefCell::new(WinData::default())).borrow_mut()
}

/// app_id и заголовок окна.
pub fn class_title(window: &Window) -> (String, String) {
    let Some(t) = window.toplevel() else { return Default::default() };
    with_states(t.wl_surface(), |states| {
        states
            .data_map
            .get::<XdgToplevelSurfaceData>()
            .map(|d| {
                let d = d.lock().unwrap();
                (d.app_id.clone().unwrap_or_default(), d.title.clone().unwrap_or_default())
            })
            .unwrap_or_default()
    })
}

pub fn ws_name(id: i32) -> String {
    if id == SPECIAL { SPECIAL_NAME.into() } else { id.to_string() }
}

#[derive(Debug, Default)]
pub struct Workspaces {
    /// активный стол каждого монитора (по имени монитора)
    pub active: HashMap<String, i32>,
    /// на каком мониторе стол
    pub monitor_of: HashMap<i32, String>,
    /// свёрнутые окна показаны (Delta: «показать свёрнутые»)
    pub special_shown: bool,
    /// столы, о которых Delta уже знает (createworkspacev2)
    pub known: BTreeSet<i32>,
    pub next_address: u64,
}

impl Shell {
    pub fn focused_output_name(&self) -> String {
        self.output_under_pointer().map(|o| o.name()).unwrap_or_default()
    }

    /// Активный стол монитора (по умолчанию первый).
    pub fn active_ws(&self, output: &str) -> i32 {
        self.workspaces.active.get(output).copied().unwrap_or(1)
    }

    pub fn focused_ws(&self) -> i32 {
        self.active_ws(&self.focused_output_name())
    }

    fn ensure_ws(&mut self, id: i32, output: &str) {
        self.workspaces.monitor_of.entry(id).or_insert_with(|| output.to_string());
        if self.workspaces.known.insert(id) {
            self.ipc_event("createworkspacev2", &format!("{id},{}", ws_name(id)));
            self.ipc_event("createworkspace", &ws_name(id));
        }
    }

    /// Новый монитор — у него свой активный стол: первый свободный номер.
    pub fn output_added(&mut self, output: &Output) {
        let name = output.name();
        if self.workspaces.active.contains_key(&name) {
            return;
        }
        let taken: BTreeSet<i32> = self.workspaces.active.values().copied().collect();
        let id = (1..).find(|i| !taken.contains(i)).unwrap();
        self.workspaces.active.insert(name.clone(), id);
        self.ensure_ws(id, &name);
        let idx = self.space.outputs().position(|o| o == output).unwrap_or(0);
        self.ipc_event("monitoradded", &name);
        self.ipc_event("monitoraddedv2", &format!("{idx},{name},{}", output_description(output)));
    }

    pub fn output_removed(&mut self, output: &Output) {
        let name = output.name();
        self.workspaces.active.remove(&name);
        // столы монитора — на первый оставшийся
        let first = self.space.outputs().next().map(|o| o.name()).unwrap_or_default();
        for m in self.workspaces.monitor_of.values_mut() {
            if *m == name {
                *m = first.clone();
            }
        }
        self.ipc_event("monitorremoved", &name);
    }

    /// Новое окно — на активный стол монитора под мышью, адрес по порядку.
    pub fn track_window(&mut self, window: &Window) {
        let ws = self.focused_ws();
        let output = self.focused_output_name();
        self.ensure_ws(ws, &output);
        self.workspaces.next_address += 1;
        let address = 0x5a00_0000 + self.workspaces.next_address * 0x10;
        {
            let mut d = data(window);
            d.address = address;
            d.workspace = ws;
        }
        self.windows.push(window.clone());
        let (class, title) = class_title(window);
        self.ipc_event("openwindow", &format!("{address:x},{},{class},{title}", ws_name(ws)));
    }

    pub fn untrack_window(&mut self, window: &Window) {
        let address = data(window).address;
        self.windows.retain(|w| w != window);
        self.space.unmap_elem(window);
        self.ipc_event("closewindow", &format!("{address:x}"));
        self.drop_empty_workspaces();
    }

    /// Окно видно, если его стол активен на своём мониторе (или это
    /// показанные свёрнутые).
    pub fn is_visible(&self, window: &Window) -> bool {
        let ws = data(window).workspace;
        if ws == SPECIAL {
            return self.workspaces.special_shown;
        }
        let monitor = self.workspaces.monitor_of.get(&ws).cloned().unwrap_or_default();
        self.workspaces.active.get(&monitor) == Some(&ws)
            || (!self.workspaces.active.contains_key(&monitor) && ws == self.focused_ws())
    }

    /// Привести Space к столам: видимые окна — на экран в порядке наложения,
    /// остальные — прочь (место запоминается).
    pub fn update_visibility(&mut self) {
        for window in self.windows.clone() {
            let visible = self.is_visible(&window);
            let mapped = self.space.element_location(&window);
            match (visible, mapped) {
                (true, None) => {
                    let loc = data(&window).loc;
                    self.space.map_element(window.clone(), loc, false);
                }
                (false, Some(loc)) => {
                    data(&window).loc = loc;
                    self.space.unmap_elem(&window);
                }
                _ => {}
            }
        }
        // порядок наложения — как в списке окон
        for window in self.windows.clone() {
            if self.space.element_location(&window).is_some() {
                self.space.raise_element(&window, false);
            }
        }
    }

    /// Поднять окно в списке (порядок наложения) — вместе с Space.
    pub fn raise_in_stack(&mut self, window: &Window) {
        if let Some(i) = self.windows.iter().position(|w| w == window) {
            let w = self.windows.remove(i);
            self.windows.push(w);
        }
    }

    /// Перейти на стол (Super+1…9, щелчок в доке Delta).
    pub fn switch_workspace(&mut self, id: i32) {
        if id == SPECIAL {
            self.toggle_special();
            return;
        }
        let output = self.focused_output_name();
        let old = self.active_ws(&output);
        if old == id && !self.workspaces.special_shown {
            return;
        }
        // стол уже показан на другом мониторе — туда только фокус (как Hyprland)
        self.ensure_ws(id, &output);
        self.workspaces.monitor_of.insert(id, output.clone());
        self.workspaces.active.insert(output.clone(), id);
        self.workspaces.special_shown = false;
        self.update_visibility();
        self.focus_top();
        self.ipc_event("workspace", &ws_name(id));
        self.ipc_event("workspacev2", &format!("{id},{}", ws_name(id)));
        self.ipc_event("focusedmon", &format!("{output},{}", ws_name(id)));
        self.ipc_event("focusedmonv2", &format!("{output},{id}"));
        self.drop_empty_workspaces();
    }

    /// Номер стола из того, что пишет Delta или Hyprland: «3», «e+1», «-1»…
    pub fn resolve_ws(&self, arg: &str) -> Option<i32> {
        let arg = arg.trim().trim_matches('"');
        let cur = self.focused_ws();
        if let Some(rest) = arg.strip_prefix("special") {
            let _ = rest;
            return Some(SPECIAL);
        }
        if let Some(n) = arg.strip_prefix("name:") {
            return n.parse().ok();
        }
        // e±N — среди занятых столов, r±N и ±N — просто по номеру
        if let Some(rel) = arg.strip_prefix('e') {
            let step: i32 = rel.parse().ok()?;
            let mut used: Vec<i32> = self.workspaces.known.iter().copied().filter(|&i| i > 0).collect();
            used.sort();
            let pos = used.iter().position(|&i| i == cur).unwrap_or(0) as i32;
            let n = used.len() as i32;
            if n == 0 {
                return Some(cur);
            }
            return Some(used[((pos + step) % n + n) as usize % n as usize]);
        }
        if let Some(rel) = arg.strip_prefix('r') {
            return Some((cur + rel.parse::<i32>().ok()?).max(1));
        }
        if arg.starts_with('+') || (arg.starts_with('-') && arg.len() > 1) {
            return Some((cur + arg.parse::<i32>().ok()?).max(1));
        }
        arg.parse().ok().filter(|&i: &i32| i >= 1)
    }

    /// Окно — на другой стол; follow — перейти за ним.
    pub fn move_to_workspace(&mut self, window: &Window, id: i32, follow: bool) {
        let output = self.focused_output_name();
        self.ensure_ws(id, &output);
        let address = {
            let mut d = data(window);
            if let Some(loc) = self.space.element_location(window) {
                d.loc = loc;
            }
            d.workspace = id;
            d.address
        };
        self.ipc_event("movewindow", &format!("{address:x},{}", ws_name(id)));
        self.ipc_event("movewindowv2", &format!("{address:x},{id},{}", ws_name(id)));
        if follow && id != SPECIAL {
            self.switch_workspace(id);
        } else {
            self.update_visibility();
            if self.focused_window().as_ref() == Some(window) {
                self.focus_top();
            }
        }
        self.drop_empty_workspaces();
    }

    /// Показать или спрятать свёрнутые окна.
    pub fn toggle_special(&mut self) {
        self.workspaces.special_shown = !self.workspaces.special_shown;
        self.ensure_ws(SPECIAL, &self.focused_output_name());
        self.update_visibility();
        self.focus_top();
        let output = self.focused_output_name();
        let shown = if self.workspaces.special_shown { SPECIAL_NAME } else { "" };
        let id = if self.workspaces.special_shown { SPECIAL.to_string() } else { String::new() };
        self.ipc_event("activespecial", &format!("{shown},{output}"));
        self.ipc_event("activespecialv2", &format!("{id},{shown},{output}"));
    }

    /// Пустые неактивные столы исчезают (как у Hyprland) — Delta убирает точки.
    fn drop_empty_workspaces(&mut self) {
        let active: BTreeSet<i32> = self.workspaces.active.values().copied().collect();
        let used: BTreeSet<i32> = self.windows.iter().map(|w| data(w).workspace).collect();
        let gone: Vec<i32> =
            self.workspaces.known.iter().copied().filter(|i| !active.contains(i) && !used.contains(i)).collect();
        for id in gone {
            self.workspaces.known.remove(&id);
            self.workspaces.monitor_of.remove(&id);
            self.ipc_event("destroyworkspace", &ws_name(id));
            self.ipc_event("destroyworkspacev2", &format!("{id},{}", ws_name(id)));
        }
    }

    /// Монитор, на котором окно (по его середине), иначе под мышью.
    pub fn output_of(&self, window: &Window) -> Option<Output> {
        let geo = self.space.element_geometry(window)?;
        let center = (geo.loc + geo.size.downscale(2).to_point()).to_f64();
        self.space.output_under(center).next().cloned().or_else(|| self.output_under_pointer())
    }

    /// Развернуть / во весь экран / обратно. Повтор того же — возврат.
    pub fn set_mode(&mut self, window: &Window, mode: Mode) {
        let Some(toplevel) = window.toplevel().cloned() else { return };
        let Some(output) = self.output_of(window) else { return };
        let current = data(window).mode;
        let target = if current == mode { Mode::Normal } else { mode };

        let geo = match target {
            Mode::Normal => data(window).restore.take(),
            Mode::Maximized => Some(self.usable_area(&output)),
            Mode::Fullscreen => self.space.output_geometry(&output),
        };
        if current == Mode::Normal && target != Mode::Normal {
            let loc = self.space.element_location(window).unwrap_or_default();
            data(window).restore = Some(Rectangle::new(loc, window.geometry().size));
        }
        data(window).mode = target;

        toplevel.with_pending_state(|s| {
            s.states.unset(xdg_toplevel::State::Maximized);
            s.states.unset(xdg_toplevel::State::Fullscreen);
            match target {
                Mode::Maximized => {
                    s.states.set(xdg_toplevel::State::Maximized);
                }
                Mode::Fullscreen => {
                    s.states.set(xdg_toplevel::State::Fullscreen);
                }
                Mode::Normal => {}
            }
            s.size = match (target, geo) {
                (Mode::Normal, Some(g)) => Some(g.size),
                (Mode::Normal, None) => None,
                (_, g) => g.map(|g| g.size),
            };
            s.fullscreen_output = None;
        });
        toplevel.send_pending_configure();
        if let Some(g) = geo {
            self.space.map_element(window.clone(), g.loc, true);
        }
        self.raise_in_stack(window);
        self.focus_window(window, SERIAL_COUNTER.next_serial());
        let fs = if target == Mode::Normal { "0" } else { "1" };
        self.ipc_event("fullscreen", fs);
    }

    /// Панель заняла или отпустила край: развёрнутые окна монитора — по новой зоне.
    pub fn zones_changed(&mut self, output: &Output) {
        let area = self.usable_area(output);
        for window in self.windows.clone() {
            if data(&window).mode != Mode::Maximized || self.output_of(&window).as_ref() != Some(output) {
                continue;
            }
            if let Some(t) = window.toplevel() {
                t.with_pending_state(|s| s.size = Some(area.size));
                t.send_pending_configure();
            }
            if self.space.element_location(&window).is_some() {
                self.space.map_element(window.clone(), area.loc, false);
            } else {
                data(&window).loc = area.loc;
            }
        }
    }

    pub fn window_by_address(&self, address: u64) -> Option<Window> {
        self.windows.iter().find(|w| data(w).address == address).cloned()
    }

    /// Окно по селектору Hyprland: «address:0x…», «class:^delta-settings$»,
    /// «title:…», «activewindow»; пусто — окно с фокусом.
    pub fn select_window(&self, selector: &str) -> Option<Window> {
        let sel = selector.trim().trim_matches('"');
        if sel.is_empty() || sel == "activewindow" {
            return self.focused_window();
        }
        if let Some(addr) = sel.strip_prefix("address:") {
            let addr = u64::from_str_radix(addr.trim_start_matches("0x"), 16).ok()?;
            return self.window_by_address(addr);
        }
        let (field, pattern) = sel.split_once(':').unwrap_or(("class", sel));
        let pattern = pattern.trim_start_matches('^').trim_end_matches('$');
        self.windows
            .iter()
            .rev()
            .find(|w| {
                let (class, title) = class_title(w);
                let value = if field == "title" { title } else { class };
                value == pattern
            })
            .cloned()
    }
}

/// «Производитель Модель (Разъём)» — как description у Hyprland.
pub fn output_description(output: &Output) -> String {
    let p = output.physical_properties();
    format!("{} {} ({})", p.make, p.model, output.name())
}
