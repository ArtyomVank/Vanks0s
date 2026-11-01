//! `vanks-shell --probe` — что увидит настоящая сессия на этом компьютере,
//! ничего не захватывая: видеокарты (udev), мониторы (sysfs, EDID), доступ
//! к месту и настройки Delta. Можно запускать откуда угодно, хоть из Hyprland.

use std::{fs, path::Path};

use smithay::backend::udev::{all_gpus, primary_gpu};

use crate::{backend, edid, settings::Settings};

pub fn run() {
    let seat = std::env::var("XDG_SEAT").unwrap_or_else(|_| "seat0".into());
    println!("Место: {seat}");

    let primary = primary_gpu(&seat).ok().flatten();
    match all_gpus(&seat) {
        Ok(gpus) if !gpus.is_empty() => {
            for gpu in gpus {
                let mark = if Some(&gpu) == primary.as_ref() { "  ← основная" } else { "" };
                println!("Видеокарта: {} ({}){mark}", gpu.display(), driver(&gpu).unwrap_or_else(|| "драйвер ?".into()));
            }
        }
        Ok(_) => println!("Видеокарт не найдено"),
        Err(e) => println!("Видеокарты не опросились: {e}"),
    }

    let mut connectors: Vec<_> = fs::read_dir("/sys/class/drm")
        .map(|d| d.flatten().map(|e| e.path()).collect())
        .unwrap_or_default();
    connectors.retain(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("card") && n.contains('-')));
    connectors.sort();
    for c in connectors {
        let name = c.file_name().unwrap().to_string_lossy().to_string();
        let status = read(&c.join("status")).unwrap_or_default();
        if status != "connected" {
            println!("  {name}: не подключён");
            continue;
        }
        let who = fs::read(c.join("edid"))
            .ok()
            .and_then(|b| edid::parse(&b))
            .map(|i| format!("{} {}", i.make, i.model))
            .unwrap_or_else(|| "без EDID".into());
        let mode = read(&c.join("modes")).and_then(|m| m.lines().next().map(str::to_string)).unwrap_or_else(|| "?".into());
        println!("  {name}: {who}, {mode}");
    }

    let access = if Path::new("/run/seatd.sock").exists() {
        "seatd"
    } else if Path::new("/run/systemd/seats").exists() {
        "logind"
    } else {
        "нет (ни logind, ни seatd)"
    };
    println!("Доступ к месту (libseat): {access}");
    if backend::inside_session() {
        println!("Сейчас идёт графическая сессия: vanks-shell откроется окном отладки.");
        println!("Настоящая сессия — с текстовой консоли (Ctrl+Alt+F3) или с экрана входа.");
    }

    let input = Settings::load().input;
    println!(
        "Раскладки: {} ({}), повтор {}/{} мс, мышь {:+.2}, тап {}, естественная прокрутка {}",
        input.xkb_layout(),
        input.switch_keys,
        input.repeat_rate,
        input.repeat_delay,
        input.sensitivity,
        yes(input.tap_to_click),
        yes(input.natural_scroll)
    );
}

fn read(p: &Path) -> Option<String> {
    fs::read_to_string(p).ok().map(|s| s.trim().to_string())
}

/// /dev/dri/card1 → драйвер из /sys/class/drm/card1/device/driver
fn driver(dev: &Path) -> Option<String> {
    let name = dev.file_name()?;
    let link = fs::read_link(Path::new("/sys/class/drm").join(name).join("device/driver")).ok()?;
    Some(link.file_name()?.to_string_lossy().into())
}

fn yes(b: bool) -> &'static str {
    if b { "да" } else { "нет" }
}
