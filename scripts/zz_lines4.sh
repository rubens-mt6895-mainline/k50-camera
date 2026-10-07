#!/bin/sh
# zz_lines4.sh - is the "half frame" limit really ysize/2?  If so, ys=6000 -> a full
# 3000-line frame.  pak_dbl=0 (PROVEN correct packing), TPG ON (deterministic bytes).
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
  sleep 4
  printf "%-30s %s\n" "$tag" "$(grep -E 'last_result|frame_ready' /proc/camcap_info | tr -d '\n')"
  printf "   nz: 1k=%s 3.7M=%s 7.4M=%s 7.6M=%s 11.2M=%s 14.9M=%s 15.1M=%s 16.7M=%s\n" \
     "$(probe 1000)" "$(probe 3749000)" "$(probe 7490000)" "$(probe 7501000)" \
     "$(probe 11240000)" "$(probe 14990000)" "$(probe 15011000)" "$(probe 16770000)"
}

rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>&1
sleep 1
$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1   # TPG on

try "ys=3000"  4000 3000 5000 3000 5000
try "ys=6000"  4000 6000 5000 6000 5000
try "ys=12000" 4000 12000 5000 12000 5000
try "ys=6000 xs=10000" 4000 6000 10000 6000 10000
echo "--- done"
