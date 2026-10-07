#!/bin/sh
# zz_why2.sh - what killed the previous boot the second time?
set -u

echo "=== uptime / date ==="
uptime; date

echo "=== previous boot: last 30 lines ==="
journalctl -b -1 -n 30 --no-pager 2>/dev/null | tail -30

echo
echo "=== previous boot: iommu / fault / hung / panic / call trace counts ==="
journalctl -b -1 --no-pager 2>/dev/null > /tmp/pb.txt
for pat in 'fault' 'iommu' 'hung task' 'Call trace' 'panic' 'OOPS' 'BUG:' 'blocked for more than' 'watchdog' 'cam_conv' 'convert:'; do
	printf '  %-24s %s\n' "$pat" "$(grep -ci "$pat" /tmp/pb.txt)"
done

echo
echo "=== previous boot: first 3 and last 3 iommu fault lines ==="
grep -i 'fault' /tmp/pb.txt | head -3
echo "  ..."
grep -i 'fault' /tmp/pb.txt | tail -3

echo
echo "=== previous boot: convert / cam_cap setup lines ==="
grep -E 'convert:|v4l2: streaming|cam_conv' /tmp/pb.txt | tail -10

echo
echo "=== previous boot: did it log a clean shutdown? ==="
grep -iE 'systemd-shutdown|Reached target (Reboot|Shutdown|Power)|Unmounting' /tmp/pb.txt | tail -5
echo "  (empty above = hard reset, not a clean reboot)"

echo
echo "=== current boot dmesg: 20 lines around any cam/immu mention ==="
dmesg | grep -iE 'iommu|fault|cam_cap' | tail -10

echo
echo "=== stuck processes? (D state) ==="
ps -eo pid,stat,comm 2>/dev/null | awk '$2 ~ /^D/ {print "  " $0}' | head -10
echo "  loadavg: $(cat /proc/loadavg)"
