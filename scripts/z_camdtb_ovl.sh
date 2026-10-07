#!/bin/bash
K=${HOME}/work/mt6895-mainline/linux
cd "$K"
echo "=== camdtb commit overlay.c of_overlay_fdt_apply ==="
git show 0b8dd2e87b3d:drivers/of/overlay.c 2>&1 | sed -n '/^int of_overlay_fdt_apply/,/^}/p' | head -60
echo "=== fdt_check_header usage ==="
git show 0b8dd2e87b3d:drivers/of/overlay.c 2>&1 | grep -n -B2 -A6 "fdt_check_header" | head -30
