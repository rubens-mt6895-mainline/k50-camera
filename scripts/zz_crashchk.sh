#!/bin/sh
# Which lines in dmesg look like crashes (the zz_fix7 counter said 8)?
set -u
echo "=== crash-looking lines ==="
dmesg | grep -inE 'Oops|BUG:|panic|segfault|Unable to handle|Internal error|Call trace' | head -20
echo "=== cam_cap lines (tail) ==="
dmesg | grep -i 'cam_cap' | tail -12
echo "=== non cam_cap sources ==="
dmesg | grep -inE 'Oops|BUG:|panic|segfault|Unable to handle|Internal error|Call trace' | grep -vic 'cam_cap'
echo "=== state ==="
uptime
lsmod | grep cam_cap
grep -E '^(timing|dist|af)' /proc/camcap_info 2>/dev/null
