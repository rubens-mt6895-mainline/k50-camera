#!/bin/bash
echo "=== find seninf_impl.c ==="
find ${HOME}/fp_work/cam -name "seninf_impl.c" 2>/dev/null
F=$(find ${HOME}/fp_work/cam -name "seninf_impl.c" 2>/dev/null | head -1)
echo "file: $F"
echo "=== cam mux EN / enable patterns ==="
grep -n -iE "cam_mux.*en|MUX_EN|mux.*enable|cammux|CAM_MUX" "$F" 2>/dev/null | head -25
echo "=== SENINF_CAM_MUX register defines ==="
grep -n -iE "SENINF_CAM_MUX|CAMMUX" "$F" 2>/dev/null | head -20
