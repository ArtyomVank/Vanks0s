#!/usr/bin/env bash
# Vanks OS — оболочка, выбранная в Vanks Setup (поле desktop в vankos/choice.json
# на разделе VANKOS или Ventoy), становится выбранной на экране установщика.
set -u

CONF=/etc/calamares/modules/shellchooser.conf
[ -w "${CONF}" ] || exit 0

for dev in /dev/disk/by-label/VANKOS /dev/disk/by-label/Ventoy; do
    [ -b "${dev}" ] || continue
    mnt=$(mktemp -d)
    if mount -o ro "${dev}" "${mnt}" 2>/dev/null; then
        choice=$(sed -n 's/.*"desktop": *"\([a-z-]*\)".*/\1/p' "${mnt}/vankos/choice.json" 2>/dev/null | head -n1)
        umount "${mnt}"
        rmdir "${mnt}"
        case "${choice}" in
            delta|delta-hyprland|gnome)
                sed -i "s/^default: .*/default: ${choice}/" "${CONF}"
                exit 0 ;;
        esac
    else
        rmdir "${mnt}"
    fi
done
exit 0
