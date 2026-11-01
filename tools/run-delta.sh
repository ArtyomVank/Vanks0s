#!/usr/bin/env bash
# Delta поверх Vanks Shell в окне отладки — без установки, прямо из
# исходников Delta рядом (../vankos/delta):
#
#   tools/run-delta.sh               собрать и запустить в окне отладки
#   tools/run-delta.sh --tty         настоящая сессия: только с текстовой консоли
#   DELTA_SRC=/путь/к/vankos tools/run-delta.sh
#
# Своя папка HOME (build/delta-home) и своя шина D-Bus: настройки,
# уведомления и плееры настоящей сессии не трогаются.
set -eu
cd "$(dirname "$0")/.."
src=$(realpath "${DELTA_SRC:-../vankos}")
[ -d "${src}/delta/shell" ] || { echo "нет исходников Delta в ${src}" >&2; exit 1; }
backend=winit
if [ "${1:-}" = --tty ]; then
    backend=tty
    shift
fi
cargo build
mkdir -p build/delta-home
export HOME=${PWD}/build/delta-home
export DELTA_NESTED=1 DELTA_DATA=${src}/delta DELTA_WALLPAPERS=${src}/wallpapers
export PATH=${src}/delta/bin:${PATH}
# XDG_*_HOME вели бы в настоящий ~/.config — пусть берутся от HOME
unset DISPLAY XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
exec dbus-run-session -- "${PWD}/target/debug/vanks-shell" --backend "${backend}" "$@"
