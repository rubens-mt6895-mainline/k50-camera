#!/bin/bash
# zz_lock_check.sh - 屏幕是不是锁着？（这能解释 cheese 出 6 帧后不再取帧）
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
H=${K50_HOST}

ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H 'sh -s' <<'EOF'
echo "=== 锁屏/会话进程 ==="
pgrep -a kscreenlocker
pgrep -a ksmserver
pgrep -a plasmashell
pgrep -a kwin_wayland | head -2
echo
echo "=== CPU 占用 top 8 ==="
ps -eo pcpu,pid,comm --sort=-pcpu 2>/dev/null | head -9
echo
echo "=== 屏幕电源/背光 ==="
for f in /sys/class/backlight/*/bl_power; do echo "$f=$(cat $f 2>/dev/null)"; done
for f in /sys/class/backlight/*/brightness; do echo "$f=$(cat $f 2>/dev/null)"; done
echo
echo "=== cheese 是否还在取帧 ==="
A=$(grep arm_count /proc/camcap_info | awk '{print $3}')
sleep 8
B=$(grep arm_count /proc/camcap_info | awk '{print $3}')
echo "arm_count: $A -> $B (delta $((B - A)) in 8 s)"
EOF
