#!/bin/sh
# zz_final5.sh - FULL FRAME capture.
#   dbl_data_bus=2 + pak_mode=0x82 (12-bit out) + pak_dbl=2 + route_pix_mode=2
#   row = 4000 px * 1.5 B = 6000 bytes ; 3000 rows = 18,000,000 bytes
#   => need frame_bytes=18874368 (module allocates exactly this, CMA pool is 32 MiB)
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 route_pix_mode=2 \
        frame_bytes=18874368 2>&1
sleep 2
grep -E 'buffer_phys|buffer_dma|buffer_size|mapping' /proc/camcap_info

cap() {  # cap <tag> <xsize> <ysize>
  tag=$1; xs=$2; ys=$3
  dd if=/dev/zero of=/dev/mem bs=1M count=18 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 $ys $xs $ys $xs" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 4
  dd if=$IF of=/tmp/h_$tag.bin bs=1M count=19 2>/dev/null
  printf "%-7s %s nz=%s md5=%s\n" "$tag" \
     "$(grep -E 'frame_ready|last_result' /proc/camcap_info | tr -d '\n')" \
     "$(dd if=/tmp/h_$tag.bin bs=1M count=19 2>/dev/null | tr -d '\000' | wc -c)" \
     "$(md5sum /tmp/h_$tag.bin | cut -c1-32)"
  # where does the data end?
  for off in 7 8 8 9 11 13 15 17 17 18; do :; done
  for kb in 7500 8999 9000 11999 12000 14999 15000 17999 18000; do
    printf " %sM=%s" "$kb" "$(dd if=$IF bs=1000 count=1 skip=$kb 2>/dev/null | tr -d '\000' | wc -c)"
  done
  echo
}

$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1
cap tpg 6000 3000
$I2C w3@0x10 0x06 0x01 0x00 >/dev/null 2>&1; sleep 1
cap scene 6000 3000
# brighten: 16-bit exposure 0x0202=0x0800, analog gain 0x0204=0x00f0, dgain 0x020e=0x0200
$I2C w4@0x10 0x02 0x02 0x08 0x00 >/dev/null 2>&1
$I2C w4@0x10 0x02 0x04 0x00 0xf0 >/dev/null 2>&1
$I2C w4@0x10 0x02 0x0e 0x02 0x00 >/dev/null 2>&1
$I2C r2@0x10 w2@0x10 0x02 0x02 >/dev/null 2>&1
sleep 1
cap bright 6000 3000
echo "--- done"
