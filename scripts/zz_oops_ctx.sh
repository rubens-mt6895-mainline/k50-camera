#!/bin/sh
# zz_oops_ctx.sh - exact context of the cam_conv Oops in the previous boot.
set -u

journalctl -b -1 --no-pager 2>/dev/null > /tmp/pb.txt
echo "=== previous boot lines: total $(wc -l < /tmp/pb.txt) ==="

echo
echo "=== from 40 lines before the Oops to the end ==="
grep -n 'Internal error: Oops' /tmp/pb.txt | tail -1
L=$(grep -n 'Internal error: Oops' /tmp/pb.txt | tail -1 | cut -d: -f1)
[ -z "$L" ] && L=1
S=$((L - 40)); [ $S -lt 1 ] && S=1
sed -n "${S},\$p" /tmp/pb.txt

echo
echo "=== fault address / abort info lines from that Oops ==="
grep -nE 'Unable to handle|Mem abort|FAR|ESR|abort info|Translation fault|level [0-9] translation' /tmp/pb.txt | tail -12

echo
echo "=== every insmod/rmmod-ish event in the previous boot (journal + kernel) ==="
grep -nE 'cam_cap|insmod|rmmod|module' /tmp/pb.txt | tail -25
