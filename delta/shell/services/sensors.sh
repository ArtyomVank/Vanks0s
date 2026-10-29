#!/bin/sh
# Delta — однократный поиск датчиков для services/SystemStats.qml.
# Печатает строки «ключ=значение»; дальше оболочка сама читает найденные
# файлы /sys раз в секунду, без запуска процессов.
#
#   cputemp=  файл температуры процессора (k10temp / zenpower / coretemp)
#   cpuname=  модель процессора
#   gpu=      amd | nvidia | intel
#   gpubusy=  загрузка AMD (gpu_busy_percent)
#   gputemp=  температура видеокарты из hwmon
#   vramused= / vramtotal=  видеопамять AMD
#   nvsmi=1   есть nvidia-smi
#   gpuname=  модель видеокарты (если удалось узнать без lspci)

# hwmon: temp*_input с нужной подписью, иначе temp1_input
pick_temp() {
    dir=$1; shift
    for want in "$@"; do
        for l in "$dir"/temp*_label; do
            [ -r "$l" ] || continue
            case "$(cat "$l" 2>/dev/null)" in
                "$want"*) f=${l%_label}_input; [ -r "$f" ] && { echo "$f"; return 0; } ;;
            esac
        done
    done
    [ -r "$dir/temp1_input" ] && { echo "$dir/temp1_input"; return 0; }
    return 1
}

for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    case "$(cat "$h/name")" in
        k10temp|zenpower) t=$(pick_temp "$h" Tctl Tdie) && { echo "cputemp=$t"; break; } ;;
        coretemp)         t=$(pick_temp "$h" "Package id" "Physical id") && { echo "cputemp=$t"; break; } ;;
    esac
done

name=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n1)
[ -n "$name" ] && echo "cpuname=$name"

# видеокарта: дискретная (AMD/NVIDIA) важнее встроенной Intel
intel=""
for c in /sys/class/drm/card[0-9]; do
    d=$c/device
    [ -r "$d/vendor" ] || continue
    case "$(cat "$d/vendor")" in
        0x1002)
            echo "gpu=amd"
            [ -r "$d/gpu_busy_percent" ] && echo "gpubusy=$d/gpu_busy_percent"
            [ -r "$d/mem_info_vram_used" ] && echo "vramused=$d/mem_info_vram_used"
            [ -r "$d/mem_info_vram_total" ] && echo "vramtotal=$d/mem_info_vram_total"
            for h in "$d"/hwmon/hwmon*; do
                t=$(pick_temp "$h" edge junction) && { echo "gputemp=$t"; break; }
            done
            intel=""; found=1; break ;;
        0x10de)
            echo "gpu=nvidia"
            if command -v nvidia-smi >/dev/null 2>&1; then
                echo "nvsmi=1"
                n=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
                [ -n "$n" ] && echo "gpuname=$n"
            fi
            intel=""; found=1; break ;;
        0x8086) [ -z "$intel" ] && intel=$d ;;
    esac
done
if [ -z "${found:-}" ] && [ -n "$intel" ]; then
    echo "gpu=intel"
    for h in "$intel"/hwmon/hwmon*; do
        t=$(pick_temp "$h" pkg gt) && { echo "gputemp=$t"; break; }
    done
fi
exit 0
