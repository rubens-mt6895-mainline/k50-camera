#!/bin/sh
# zz_gst_switch2.sh - same live caps switch as zz_gst_switch.sh, but counts the
# buffers that actually arrive after every switch: a renegotiation that wedges
# leaves the application showing a frozen image with no GStreamer error.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "=== free the camera ==="
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
dmesg -c >/dev/null

cat > /tmp/gst_switch2.py <<'EOF'
import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst, GLib

Gst.init(None)
pipe = Gst.parse_launch(
    "v4l2src name=src ! capsfilter name=cf ! fakesink name=fs sync=false async=false")
src = pipe.get_by_name("src")
cf = pipe.get_by_name("cf")
bus = pipe.get_bus()

seq = [(960, 540), (1920, 1080), (4000, 2256), (2000, 1500), (1920, 1080), (2000, 1500)]
state = {"i": 0, "nbuf": 0, "mark": 0, "errors": 0}


def probe(pad, info):
    if info.type & Gst.PadProbeType.BUFFER:
        state["nbuf"] += 1
    return Gst.PadProbeReturn.OK


src.get_static_pad("src").add_probe(Gst.PadProbeType.BUFFER, probe)


def step():
    i = state["i"]
    got = state["nbuf"] - state["mark"]
    state["mark"] = state["nbuf"]
    if i == 0:
        print("startup: %d buffers" % got, flush=True)
    else:
        w, h = seq[i - 1]
        print("after switch %d (%dx%d): %d buffers" % (i, w, h, got), flush=True)
    if i >= len(seq):
        print("DONE %d switches, total buffers=%d, errors=%d"
              % (len(seq), state["nbuf"], state["errors"]), flush=True)
        pipe.set_state(Gst.State.NULL)
        GLib.timeout_add(300, lambda: (ml.quit(), False)[1])
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
    return True


bus.add_signal_watch()
bus.connect("message", on_bus)
ml = GLib.MainLoop()
pipe.set_state(Gst.State.PLAYING)
GLib.timeout_add(3000, step)
GLib.timeout_add_seconds(70, lambda: (print("TIMEOUT", flush=True), pipe.set_state(Gst.State.NULL), ml.quit(), False)[3])
ml.run()
print("exit", flush=True)
EOF

echo "=== run (timeout 100) ==="
timeout 100 python3 /tmp/gst_switch2.py > /tmp/gst_switch2.log 2>&1
echo "gst rc=$?"
grep -E '^(startup|after|-->|DONE|TIMEOUT|ERROR|WARN|exit)' /tmp/gst_switch2.log

echo "=== driver log ==="
dmesg | grep -E 'cam_cap: (v4l2|mode|rx|arm seq)' | tail -25

echo "=== state ==="
grep -E '^(vf_on|arm_count|frame_ready|last_result)' /proc/camcap_info | head -6

echo "=== health ==="
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
uptime
echo "=== zz_gst_switch2 done ==="
