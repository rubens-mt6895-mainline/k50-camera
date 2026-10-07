#!/system/bin/sh
# Dump the *working* camera state on HyperOS (root) so it can be replayed on
# mainline.  Run this WHILE THE CAMERA APP IS IN PREVIEW.
#
#   adb push cam_dump_hyperos.sh /data/local/tmp/
#   adb shell chmod 755 /data/local/tmp/cam_dump_hyperos.sh
#   adb shell /data/local/tmp/cam_dump_hyperos.sh > dump.txt
#
OUT=${1:-/data/local/tmp/cam_dump.txt}

say() { echo; echo "########## $* ##########"; }

say "HEADER $(date)"
echo "kernel: $(uname -r)"
echo "model : $(getprop ro.product.model)"
echo "build : $(getprop ro.build.version.release) $(getprop ro.build.display.id 2>/dev/null)"
echo "selinux: $(getenforce 2>/dev/null)"

say "CAMERA MODULES"
lsmod 2>/dev/null | grep -iE 'cam|seninf|imgsensor|eeprom'

say "CAMERA PROCESSES"
ps -A 2>/dev/null | grep -iE 'camera|cam_' | head -20

say "MTK_CAM_DBG TREE (per context: ctrl=write-only, data=read)"
for d in /sys/kernel/debug/mtk_cam_dbg/*/; do
  n=$(basename "$d")
  sz=$(wc -c < "$d/data" 2>/dev/null)
  echo "--- ctx $n (data bytes=${sz:-?}) ---"
  cat "$d/data" 2>/dev/null | head -80
done

say "MTK_CAM_EXP_DUMP"
cat /sys/kernel/debug/mtk_cam_exp_dump 2>/dev/null | head -60

say "CLOCK SUMMARY (camera clocks)"
cat /sys/kernel/debug/clk/clk_summary 2>/dev/null \
  | grep -iE 'camtg|seninf|cam|clk_summary|\||enable' | head -80

say "GPIO (camera-related)"
cat /sys/kernel/debug/gpio 2>/dev/null \
  | grep -iE 'cam|vcam|avdd|dvdd|afvdd|rst|mclk|pwr' | head -40

say "PINMUX for cam0 pinctrl group"
for f in /sys/kernel/debug/pinctrl/*/pinmux-pins; do
  echo "--- $f ---"
  cat "$f" 2>/dev/null | grep -iE 'cam|MCLK|RST|AVDD|DVDD' | head -30
done

say "REGULATORS (camera supplies)"
for r in /sys/class/regulator/regulator.*/; do
  n=$(cat "$r/name" 2>/dev/null)
  case "$n" in
    *cam*|*fan53870*|*vcam*|*avdd*|*dvdd*|*afvdd*|*ldo*)
      echo "$n: $(cat $r/state 2>/dev/null) $(cat $r/microvolts 2>/dev/null)" ;;
  esac
done 2>/dev/null

say "FAN53870 raw (i2c-? @0x35)"
for b in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if [ -e "/dev/i2c-$b" ]; then
    v=$(i2cdump -y -f "$b" 0x35 2>/dev/null | head -8)
    if [ -n "$v" ]; then echo "--- i2c-$b ---"; echo "$v"; fi
  fi
done

say "SENSOR I2C probe (IMX582 @0x10 / 0x1a)"
for b in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
  if [ -e "/dev/i2c-$b" ]; then
    r=$(i2cdetect -y -r "$b" 2>/dev/null | sed -n '2,12p')
    if echo "$r" | grep -qE '10|1a'; then
      echo "--- i2c-$b has sensor ---"; echo "$r"
    fi
  fi
done

say "V4L2 DEVICES"
ls -l /dev/video* 2>/dev/null | head -20
for v in /dev/video*; do
  n=${v#/dev/video}
  echo "video$n: $(cat /sys/class/video4linux/video$n/name 2>/dev/null)"
done 2>/dev/null

say "MEDIA / SENINF NODES"
ls -l /dev/seninf* /dev/camsv* /dev/media* 2>/dev/null | head -20

say "DMESG (camera-related, last 80)"
dmesg 2>/dev/null | grep -iE 'seninf|csi2|dphy|cammux|imgsensor|imx582|cam_' | tail -80

say "DUMP COMPLETE $(date)"
echo "wrote: $OUT"
