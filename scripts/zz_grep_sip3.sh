#!/bin/bash
K=${KDIR}
echo "=== mtk-smi.c 745..800 ==="
sed -n '745,800p' $K/drivers/memory/mtk-smi.c
echo
echo "=== all flags_general occurrences with context ==="
grep -n "flags_general\|static const struct mtk_smi_plat_data\|MTK_SMI_FLAG_" $K/drivers/memory/mtk-smi.c | sed -n '1,80p'
