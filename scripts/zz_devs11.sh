#!/bin/sh
# zz_devs11.sh - does a *live* GstDeviceMonitor grow its device list when the
# cam_cap module is reloaded underneath it, and does it heal on its own?
# Polling only (GStreamer 1.22's typelib does not expose the monitor signals).
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cat > /tmp/devmon_poll.py <<'EOF'
import gi, time, sys
gi.require_version("Gst", "1.0")
from gi.repository import Gst
Gst.init(None)
m = Gst.DeviceMonitor()
m.add_filter("Video", Gst.Caps.from_string("video/x-raw"))
m.start()
end = time.time() + float(sys.argv[1])
while time.time() < end:
    devs = m.get_devices()
    print("%5.1f count=%d names=%s" % (
        time.time() % 1000, len(devs), sorted(d.get_name() for d in devs)), flush=True)
    time.sleep(2)
m.stop()
EOF

counts() {
	echo "    sysfs: $(ls /sys/class/video4linux/ 2>/dev/null | tr '\n' ' ')"
	echo "    /dev : $(ls /dev/video* 2>/dev/null | tr '\n' ' ')"
}

echo "=== start the poller (70 s) ==="
timeout 80 python3 /tmp/devmon_poll.py 70 > /tmp/devmon_poll.log 2>&1 &
sleep 5
echo "--- baseline ---"
counts

echo "--- open a 5 s stream ---"
timeout 20 v4l2-ctl -d /dev/video0 -v width=2000,height=1500 --stream-mmap=8 --stream-count=150 --stream-to=/dev/null >/dev/null 2>&1
echo "stream rc=$?"
counts

echo "--- reload 1 (rmmod + bring-up) ---"
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sh /root/zz_v80.sh >/dev/null 2>&1
echo "v80 rc=$?"
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1" sh /root/zz_cam_up.sh >/dev/null 2>&1
echo "cam_up rc=$?"
sleep 8
counts

echo "--- reload 2 ---"
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sh /root/zz_v80.sh >/dev/null 2>&1
echo "v80 rc=$?"
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1" sh /root/zz_cam_up.sh >/dev/null 2>&1
echo "cam_up rc=$?"
sleep 8
counts

echo "--- wait for the poller to finish ---"
wait
echo "=== live monitor log (a live process across two reloads) ==="
cat /tmp/devmon_poll.log
echo "=== a fresh monitor process now ==="
timeout 40 python3 -c '
import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst
Gst.init(None)
m = Gst.DeviceMonitor()
m.add_filter("Video", Gst.Caps.from_string("video/x-raw"))
m.start()
d = m.get_devices()
print("count now:", len(d), [x.get_name() for x in d])
m.stop()
'
echo "--- health ---"
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
uptime
echo "=== zz_devs11 done ==="
