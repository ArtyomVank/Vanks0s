//! Vanks Shell — своя графическая оболочка Vanks OS на Wayland.
//!
//! Композитор: протокол Wayland, окна xdg-shell, клавиатура и мышь,
//! перемещение и размер окон, фокус по щелчку. Внутри графической сессии
//! открывается окном отладки (winit), с текстовой консоли или экрана входа —
//! настоящей сессией (DRM/KMS, libinput, libseat). План до 1.0 — docs/ROADMAP.md.
//!
//!     vanks-shell                      окно отладки или настоящая сессия — по месту запуска
//!     vanks-shell -c <команда>         внутри — эта команда, а не терминал
//!     vanks-shell --backend winit|tty  выбрать явно
//!     vanks-shell --probe              видеокарты, мониторы, доступ — ничего не захватывая
//!     vanks-shell --version

#![allow(irrefutable_let_patterns)]

mod backend;
mod config;
mod cursor;
mod dispatch;
mod edid;
mod focus;
mod grabs;
mod handlers;
mod input;
mod ipc;
mod lock;
mod probe;
mod protocols;
mod render;
mod settings;
mod state;
mod workspaces;

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
    let mut kind = backend::Kind::detect();
    while let Some(a) = args.next() {
        match a.as_str() {
            "-c" | "--command" => command = args.next(),
            "--backend" => match args.next().as_deref().and_then(backend::Kind::parse) {
                Some(k) => kind = k,
                None => {
                    eprintln!("vanks-shell: --backend winit или tty");
                    std::process::exit(2);
                }
            },
            "--probe" => {
                probe::run();
                return Ok(());
            }
            "--version" | "-V" => {
                println!("vanks-shell {}", env!("CARGO_PKG_VERSION"));
                return Ok(());
            }
            "-h" | "--help" => {
                println!("vanks-shell [-c <команда>] [--backend winit|tty] [--probe] — композитор Vanks OS");
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

    // видеокарту и ввод уже ведёт другая сессия: захват сломал бы её
    // окну отладки нужна сессия вокруг. Если её сокета нет, наш собственный
    // занял бы то же имя, и оболочка подключилась бы сама к себе и зависла
    if kind == backend::Kind::Winit {
        if let (Some(display), Some(dir)) = (std::env::var_os("WAYLAND_DISPLAY"), std::env::var_os("XDG_RUNTIME_DIR")) {
            if !std::path::Path::new(&dir).join(&display).exists() {
                return Err(format!("нет сессии Wayland «{}», окну отладки негде открыться", display.to_string_lossy()).into());
            }
        }
    }
    if kind == backend::Kind::Udev && backend::inside_session() && std::env::var_os("VANKS_FORCE_TTY").is_none() {
        eprintln!("vanks-shell: уже идёт графическая сессия — настоящая сессия запускается с консоли (Ctrl+Alt+F3).");
        eprintln!("Окно отладки: vanks-shell --backend winit");
        std::process::exit(1);
    }

    let mut event_loop: EventLoop<'static, CalloopData> = EventLoop::try_new()?;
    // kill, выход из системы, Ctrl+C в консоли — штатный выход: сокет убран,
    // видеокарта и консоль возвращены. Раньше всех потоков (EGL, winit):
    // сигналы блокируются в потоке и наследуются новыми
    let signals = calloop::signals::Signals::new(&[calloop::signals::Signal::SIGTERM, calloop::signals::Signal::SIGINT])?;
    event_loop.handle().insert_source(signals, |event, _, data| {
        tracing::info!(signal = ?event.signal(), "выход по сигналу");
        data.state.loop_signal.stop();
    })?;

    let display: Display<Shell> = Display::new()?;
    let display_handle = display.handle();
    let state = Shell::new(&mut event_loop, display);
    let mut data = CalloopData { state, display_handle };
    if let Err(e) = data.state.init_ipc() {
        tracing::warn!("IPC не поднялся — Delta не увидит оболочку: {e}");
    }

    match kind {
        backend::Kind::Winit => backend::winit::init(&mut event_loop, &mut data)?,
        backend::Kind::Udev => backend::udev::init(&mut event_loop, &mut data)?,
    }
    tracing::info!(socket = ?data.state.socket_name, backend = ?kind, "vanks-shell запущен");

    // программы внутри — на нашем сокете, а не на сессии вокруг. Без -c —
    // Delta (или терминал, если Delta нет)
    let nested = std::env::var_os("DELTA_NESTED").is_some() || kind == backend::Kind::Winit;
    let commands = match command {
        Some(c) => vec![c],
        None => config::autostart(nested),
    };
    data.state.start_xwayland(commands);

    // ответы программам — после каждого прохода цикла, а не только с кадром:
    // монитор может спать (или окно отладки быть скрыто), а программы ждут
    event_loop.run(None, &mut data, |data| {
        data.state.space.refresh();
        data.state.popups.cleanup();
        data.state.lock_watchdog();
        data.state.foreign_toplevel_refresh();
        let _ = data.display_handle.flush_clients();
    })?;
    Ok(())
}
