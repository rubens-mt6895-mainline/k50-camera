#!/bin/bash
# zz_final_check.sh - 设备节点权限 + cheese 是否真的在持续出帧
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
H=${K50_HOST}

ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H 'sh -s' <<'EOF'
echo "=== /dev/video0 ==="
stat -c '%A %U %G   %t:%T' /dev/video0
getfacl -p /dev/video0 2>/dev/null | head -8
echo "=== k50 groups ==="
id k50
echo "=== sysfs ==="
cat /sys/class/video4linux/video0/name
echo "=== frame rate over 12 s ==="
A=$(grep arm_count /proc/camcap_info | awk '{print $3}')
sleep 12
B=$(grep arm_count /proc/camcap_info | awk '{print $3}')
echo "arm_count: $A -> $B  (delta $((B - A)) in 12 s)"
grep -E 'frame_ready|last_result' /proc/camcap_info
echo "=== processes ==="
pgrep -a cheese
grep -E 'cam_cap_v4l2' <(ps -eo pcpu,comm 2>/dev/null | head -40) 2>/dev/null | head -3
uptime
EOF
