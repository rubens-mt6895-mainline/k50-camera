#!/bin/bash
# wsl_isp_syms.sh - what does the extracted vendor ISP blob actually need?
R=${K50_REPO}/isp71_ref
S=${KDIR}/Module.symvers
cd "$R" || exit 1

readelf -sW mtk-cam-isp.ko | awk '$7=="UND" && $8!="" {print $8}' | sed 's/@.*//' | sort -u > /tmp/und.txt
echo "=== unique undefined symbols in mtk-cam-isp.ko ==="
wc -l < /tmp/und.txt

echo
echo "=== by prefix ==="
for p in mtk_cam mtk_ imgsys ccu isp_ cam_ v4l2_ vb2_ media_ dma_ devm_ of_ clk_ regmap_ pm_ platform_ kthread_ device_ misc_ debugfs_; do
  c=$(grep -c "^$p" /tmp/und.txt)
  [ "$c" -gt 0 ] && echo "  ${p}*  $c"
done

echo
echo "=== vendor-internal imports (isp/cam/ccu/imgsys/mtk) ==="
grep -E '^(mtk_cam|mtk_|imgsys|ccu|isp|cam_)' /tmp/und.txt | head -50

if [ -f "$S" ]; then
  awk '{print $2}' "$S" | sed 's/@.*//' | sort -u > /tmp/have.txt
  echo
  echo "=== kernel exports really present in mainline (Module.symvers) ==="
  awk '{print $2}' "$S" | sed 's/@.*//' | sort -u | wc -l
  echo "=== satisfiable imports: $(comm -12 /tmp/und.txt /tmp/have.txt | wc -l) / $(wc -l < /tmp/und.txt) ==="
  echo "=== NOT available in mainline (count) ==="
  comm -23 /tmp/und.txt /tmp/have.txt | wc -l
  echo "--- first 60 of them ---"
  comm -23 /tmp/und.txt /tmp/have.txt | head -60
else
  echo "no Module.symvers at $S"
fi
