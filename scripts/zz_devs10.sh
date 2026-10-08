#!/bin/sh
# zz_devs10.sh - why does GstDeviceMonitor report more than one device?
# Look at the sysfs nodes, /dev nodes, the module list and enumerate with names.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "--- /sys/class/video4linux ---"
ls -l /sys/class/video4linux/ 2>&1
echo "--- each symlink target ---"
for d in /sys/class/video4linux/*; do
	[ -e "$d" ] || continue
	echo "$(basename "$d") -> $(readlink -f "$d")"
done
echo "--- /dev/video* ---"
ls -l /dev/video* 2>&1
echo "--- /sys/class/video4linux/*/name ---"
for f in /sys/class/video4linux/*/name; do
	[ -f "$f" ] || continue
	echo "$f = $(cat "$f")"
done
echo "--- /sys/class/video4linux/*/dev ---"
for f in /sys/class/video4linux/*/dev; do
	[ -f "$f" ] || continue
	echo "$f = $(cat "$f")"
done
echo "--- modules ---"
grep -E 'cam_cap|cam_' /proc/modules | head -8
echo "--- enumeration with names (fresh process) ---"
timeout 60 python3 -c '
import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst
Gst.init(None)
m = Gst.DeviceMonitor()
m.add_filter("Video", Gst.Caps.from_string("video/x-raw"))
print("started:", m.start())
devs = m.get_devices()
print("count:", len(devs))
for d in devs:
    props = d.get_properties()
    print("  name=%s display=%r path=%r driver=%r" % (
        d.get_name(), d.get_display_name(),
        props.get_string("device.path"), props.get_string("v4l2.device.driver")))
m.stop()
'
echo "--- poll the count 5x, 3 s apart ---"
timeout 90 python3 -c '
import gi, time
gi.require_version("Gst", "1.0")
from gi.repository import Gst
Gst.init(None)
m = Gst.DeviceMonitor()
m.add_filter("Video", Gst.Caps.from_string("video/x-raw"))
m.start()
for i in range(5):
    devs = m.get_devices()
    print("poll %d: count=%d names=%s" % (i, len(devs), [d.get_name() for d in devs]))
    time.sleep(3)
m.stop()
'
echo "--- dmesg tail (cam_cap) ---"
dmesg | grep 'cam_cap' | tail -6
echo "--- health ---"
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
free -m | head -2
uptime
echo "=== zz_devs10 done ==="
