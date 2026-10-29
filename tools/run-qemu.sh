#!/usr/bin/env bash
# Vanks OS — запуск собранного ISO в QEMU.
#
#   ./tools/run-qemu.sh                # последний ISO из build/out, UEFI
#   VANKOS_QEMU_MEM=6G ./tools/run-qemu.sh
#   VANKOS_QEMU_BIOS=1 ./tools/run-qemu.sh   # проверить BIOS-загрузку
#
# Требуется: qemu-full (или qemu-desktop + qemu-system-x86) и edk2-ovmf.
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-$(find "${PROJECT_DIR}/build/out" -maxdepth 1 -name '*.iso' -type f | sort | tail -n1)}"
MEM="${VANKOS_QEMU_MEM:-8G}"
CPUS="${VANKOS_QEMU_CPUS:-4}"

[[ -n "${ISO}" && -f "${ISO}" ]] || { echo "ISO не найден: сначала соберите ./build.sh" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "нужен qemu-system-x86_64 (pacman -S qemu-full)" >&2; exit 1; }

echo "ISO: ${ISO}"
echo "RAM: ${MEM} (live-система копируется в память, меньше 6G не хватит)"

# KVM есть не везде: внутри виртуалки без nested virtualization /dev/kvm отсутствует.
accel_args=()
if [[ -w /dev/kvm ]]; then
    accel_args=(-enable-kvm -cpu host)
    echo "ускорение: KVM"
else
    echo "ускорение: нет /dev/kvm — работаем на эмуляции (медленно, но грузится)"
fi

common_args=(
    "${accel_args[@]}" -smp "${CPUS}" -m "${MEM}"
    -cdrom "${ISO}" -boot d
    -device virtio-vga-gl -display gtk,gl=on
    -device qemu-xhci
    -device usb-tablet
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0
)

if [[ "${VANKOS_QEMU_BIOS:-0}" == "1" ]]; then
    echo "прошивка: BIOS (SeaBIOS)"
    exec qemu-system-x86_64 -machine pc "${common_args[@]}"
fi

OVMF_CODE=""
for candidate in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f "${candidate}" ]] && OVMF_CODE="${candidate}" && break
done

[[ -n "${OVMF_CODE}" ]] || {
    echo "не найден OVMF (pacman -S edk2-ovmf). Для BIOS-теста: VANKOS_QEMU_BIOS=1" >&2
    exit 1
}

VARS="${PROJECT_DIR}/build/OVMF_VARS.fd"
if [[ ! -f "${VARS}" ]]; then
    cp "${OVMF_CODE%CODE*}"VARS.*.fd "${VARS}" 2>/dev/null || \
    cp "$(dirname "${OVMF_CODE}")/OVMF_VARS.4m.fd" "${VARS}" 2>/dev/null || true
fi
[[ -f "${VARS}" ]] || { echo "не удалось подготовить OVMF_VARS" >&2; exit 1; }

echo "прошивка: UEFI (${OVMF_CODE})"
exec qemu-system-x86_64 -machine q35 "${common_args[@]}" \
    -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
    -drive if=pflash,format=raw,file="${VARS}"
