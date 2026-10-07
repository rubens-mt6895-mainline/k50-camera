#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
echo "up: $($H uptime)"

echo "===== APMIXED PLL region 0x1000c300-0x1000c360 (univpll/apll1/apll2/mainpll) ====="
$H 'for a in 0x1000c300 0x1000c304 0x1000c308 0x1000c30c 0x1000c310 0x1000c314 0x1000c318 0x1000c320 0x1000c328 0x1000c32c 0x1000c330 0x1000c334 0x1000c338 0x1000c33c 0x1000c340 0x1000c344 0x1000c348 0x1000c34c 0x1000c350 0x1000c354 0x1000c358 0x1000c35c 0x1000c360; do printf "%08x = %s\n" $a "$(busybox devmem $a 32)"; done'
echo
echo "===== HWV block 0x10320000: PLL EN/DONE + CLK_CFG STA (0x1C00+) ====="
$H 'for o in 0x1400 0x1404 0x1408 0x140c 0x1464 0x1468 0x1c00 0x1c04 0x1c30 0x1c34 0x1c38 0x1c3c 0x1c40 0x1c44; do a=$((0x10320000+o)); printf "%08x = %s\n" $a "$(busybox devmem $a 32)"; done'
echo
echo "===== HWV CLK_CFG_20 SET/CLR/STA raw ====="
$H 'for a in 0x10320000 0x10320004 0x10320010 0x10320014 0x10320060 0x10320064 0x10321c30 0x10321c34; do printf "%08x = %s\n" $a "$(busybox devmem $a 32)"; done'
echo
echo "===== clk_summary: mainpll / cam_sel / seninf / cam_m_seninf ====="
$H 'grep -nE "^\s+(mainpll|cam_sel|cam_ck|seninf_sel|seninf_ck|cam_m_seninf_con|cam_m_camsv_con|cam_m_cam_con)" /sys/kernel/debug/clk/clk_summary | cut -c1-130'
echo
echo "===== clk_summary: ALL mainpll* lines with enable counts ====="
$H 'grep -n "mainpll" /sys/kernel/debug/clk/clk_summary | cut -c1-130'
