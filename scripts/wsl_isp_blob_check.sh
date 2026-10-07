#!/bin/bash
# wsl_isp_blob_check.sh - is the extracted vendor ISP module usable at all?
R=${K50_REPO}/isp71_ref
cd "$R" || exit 1
for f in mtk-cam-isp.ko mtk-cam-plat-mt6895.ko; do
  echo "=================== $f ==================="
  file "$f" 2>/dev/null
  echo "--- elf header ---"
  readelf -h "$f" 2>&1 | sed -n '1,12p'
  echo "--- .text/.modinfo sizes ---"
  readelf -S "$f" 2>&1 | grep -E '\.text|\.modinfo|\.rodata' | head -8
  echo "--- vermagic ---"
  strings "$f" 2>/dev/null | grep -a '^vermagic=' | head -3
  echo "--- undefined symbols count ---"
  readelf -sW "$f" 2>&1 | awk '$7=="UND" && $8!="" {c++} END {print "UND="c+0}'
  echo "--- defined funcs count ---"
  readelf -sW "$f" 2>&1 | awk '$4=="FUNC" && $7!="UND" && $8!="" {c++} END {print "FUNC="c+0}'
done
