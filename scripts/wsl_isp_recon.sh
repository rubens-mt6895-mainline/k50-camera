#!/bin/bash
# wsl_isp_recon.sh - what ISP support exists in this mainline tree?
K=${KDIR}
cd "$K" || exit 1

echo "=== drivers/media/platform/mediatek ==="
ls drivers/media/platform/mediatek/ 2>&1

echo "=== any isp-looking directories/files ==="
find drivers/media -iname '*isp*' | head -40

echo "=== config symbols mentioning ISP ==="
grep -nE 'CONFIG_.*ISP' .config | head -20

echo "=== machine compatibles for mediatek isp ==="
grep -rn 'mediatek,mt[0-9]*-isp' --include='*.c' --include='*.yaml' --include='*.dtsi' . 2>/dev/null | head -20

echo "=== seninf / camsv drivers in tree ==="
grep -rln 'seninf\|camsv' --include='*.c' --include='*.h' drivers/media drivers/staging 2>/dev/null | head -20

echo "=== imx582 / imx586 sensor drivers ==="
ls drivers/media/i2c/ | grep -iE 'imx5|imx6' | head

echo "=== camisp / mdp / mdp3 present? ==="
ls drivers/media/platform/mediatek/*/ -d 2>/dev/null
