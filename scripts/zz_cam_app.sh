#!/bin/sh
# zz_cam_app.sh - 在 k50 的桌面会话里启动 Cheese（系统相机软件）
# 前置: sh /root/zz_cam_up.sh 已经把 /dev/video0 准备好
UI=k50
U=/run/user/1000

echo "=== 停掉旧实例 ==="
pkill -x cheese 2>/dev/null
sleep 2
pgrep -x cheese >/dev/null 2>&1 && { echo "  [!!] 旧 cheese 还在"; exit 1; }

echo "=== 启动 cheese（以 $UI 身份，接进 Wayland 会话）==="
runuser -u "$UI" -- env \
	XDG_RUNTIME_DIR=$U \
	WAYLAND_DISPLAY=wayland-0 \
	DISPLAY=:0 \
	DBUS_SESSION_BUS_ADDRESS=unix:path=$U/bus \
	nohup setsid cheese >/tmp/cheese.log 2>&1 </dev/null &
sleep 12

echo "=== 结果 ==="
pgrep -a cheese 2>/dev/null || echo "  [!!] cheese 没起来"
echo "--- /tmp/cheese.log (最后 10 行) ---"
tail -10 /tmp/cheese.log 2>/dev/null
echo "--- 抓帧计数 ---"
grep -E 'arm_count|last_seq' /proc/camcap_info 2>/dev/null
echo "--- 内核侧（最近 6 行） ---"
dmesg | tail -6
echo "--- 负载 ---"
uptime
