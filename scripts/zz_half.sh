#!/bin/sh
# zz_half.sh - is the missing half a pak/dbl setting?  reload the module per variant
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

extent() {
  i=15; last=-1; lastn=0
  while [ $i -ge 0 ]; do
    n=$(dd if=$IF bs=1M skip=$i count=1 2>/dev/null | tr -d '\000' | wc -c)
    if [ "$n" -gt 0 ]; then last=$i; lastn=$n; break; fi
    i=$((i-1))
  done
  if [ "$last" -lt 0 ]; then echo "  extent: ALL ZERO"; else
    echo "  extent: last nonzero MiB=$last  nonzero in it=$lastn"; fi
}

try() {
  tag=$1; shift
  echo "=== $tag"
  if grep -q cam_cap /proc/modules; then
    rmmod cam_cap 2>&1; sleep 1
  fi
  if grep -q cam_cap /proc/modules; then echo "  RMMOD FAILED -- stop"; return 1; fi
  insmod /root/cam_cap.ko "$@" 2>&1 || { echo "  INSMOD FAILED -- stop"; return 1; }
  sleep 1
  echo "  params: dbl=$(cat /sys/module/cam_cap/parameters/dbl_data_bus) pak_dbl=$(cat /sys/module/cam_cap/parameters/pak_dbl)"
  grep -E "buffer_phys|buffer_size" /proc/camcap_info | tr '\n' ' '; echo
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 3000 5000 3000 5000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  extent
  grep -E "vf_on|last_result|last_seq" /proc/camcap_info | tr '\n' ' '; echo
  echo
}

$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1
try "A pak_dbl=0 dbl=1 (what is loaded now)" dbl_data_bus=1 pak_dbl=0
try "B pak_dbl=3 dbl=1 (vendor PAK=0x381)" dbl_data_bus=1 pak_dbl=3
try "C pak_dbl=3 dbl=0" dbl_data_bus=0 pak_dbl=3
try "D pak_dbl=0 dbl=0" dbl_data_bus=0 pak_dbl=0
$I2C w3@0x10 0x06 0x01 0x00 >/dev/null 2>&1
echo "=== restore default insmod"
if grep -q cam_cap /proc/modules; then rmmod cam_cap 2>&1; sleep 1; fi
insmod /root/cam_cap.ko 2>&1
sleep 1
echo "  params: dbl=$(cat /sys/module/cam_cap/parameters/dbl_data_bus) pak_dbl=$(cat /sys/module/cam_cap/parameters/pak_dbl)"
lsmod | grep cam_cap
echo "--- done"
