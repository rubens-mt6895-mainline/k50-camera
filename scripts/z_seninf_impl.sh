#!/bin/bash
F=${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/common/v1_1/seninf.c
echo "=== dump + switch implementation ==="
sed -n '40,140p' $F
echo "=== set_cam_mux_for_switch ==="
sed -n '340,420p' $F
