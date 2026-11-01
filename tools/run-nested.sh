#!/usr/bin/env bash
# Vanks Shell в окне отладки внутри текущей сессии.
#
#   tools/run-nested.sh [-c <команда>]       собрать и запустить
#   RUST_LOG=debug tools/run-nested.sh       подробный журнал
#   VANKS_TERMINAL=foot tools/run-nested.sh  другой терминал
#
# Окно открывается в той сессии, что в WAYLAND_DISPLAY (или DISPLAY).
set -eu
cd "$(dirname "$0")/.."
cargo build
exec target/debug/vanks-shell "$@"
