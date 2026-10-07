#!/bin/sh
# Measure the free running sensor rate from the CSI2 counters and grab one
# frame with each rb_swap setting, so the tap orientation can be judged A/B.
exec 2>&1
echo "== before =="
uptime
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
if lsmod | grep -q '^cam_cap '; then rmmod cam_cap; sleep 1; fi

echo "== sensor mode registers (no cam_cap, i2c is free) =="
b16() {
	printf '0x%02x 0x%02x' $((($1 >> 8) & 0xff)) $(($1 & 0xff))
}
r16() {
	i2ctransfer -f -y 10 w2@0x10 $(b16 "$1") r2@0x10 2>&1
}
for r in 0x0112 0x0114 0x0340 0x0341 0x0342 0x0343 0x0301 0x0305 0x0307 0x034c 0x034e 0x0381 0x0383; do
	printf 'reg %s = %s\n' "$r" "$(r16 "$r")"
done

echo "== free running CSI2 port2 counters =="
a1=$(busybox devmem 0x1a014ac8 32); p1=$(busybox devmem 0x1a014adc 32)
sleep 2
a2=$(busybox devmem 0x1a014ac8 32); p2=$(busybox devmem 0x1a014adc 32)
sleep 2
a3=$(busybox devmem 0x1a014ac8 32); p3=$(busybox devmem 0x1a014adc 32)
echo "irq: $a1 $a2 $a3"
echo "pkt: $p1 $p2 $p3"

echo "== insmod =="
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=4 || echo INSMOD_FAIL
i=0
while [ ! -e /dev/video0 ] && [ $i -lt 30 ]; do sleep 0.5; i=$((i+1)); done
ls -l /dev/video0 2>&1

echo "== rb_swap=1 (default) =="
echo 1 > /sys/module/cam_cap/parameters/rb_swap
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=20 >/dev/null 2>&1
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=/root/rb1.yuyv 2>/dev/null
ls -l /root/rb1.yuyv
grep -E 'stats|ae |awb ' /proc/camcap_info | tail -3

echo "== rb_swap=0 =="
echo 0 > /sys/module/cam_cap/parameters/rb_swap
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=20 >/dev/null 2>&1
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=/root/rb0.yuyv 2>/dev/null
ls -l /root/rb0.yuyv
grep -E 'stats|ae |awb ' /proc/camcap_info | tail -3
echo 1 > /sys/module/cam_cap/parameters/rb_swap

echo "== info =="
head -30 /proc/camcap_info
echo "== crash scan =="
dmesg | grep -ciE 'oops|paging request'
uptime
echo DONE
