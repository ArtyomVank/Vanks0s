//! Настройки. Пока — постоянные значения и переменные окружения; файл
//! настроек (общий с «Настройками» Delta) — в плане, docs/ROADMAP.md.

/// Терминал для Super+Enter и запуска без -c: VANKS_TERMINAL, иначе kitty.
pub fn terminal() -> String {
    std::env::var("VANKS_TERMINAL").unwrap_or_else(|_| "kitty".into())
}

/// Цвет фона, пока нет обоев: тёмный фиолетовый, как акцент Delta по умолчанию.
pub const BACKGROUND: [f32; 4] = [0.07, 0.06, 0.11, 1.0];

/// Новые окна — каскадом от центра, со сдвигом на столько точек.
pub const CASCADE_STEP: i32 = 32;
