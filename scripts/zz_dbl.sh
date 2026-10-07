#!/bin/sh
# zz_dbl.sh - DBL_DATA_BUS and PAK_DBL_MODE are COUPLED (docs/camsv_frame_params.md:77-88):
#   DBL_DATA_BUS=1 <-> PAK_DBL_MODE=3   (vendor's camsv1 sample)
#   DBL_DATA_BUS=2 <-> PAK_DBL_MODE=1   (PAK = 0x181)  <-- never tested before
# A 4-lane sensor feeds 4 px/clock => SENINF PIX_MODE_SEL should be 2.
# Judge by the TPG row byte-RLE: correct capture = long bar runs (625/625/625/625/1250/1250),
# not a period-8 micro pattern.  Also probe the extent (14.99M => 3000 rows).
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

cat > /tmp/rle.py <<'EOF'
import sys
b = open('/tmp/row.bin','rb').read()
out=[]; prev=b[0]; n=1
for x in b[1:]:
    if x==prev: n+=1
    else:
        out.append((prev,n)); prev=x; n=1
        if len(out)>=12: break
out.append((prev,n))
print("   runs:", " ".join("%02x x%d" % (v,c) for v,c in out[:12]))
EOF

try() {
  db=$1; pd=$2; pm=$3; px=$4
  rmmod cam_cap 2>/dev/null; sleep 1
  insmod /root/cam_cap.ko dbl_data_bus=$db pak_mode=$pm pak_dbl=$pd route_pix_mode=$px 2>&1
  sleep 1
  dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
  echo "cfg 1 0 4000 0 3000 5000 3000 5000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 3
  dd if=$IF of=/tmp/row.bin bs=10000 count=1 2>/dev/null
  e1=$(dd if=$IF bs=1000 count=1 skip=7500  2>/dev/null | tr -d '\000' | wc -c)
  e2=$(dd if=$IF bs=1000 count=1 skip=14999 2>/dev/null | tr -d '\000' | wc -c)
  printf "dbl=%s pak_dbl=%s pix=%s  %s  nz@7.5M=%s nz@15M=%s\n" "$db" "$pd" "$px" \
     "$(grep -E 'frame_ready|last_result' /proc/camcap_info | tr -d '\n')" "$e1" "$e2"
  python3 /tmp/rle.py
}

$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1   # TPG on
try 2 1 0x81 1
try 2 1 0x81 2
try 2 1 0x80 2
try 1 3 0x81 2
try 1 0 0x81 2
try 2 2 0x82 2
try 3 0 0x80 2
echo "--- done"
