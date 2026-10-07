#!/bin/sh
# zz_final2.sh - pak_mode=0x80 + pak_dbl=3 gave a PURE ff/00 histogram (correct RAW10 packing)
# AND frame_ready=1.  Capture real scene frames with that combination.
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_mode=0x80 pak_dbl=3 2>&1
sleep 1
grep -E 'buffer_phys|buffer_dma|mapping' /proc/camcap_info

cap() {  # cap <tag>
  tag=$1
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 3000 5000 3000 5000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  dd if=$IF of=/tmp/f2_$tag.bin bs=1M count=16 2>/dev/null
  printf "%-8s %s nz=%s md5=%s\n" "$tag" \
     "$(grep -E 'frame_ready|last_result' /proc/camcap_info | tr -d '\n')" \
     "$(dd if=/tmp/f2_$tag.bin bs=1M count=16 2>/dev/null | tr -d '\000' | wc -c)" \
     "$(md5sum /tmp/f2_$tag.bin | cut -c1-32)"
  dd if=/tmp/f2_$tag.bin bs=20000 count=1 2>/dev/null | od -An -tx1 -v \
     | tr -s ' ' '\n' | grep -v '^$' | sort | uniq -c | sort -rn | head -4 | tr '\n' '/'
  echo
}

$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1   # TPG on
cap tpg
$I2C w3@0x10 0x06 0x01 0x00 >/dev/null 2>&1; sleep 1   # TPG off
cap scene
$I2C w2@0x10 0x02 0x04 >/dev/null 2>&1; $I2C w3@0x10 0x02 0x04 0xf0 >/dev/null 2>&1
$I2C w3@0x10 0x02 0x0e 0x02 >/dev/null 2>&1; $I2C w3@0x10 0x02 0x0f 0x00 >/dev/null 2>&1
sleep 1
cap bright
echo "--- done"
