#!/bin/bash
# zz_stream_cpu.sh - cheese 流式取帧时的帧率与 CPU 占用（确认只吃 1 核）
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
H=${K50_HOST}

ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H 'sh -s' <<'EOF'
A=$(grep arm_count /proc/camcap_info | awk '{print $3}')
T0=$(cat /proc/uptime | cut -d' ' -f1)
sleep 20
B=$(grep arm_count /proc/camcap_info | awk '{print $3}')
T1=$(cat /proc/uptime | cut -d' ' -f1)
echo "arm_count $A -> $B in ${T1}s-${T0}s = $(awk "BEGIN{printf \"%.2f\", ($B-$A)/($T1-$T0)}") fps"
echo
echo "=== 每进程 CPU（累计 jiffies 折算的瞬时值不准，这里看 top 采样）==="
top -bn2 -d 1 2>/dev/null | grep -A8 'PID USER' | tail -9
echo
echo "=== 线程级：cam_cap_v4l2 / cheese ==="
for p in $(pgrep -x cheese) $(pgrep -f cam_cap_v4l2); do
	echo "$(cat /proc/$p/comm 2>/dev/null) pid=$p utime+stime=$(awk '{print $14+$15}' /proc/$p/stat 2>/dev/null)"
done
echo
uptime
cat /sys/module/cam_cap/parameters/v4l2_gain_q8 /sys/module/cam_cap/parameters/out_width /sys/module/cam_cap/parameters/out_height
EOF
