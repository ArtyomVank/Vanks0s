//! Правила окон: то же, что в конфиге Delta для Hyprland (hypr/hyprland.lua).

/// Что знаем об окне по его классу.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Rule {
    pub size: Option<(i32, i32)>,
    pub fullscreen: bool,
}

pub fn for_class(class: &str) -> Rule {
    let size = match class {
        "delta-settings" | "calamares" | "io.calamares.calamares" => Some((1100, 720)),
        "delta-welcome" => Some((1000, 680)),
        "delta-exe" => Some((600, 600)),
        "delta-exe-manager" => Some((1000, 720)),
        "delta-box" => Some((960, 680)),
        "delta-store" => Some((1120, 760)),
        "delta-phone" => Some((900, 640)),
        _ => None,
    };
    // CS2 без рамки: всегда настоящий весь экран, иначе останутся обои и ожидание монитора
    Rule { size, fullscreen: class == "cs2" }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rules() {
        assert_eq!(for_class("delta-settings").size, Some((1100, 720)));
        assert!(for_class("cs2").fullscreen);
        assert_eq!(for_class("firefox"), Rule::default());
    }
}
