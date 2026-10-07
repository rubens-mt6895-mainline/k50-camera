#!/bin/bash
K=${KDIR}
echo "=== mt6895.dtsi 2440-2660 ==="
sed -n '2440,2660p' $K/arch/arm64/boot/dts/mediatek/mt6895.dtsi
