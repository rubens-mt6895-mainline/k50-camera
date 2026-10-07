#!/bin/sh
# zz_pak2.sh - find the (pak_dbl, FMT_SEL.TG1_SW) combination that BOTH completes the
# frame AND packs correctly.  Ground truth = sensor test pattern (500-px black/white
# bars) whose correct RAW10 packing gives a byte histogram of ~50% 0xff / 50% 0x00.
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

hist() {
  dd if=$IF bs=20000 count=1 2>/dev/null | od -An -tx1 -v | tr -s ' ' '\n' \
    | grep -v '^$' | sort | uniq -c | sort -rn | head -4 | tr '\n' '/'
}

try() {
  dbl=$1; ps=$2; fs=$3; tag=$4
  rmmod cam_cap 2>/dev/null; sleep 1
  insmod /root/cam_cap.ko dbl_data_bus=$dbl pak_dbl=$ps fmt_sel=$fs 2>&1
  sleep 1
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 3000 5000 3000 5000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 2
  printf "%-30s %s\n" "$tag" "$(grep -E 'last_result|frame_ready' /proc/camcap_info | tr -d '\n')"
  nz=$(dd if=$IF bs=1M count=16 2>/dev/null | od -An -tx1 -v | tr -s ' ' '\n' | grep -vc '^00$')
  printf "   nonzero-bytes(first 16M)=%s\n" "$nz"
  printf "   hist20k: %s\n" "$(hist)"
}

echo "===== TPG ON (100% pattern) ====="
$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1
try 1 0 0    "dbl=1 pak_dbl=0 fs=0x00"
try 1 3 0    "dbl=1 pak_dbl=3 fs=0x00"
try 1 3 0x61 "dbl=1 pak_dbl=3 fs=0x61"
try 1 2 0x41 "dbl=1 pak_dbl=2 fs=0x41"
try 1 1 0x21 "dbl=1 pak_dbl=1 fs=0x21"

echo "===== TPG OFF (real scene) with the best candidate ====="
$I2C w3@0x10 0x06 0x01 0x00 >/dev/null 2>&1; sleep 1
try 1 3 0x61 "dbl=1 pak_dbl=3 fs=0x61 scene"
echo "--- done"
