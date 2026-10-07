#!/bin/sh
# zz_v72.sh -- device-side diagnostic: power/GPIO/I2C + register writability
echo "=== date ==="; date; uptime
echo "=== lsmod ==="; lsmod
echo "=== gpio exports ==="; ls /sys/class/gpio/ 2>&1 | tr '\n' ' '; echo
echo "=== gpio values ==="
for g in 149 20 159 158 155 152 164; do
  if [ -d /sys/class/gpio/gpio$g ]; then
    echo "gpio$g dir=$(cat /sys/class/gpio/gpio$g/direction 2>/dev/null) val=$(cat /sys/class/gpio/gpio$g/value 2>/dev/null)"
  else
    echo "gpio$g NOT-exported"
  fi
done
echo "=== regulators (cam-related) ==="
grep -iE "vcam|cam|fan|dovdd|afvdd|vbuck|vmm|dvfs" /sys/kernel/debug/regulator/regulator_summary 2>&1 | head -40
echo "=== i2c adapters ==="
ls /sys/class/i2c-adapter/ 2>&1 | tr '\n' ' '; echo
for b in 8 9 10 11; do
  echo "--- i2cdetect -y -r $b ---"
  i2cdetect -y -r $b 2>&1
done
echo "=== sensor reads (bus 10 @0x10) ==="
i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1
i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1
i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1
echo "=== GPIO / MCLK regs ==="
for a in 10005000 10005040 10005050 10005100 10005140 10005150 10005200 10005240 10005250 10005420 10005430 10005440; do
  printf "%s = %s\n" "$a" "$(busybox devmem 0x$a)"
done
echo "=== dmesg cam/i2c ==="
dmesg | grep -iE "i2c|mt65xx|pinctrl|fan53870|cam_|seninf|regulator" 2>&1 | tail -40
echo "=== DPHY/CSI2 register writability (write 0xffffffff, read, restore) ==="
python3 - <<'PYEOF'
import mmap, os, struct
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
cache = {}
def pg(a):
    b = a & ~0xfff
    if b not in cache:
        cache[b] = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED,
                             mmap.PROT_READ | mmap.PROT_WRITE, offset=b)
    return cache[b], a - b
def rd(a):
    m, o = pg(a); return struct.unpack("<I", m[o:o+4])[0]
def wr(a, v):
    m, o = pg(a); m[o:o+4] = struct.pack("<I", v & 0xffffffff)
tests = [(0x11C86000, "DPHY_2"), (0x1A014A00, "CSI2_2"), (0x1A014200, "CTRL_2")]
offs = (0x00, 0x04, 0x08, 0x10, 0x14, 0x20, 0x30, 0x8c, 0xe0, 0x10)
for base, name in tests:
    for off in offs:
        a = base + off
        orig = rd(a)
        wr(a, 0xFFFFFFFF); got = rd(a)
        wr(a, orig)
        print("%s+%03x orig=%08x wmask=%08x %s" % (name, off, orig, got,
              "READONLY" if got == 0 else ("ALL-WR" if got == 0xffffffff else "PARTIAL")))
PYEOF
echo "=== done ==="
