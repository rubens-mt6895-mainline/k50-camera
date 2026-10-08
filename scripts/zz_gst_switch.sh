#!/bin/sh
# zz_gst_switch.sh - reproduce what Cheese does when the user picks another
# resolution: one v4l2src pipeline that stays PLAYING while the capsfilter's
# caps change (i.e. a live renegotiation: STREAMOFF -> S_FMT -> STREAMON on the
# same open file handle, buffers kept allocated).
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "=== free the camera ==="
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

echo "=== reload cam_cap (preview 2000x1500, conv_threads=8, pipeline=1) ==="
rmmod cam_cap 2>&1
sh /root/zz_v80.sh >/dev/null 2>&1
echo "v80 rc=$?"
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1" sh /root/zz_cam_up.sh >/dev/null 2>&1
echo "cam_up rc=$?"
sleep 1
dmesg -c >/dev/null

cat > /tmp/gst_switch.py <<'EOF'
import gi, sys
gi.require_version("Gst", "1.0")
from gi.repository import Gst, GLib

Gst.init(None)
pipe = Gst.parse_launch(
    "v4l2src name=src ! capsfilter name=cf ! fakesink name=fs sync=false async=false")
cf = pipe.get_by_name("cf")
bus = pipe.get_bus()

seq = [(960, 540), (1920, 1080), (4000, 2256), (2000, 1500), (1920, 1080)]
state = {"i": 0, "errors": 0}


def step():
    i = state["i"]
    if i >= len(seq):
        print("DONE all %d switches, errors=%d" % (len(seq), state["errors"]), flush=True)
        pipe.set_state(Gst.State.NULL)
        GLib.timeout_add(500, lambda: (ml.quit(), False)[1])
        return False
    w, h = seq[i]
    state["i"] = i + 1
    print("--> %d: set caps %dx%d" % (i + 1, w, h), flush=True)
    cf.set_property("caps", Gst.Caps.from_string("video/x-raw,width=%d,height=%d" % (w, h)))
    return True


def on_bus(bus, msg):
    t = msg.type
    if t == Gst.MessageType.ERROR:
        err, dbg = msg.parse_error()
        state["errors"] += 1
        print("ERROR: %s | %s" % (err.message, (dbg or "").splitlines()[0] if dbg else ""), flush=True)
    elif t == Gst.MessageType.WARNING:
        w, _ = msg.parse_warning()
        print("WARN: %s" % w.message, flush=True)
    elif t == Gst.MessageType.EOS:
        print("EOS", flush=True)
    return True


bus.add_signal_watch()
bus.connect("message", on_bus)
ml = GLib.MainLoop()
pipe.set_state(Gst.State.PLAYING)
GLib.timeout_add(2000, step)


def give_up():
    print("TIMEOUT after %d switches, errors=%d" % (state["i"], state["errors"]), flush=True)
    pipe.set_state(Gst.State.NULL)
    ml.quit()
    return False


GLib.timeout_add_seconds(60, give_up)
ml.run()
print("exit", flush=True)
EOF

echo "=== run the switching pipeline (timeout 90, v4l2 ioctl trace) ==="
GST_DEBUG=v4l2src:5,v4l2object:5,v4l2bufferpool:5 GST_DEBUG_NO_COLOR=1 \
	timeout 90 python3 /tmp/gst_switch.py > /tmp/gst_switch.log 2>&1
echo "gst rc=$?"
echo "--- our prints ---"
grep -E '^(-->|DONE|TIMEOUT|ERROR|WARN|EOS|exit)' /tmp/gst_switch.log | tail -30
echo "--- ioctl trace (S_FMT / REQBUFS / STREAMON / STREAMOFF / errors) ---"
grep -aoE '(S_FMT|TRY_FMT|REQBUFS|STREAMON|STREAMOFF|G_FMT)[^;]{0,120}' /tmp/gst_switch.log | tail -40
echo "--- failures mentioned ---"
grep -aiE 'EBUSY|failed|error|not (supported|negotiat)' /tmp/gst_switch.log | tail -25

echo "=== driver log ==="
dmesg | grep -E 'cam_cap: (v4l2|mode|rx|convert|arm)' | tail -30

echo "=== state ==="
grep -E '^(vf_on|arm_count|frame_ready|last_result|out)' /proc/camcap_info | head -12
fuser -v /dev/video0 2>&1 | head -5

echo "=== health ==="
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
free -m | head -2
uptime
echo "=== zz_gst_switch done ==="
