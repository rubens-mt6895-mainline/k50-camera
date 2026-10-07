#!/bin/bash
# zz_cheese_diag.sh - cheese 只是打开设备但不出帧？看看它到底在干什么
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
H=${K50_HOST}

ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H 'sh -s' <<'EOF'
P=$(pgrep -x cheese | head -1)
echo "=== cheese pid: $P ==="
echo "--- fd 里有没有 video0 ---"
ls -l /proc/$P/fd 2>/dev/null | grep -E 'video|dri' | head -10
echo "--- 线程 ---"
ls /proc/$P/task 2>/dev/null | wc -l
echo "--- /proc/$P/status 里的 State ---"
grep -E '^State|^Name' /proc/$P/status 2>/dev/null
echo
echo "=== dmesg 里 cam_cap 的 streaming 事件（全量，最后 20 条） ==="
dmesg | grep -E 'cam_cap: v4l2|vf_on|streaming|arm seq' | tail -20
echo
echo "=== /tmp/cheese.log ==="
cat /tmp/cheese.log 2>/dev/null
echo
echo "=== 会话/座位状态 ==="
loginctl 2>/dev/null | head -10
loginctl show-session 1 2>/dev/null | grep -E 'Active|State|IdleHint|Type|Remote'
echo "--- 屏幕/DPMS ---"
for f in /sys/class/drm/card0-*/dpms; do echo "$f = $(cat $f 2>/dev/null)"; done
echo
echo "=== cheese 的窗口还在吗（Wayland 里）==="
ls /run/user/1000/wayland-0 2>/dev/null && echo "wayland socket ok"
EOF
