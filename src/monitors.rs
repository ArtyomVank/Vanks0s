//! Мониторы из настроек Delta: `monitors` в settings.json и `hl.monitor(...)`,
//! которые раздел «Экран» присылает через `hyprctl eval`. Поля те же, что читает
//! delta-apply. Повтор экрана, VRR и цвет пока не применяются.

use serde_json::{Map, Value};
use smithay::{
    desktop::layer_map_for_output,
    output::{Output, Scale},
    utils::Transform,
};

use crate::{
    workspaces::{data, output_description, Mode},
    Shell,
};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct MonitorRule {
    /// имя порта или «desc:начало описания»
    pub key: String,
    pub disabled: bool,
    pub mode: Option<(i32, i32, f64)>,
    pub position: Option<(i32, i32)>,
    pub scale: Option<f64>,
    pub transform: Option<i32>,
}

/// «1920x1080@200.00Hz», «1920x1080»; «preferred» и прочие слова — None.
fn parse_mode(s: &str) -> Option<(i32, i32, f64)> {
    let (size, hz) = s.split_once('@').unwrap_or((s, "0"));
    let (w, h) = size.split_once('x')?;
    Some((w.parse().ok()?, h.parse().ok()?, hz.trim_end_matches("Hz").parse().ok()?))
}

fn parse_position(s: &str) -> Option<(i32, i32)> {
    let (x, y) = s.split_once('x')?;
    Some((x.parse().ok()?, y.parse().ok()?))
}

impl MonitorRule {
    pub fn from_value(v: &Value) -> Option<Self> {
        let key = v.get("match").or_else(|| v.get("output"))?.as_str()?.trim().to_string();
        if key.is_empty() {
            return None;
        }
        Some(Self {
            key,
            disabled: v.get("disabled").and_then(Value::as_bool).unwrap_or(false),
            mode: v.get("mode").and_then(Value::as_str).and_then(parse_mode),
            position: v.get("position").and_then(Value::as_str).and_then(parse_position),
            scale: v.get("scale").and_then(Value::as_f64).map(|s| s.clamp(0.25, 4.0)),
            transform: v.get("transform").and_then(Value::as_i64).map(|t| t.clamp(0, 7) as i32),
        })
    }

    pub fn matches(&self, name: &str, description: &str) -> bool {
        match self.key.strip_prefix("desc:") {
            Some(d) => !d.trim().is_empty() && description.starts_with(d.trim()),
            None => self.key == name,
        }
    }
}

/// Все `hl.monitor({ ... })` из сценария `hyprctl eval`; остальное в нём не наше.
pub fn parse_lua(script: &str) -> Vec<MonitorRule> {
    let mut rules = Vec::new();
    let mut rest = script;
    while let Some(at) = rest.find("hl.monitor(") {
        rest = &rest[at + "hl.monitor(".len()..];
        let Some(open) = rest.find('{') else { break };
        rest = &rest[open + 1..];
        let (table, used) = parse_table(rest);
        rest = &rest[used..];
        if let Some(rule) = MonitorRule::from_value(&Value::Object(table)) {
            rules.push(rule);
        }
    }
    rules
}

/// Плоская таблица Lua: `ключ = "строка" | число | слово`. Возвращает и сколько прочитано.
fn parse_table(s: &str) -> (Map<String, Value>, usize) {
    let mut table = Map::new();
    let mut i = 0;
    loop {
        i += s[i..].len() - s[i..].trim_start_matches([' ', '\t', '\n', ',']).len();
        if i >= s.len() || s[i..].starts_with('}') {
            return (table, (i + 1).min(s.len()));
        }
        let Some(eq) = s[i..].find('=') else { return (table, s.len()) };
        let key = s[i..i + eq].trim().to_string();
        i += eq + 1;
        i += s[i..].len() - s[i..].trim_start().len();
        let value = if s[i..].starts_with('"') {
            // конец строки: кавычка без обратной косой черты перед ней
            let mut end = None;
            let mut escaped = false;
            for (n, c) in s[i + 1..].char_indices() {
                match c {
                    '"' if !escaped => {
                        end = Some(i + 1 + n);
                        break;
                    }
                    '\\' if !escaped => escaped = true,
                    _ => escaped = false,
                }
            }
            let Some(end) = end else { return (table, s.len()) };
            let text = serde_json::from_str(&s[i..=end]).unwrap_or(Value::Null);
            i = end + 1;
            text
        } else {
            let len = s[i..].find([',', '}', '\n']).unwrap_or(s.len() - i);
            let word = s[i..i + len].trim();
            i += len;
            serde_json::from_str(word).unwrap_or_else(|_| Value::String(word.to_string()))
        };
        table.insert(key, value);
    }
}

pub fn transform_from(value: i32) -> Transform {
    match value {
        1 => Transform::_90,
        2 => Transform::_180,
        3 => Transform::_270,
        4 => Transform::Flipped,
        5 => Transform::Flipped90,
        6 => Transform::Flipped180,
        7 => Transform::Flipped270,
        _ => Transform::Normal,
    }
}

pub fn transform_number(transform: Transform) -> i32 {
    (0..8).find(|&n| transform_from(n) == transform).unwrap_or(0)
}

impl Shell {
    pub fn rule_for(&self, output: &Output) -> Option<MonitorRule> {
        let description = output_description(output);
        self.settings.monitors.iter().rev().find(|r| r.matches(&output.name(), &description)).cloned()
    }

    /// Сначала включаем, потом выключаем: в любой момент хоть один экран горит.
    pub fn apply_monitor_rules(&mut self, rules: &[MonitorRule]) -> Result<(), String> {
        let matching = |outputs: Vec<Output>, rule: &MonitorRule| -> Vec<Output> {
            outputs.into_iter().filter(|o| rule.matches(&o.name(), &output_description(o))).collect()
        };
        for rule in rules.iter().filter(|r| !r.disabled) {
            for output in matching(self.disabled_outputs(), rule) {
                self.enable_output(&output, Some(rule))?;
            }
            for output in matching(self.space.outputs().cloned().collect(), rule) {
                self.apply_rule(&output, rule)?;
            }
        }
        for rule in rules.iter().filter(|r| r.disabled) {
            for output in matching(self.space.outputs().cloned().collect(), rule) {
                if self.space.outputs().count() <= 1 {
                    return Err("нельзя выключить последний экран".into());
                }
                self.disable_output(&output)?;
            }
        }
        self.fixup_windows();
        self.schedule_all();
        Ok(())
    }

    /// settings.json поменялся: правила заново, а выключенный экран, для
    /// которого правила больше нет, снова включается.
    pub fn reload_monitors(&mut self) {
        for output in self.disabled_outputs() {
            let rule = self.rule_for(&output);
            if rule.as_ref().is_none_or(|r| !r.disabled) {
                if let Err(e) = self.enable_output(&output, rule.as_ref()) {
                    tracing::warn!(name = output.name(), "{e}");
                }
            }
        }
        let rules = self.settings.monitors.clone();
        if let Err(e) = self.apply_monitor_rules(&rules) {
            tracing::warn!("мониторы: {e}");
        }
    }

    fn apply_rule(&mut self, output: &Output, rule: &MonitorRule) -> Result<(), String> {
        let mode = match rule.mode {
            Some(want) => self.set_output_mode(output, want)?,
            None => None,
        };
        // кадр окна отладки перевёрнут: его поворот менять нельзя
        let transform = rule.transform.filter(|_| self.udev.is_some()).map(transform_from).filter(|t| *t != output.current_transform());
        let scale = rule.scale.filter(|s| (s - output.current_scale().fractional_scale()).abs() > 1e-3);
        let old_loc = self.space.output_geometry(output).map(|g| g.loc).unwrap_or_default();
        let new_loc = rule.position.map(Into::into).filter(|p| *p != old_loc);
        if mode.is_none() && transform.is_none() && scale.is_none() && new_loc.is_none() {
            return Ok(());
        }
        tracing::info!(name = output.name(), ?mode, ?transform, ?scale, ?new_loc, "монитор меняется");

        // окна монитора едут вместе с ним
        let windows: Vec<_> = self.windows.clone().into_iter().filter(|w| self.output_of(w).as_ref() == Some(output)).collect();
        output.change_current_state(mode, transform, scale.map(Scale::Fractional), new_loc);
        if let Some(loc) = new_loc {
            self.space.map_output(output, loc);
            for window in windows {
                let at = self.space.element_location(&window).unwrap_or_else(|| data(&window).loc);
                self.move_window(&window, at + (loc - old_loc));
            }
        }
        self.output_changed(output);
        Ok(())
    }

    /// Размер или место монитора другие: панели и окна на весь экран — заново.
    pub fn output_changed(&mut self, output: &Output) {
        layer_map_for_output(output).arrange();
        self.zones_changed(output);
        let Some(geo) = self.space.output_geometry(output) else { return };
        for window in self.windows.clone() {
            if data(&window).mode == Mode::Fullscreen && self.output_of(&window).as_ref() == Some(output) {
                self.resize_window(&window, geo.size);
                self.move_window(&window, geo.loc);
            }
        }
        self.ipc_event("configreloaded", "");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rules_from_settings() {
        let v = serde_json::json!({
            "match": "desc:MKG MJF24F200", "mode": "1920x1080@200.00", "position": "-1920x0", "scale": 1.25, "transform": 1, "vrr": 0
        });
        let r = MonitorRule::from_value(&v).unwrap();
        assert_eq!(r.mode, Some((1920, 1080, 200.0)));
        assert_eq!(r.position, Some((-1920, 0)));
        assert_eq!((r.scale, r.transform), (Some(1.25), Some(1)));
        assert!(r.matches("HDMI-A-1", "MKG MJF24F200 005TR9QT8YU"));
        assert!(!r.matches("HDMI-A-1", "SAM Other"));

        let auto = MonitorRule::from_value(&serde_json::json!({ "output": "DP-1", "mode": "preferred", "position": "auto", "scale": "auto" })).unwrap();
        assert_eq!((auto.mode, auto.position, auto.scale), (None, None, None));
        assert!(auto.matches("DP-1", "") && !auto.matches("DP-2", ""));
        assert!(MonitorRule::from_value(&serde_json::json!({ "mode": "1x1" })).is_none());
    }

    #[test]
    fn rules_from_lua() {
        let script = "hl.monitor({ output = \"desc:A \\\"B\\\", C\", mode = \"1280x800@60.00\", position = \"10x20\", scale = 1.5, transform = 0, vrr = 0 })\n\
                      hl.config({ misc = { x = 1 } })\n\
                      hl.monitor({ output = \"DP-2\", disabled = true })";
        let rules = parse_lua(script);
        assert_eq!(rules.len(), 2);
        assert_eq!(rules[0].key, "desc:A \"B\", C");
        assert_eq!(rules[0].mode, Some((1280, 800, 60.0)));
        assert_eq!(rules[0].position, Some((10, 20)));
        assert_eq!(rules[0].scale, Some(1.5));
        assert_eq!((rules[1].key.as_str(), rules[1].disabled), ("DP-2", true));
        assert!(parse_lua("hl.config({ render = { cm_auto_hdr = 1 } })").is_empty());
        assert!(parse_lua("hl.monitor({ output = \"обрыв").is_empty());
    }

    #[test]
    fn transforms() {
        for n in 0..8 {
            assert_eq!(transform_number(transform_from(n)), n);
        }
    }
}
