#!/bin/bash
# wsl_tree_check.sh - how complete is this mainline tree, and what does the K50
# device tree say about the ISP?
K=${KDIR}
cd "$K" || exit 1

echo "=== git HEAD ==="
git log -1 --format='%H' 2>&1 | head -1
echo "=== media/i2c: file count ==="
ls drivers/media/i2c 2>/dev/null | wc -l
echo "=== media/i2c: sample ==="
ls drivers/media/i2c 2>/dev/null | head -10
echo "=== media/i2c: imx drivers ==="
ls drivers/media/i2c 2>/dev/null | grep -i imx | head
echo "=== media/platform: entries ==="
ls drivers/media/platform 2>/dev/null | wc -l
ls drivers/media/platform 2>/dev/null | head -20
echo "=== v4l2-core: file count ==="
ls drivers/media/v4l2-core 2>/dev/null | wc -l

echo
echo "=== K50 FDT: isp / camsys / cam nodes ==="
grep -nE 'isp|camsys|seninf|camsv' ${K50_REPO}/hyperos_fdt.dts 2>/dev/null | head -50
