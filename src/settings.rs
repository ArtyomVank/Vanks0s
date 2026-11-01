//! Настройки Delta, которые нужны оболочке: тот же `~/.config/delta/settings.json`,
//! что правят «Настройки» Delta. Чего нет у пользователя — берётся из
//! умолчаний Delta (`/usr/share/delta/defaults/settings.json`), а если нет и
//! их — из значений ниже (они совпадают с умолчаниями Delta).

use std::path::PathBuf;

use serde::Deserialize;
use serde_json::Value;

/// Раздел `input`: клавиатура, мышь, тачпад.
#[derive(Debug, Clone, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Input {
    /// раскладки xkb по порядку: ["us", "ru"]
    pub layouts: Vec<String>,
    /// как переключать раскладку — опция xkb, например grp:alt_shift_toggle
    pub switch_keys: String,
    /// повтор нажатий в секунду и задержка перед повтором, мс
    pub repeat_rate: i32,
    pub repeat_delay: i32,
    /// скорость мыши от -1 до 1 (ускорение libinput)
    pub sensitivity: f64,
    pub natural_scroll: bool,
    pub tap_to_click: bool,
}

impl Default for Input {
    fn default() -> Self {
        Self {
            layouts: vec!["us".into(), "ru".into()],
            switch_keys: "grp:alt_shift_toggle".into(),
            repeat_rate: 30,
            repeat_delay: 300,
            sensitivity: 0.0,
            natural_scroll: true,
            tap_to_click: true,
        }
    }
}

impl Input {
    /// Раскладки для xkb через запятую. Как delta-apply: только похожие на
    /// имя раскладки (2–8 латинских букв), пусто — «us».
    pub fn xkb_layout(&self) -> String {
        let ok: Vec<&str> = self
            .layouts
            .iter()
            .map(String::as_str)
            .filter(|l| (2..=8).contains(&l.len()) && l.bytes().all(|b| b.is_ascii_lowercase()))
            .collect();
        if ok.is_empty() { "us".into() } else { ok.join(",") }
    }

    pub fn repeat(&self) -> (i32, i32) {
        (self.repeat_delay.clamp(100, 2000), self.repeat_rate.clamp(1, 100))
    }
}

/// Раздел windows: то, что нужно самому композитору.
#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Windows {
    pub snap: bool,
    #[serde(rename = "gapsOut")]
    pub gaps_out: i32,
}

impl Default for Windows {
    fn default() -> Self {
        Self { snap: true, gaps_out: 14 }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Settings {
    pub input: Input,
    pub windows: Windows,
    pub monitors: Vec<crate::monitors::MonitorRule>,
}

fn data_dir() -> PathBuf {
    std::env::var_os("DELTA_DATA").map(PathBuf::from).unwrap_or_else(|| "/usr/share/delta".into())
}

fn config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .map(|c| c.join("delta"))
}

fn read_json(path: PathBuf) -> Option<Value> {
    let text = std::fs::read_to_string(&path).ok()?;
    match serde_json::from_str(&text) {
        Ok(v) => Some(v),
        Err(e) => {
            tracing::warn!("{}: не читается ({e}), беру умолчания", path.display());
            None
        }
    }
}

/// Пользовательские значения поверх умолчаний — по ключам, как в delta-apply.
fn merge(base: &mut Value, over: Value) {
    match (base, over) {
        (Value::Object(b), Value::Object(o)) => {
            for (k, v) in o {
                merge(b.entry(k).or_insert(Value::Null), v);
            }
        }
        (b, o) => *b = o,
    }
}

fn section<T: serde::de::DeserializeOwned + Default>(merged: &Value, key: &str) -> T {
    merged
        .get(key)
        .cloned()
        .and_then(|v| serde_json::from_value(v).map_err(|e| tracing::warn!("{key}: {e}")).ok())
        .unwrap_or_default()
}

impl Settings {
    pub fn load() -> Self {
        let mut merged = read_json(data_dir().join("defaults/settings.json")).unwrap_or(Value::Null);
        if let Some(user) = config_dir().and_then(|d| read_json(d.join("settings.json"))) {
            merge(&mut merged, user);
        }
        let monitors = merged
            .get("monitors")
            .and_then(Value::as_array)
            .map(|list| list.iter().filter_map(crate::monitors::MonitorRule::from_value).collect())
            .unwrap_or_default();
        Settings { input: section(&merged, "input"), windows: section(&merged, "windows"), monitors }
    }
}
