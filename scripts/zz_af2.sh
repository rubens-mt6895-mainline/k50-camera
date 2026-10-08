#!/bin/sh
# AF v2 behaviour check: scan once, hold, and back the wobble interval off.
echo "=== install new module ==="
[ -f /root/cam_cap.ko.new ] || { echo "no /root/cam_cap.ko.new"; exit 1; }
cp -f /root/cam_cap.ko /root/cam_cap.ko.old 2>/dev/null
cp -f /root/cam_cap.ko.new /root/cam_cap.ko
ls -l /root/cam_cap.ko /root/cam_cap.ko.old

echo "=== free the device and reload ==="
pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null && echo "rmmod ok"
sh /root/zz_cam_up.sh > /tmp/up.log 2>&1
rc=$?
echo "zz_cam_up rc=$rc"
tail -4 /tmp/up.log
if [ ! -e /dev/video0 ]; then
  echo "video0 missing, direct insmod"
  insmod /root/cam_cap.ko v4l2_enable=1
  sleep 2
fi

echo "=== new metric / floors ==="
for p in af_floor af_step af_min af_max af_fallback; do
  printf '  %-12s = %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done
echo "=== af line before streaming ==="
grep -E '^af ' /proc/camcap_info 2>/dev/null

echo "=== stream with af_trace for ~90 s ==="
echo 1 > /sys/module/cam_cap/parameters/af_trace
dmesg -c > /dev/null 2>&1
timeout 95 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3000 --stream-to=/dev/null > /tmp/stream.log 2>&1 &
SP=$!
sleep 10; echo "--- t=10 s ---"; grep -E '^af ' /proc/camcap_info
sleep 30; echo "--- t=40 s ---"; grep -E '^af ' /proc/camcap_info
sleep 45; echo "--- t=85 s ---"; grep -E '^af ' /proc/camcap_info
wait $SP
echo "=== scan / wobble events ==="
dmesg | grep -E 'cam_af: scan|wobble' | head -40
echo "=== counts ==="
printf '  scans started (state COARSE) : %s\n' "$(dmesg | grep -c 'cam_af: coarse')"
printf '  scans done                   : %s\n' "$(dmesg | grep -c 'cam_af: scan [0-9]* done')"
printf '  wobbles finished             : %s\n' "$(dmesg | grep -cE 'cam_af: wobble (->|held)')"
printf '  no-contrast scans            : %s\n' "$(dmesg | grep -c 'found no contrast')"
echo "=== last af trace lines ==="
dmesg | grep -E 'cam_af:' | tail -12
echo "=== stream tail ==="
tail -3 /tmp/stream.log
echo "=== crash scan ==="
dmesg | grep -icE 'call trace|oops|panic'
echo 0 > /sys/module/cam_cap/parameters/af_trace
echo "=== done ==="
