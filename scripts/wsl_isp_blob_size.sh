#!/bin/bash
# wsl_isp_blob_size.sh - size and shape of the vendor ISP blob
R=${K50_REPO}/isp71_ref
cd "$R" || exit 1
echo "=== section sizes (mtk-cam-isp.ko) ==="
readelf -SW mtk-cam-isp.ko 2>/dev/null | awk '$2 ~ /^\.(text|rodata|data|bss|init|exit|modinfo|rela)/ {print $2, $7}' | head -20
echo "=== relocation section count ==="
readelf -SW mtk-cam-isp.ko 2>/dev/null | grep -c 'RELA'
echo "=== strings that look like ISP firmware / ccu / imgsys ==="
strings mtk-cam-isp.ko 2>/dev/null | grep -aiE 'firmware|\.bin|ccu|ccd|imgsys|tee|secure' | sort -u | head -25
echo
echo "=== depends / srcversion ==="
strings mtk-cam-isp.ko 2>/dev/null | grep -aE '^(depends|srcversion|name|license|alias)=' | head -12
