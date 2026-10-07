#!/bin/sh
# device-side driver for port2_rx71.py
date; uptime
echo "--- lsmod ---"; lsmod
echo "--- GPIO152 mux (0x10005430, want bit0=1) ---"; busybox devmem 0x10005430
echo "--- files ---"; ls -l /root/cam_go_v6.sh /root/port2_rx71.py 2>&1

if ! lsmod | grep -q cam_rails; then
  echo "--- cam_rails not loaded: running /root/cam_go_v6.sh ---"
  sh /root/cam_go_v6.sh 2>&1 | tail -40
else
  echo "--- cam_rails already loaded; reloading rails+clk only ---"
  for m in cam_rails; do rmmod $m 2>/dev/null; done
  insmod /root/cam_rails.ko 2>/dev/null || modprobe cam_rails 2>/dev/null
fi

echo "--- sensor id read (bus 10 @0x10) ---"
i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1
i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1

echo "=== running port2_rx71.py (10s sample) ==="
python3 /root/port2_rx71.py 10 2>&1
