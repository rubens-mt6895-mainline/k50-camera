#!/usr/bin/env python3
"""sensor_bring.py - replay a sensor's vendor register tables and start streaming.

    sensor_bring.py <bus> <addr> <table.txt> [table.txt ...]

The table files are `0xREG 0xVAL` lines, as produced by gen_sensor_tables.py
from the upstream driver's `struct cci_reg_sequence` arrays.

The order and the delays mirror the verified IMX582 sequence in
imx582_bring.py: stream off, 20 ms, each table in turn, 20 ms between them,
then stream on and 50 ms.  The first table is the sensor's init sequence, the
rest are mode tables; the last one wins for any register they share.
"""
import ctypes
import fcntl
import os
import sys
import time

I2C_RDWR = 0x0707


class i2c_msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16),
                ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16),
                ("buf", ctypes.POINTER(ctypes.c_uint8))]


class i2c_rdwr_ioctl_data(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(i2c_msg)),
                ("nmsgs", ctypes.c_uint32)]


def make_helpers(fd, addr, a8=False):
    # a8=True selects the 8-bit register address layout (one address byte, one
    # data byte) used by the GalaxyCore parts; the default is the 16-bit
    # address layout the Sony and Samsung sensors use on this board.
    alen = 1 if a8 else 2

    def wr(reg, val):
        buf = (ctypes.c_uint8 * (alen + 1))()
        if a8:
            buf[0] = reg & 0xff
        else:
            buf[0] = (reg >> 8) & 0xff
            buf[1] = reg & 0xff
        buf[alen] = val & 0xff
        msg = i2c_msg(addr, 0, alen + 1,
                      ctypes.cast(buf, ctypes.POINTER(ctypes.c_uint8)))
        data = i2c_rdwr_ioctl_data(ctypes.pointer(msg), 1)
        fcntl.ioctl(fd, I2C_RDWR, data)

    def rd(reg):
        abuf = (ctypes.c_uint8 * alen)()
        if a8:
            abuf[0] = reg & 0xff
        else:
            abuf[0] = (reg >> 8) & 0xff
            abuf[1] = reg & 0xff
        vbuf = (ctypes.c_uint8 * 1)(0)
        msgs = (i2c_msg * 2)()
        msgs[0] = i2c_msg(addr, 0, alen,
                          ctypes.cast(abuf, ctypes.POINTER(ctypes.c_uint8)))
        msgs[1] = i2c_msg(addr, 1, 1,
                          ctypes.cast(vbuf, ctypes.POINTER(ctypes.c_uint8)))
        data = i2c_rdwr_ioctl_data(msgs, 2)
        fcntl.ioctl(fd, I2C_RDWR, data)
        return vbuf[0]

    return wr, rd


def load_table(path):
    pairs = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        reg, val = line.split()
        pairs.append((int(reg, 16), int(val, 16)))
    return pairs


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    bus = int(sys.argv[1])
    addr = int(sys.argv[2], 0)
    tables = sys.argv[3:]
    # A8=1 selects the 8-bit register address layout (GalaxyCore GC02M1); the
    # default is the 16-bit layout used by the Sony/Samsung sensors here.
    a8 = os.environ.get("A8", "") not in ("", "0")
    # Stream-on register: 0x0100 = 1 for the Sony/Samsung parts, 0x3e = 0x90
    # for the GC02M1 (its vendor driver's REG_STREAM / STREAM_ON / STREAM_OFF).
    # Overridable so the same helper covers other 8-bit parts.
    sreg = int(os.environ.get("SREG", "0x3e" if a8 else "0x0100"), 0)
    son = int(os.environ.get("SON", "0x90" if a8 else "0x01"), 0)
    soff = int(os.environ.get("SOFF", "0x00"), 0)

    dev = "/dev/i2c-%d" % bus
    fd = os.open(dev, os.O_RDWR)
    wr, rd = make_helpers(fd, addr, a8)
    print("== %s @0x%02x (reg addr %d bit) ==" % (dev, addr, 8 if a8 else 16))
    if a8:
        print("   id: 0x00f0=0x%02x 0x00f1=0x%02x" % (rd(0x00f0), rd(0x00f1)))
    else:
        print("   id: 0x0016=0x%02x 0x0017=0x%02x 0x0018=0x%02x"
              % (rd(0x0016), rd(0x0017), rd(0x0018)))

    print("== stream off (0x%04x = 0x%02x) ==" % (sreg, soff))
    wr(sreg, soff)
    time.sleep(0.02)

    for t in tables:
        pairs = load_table(t)
        print("== %s: %d pairs ==" % (os.path.basename(t), len(pairs)))
        t0 = time.time()
        for reg, val in pairs:
            wr(reg, val)
        print("   %d writes in %.1f ms"
              % (len(pairs), (time.time() - t0) * 1000.0))
        time.sleep(0.02)

    print("== stream on (0x%04x = 0x%02x) ==" % (sreg, son))
    wr(sreg, son)
    time.sleep(0.05)

    print("== after ==")
    regs = ((0x00f0, 0x00f1, 0x003e, 0x003f, 0x00fe, 0x00ff) if a8 else
            (0x0100, 0x0101, 0x0112, 0x0113, 0x0114, 0x0115,
             0x0307, 0x030e, 0x030f, 0x0310,
             0x0340, 0x0341, 0x0342, 0x0343, 0x034c, 0x034d, 0x034e, 0x034f))
    for r in regs:
        print("  0x%04x = 0x%02x" % (r, rd(r)))

    os.close(fd)
    print("== sensor_bring done ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
