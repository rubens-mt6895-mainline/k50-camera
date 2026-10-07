#!/bin/bash
K=${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src/isp6s
echo "=== seninf_cfg.h (MIPI config constants) ==="
head -120 "$K/seninf/seninf_cfg.h" 2>/dev/null
echo "=== seninf_impl.c (full 239 lines) ==="
cat "$K/seninf/seninf_impl.c" 2>/dev/null
