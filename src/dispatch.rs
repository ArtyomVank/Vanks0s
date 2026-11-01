//! `dispatch` — команды окнам и столам. Delta шлёт их в Lua-виде Hyprland
//! 0.57 (`hl.dsp.focus({ workspace = 2 })`), старые программы — классическим
//! (`workspace 2`). Оба вида сводятся к одним и тем же действиям оболочки.

use std::collections::HashMap;

use crate::{
    workspaces::{Mode, SPECIAL},
    Shell,
};

/// Аргументы Lua-вызова: `("minimized")` или `({ workspace = 2, follow = false })`.
#[derive(Debug, Default)]
struct Args {
    positional: Vec<String>,
    named: HashMap<String, String>,
}

impl Args {
    fn get(&self, key: &str) -> Option<&str> {
        self.named.get(key).map(String::as_str)
    }
    fn flag(&self, key: &str, default: bool) -> bool {
        self.get(key).map(|v| v == "true").unwrap_or(default)
    }
}

/// «hl.dsp.window.move({ … })» → ("window.move", аргументы).
fn parse_lua(s: &str) -> Option<(String, Args)> {
    let s = s.trim().strip_prefix("hl.dsp.")?;
    let open = s.find('(')?;
    let name = s[..open].trim().to_string();
    let inner = s[open + 1..].trim_end().strip_suffix(')')?.trim();
    let mut args = Args::default();
    let body = match inner.strip_prefix('{') {
        Some(b) => b.strip_suffix('}')?.trim(),
        None => {
            if !inner.is_empty() {
                args.positional.push(unquote(inner));
            }
            return Some((name, args));
        }
    };
    for part in split_top(body) {
        match part.split_once('=') {
            Some((k, v)) => {
                args.named.insert(k.trim().to_string(), unquote(v.trim()));
            }
            None if !part.trim().is_empty() => args.positional.push(unquote(part.trim())),
            None => {}
        }
    }
    Some((name, args))
}

/// Разделить по запятым вне кавычек.
fn split_top(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    for c in s.chars() {
        match (quote, c) {
            (None, '"' | '\'') => {
                quote = Some(c);
                cur.push(c);
            }
            (Some(q), c) if c == q => {
                quote = None;
                cur.push(c);
            }
            (None, ',') => out.push(std::mem::take(&mut cur)),
            _ => cur.push(c),
        }
    }
    out.push(cur);
    out
}

fn unquote(v: &str) -> String {
    let v = v.trim();
    for q in ['"', '\''] {
        if v.len() >= 2 && v.starts_with(q) && v.ends_with(q) {
            return v[1..v.len() - 1].to_string();
        }
    }
    v.to_string()
}

impl Shell {
    /// Выполнить dispatch; ответ — «ok» или текст ошибки.
    pub fn dispatch(&mut self, command: &str) -> String {
        let command = command.trim();
        let ok = if command.starts_with("hl.dsp.") {
            match parse_lua(command) {
                Some((name, args)) => self.dispatch_lua(&name, &args),
                None => false,
            }
        } else {
            let (name, arg) = command.split_once(' ').unwrap_or((command, ""));
            self.dispatch_legacy(name, arg.trim())
        };
        if ok {
            "ok".into()
        } else {
            tracing::debug!(command, "dispatch не понят");
            format!("Invalid dispatcher: {command}")
        }
    }

    fn dispatch_lua(&mut self, name: &str, a: &Args) -> bool {
        match name {
            "focus" => {
                if let Some(ws) = a.get("workspace") {
                    self.resolve_ws(ws).map(|id| self.switch_workspace(id)).is_some()
                } else if let Some(sel) = a.get("window") {
                    self.focus_selector(sel)
                } else {
                    // направление (стрелки) — для плавающих окон пока ничего
                    true
                }
            }
            "window.move" => {
                let Some(id) = a.get("workspace").and_then(|w| self.resolve_ws(w)) else { return true };
                let Some(window) = self.select_window(a.get("window").unwrap_or("")) else { return false };
                self.move_to_workspace(&window, id, a.flag("follow", true));
                true
            }
            "window.fullscreen" => {
                let mode = match a.get("mode") {
                    Some("maximized") => Mode::Maximized,
                    _ => Mode::Fullscreen,
                };
                let Some(window) = self.select_window(a.get("window").unwrap_or("")) else { return false };
                self.set_mode(&window, mode);
                true
            }
            "window.close" | "window.kill" => {
                let Some(window) = self.select_window(a.get("window").unwrap_or("")) else { return false };
                crate::workspaces::close(&window);
                true
            }
            "workspace.toggle_special" => {
                self.toggle_special();
                true
            }
            "exec_cmd" => {
                if let Some(cmd) = a.positional.first() {
                    self.spawn(cmd);
                }
                true
            }
            "global" => {
                if let Some(id) = a.positional.first() {
                    self.trigger_global(id, true);
                    self.trigger_global(id, false);
                }
                true
            }
            "exit" => {
                self.loop_signal.stop();
                true
            }
            // свойства окна («желе» Delta), плавание, раскладка — у нас окна и
            // так плавающие, эффекты — в 0.5
            "window.set_prop" | "window.float" | "window.pin" | "window.drag" | "window.resize" | "layout" => true,
            _ => false,
        }
    }

    fn dispatch_legacy(&mut self, name: &str, arg: &str) -> bool {
        match name {
            "workspace" => self.resolve_ws(arg).map(|id| self.switch_workspace(id)).is_some(),
            "movetoworkspace" | "movetoworkspacesilent" => {
                let (ws, sel) = arg.split_once(',').unwrap_or((arg, ""));
                let Some(id) = self.resolve_ws(ws) else { return false };
                let Some(window) = self.select_window(sel) else { return false };
                self.move_to_workspace(&window, id, name == "movetoworkspace");
                true
            }
            "togglespecialworkspace" => {
                self.toggle_special();
                true
            }
            "fullscreen" => {
                let mode = if arg.trim() == "1" { Mode::Maximized } else { Mode::Fullscreen };
                let Some(window) = self.focused_window() else { return false };
                self.set_mode(&window, mode);
                true
            }
            "killactive" => {
                if let Some(w) = self.focused_window() {
                    crate::workspaces::close(&w);
                }
                true
            }
            "closewindow" => {
                let Some(window) = self.select_window(arg) else { return false };
                crate::workspaces::close(&window);
                true
            }
            "focuswindow" => self.focus_selector(arg),
            "exec" => {
                self.spawn(arg);
                true
            }
            "global" => {
                self.trigger_global(arg, true);
                self.trigger_global(arg, false);
                true
            }
            "exit" => {
                self.loop_signal.stop();
                true
            }
            "togglefloating" | "setprop" | "pin" | "movefocus" | "layoutmsg" | "dpms" => true,
            _ => false,
        }
    }

    /// Фокус окну по селектору; оно на другом столе — перейти туда.
    fn focus_selector(&mut self, sel: &str) -> bool {
        let Some(window) = self.select_window(sel) else { return false };
        self.activate_window(&window, smithay::utils::SERIAL_COUNTER.next_serial());
        true
    }

    /// Поднять окно: на его стол (или показать свёрнутые) и фокус ему.
    pub fn activate_window(&mut self, window: &smithay::desktop::Window, serial: smithay::utils::Serial) {
        if !self.is_visible(window) {
            let ws = crate::workspaces::data(window).workspace;
            if ws == SPECIAL {
                self.toggle_special();
            } else {
                self.switch_workspace(ws);
            }
        }
        self.raise_in_stack(window);
        self.focus_window(window, serial);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lua_calls() {
        let (n, a) = parse_lua(r#"hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:0x5a000010" })"#).unwrap();
        assert_eq!(n, "window.move");
        assert_eq!(a.get("workspace"), Some("special:minimized"));
        assert!(!a.flag("follow", true));
        assert_eq!(a.get("window"), Some("address:0x5a000010"));

        let (n, a) = parse_lua(r#"hl.dsp.workspace.toggle_special("minimized")"#).unwrap();
        assert_eq!(n, "workspace.toggle_special");
        assert_eq!(a.positional, vec!["minimized"]);

        let (n, a) = parse_lua("hl.dsp.focus({ workspace = 3 })").unwrap();
        assert_eq!((n.as_str(), a.get("workspace")), ("focus", Some("3")));

        let (n, a) = parse_lua("hl.dsp.window.fullscreen()").unwrap();
        assert_eq!(n, "window.fullscreen");
        assert!(a.named.is_empty() && a.positional.is_empty());

        let (_, a) = parse_lua(r#"hl.dsp.window.set_prop({ prop = "alpha", value = "0.5, x", window = "address:0x1" })"#).unwrap();
        assert_eq!(a.get("value"), Some("0.5, x"));
    }
}
