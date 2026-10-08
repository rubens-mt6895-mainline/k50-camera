#!/bin/sh
# zz_devs8.sh - install the Gst typelib (one small package) and enumerate
# GstDeviceMonitor the way Cheese does.  Run as root and as k50.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "=== install gir1.2-gstreamer-1.0 ==="
timeout 240 apt-get install -y gir1.2-gstreamer-1.0 2>&1 | tail -5
echo "=== typelib now? ==="
ls -l /usr/lib/aarch64-linux-gnu/girepository-1.0/ | grep -i gst | head -5
cat > /tmp/gst_enum.py <<'PYEOF'
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
Gst.init(None)
print("gst", Gst.version_string())
mon = Gst.DeviceMonitor()
mon.add_filter('Video', Gst.Caps.from_string('video/x-raw'))
mon.start()
devs = mon.get_devices()
print("device count:", len(devs))
for i, d in enumerate(devs):
    print("[%d] name=%r class=%r display=%r" % (i, d.get_name(), d.get_device_class(), d.get_display_name()))
    props = d.get_properties()
    if props is not None:
        for k in ('api.v4l2.path', 'device.api', 'v4l2.device.card', 'v4l2.device.driver',
                  'v4l2.device.bus_info', 'device.path'):
            if props.has_field(k):
                print("      %s = %r" % (k, props.get_string(k)))
    caps = d.get_caps()
    if caps is not None:
        for j in range(min(caps.get_size(), 8)):
            print("      caps: %s" % caps.get_structure(j).to_string())
mon.stop()
PYEOF
echo "=== enumerate as root ==="
timeout 90 python3 /tmp/gst_enum.py 2>&1 | head -60
echo "=== enumerate as k50 ==="
su k50 -s /bin/sh -c 'timeout 90 python3 /tmp/gst_enum.py' 2>&1 | head -60
echo "=== zz_devs8 done ==="
