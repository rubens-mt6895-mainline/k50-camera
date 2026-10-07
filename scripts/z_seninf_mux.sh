#!/bin/bash
echo "=== CAM_MUX_EN anywhere in ksrc ==="
grep -rn "CAM_MUX_EN" ${HOME}/fp_work/cam/ksrc 2>/dev/null | head -10
echo "=== 0x410 / mux enable in seninf common ==="
grep -rn -iE "MUX_EN|mux.*en.*0x|CAM_MUX" ${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/common/v1_1/seninf.c ${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/common/v1_1/seninf_drv.h 2>/dev/null | head -20
echo "=== seninf_drv.h cam mux section ==="
grep -n -iE "mux|MUX" ${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/common/v1_1/seninf_drv.h 2>/dev/null | head -40
echo "=== seninf.h mux ==="
grep -n -iE "mux|MUX" ${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/common/v1_1/seninf.h 2>/dev/null | head -40
