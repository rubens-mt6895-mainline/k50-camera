#!/bin/sh
# zz_modechk.sh - why does "echo 'mode custom2 1' > /proc/camcap" fail while the
# ioctl path works?  Compare the one-argument and two-argument spellings and a
# genuinely unknown command, and watch the driver's own messages.
set -u

show() {
	dmesg | grep 'cam_cap:' | grep -vE '[0-9]+/[0-9]+ 0x[0-9a-f]+$' | tail -12 | sed 's/^/  /'
}

regs() {
	echo "  0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1) active=$(grep -c 'mode:' /dev/null 2>/dev/null; true)"
}

echo "=== A. two arguments: mode preview 2 ==="
dmesg -c >/dev/null 2>&1
echo "mode preview 2" > /proc/camcap; echo "  rc=$?"
show
regs

echo
echo "=== B. one argument: mode preview ==="
dmesg -c >/dev/null 2>&1
echo "mode preview" > /proc/camcap; echo "  rc=$?"
show
regs

echo
echo "=== C. unknown command (what does an unknown command return?) ==="
dmesg -c >/dev/null 2>&1
echo "bogus" > /proc/camcap; echo "  rc=$?"
show

echo
echo "=== D. ls /proc/camcap_info mode/timing ==="
grep -E '^(mode|timing|stats)' /proc/camcap_info 2>/dev/null | sed 's/^/  /'

echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
echo "### zz_modechk done"
