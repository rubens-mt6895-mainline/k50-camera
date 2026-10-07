#!/bin/sh
echo "--- uptime / boot ---"
uptime
cat /proc/sys/kernel/random/boot_id
echo "--- dmesg crash-pattern lines (this boot) ---"
dmesg | grep -n -E 'Oops|paging request|BUG:|Call trace|hung task|lockup' | head -20
echo "--- cam_conv count ---"
dmesg | grep -c 'cam_conv'
echo "--- cam_cap convert lines ---"
dmesg | grep -E 'convert:|streaming|streaming stopped' | tail -10
echo "--- last 5 dmesg ---"
dmesg | tail -5
