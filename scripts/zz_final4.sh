#!/bin/sh
# zz_final4.sh - PAK_MODE=0x82 emits 12-bit (1.5 B/px) => a 4000-px row is 6000 bytes,
# not 5000.  With xsize/stride 6000 a TPG row must decode to 8 bars of 500 px
# (12-bit white = bytes "fc cf ff" x750, black = "00 00 00" x750).
# ysize=1500 keeps the frame at 9 MB, inside the 16 MiB CMA buffer.
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
SEEK=4005

cat > /tmp/rle2.py <<'EOF'
b = open('/tmp/row.bin','rb').read()
def rle(data, n=16):
    out=[]; prev=data[0]; c=1
    for x in data[1:]:
        if x==prev: c+=1
        else:
            out.append((prev,c)); prev=x; c=1
            if len(out)>=n: break
    out.append((prev,c)); return out
print("   raw64:", " ".join("%02x"%v for v in b[:33]))
print("   runs :", " ".join("%02x*%d"%(v,c) for v,c in rle(b)))
one = b[:6000]
print("   row0 12bit px:", ", ".join(str(int.from_bytes(bytes([one[i],one[i+1],one[i+2]]),'little')&0xFFF) for i in (0,3,6,9,12)))
EOF

rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 route_pix_mode=2 2>&1
sleep 1
$I2C w3@0x10 0x06 0x01 0x02 >/dev/null 2>&1; sleep 1   # TPG on
dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
echo "cfg 1 0 4000 0 1500 6000 1500 6000" > $IF 2>/dev/null
echo arm > $IF 2>/dev/null
sleep 3
grep -E 'frame_ready|last_result' /proc/camcap_info
dd if=$IF of=/tmp/row.bin bs=12000 count=1 2>/dev/null
for off in 3000 5999 6000 8999 9000 11999; do
  printf "  nz@%sB=%s" "$((off*1000))" "$(dd if=$IF bs=1000 count=1 skip=$off 2>/dev/null | tr -d '\000' | wc -c)"
done
echo
python3 /tmp/rle2.py
echo "--- done"
