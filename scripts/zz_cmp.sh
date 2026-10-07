#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"

echo "===== HyperOS working clk_preview: cam / seninf / lp ====="
grep -nE "cam_m_|cam_lp|seninf|cam_ck|cam_sel|camtg|cammux|camsv|pda|mraw" \
  ${K50_REPO}/hyperos_workstate/clk_preview.txt | head -70

echo
echo "===== HyperOS clk_preview: lines around cam subtree ====="
awk '/cam_main|cam_m_/{f=1} f&&c<50{print NR": "$0; c++}' \
  ${K50_REPO}/hyperos_workstate/clk_preview.txt | head -50

echo
echo "===== device: cam_main syscon 0x1a000000..0x3C (hex offsets) ====="
$H 'for o in 0x0 0x4 0x8 0xc 0x10 0x14 0x18 0x1c 0x20 0x24 0x28 0x2c 0x30 0x34 0x38 0x3c; do a=$((0x1a000000+o)); printf "%08x = %s\n" $a "$(busybox devmem $a 32)"; done'

echo
echo "===== device: all cam_m_* gates Y/N ====="
$H 'grep -E "cam_m_" /sys/kernel/debug/clk/clk_summary | sed "s/  */ /g" | cut -c1-150'
