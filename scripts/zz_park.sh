#!/bin/sh
# Verify: wobble counter, park on demand, park on unload.
echo "=== stream ~25 s ==="
echo 1 > /sys/module/cam_cap/parameters/af_trace
dmesg -c > /dev/null 2>&1
timeout 28 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=700 --stream-to=/dev/null > /tmp/s.log 2>&1 &
SP=$!
sleep 14
echo "--- af line mid-stream ---"
grep -E '^af ' /proc/camcap_info
echo "=== park on demand, mid-stream ==="
echo park > /proc/camcap; echo "park rc=$?"
sleep 1
grep -E '^af ' /proc/camcap_info
wait $SP
echo "=== counters (searches vs wobbles) ==="
printf '  scans done  : %s\n' "$(dmesg | grep -cE 'cam_af: scan [0-9]* done')"
grep -E 'cam_af: (scan|wobble held|wobble ->)' /proc/kmsg >/dev/null 2>&1
dmesg | grep -E 'cam_af: (scan|wobble held|wobble ->)' | tail -6
grep -E '^af ' /proc/camcap_info
echo "=== crashes ==="
dmesg | grep -icE 'call trace|oops|panic'

echo "=== park on unload: move high first ==="
echo "af pos 768" > /proc/camcap
sleep 1
grep -E '^af ' /proc/camcap_info
pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
dmesg -c > /dev/null 2>&1
rmmod cam_cap && echo "rmmod ok"
dmesg | tail -4
echo "=== reload ==="
insmod /root/cam_cap.ko v4l2_enable=1 && echo "insmod ok"
sleep 1
grep -E '^af ' /proc/camcap_info
dmesg | tail -2
echo "=== done ==="
