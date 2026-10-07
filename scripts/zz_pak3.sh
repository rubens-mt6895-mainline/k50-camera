#!/bin/sh
# zz_pak3.sh - PAK_DBL=3 keeps every sensor line (proven by TPG even/odd row alternation)
# but the pixel format is wrong.  The vendor's cal_cfg_info stores 0x380/0x381/0x382/0x38F.
# Sweep PAK_MODE x PAK_DBL and look for the TPG histogram that is PURE ff/00 (that is what
# the known-good pak_dbl=0 capture produced = correct 4px/5B RAW10).
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

hist() {
  dd if=$IF bs=20000 count=1 2>/dev/null | od -An -tx1 -v | tr -s ' ' '\n' \
    | grep -v '^$' | sort | uniq -c | sort -rn | head -4 | tr '\n' '/'
}

try() {
  pm=$1; pd=$2
  rmmod cam_cap 2>/dev/null; sleep 1
  insmod /root/cam_cap.ko dbl_data_bus=1 pak_mode=$pm pak_dbl=$pd 2>&1
  sleep 1
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 3000 5000 3000 5000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  printf "pak_mode=%-4s dbl=%s  %-34s\n" "$pm" "$pd" \
      "$(grep -E 'last_result|frame_ready' /proc/camcap_info | tr -d '\n')"
  printf "    nz16M=%-9s hist20k: %s\n" \
      "$(dd if=$IF bs=1M count=16 2>/dev/null | tr -d '\000' | wc -c)" \
      "$(hist)"
}

$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1   # TPG on
try 0x81 3
try 0x8f 3
try 0x8f 0
try 0x80 3
try 0x82 3
try 0x83 3
try 0x8b 3
try 0x87 3
echo "--- done"
