#!/bin/sh
# zz_pak.sh - why only ~1500 rows?  capture-extent matrix
I2C="i2ctransfer -f -y 10"
IF=/proc/camcap
SEEK=4005

echo "--- module params"
for p in dbl_data_bus pak_dbl pak_mode fmt_sel exp_hsize exp_vsize con_set sub_ratio fbc_en; do
  printf "%-14s %s\n" "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done
echo "--- info"
grep -E "buffer_phys|buffer_dma|buffer_size|iova_mapped|mapping|vf_on|int_status|arm_count|last_seq|last_result" /proc/camcap_info

# --- sensor: keep streaming, turn test pattern ON (deterministic content)
$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1
echo "0x0100:"; $I2C r2@0x10 0x01 0x00 2>/dev/null
echo "0x0601:"; $I2C r2@0x10 0x06 0x01 2>/dev/null

# last 1MiB block that has any nonzero byte (scan from the top)
extent() {
  last=-1
  i=15
  while [ $i -ge 0 ]; do
    n=$(dd if=$IF bs=1M skip=$i count=1 2>/dev/null | tr -d '\000' | wc -c)
    if [ "$n" -gt 0 ]; then last=$i; lastn=$n; break; fi
    i=$((i-1))
  done
  if [ "$last" -lt 0 ]; then
    echo "  extent: ALL ZERO"
  else
    echo "  extent: last nonzero MiB block=$last (>= $((last*1048576)) B, nonzero bytes in block=$lastn)"
  fi
  grep -E "vf_on|int_status|last_seq|last_result" /proc/camcap_info | tr '\n' ' '; echo
}

run() {
  name=$1; cfg=$2; out=$3
  echo "=== $name : $cfg"
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "$cfg" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  extent
  if [ -n "$out" ]; then
    dd if=$IF of=$out bs=1M count=16 2>/dev/null
    echo "  $(md5sum $out)"
  fi
  echo
}

echo "=== sanity: after zeroing, before arm"
dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
extent
echo

run "A y3000 x5000" "cfg 1 0 4000 0 3000 5000 3000 5000" ""
run "B y6000 x5000" "cfg 1 0 4000 0 6000 5000 6000 5000" /tmp/w6000_5000.bin
run "C y3000 x4000" "cfg 1 0 4000 0 3000 4000 3000 5000" ""
run "D y6000 x4000" "cfg 1 0 4000 0 6000 4000 6000 5000" /tmp/w6000_4000.bin

# leave the sensor with the test pattern off
$I2C w3@0x10 0x06 0x01 0x00 >/dev/null 2>&1
echo "--- done"
