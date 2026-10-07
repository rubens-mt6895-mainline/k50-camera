#!/bin/sh
# zz_final3.sh - the ONE combination that reports frame_ready=1 AND fills 15 MB (3000 lines):
#   dbl_data_bus=2 (matches 4-lane 4px/clk) + pak_dbl=2 + pak_mode=0x82 + route_pix_mode=2
# Capture TPG-on (known geometry => proves the decode) and TPG-off (real scene).
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 route_pix_mode=2 2>&1
sleep 1

cap() {
  tag=$1
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 3000 5000 3000 5000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  dd if=$IF of=/tmp/g_$tag.bin bs=1M count=16 2>/dev/null
  printf "%-6s %s md5=%s\n" "$tag" \
     "$(grep -E 'frame_ready|last_result' /proc/camcap_info | tr -d '\n')" \
     "$(md5sum /tmp/g_$tag.bin | cut -c1-32)"
}

$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1
cap tpg
$I2C w3@0x10 0x06 0x01 0x00 >/dev/null 2>&1; sleep 1
cap scene
echo "--- done"
