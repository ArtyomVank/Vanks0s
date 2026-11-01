#!/usr/bin/env bash
# композитор Delta в окне отладки внутри текущей сессии.
#
#   tools/run-nested.sh [-c <команда>]       собрать и запустить
#   RUST_LOG=debug tools/run-nested.sh       подробный журнал
#   DELTA_TERMINAL=foot tools/run-nested.sh  другой терминал
#
# Окно открывается в той сессии, что в WAYLAND_DISPLAY (или DISPLAY).
# Настоящая сессия — с консоли или экрана входа, см. docs/TESTING.md.
set -eu
cd "$(dirname "$0")/.."
cargo build
exec target/debug/delta-compositor --backend winit "$@"
