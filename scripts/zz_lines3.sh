#!/bin/sh
# zz_lines3.sh - with pak_dbl=0 (PROVEN correct 4px/5B packing: pure ff/00 TPG bytes)
# find the frame geometry that lets the TG COMPLETE.  Probes a few buffer offsets to
# locate the extent without streaming all 16 MB through od.
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

probe() {
  dd if=$IF bs=1 skip=$1 count=2000 2>/dev/null | od -An -tx1 -v | tr -d ' \n' | tr -d '0' | wc -c
}

try() {
  tag=$1; pe=$2; le=$3; xs=$4; ys=$5; st=$6
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 $pe 0 $le $xs $ys $st" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  printf "%-42s %s\n" "$tag" "$(grep -E 'last_result|frame_ready' /proc/camcap_info | tr -d '\n')"
  printf "   nz@1k=%s nz@3.74M=%s nz@3.76M=%s nz@7.49M=%s nz@7.51M=%s nz@10M=%s nz@14.99M=%s\n" \
     "$(probe 1000)" "$(probe 3749000)" "$(probe 3751000)" "$(probe 7499000)" \
     "$(probe 7501000)" "$(probe 10000000)" "$(probe 14999000)"
}

echo "=== load pak_dbl=0 dbl_data_bus=1 ==="
rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>&1
sleep 1
grep -E 'buffer_phys|iova_mapped|mapping' /proc/camcap_info

echo "=== TPG ON ==="
$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1

try "x=5000 y=3000 (baseline)"        4000 3000 5000 3000 5000
try "x=5000 y=1500"                   4000 1500 5000 1500 5000
try "x=5000 y=3000 lin_end=1500"      4000 1500 5000 3000 5000
try "x=2500 y=1500"                   2000 1500 2500 1500 2500
try "x=5000 y=2999 lin_end=2999"      4000 2999 5000 2999 5000
try "x=5000 y=2000"                   4000 2000 5000 2000 5000

echo "=== CAMSV readback after x=5000 y=1500 ==="
echo "cfg 1 0 4000 0 1500 5000 1500 5000" > $IF 2>/dev/null
sed -n '1,80p' /proc/camcap | grep -iE 'PAK|FMT_SEL|GRAB|XSIZE|YSIZE|STRIDE|VF_CON|MODULE_EN' | head -20
echo "--- done"
