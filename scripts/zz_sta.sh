#!/bin/sh
W=${KDIR}
echo "===== ALL sta_mask values in mtk-scpsys-mt6895.c ====="
grep -n "sta_mask\|\.name = \|ctl_offs" $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c | head -80
echo
echo "===== ctrl_reg (pwr_sta offsets) for mt6895 ====="
grep -n -B4 -A12 "pwr_sta_offs" $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c | head -40
