//! Vanks Shell — своя графическая оболочка Vanks OS на Wayland.
//!
//! Сейчас это фундамент композитора: протокол Wayland, окна xdg-shell,
//! клавиатура и мышь, перемещение и изменение размера окон, фокус по щелчку.
//! Запускается окном внутри текущей сессии (бэкенд winit) — так его удобно
//! отлаживать, не выходя из Hyprland. Вход в настоящую сессию (DRM, libinput)
//! и всё, что нужно до 1.0, — в docs/ROADMAP.md.
//!
//!     vanks-shell                  окно отладки, внутри — терминал
//!     vanks-shell -c <команда>     окно отладки, внутри — эта команда
//!     vanks-shell --version

#![allow(irrefutable_let_patterns)]

mod backend;
mod config;
mod grabs;
mod handlers;
mod input;
mod state;

use smithay::reexports::{
    calloop::EventLoop,
    wayland_server::{Display, DisplayHandle},
};
pub use state::Shell;

/// Состояние, которое цикл событий передаёт каждому обработчику.
pub struct CalloopData {
    pub state: Shell,
    pub display_handle: DisplayHandle,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let mut command: Option<String> = None;
    while let Some(a) = args.next() {
        match a.as_str() {
            "-c" | "--command" => command = args.next(),
            "--version" | "-V" => {
                println!("vanks-shell {}", env!("CARGO_PKG_VERSION"));
                return Ok(());
            }
            "-h" | "--help" => {
                println!("vanks-shell [-c <команда>] — композитор Vanks OS в окне отладки");
                return Ok(());
            }
            other => {
                eprintln!("vanks-shell: неизвестный ключ {other}");
                std::process::exit(2);
            }
        }
    }

    if let Ok(env_filter) = tracing_subscriber::EnvFilter::try_from_default_env() {
        tracing_subscriber::fmt().with_env_filter(env_filter).init();
    } else {
        // свои события — да, служебные сообщения Smithay — только предупреждения
        tracing_subscriber::fmt().with_env_filter("vanks_shell=info,smithay=warn").init();
    }

    let mut event_loop: EventLoop<CalloopData> = EventLoop::try_new()?;
    let display: Display<Shell> = Display::new()?;
    let display_handle = display.handle();
    let state = Shell::new(&mut event_loop, display);
    let mut data = CalloopData { state, display_handle };

    backend::winit::init(&mut event_loop, &mut data)?;
    tracing::info!(socket = ?data.state.socket_name, "vanks-shell запущен");

    // программы внутри — на нашем сокете, а не на сессии вокруг
    let command = command.unwrap_or_else(|| config::terminal());
    data.state.spawn(&command);

    event_loop.run(None, &mut data, |_| {})?;
    Ok(())
}
