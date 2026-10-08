#!/bin/sh
# zz_devs12.sh - (1) how many cameras does GStreamer see after 6 live resolution
# switches and no module reload?  (2) what does a *second* file descriptor on
# /dev/video0 get while the first one is streaming?
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
dmesg -c >/dev/null

cat > /tmp/dev_enum.py <<'PYEOF'
import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst
Gst.init(None)
m = Gst.DeviceMonitor()
m.add_filter("Video", Gst.Caps.from_string("video/x-raw"))
m.start()
d = m.get_devices()
print("count:", len(d))
for x in d:
    print("   name=%s display=%r path=%r driver=%r" % (
        x.get_name(), x.get_display_name(),
        x.get_properties().get_string("device.path"),
        x.get_properties().get_string("v4l2.device.driver")))
m.stop()
PYEOF

cat > /tmp/dev_twofd.py <<'PYEOF'
import ctypes, fcntl, os, time

class Pix(ctypes.Structure):
    _fields_ = [("width", ctypes.c_uint32), ("height", ctypes.c_uint32),
                ("pixelformat", ctypes.c_uint32), ("field", ctypes.c_uint32),
                ("bytesperline", ctypes.c_uint32), ("sizeimage", ctypes.c_uint32),
                ("colorspace", ctypes.c_uint32), ("priv", ctypes.c_uint32),
                ("flags", ctypes.c_uint32), ("ycbcr_enc", ctypes.c_uint32),
                ("quantization", ctypes.c_uint32), ("xfer_func", ctypes.c_uint32),
                ("reserved", ctypes.c_uint32 * 38)]      # union = 200 bytes

class Fmt(ctypes.Structure):
    # the kernel union is 8-byte aligned, so the payload starts at offset 8
    _fields_ = [("type", ctypes.c_uint32), ("_pad", ctypes.c_uint32), ("fmt", Pix)]

class Req(ctypes.Structure):
    _fields_ = [("count", ctypes.c_uint32), ("type", ctypes.c_uint32),
                ("memory", ctypes.c_uint32), ("capabilities", ctypes.c_uint32),
                ("flags", ctypes.c_uint32)]

S_FMT = 0xC0D05605          # _IOWR(V, 5, struct v4l2_format)
REQBUFS = 0xC0145608        # _IOWR(V, 8, struct v4l2_requestbuffers)
STREAMON = 0x40045612       # _IO(V, 18)
STREAMOFF = 0x40045613      # _IO(V, 19)
CAPTURE = 1
MMAP = 1

print("sizes: Fmt=%d Req=%d" % (ctypes.sizeof(Fmt), ctypes.sizeof(Req)))

def s_fmt(fd, w, h):
    f = Fmt(type=CAPTURE)
    f.fmt.width, f.fmt.height, f.fmt.pixelformat, f.fmt.field = w, h, 0x56595559, 0
    try:
        fcntl.ioctl(fd, S_FMT, f)
        return "ok -> %dx%d" % (f.fmt.width, f.fmt.height)
    except OSError as e:
        return "error: %s (%d)" % (e.strerror, e.errno)

def reqbufs(fd, n):
    r = Req(count=n, type=CAPTURE, memory=MMAP)
    try:
        fcntl.ioctl(fd, REQBUFS, r)
        return "ok count=%d" % r.count
    except OSError as e:
        return "error: %s (%d)" % (e.strerror, e.errno)

def onoff(fd, num):
    t = ctypes.c_int(CAPTURE)
    try:
        fcntl.ioctl(fd, num, t)
        return "ok"
    except OSError as e:
        return "error: %s (%d)" % (e.strerror, e.errno)

a = os.open("/dev/video0", os.O_RDWR)
b = os.open("/dev/video0", os.O_RDWR)
print("fd A:", a, " fd B:", b)
print("A s_fmt 2000x1500 :", s_fmt(a, 2000, 1500))
print("A reqbufs 4       :", reqbufs(a, 4))
print("A streamon        :", onoff(a, STREAMON))
time.sleep(1)
print("B s_fmt 1920x1080 :", s_fmt(b, 1920, 1080), "  <- clicking the duplicate entry")
print("B reqbufs 4       :", reqbufs(b, 4))
print("B streamon        :", onoff(b, STREAMON))
time.sleep(1)
print("A streamoff       :", onoff(a, STREAMOFF))
time.sleep(1)
print("B s_fmt 1920x1080 :", s_fmt(b, 1920, 1080), "  <- after the first one let go")
print("B reqbufs 4       :", reqbufs(b, 4))
print("B streamon        :", onoff(b, STREAMON))
time.sleep(1)
print("B streamoff       :", onoff(b, STREAMOFF))
os.close(a)
os.close(b)
PYEOF

echo "=== 1. enumeration after the switch test (no reload since) ==="
timeout 40 python3 /tmp/dev_enum.py 2>&1

echo
echo "=== 2. two file descriptors on the same device ==="
timeout 60 python3 /tmp/dev_twofd.py 2>&1

echo
echo "=== 3. state ==="
echo "    /dev : $(ls /dev/video* 2>/dev/null | tr '\n' ' ')"
echo "    sysfs: $(ls /sys/class/video4linux/ 2>/dev/null | tr '\n' ' ')"
grep -E '^(vf_on|arm_count|frame_ready|last_result)' /proc/camcap_info | head -6
echo "=== driver log ==="
dmesg | grep -E 'cam_cap: (v4l2|mode|rx|arm seq)' | tail -12
echo "=== health ==="
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
uptime
echo "=== zz_devs12 done ==="
