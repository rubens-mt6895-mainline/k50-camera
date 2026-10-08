#!/bin/sh
# zz_field.sh - does the current module accept an interlaced field?  A probe
# with V4L2_FIELD_ALTERNATE that succeeds is what makes GStreamer advertise an
# extra interlace-mode=alternate caps entry for the same size.  Read-only:
# TRY_FMT does not touch the stream.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "=== try_fmt with field=alternate ==="
v4l2-ctl -d /dev/video0 --try-fmt-video=width=960,height=540,pixelformat=YUYV,field=alternate 2>&1
echo "rc=$?"
echo "=== try_fmt with field=none ==="
v4l2-ctl -d /dev/video0 --try-fmt-video=width=960,height=540,pixelformat=YUYV,field=none 2>&1
echo "rc=$?"
echo "=== try_fmt with field=any ==="
v4l2-ctl -d /dev/video0 --try-fmt-video=width=960,height=540,pixelformat=YUYV,field=any 2>&1
echo "rc=$?"
echo "=== g_fmt ==="
v4l2-ctl -d /dev/video0 --get-fmt-video 2>&1 | head -12
echo "=== zz_field done ==="
