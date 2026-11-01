//! Прилипание окна к краю, как в Delta на Hyprland: курсор у левого или правого
//! края — половина экрана, у угла — четверть, у верхнего — весь экран. Подсветку
//! рисует Delta (Snap.qml), а о перетаскивании узнаёт из delta-drag.json.

use smithay::{
    output::Output,
    utils::{Logical, Point, Rectangle},
};

use crate::{workspaces::data, Shell};

/// Зона: имя для Delta и место окна.
#[derive(Debug, Clone, PartialEq)]
pub struct Zone {
    pub name: &'static str,
    pub rect: Rectangle<i32, Logical>,
}

/// Зона под курсором. monitor — весь монитор, area — без панелей, g — отступ.
pub fn zone_at(monitor: Rectangle<i32, Logical>, area: Rectangle<i32, Logical>, p: Point<f64, Logical>, g: i32) -> Option<Zone> {
    const EDGE: f64 = 14.0;
    let (mx, my, mw, mh) = (monitor.loc.x as f64, monitor.loc.y as f64, monitor.size.w as f64, monitor.size.h as f64);
    let corner = (mh * 0.18).max(100.0);
    let left = p.x - mx <= EDGE;
    let right = mx + mw - p.x <= EDGE;
    let top = p.y - my <= EDGE;

    let name = if left || right {
        if p.y - my < corner {
            if left { "tl" } else { "tr" }
        } else if my + mh - p.y < corner {
            if left { "bl" } else { "br" }
        } else if left {
            "left"
        } else {
            "right"
        }
    } else if top {
        "max"
    } else {
        return None;
    };

    let (ax, ay, aw, ah) = (area.loc.x, area.loc.y, area.size.w, area.size.h);
    let (hw, hh) = ((aw - 3 * g) / 2, (ah - 3 * g) / 2);
    let (lx, rx) = (ax + g, ax + 2 * g + hw);
    let (ty, by) = (ay + g, ay + 2 * g + hh);
    let (x, y, w, h) = match name {
        "left" => (lx, ty, hw, ah - 2 * g),
        "right" => (rx, ty, hw, ah - 2 * g),
        "tl" => (lx, ty, hw, hh),
        "tr" => (rx, ty, hw, hh),
        "bl" => (lx, by, hw, hh),
        "br" => (rx, by, hw, hh),
        _ => (ax + g, ay + g, aw - 2 * g, ah - 2 * g),
    };
    Some(Zone { name, rect: Rectangle::new((x, y).into(), (w, h).into()) })
}

impl Shell {
    /// Зона под точкой на её мониторе. Зовётся и из захвата мыши, поэтому саму
    /// мышь здесь не спрашиваем: она заперта на время захвата.
    pub fn snap_zone(&self, p: Point<f64, Logical>) -> (Option<Output>, Option<Zone>) {
        let Some(output) = self.space.output_under(p).next().cloned() else { return (None, None) };
        if !self.settings.windows.snap {
            return (Some(output), None);
        }
        let Some(monitor) = self.space.output_geometry(&output) else { return (Some(output), None) };
        let zone = zone_at(monitor, self.usable_area(&output), p, self.settings.windows.gaps_out.clamp(0, 60));
        (Some(output), zone)
    }

    /// Состояние перетаскивания — в delta-drag.json, как его писал hyprland.lua.
    pub fn write_drag(&mut self, state: &str, window: &smithay::desktop::Window, monitor: &str, grip: Point<i32, Logical>, zone: Option<&Zone>) {
        let Some(dir) = self.ipc.as_ref().map(|i| i.dir.clone()) else { return };
        self.drag_seq += 1;
        let at = self.space.element_location(window).unwrap_or_default();
        let size = window.geometry().size;
        let rect = zone.map(|z| z.rect).unwrap_or_default();
        let line = serde_json::json!({
            "seq": self.drag_seq,
            "state": state,
            "address": format!("0x{:x}", data(window).address),
            "monitor": monitor,
            "x": at.x, "y": at.y, "w": size.w, "h": size.h,
            "gx": grip.x, "gy": grip.y,
            "zone": zone.map(|z| z.name).unwrap_or(""),
            "zx": rect.loc.x, "zy": rect.loc.y, "zw": rect.size.w, "zh": rect.size.h,
        });
        if let Err(e) = std::fs::write(dir.join("delta-drag.json"), format!("{line}\n")) {
            tracing::debug!("delta-drag.json: {e}");
        }
    }

    /// Отпустили окно: зона есть — занимает её, прежний размер запоминается.
    pub fn finish_drag(&mut self, window: &smithay::desktop::Window, monitor: &str, grip: Point<i32, Logical>, zone: Option<Zone>) {
        self.write_drag("end", window, monitor, grip, zone.as_ref());
        let Some(zone) = zone else { return };
        if zone.name == "max" {
            self.set_mode(window, crate::workspaces::Mode::Maximized);
            return;
        }
        let loc = self.space.element_location(window).unwrap_or_default();
        self.fx_geometry_from(window, Rectangle::new(loc, window.geometry().size));
        data(window).snapped = Some(window.geometry().size);
        self.resize_window(window, zone.rect.size);
        self.move_window(window, zone.rect.loc);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(x: i32, y: i32, w: i32, h: i32) -> Rectangle<i32, Logical> {
        Rectangle::new((x, y).into(), (w, h).into())
    }

    #[test]
    fn zones() {
        let m = r(0, 0, 1920, 1080);
        let a = r(0, 58, 1920, 1022);
        let z = |x: f64, y: f64| zone_at(m, a, (x, y).into(), 14);
        assert_eq!(z(900.0, 500.0), None);
        assert_eq!(z(900.0, 1079.0), None);
        assert_eq!(z(900.0, 3.0).unwrap().name, "max");
        let left = z(3.0, 500.0).unwrap();
        assert_eq!((left.name, left.rect), ("left", r(14, 72, 939, 994)));
        let right = z(1919.0, 500.0).unwrap();
        assert_eq!((right.name, right.rect), ("right", r(967, 72, 939, 994)));
        assert_eq!(z(3.0, 50.0).unwrap().name, "tl");
        assert_eq!(z(1919.0, 1070.0).unwrap().name, "br");
        // второй монитор справа
        let m2 = r(1920, 0, 1920, 1080);
        assert_eq!(zone_at(m2, m2, (1925.0, 500.0).into(), 0).unwrap().name, "left");
    }
}
