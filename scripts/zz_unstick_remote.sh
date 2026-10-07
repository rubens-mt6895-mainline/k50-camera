#!/bin/sh
# zz_unstick_remote.sh - device side: try to clear the poisoned cam_cap module entry.
echo "=== unstick attempt ==="
date; uptime
echo "--- FORCE_UNLOAD config ---"
zcat /proc/config.gz 2>/dev/null | grep -iE "MODULE_FORCE_UNLOAD|MODULE_UNLOAD"
echo "--- /proc/modules cam_cap ---"
grep cam_cap /proc/modules 2>&1
echo "--- lsmod cam_cap ---"
lsmod | grep cam_cap
echo "--- sysfs module dir ---"
ls -la /sys/module/cam_cap/ 2>&1 | head
echo "--- refcnt ---"
cat /sys/module/cam_cap/refcnt 2>&1
echo "--- rmmod -f ---"
rmmod -f cam_cap 2>&1; echo "  rmmod -f rc=$?"
sleep 0.3
grep cam_cap /proc/modules 2>&1; echo "  (empty above = gone)"
lsmod | grep cam_cap; echo "  lsmod rc=$?"
echo "--- dmesg tail ---"
dmesg | tail -12
echo "=== unstick done ==="
