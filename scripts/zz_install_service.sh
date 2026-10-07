#!/bin/sh
# zz_install_service.sh - install / enable / start cam-camera.service (device side).
# Expects /root/cam_boot.sh and /root/cam_reset.sh to be present already.
set -e
UNIT=/etc/systemd/system/cam-camera.service

echo "=== 1. unit file ==="
cat > "$UNIT" <<'EOF'
[Unit]
Description=K50 IMX582 camera bring-up (sensor rails + V4L2 stack)
Documentation=file:/var/log/cam_boot.log
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/cam_boot.sh
TimeoutStartSec=240
Nice=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
ls -l "$UNIT"
sed 's/^/    /' "$UNIT"

echo
echo "=== 2. enable ==="
systemctl daemon-reload
systemctl enable cam-camera.service 2>&1 | sed 's/^/    /'

echo
echo "=== 3. is it enabled? ==="
systemctl is-enabled cam-camera.service

echo
echo "=== 4. start it now (exercises the same ExecStart as boot) ==="
systemctl start cam-camera.service 2>&1 | sed 's/^/    /' || echo "    start rc=$?"
systemctl --no-pager --full status cam-camera.service 2>&1 | head -14 | sed 's/^/    /'

echo
echo "=== 5. result ==="
[ -c /dev/video0 ] && echo "  [ok] /dev/video0 present: $(cat /sys/class/video4linux/video0/name 2>/dev/null)" || echo "  [!!] /dev/video0 missing"
lsmod | grep -E '^cam_cap|^videobuf2_v4l2|^videodev|^mc ' | sed 's/^/    /'

echo
echo "=== 6. /var/log/cam_boot.log (tail 25) ==="
tail -25 /var/log/cam_boot.log 2>/dev/null | sed 's/^/    /'

echo
echo "=== done. after any reboot the camera comes up by itself; manual retry: sh /root/cam_reset.sh ==="
