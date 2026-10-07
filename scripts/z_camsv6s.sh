#!/bin/bash
F=${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/isp6s/seninf/seninf_impl.c
echo "=== CAMSV / sv related funcs ==="
grep -n -iE "camsv|sv_tg|camsv_tg|sv_enable|sv_start|TG_SEN|sen_mode" "$F" 2>/dev/null | head -30
echo "=== file size ==="
wc -l "$F" 2>/dev/null
echo "=== whole camsv block (context) ==="
grep -n -B2 -A12 -iE "camsv_tg|camsv.*cfg|camsv.*init" "$F" 2>/dev/null | head -60
