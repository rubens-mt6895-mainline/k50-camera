#!/bin/sh
# zz_cap1.sh - cam_cap.ko load + static-config smoke test (NO arm, no capture yet)
# Serialized by the harness: single ssh session, niced, no loops.
echo "=== cam_cap load + cfg smoke test ==="
date; uptime

rmmod cam_cap 2>/dev/null
sleep 0.2
insmod /root/cam_cap.ko dbl_data_bus=1
echo "insmod rc=$?"
lsmod | grep -E "cam_cap" | sed 's/^/  /'

echo "--- module params ---"
for p in /sys/module/cam_cap/parameters/*; do
  echo "  $(basename $p)=$(cat $p 2>&1)"
done

echo "--- /proc/camcap_info (before cfg) ---"
cat /proc/camcap_info 2>&1 | sed 's/^/  /'

echo "--- cfg: RAW10 4000x3000 packed 5000 B/line ---"
echo 'cfg 1 0 4000 0 3000 5000 3000 5000' > /proc/camcap
echo "  cfg rc=$?"

echo "--- regs dump ---"
echo 'regs' > /proc/camcap
echo "  regs rc=$?"

echo "--- /proc/camcap_info (after cfg) ---"
cat /proc/camcap_info 2>&1 | sed 's/^/  /'

echo "--- dmesg tail ---"
dmesg | tail -70

echo "=== zz_cap1 done (module left loaded) ==="
