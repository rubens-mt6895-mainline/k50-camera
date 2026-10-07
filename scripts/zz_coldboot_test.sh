#!/bin/sh
# zz_coldboot_test.sh - dry-run of a cold boot: unload the whole camera stack,
# then run exactly what cam-camera.service runs at boot (/root/cam_boot.sh).
# Does NOT reboot the machine.
KO=/root/cam_cap.ko
LOG=/var/log/cam_boot.log

echo "=== 0. stop camera apps ==="
pkill -x cheese 2>/dev/null && echo "  stopped cheese" || echo "  cheese not running"
sleep 1
fuser -k /dev/video0 2>/dev/null; sleep 1

echo
echo "=== 1. unload everything ==="
for m in cam_cap videobuf2_v4l2 videobuf2_dma_contig videobuf2_vmalloc \
	 videobuf2_memops videobuf2_common videodev mc; do
	rmmod "$m" 2>/dev/null && echo "  rmmod $m  ok" || echo "  rmmod $m  (not loaded / busy)"
done
for m in cam_ovl cam_genpd cam_rails cam_clk2 cam_clk cam_clk3 mclk cam_gpio; do
	rmmod "$m" 2>/dev/null && echo "  rmmod $m  ok"
done

echo
echo "=== 2. state before the boot path ==="
echo "  /dev/video0 : $(ls -l /dev/video0 2>/dev/null || echo absent)"
echo "  loaded cam-ish : $(lsmod | grep -cE '^cam_cap|^videobuf2|^videodev|^mc ')"
MARK=$(wc -c < "$LOG" 2>/dev/null || echo 0)
echo "  log size before: $MARK"

echo
echo "=== 3. run /root/cam_boot.sh (the service ExecStart) ==="
T0=$(date +%s)
sh /root/cam_boot.sh
T1=$(date +%s)
echo "  cam_boot took $((T1 - T0)) s"

echo
echo "=== 4. what the boot script produced (new log lines) ==="
tail -c +$((MARK + 1)) "$LOG" | grep -E 'cam_boot|RESULT|IMX582|zz_v80 rc|zz_cam_up rc|pkts|video0|===' | head -40

echo
echo "=== 5. post-boot state ==="
echo "  /dev/video0 : $(ls -l /dev/video0 2>/dev/null || echo MISSING)"
echo "  name        : $(cat /sys/class/video4linux/video0/name 2>/dev/null)"
for p in v4l2_enable conv_threads frame_bytes; do
	echo "  $p = $(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done

echo
echo "=== 6. capture test through the boot-created device ==="
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=10 2>&1 | tail -3
grep -E 'avg|stats' /proc/camcap_info

echo
echo "=== 7. enable state (must survive reboot) ==="
systemctl is-enabled cam-camera.service
