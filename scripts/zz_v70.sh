#!/bin/sh
# v70: corrected port-2 D-PHY triple (vendor mtk_cam_seninf_init_iomem)
# port2: ANA_A=0x11C84000 ANA_B=0x11C85000 DPHY_TOP=0x11C86000
# control: 0x11C8A000 (=port4 per vendor table) keeps being sampled
cp -f ${K50_REPO}/scripts/port2_rx70.py /root/port2_rx70.py
echo "=================== cam_go_v6 ==================="
sh /root/cam_go_v6.sh 2>&1 | tail -14
echo "=================== fp_fast3 (fast sensor table) ==================="
/root/fp_fast3 2>&1 | tail -12
echo "=================== port2_rx70 ==================="
python3 /root/port2_rx70.py 2>&1
