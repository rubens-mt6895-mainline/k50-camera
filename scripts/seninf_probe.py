#!/usr/bin/env python3
# seninf_probe.py v2 - full analog+digital CSI2 RX init per ISP7.1
# reference, then probe PKT_CNT on each CSI port.
import mmap, os, struct, time

IF_BASE = 0x1a010000
ANA_BASE = 0x11c80000
SETTLE_DT = 0x10
HS_TRAIL = 0x34

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_cache = {}
def _map(pg):
    if pg not in _cache:
        _cache[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return _cache[pg]
def rd(addr):
    m = _map(addr & ~0xfff)
    return struct.unpack_from('<I', m, addr & 0xfff)[0]
def wr(addr, val):
    m = _map(addr & ~0xfff)
    struct.pack_into('<I', m, addr & 0xfff, val)
def rmw(addr, mask, val):
    wr(addr, (rd(addr) & ~mask) | (val & mask))
    return rd(addr)

def bits(addr, shift, mask_width, value):
    rmw(addr, ((1 << mask_width) - 1) << shift, value << shift)

def lane_param():
    return (2 << 0) | (HS_TRAIL << 8) | (SETTLE_DT << 16) | \
           (1 << 28) | (1 << 29)

def setup_port(sidx, rx_off, dphy_off):
    rx = ANA_BASE + rx_off
    dphy = ANA_BASE + dphy_off
    ctrl = IF_BASE + 0x200 + 0x1000 * (sidx - 1)
    csi2 = IF_BASE + 0xA00 + 0x1000 * (sidx - 1)

    # -- phyA power on (disable first) --
    rmw(rx + 0x20, 0x3f << 16, 0)         # EQ_OS_CAL_EN x6 = 0
    rmw(rx + 0x0, 0x2, 0)                 # BG_LPF_EN = 0
    rmw(rx + 0x0, 0x1, 0)                 # BG_CORE_EN = 0
    time.sleep(0.0002)
    rmw(rx + 0x0, 0x1, 0x1)               # BG_CORE_EN = 1
    time.sleep(0.00003)
    rmw(rx + 0x0, 0x2, 0x2)               # BG_LPF_EN = 1
    rmw(rx + 0x20, 0x3f << 16, 0x3f << 16)
    time.sleep(0.000001)

    # -- phyA init (csirx_phyA_init) --
    bits(rx + 0x04, 0, 3, 0x4)            # BG_LPRX_VTL_SEL=4
    bits(rx + 0x04, 4, 3, 0x4)            # BG_LPRX_VTH_SEL=4
    bits(rx + 0x08, 28, 3, 0x4)           # BG_ALP_RX_VTL_SEL=4
    bits(rx + 0x08, 24, 3, 0x4)           # BG_ALP_RX_VTH_SEL=4
    bits(rx + 0x04, 8, 4, 0x8)            # BG_VREF_SEL=8
    bits(rx + 0x04, 16, 3, 0x2)           # EQ_DES_VREF_SEL=2
    bits(rx + 0x14, 0, 2, 0x3)            # EQ_BW=3
    bits(rx + 0x14, 2, 2, 0x1)            # EQ_IS=1
    bits(rx + 0x14, 6, 1, 0x1)            # EQ_LATCH_EN=1
    bits(rx + 0x14, 4, 1, 0x1)            # EQ_DG0_EN=1
    bits(rx + 0x14, 5, 1, 0x1)            # EQ_DG1_EN=1
    bits(rx + 0x14, 8, 4, 0x0)            # EQ_SR0=0
    bits(rx + 0x14, 12, 4, 0x0)           # EQ_SR1=0
    rmw(rx + 0x24, 0xffff << 16, 0x3003 << 16)  # RESERVE=0x3003
    rmw(rx + 0xf0, 0x3 << 16, 0x2 << 16)  # CSR_CSI_RST_MODE=2
    bits(rx + 0x08, 0, 5, 0x10)           # L0P_HSRT=0x10
    bits(rx + 0x08, 8, 5, 0x10)           # L0N_HSRT=0x10
    bits(rx + 0x0c, 0, 5, 0x10)           # L1P_HSRT=0x10
    bits(rx + 0x0c, 8, 5, 0x10)           # L1N_HSRT=0x10
    bits(rx + 0x10, 0, 5, 0x10)           # L2P_HSRT=0x10
    bits(rx + 0x10, 8, 5, 0x10)           # L2N_HSRT=0x10
    rmw(rx + 0x0, 0x1 << 21, 0)           # T0_CDR_FIRST_EDGE=0
    rmw(rx + 0x0, 0x1 << 22, 0)           # T1_CDR_FIRST_EDGE=0
    rmw(rx + 0x08, 0x1 << 16, 0)          # T0_SELF_CAL=0
    rmw(rx + 0x08, 0x1 << 17, 0)          # T1_SELF_CAL=0
    bits(rx + 0x18, 24, 6, 0x0)           # T0_CK_DELAY=0
    bits(rx + 0x1c, 24, 6, 0x0)           # T1_CK_DELAY=0
    bits(rx + 0x18, 0, 6, 0x9)            # T0_AB=9
    bits(rx + 0x18, 8, 6, 0x9)            # T0_BC=9
    bits(rx + 0x18, 16, 6, 0x9)           # T0_CA=9
    bits(rx + 0x1c, 0, 6, 0x9)            # T1_AB=9
    bits(rx + 0x1c, 8, 6, 0x9)            # T1_BC=9
    bits(rx + 0x1c, 16, 6, 0x9)           # T1_CA=9

    # -- dphy lane params --
    for lane in range(4):
        wr(dphy + 0x20 + 4 * lane, lane_param())

    # -- CSI2 digital --
    rmw(csi2 + 0xE0, 1 << 17, 1 << 17)    # DBG_PACKET_CNT_EN
    rmw(csi2 + 0x10, 1 << 8, 1 << 8)      # RESYNC_CYCLE_CNT_OPT
    wr(csi2 + 0x0, 0xF)                   # CSI2_EN lanes 0-3
    rmw(csi2 + 0x4, 0x1, 0x0)             # CPHY_SEL=0
    wr(csi2 + 0x8, 0x0)                   # HDR_MODE_0

    # -- SENINF ctrl --
    rmw(ctrl + 0x10, 0x1, 0x1)            # RG_SENINF_CSI2_EN
    rmw(ctrl + 0x0, 0x1, 0x1)             # SENINF_EN
    return ctrl, csi2

print('# full analog+digital CSI2 init, probing PKT_CNT', flush=True)
for port, (sidx, rx_off, dphy_off) in {
        '0A': (1, 0x00000, 0x02000),
        '1A': (3, 0x04000, 0x06000),
        '2A': (5, 0x08000, 0x0A000)}.items():
    ctrl, csi2 = setup_port(sidx, rx_off, dphy_off)
    c1 = rd(csi2 + 0xDC)
    time.sleep(0.2)
    c2 = rd(csi2 + 0xDC)
    irq = rd(csi2 + 0xC8)
    fsm_c = rd(ANA_BASE + dphy_off + 0x30)
    fsm_d = rd(ANA_BASE + dphy_off + 0x34)
    print('port %s (seninf%d): pkt %08x->%08x %s irq=%08x clkFSM=%08x dataFSM=%08x'
          % (port, sidx, c1, c2, 'ACTIVE' if c2 != c1 else '',
             irq, fsm_c, fsm_d), flush=True)
