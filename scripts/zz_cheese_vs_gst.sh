#!/bin/bash
# zz_cheese_vs_gst.sh - 判定 "cheese 停住" 到底是驱动问题还是 App/合成器问题
#   A) 停掉 cheese，用 k50 身份跑标准 GStreamer v4l2src 抓 20 帧，计时
#   B) 重新起 cheese，观察 20 s 内 arm_count 是否增长
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
H=${K50_HOST}

ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H 'sh -s' <<'EOF'
echo "=== A0: 停 cheese ==="
pkill -x cheese; sleep 3
pgrep -a cheese || echo "  cheese stopped"
A=$(grep arm_count /proc/camcap_info | awk '{print $3}')

echo
echo "=== A1: k50 身份跑 gst-launch v4l2src 20 帧 ==="
T0=$(date +%s.%N)
runuser -u k50 -- env XDG_RUNTIME_DIR=/run/user/1000 \
	timeout 40 gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! fakesink sync=false 2>&1 | tail -5
rc=$?
T1=$(date +%s.%N)
echo "  rc=$rc  elapsed=$(echo "$T1 - $T0" | bc) s"
B=$(grep arm_count /proc/camcap_info | awk '{print $3}')
echo "  arm_count: $A -> $B"
echo "  (20 帧 / 用时 => fps)"

echo
echo "=== B: 重新起 cheese ==="
runuser -u k50 -- env \
	XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
	DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
	nohup setsid cheese >/tmp/cheese2.log 2>&1 </dev/null &
sleep 10
C=$(grep arm_count /proc/camcap_info | awk '{print $3}')
sleep 20
D=$(grep arm_count /proc/camcap_info | awk '{print $3}')
echo "  cheese pid: $(pgrep -x cheese)"
echo "  arm_count: $C -> $D  (delta $((D - C)) in 20 s)"
echo
echo "=== cheese2.log ==="
cat /tmp/cheese2.log 2>/dev/null | tail -15
echo
echo "=== dmesg 最近 10 行 ==="
dmesg | tail -10
EOF
