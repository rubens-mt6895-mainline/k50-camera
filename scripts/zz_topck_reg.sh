#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
W=${KDIR}

echo "===== local: PLL table / apmixed driver in clk-mt6895.c ====="
grep -n "mt6895_plls\|struct mtk_pll_data\|PLL_MAIN\|MAINPLL\|of_device_id\|compatible = \"" $W/drivers/clk/mediatek/clk-mt6895.c | head -30
echo
echo "===== local: apmixed compatible in dt ====="
grep -rn "mediatek,mt6895-apmixedsys\|mediatek,mt6895-topckgen" $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== DEVICE: topckgen CLK_CFG_20 (cam_sel / img1_sel / ipe_sel) ====="
$H 'for a in 0x10000004 0x10000008 0x1000000c 0x100000c0 0x100000c4 0x100000c8 0x10000150 0x10000154 0x10000158 0x10000160 0x10000200 0x10000210; do printf "%08x = %s\n" $a "$(busybox devmem $a 32)"; done'
echo
echo "===== DEVICE: apmixed 0x1000c000 first 0x80 ====="
$H 'for o in 0x0 0x4 0x8 0xc 0x10 0x14 0x18 0x1c 0x20 0x24 0x28 0x2c 0x30 0x34 0x38 0x3c 0x40 0x44 0x48 0x4c 0x50 0x54 0x58 0x5c 0x60 0x64 0x68 0x6c 0x70 0x74 0x78 0x7c; do a=$((0x1000c000+o)); printf "%08x = %s\n" $a "$(busybox devmem $a 32)"; done'
echo
echo "===== DEVICE: clk_summary mainpll/mmpll/univpll chain ====="
$H 'grep -E "mainpll|mmpll|univpll_|apll|tck_26m" /sys/kernel/debug/clk/clk_summary | sed "s/  */ /g" | cut -c1-120 | head -40'
