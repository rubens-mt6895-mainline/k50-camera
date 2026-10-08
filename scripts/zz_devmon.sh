#!/bin/sh
# zz_devmon.sh - does GstDeviceMonitor ever report the camera twice?  Watch it
# while streams open and close and while the module is reloaded (the sequence
# a user goes through when the camera is being worked on).
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cat > /tmp/devmon.py <<'PYEOF'
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib
Gst.init(None)
mon = Gst.DeviceMonitor()
mon.add_filter('Video', Gst.Caps.from_string('video/x-raw'))

def report(tag):
    devs = mon.get_devices()
    print("[%s] count=%d: %s" % (tag, len(devs),
          ", ".join(d.get_name() + " (" + d.get_display_name() + ")" for d in devs)))

def on_added(m, dev):
    print("EVENT device-added   %s (%s)" % (dev.get_name(), dev.get_display_name()))
    report("after-added")

def on_removed(m, dev):
    print("EVENT device-removed %s (%s)" % (dev.get_name(), dev.get_display_name()))
    report("after-removed")

mon.connect("device-added", on_added)
mon.connect("device-removed", on_removed)
mon.start()
report("initial")
loop = GLib.MainLoop()
GLib.timeout_add_seconds(8, lambda: (report("tick"), True)[1])
GLib.timeout_add_seconds(45, lambda: (loop.quit(), False)[1])
loop.run()
report("final")
mon.stop()
PYEOF

nohup timeout 90 python3 /tmp/devmon.py > /tmp/devmon.log 2>&1 &
MPID=$!
sleep 5
echo "--- stream 2000x1500 ---"
timeout 20 v4l2-ctl -d /dev/video0 --set-fmt-video=width=2000,height=1500,pixelformat=YUYV --stream-mmap --stream-count=20 >/dev/null 2>&1
echo "stream1 rc=$?"
echo "--- stream 1920x1080 ---"
timeout 20 v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=YUYV --stream-mmap --stream-count=20 >/dev/null 2>&1
echo "stream2 rc=$?"
sleep 2
echo "--- reload the module ---"
pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1 || echo "rmmod failed"
sleep 1
sh /root/zz_v80.sh >/dev/null 2>&1
sh /root/zz_cam_up.sh >/dev/null 2>&1
echo "reload done rc=$?"
sleep 25
wait $MPID 2>/dev/null
echo "--- monitor log ---"
cat /tmp/devmon.log
echo "--- current devices ---"
timeout 60 python3 -c '
import gi
gi.require_version("Gst","1.0")
from gi.repository import Gst
Gst.init(None)
m = Gst.DeviceMonitor()
m.start()
print("count now:", len(m.get_devices()))
'
echo "=== zz_devmon done ==="
