#!/usr/bin/env python3
# z_cam_ro_dump.py - READ-ONLY camera state dump (no writes!)
import mmap, os, struct, time

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def rd(a):
    pg = a & ~0xfff
    if pg not in _c: _c[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return struct.unpack_from('<I', _c[pg], a & 0xfff)[0]

CSI2 = 0x1A014A00   # intf4
CTRL = 0x1A014200
TOP  = 0x1A010000
MUX12 = 0x1A01CD00  # if_base + 0xd00 + 0x1000*12 (corrected!)
CAM0  = 0x1A010400  # cammux0 PCSR
GCSR  = 0x1A010300
DPHY  = 0x11C86000  # port2 dphy_top (3_0)
ANAA  = 0x11C84000
ANAB  = 0x11C85000

print("== gate/domain ==")
print("cam_m gate 0x1a000000 = %08x" % rd(0x1a000000))

print("== CSI2 intf4 (0x1A014A00) ==")
for off, nm in [(0x00,'EN'),(0x04,'OPT'),(0x08,'HDR_MODE_0'),(0x10,'RESYNC_MERGE'),
                (0xc0,'IRQ_EN'),(0xc8,'IRQ_STATUS'),(0xd4,'PACKET_STATUS'),
                (0xd8,'GEN_SHORT_STATUS'),(0xdc,'PKT_CNT'),(0xe0,'DBG_CTRL'),(0xf4,'DBG_OUT')]:
    print("  +%02x %-15s = %08x" % (off, nm, rd(CSI2+off)))
p1 = rd(CSI2+0xdc); time.sleep(0.5); p2 = rd(CSI2+0xdc)
print("  PKT cnt t0=%08x t1=%08x %s" % (p1, p2, '<<< RISING!' if p1 != p2 else '(static)'))

print("== DPHY port2 (0x11C86000) ==")
for off, nm in [(0x00,'LANE_EN'),(0x04,'LANE_SELECT'),(0x08,'HS_RX_EN_SW'),
                (0x10,'CLK0_HS'),(0x14,'CLK1_HS'),(0x20,'DL0_HS'),(0x24,'DL1_HS'),
                (0x28,'DL2_HS'),(0x2c,'DL3_HS'),(0x30,'CLK_FSM'),(0x34,'DATA_FSM'),
                (0xf0,'SPARE0'),(0x180,'V21_CTRL'),(0x260,'STATE_CHK_EN'),
                (0x270,'ST_CHK_L0'),(0x274,'ST_CHK_L1'),(0x278,'ST_CHK_L2'),(0x27c,'ST_CHK_L3')]:
    print("  +%03x %-12s = %08x" % (off, nm, rd(DPHY+off)))

print("== ANA A/B ==")
for P, tag in [(ANAA,'A'),(ANAB,'B')]:
    print("  ANA%s +0x00=%08x +0x20=%08x" % (tag, rd(P+0x00), rd(P+0x20)))

print("== TOP ==")
print("  +0x18 MUX_CTRL_2 = %08x (mux9-12 src)" % rd(TOP+0x18))
print("  +0x48 PHY_CTRL_CSI2 = %08x" % rd(TOP+0x48))
print("  +0x14 MUX_CTRL_1 = %08x" % rd(TOP+0x14))

print("== MUX12 (0x1A01CD00) ==")
for off, nm in [(0x00,'CTRL_0'),(0x04,'CTRL_1'),(0x08,'OPT'),(0x10,'IRQ_EN'),(0x18,'IRQ_STATUS')]:
    print("  +%02x %-10s = %08x" % (off, nm, rd(MUX12+off)))

print("== cam0 PCSR (0x1A010400) / GCSR (0x1A010300) ==")
for off, nm in [(0x00,'CTRL'),(0x04,'OPT'),(0x08,'IRQ_EN'),(0x0c,'IRQ_STATUS'),(0x14,'CHK_CTL'),(0x18,'CHK_RES'),(0x1c,'CHK_ERR')]:
    print("  cam0 +%02x %-9s = %08x" % (off, nm, rd(CAM0+off)))
for off, nm in [(0x00,'CTRL'),(0x04,'DYN_CTRL'),(0x08,'IRQ_EN'),(0x0c,'IRQ_STS')]:
    print("  gcsr +%02x %-9s = %08x" % (off, nm, rd(GCSR+off)))
