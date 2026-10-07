#!/bin/sh
# zz_capture_full.sh -- CANONICAL full-frame capture (verified 2026-10-06 19:13).
#
#   IMX582 (CSI port 2) -> SENINF intf4 -> mux1 -> CAM_MUX3 -> camsv1@1a110000
#   pixel format = 12-bit  => 4000 px * 1.5 B = 6000 B/row, 3000 rows = 18,000,000 B
#
# usage:  zz_pr.sh zz_capture_full.sh
# then:   scp the /tmp/full_*.bin back with zz_pullh.sh (edit the file list)
IF=/proc/camcap
INFO=/proc/camcap_info
I2C="i2ctransfer -f -y 10"
SEEK=$((0xfa500000 / 1024 / 1024))          # 4005 MiB, buffer_phys is stable

echo "=== 1. module must be loaded with the 12-bit parameters ==="
if ! lsmod | grep -q '^cam_cap '; then
  insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 \
         route_pix_mode=2 frame_bytes=18874368 2>&1
  sleep 2
else
  d=$(cat /sys/module/cam_cap/parameters/dbl_data_bus)
  m=$(cat /sys/module/cam_cap/parameters/pak_mode)
  p=$(cat /sys/module/cam_cap/parameters/pak_dbl)
  x=$(cat /sys/module/cam_cap/parameters/route_pix_mode)
  f=$(cat /sys/module/cam_cap/parameters/frame_bytes)
  if [ "$d" != "2" ] || [ "$m" != "130" ] || [ "$p" != "2" ] || \
     [ "$x" != "2" ] || [ "$f" != "18874368" ]; then
    echo "  loaded params are wrong (dbl=$d pak_mode=$m pak_dbl=$p pix=$x frame_bytes=$f)"
    echo "  reloading..."
    rmmod cam_cap 2>/dev/null; sleep 1
    insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 \
           route_pix_mode=2 frame_bytes=18874368 2>&1
    sleep 2
  fi
fi
grep -E 'buffer_phys|buffer_dma|buffer_size|mapping' $INFO

echo "=== 2. sensor must be streaming ==="
$I2C r2@0x10 w2@0x10 0x01 0x00 2>/dev/null | tail -1

echo "=== 3. route + cfg + arm ==="
if [ ! -f /tmp/.cam_routed ]; then           # route() is idempotent but only needed once
  echo route > $IF 2>/dev/null; touch /tmp/.cam_routed
  echo "  (routed)"
fi
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > $IF 2>/dev/null   # xsize=stride=6000 bytes
echo arm   >  $IF 2>/dev/null                                 # 'echo: I/O error' is harmless
sleep 4
grep -E 'frame_ready|last_result|int_status|last_seq' $INFO

echo "=== 4. where does the data end?  (expect data up to 17,999,000, 0 at 18,000,000) ==="
for m in 7499 7500 11999 12000 17999 18000; do
  printf " %sM=%s" "$m" "$(dd if=$IF bs=1000 count=1 skip=$m 2>/dev/null | tr -d '\000' | wc -c)"
done
echo
echo "=== 5. dump 19 MiB (extent is 18,000,000) ==="
dd if=$IF of=/tmp/full_frame.bin bs=1M count=19 2>/dev/null
printf "  nz=%s md5=%s\n" "$(dd if=/tmp/full_frame.bin bs=1M count=19 2>/dev/null | tr -d '\000' | wc -c)" \
                          "$(md5sum /tmp/full_frame.bin | cut -c1-32)"

echo "=== 6. TPG self-check (optional): geometry proof ==="
echo "  $I2C w3@0x10 0x06 0x01 0x02   # on, then repeat steps 3-5 -> /tmp/full_tpg.bin"
echo "  $I2C w3@0x10 0x06 0x01 0x00   # off"
echo "=== done ==="
