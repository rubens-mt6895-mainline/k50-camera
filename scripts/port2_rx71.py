#!/usr/bin/env python3
# port2_rx71.py -- IMX582 / CSI port 2 (4d1c, D-PHY) VENDOR-EXACT bring-up
#
# Faithful re-implementation of mtk_cam_seninf_set_csi_mipi() from
#   isp71_ref/mtk_csi_phy_3_0/mtk_cam-seninf-hw_phy_3_0.c   (3933 lines)
# with the compile-time constants actually used by the vendor kernel:
#   __SMT=0  SENINF_CK=273000000  CYCLE_MARGIN=1  RESYNC_DMY_CNT=4
#   FIX_DPHY_SETTLE=1  DPHY_SETTLE=0x1C  DPHY_TRAIL_SPEC=224
#   SENINF_HS_TRAIL_EN_CONDITION=1450000000
#   legacy_phy = 0 (non-legacy)
#
# Port 2 (CSI_PORT_2, is_4d1c=1, num_data_lanes=4, seninfIdx=4):
#   ANA A   = ana_base + 0x4000 = 0x11C84000
#   ANA B   = ana_base + 0x5000 = 0x11C85000
#   DPHY_TOP= ana_base + 0x6000 = 0x11C86000
#   CPHY_TOP= ana_base + 0x7000 = 0x11C87000
#   SENINF_TOP = 0x1A010000   (SENINF_TOP_PHY_CTRL_CSI2 = TOP + 0x48)
#   reg_if_ctrl = 0x1A014200  (SENINF_CTRL=+0x00, SENINF_CSI2_CTRL=+0x10)
#   reg_if_csi2 = 0x1A014A00
#
# Call order (mtk_cam_seninf_set_csi_mipi):
#   csirx_phy_init  -> phyA_init + dphy_init + cphy_init
#   csirx_seninf_setting
#   csirx_seninf_csi2_setting
#   csirx_seninf_top_setting
#   csirx_phy_setting -> phyA_setting (+power_on) then dphy_setting
import mmap, os, struct, sys, time

# ---------------- low level /dev/mem ---------------- #
PAGE = 0x1000
_fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
_cache = {}


def _pg(addr):
    b = addr & ~(PAGE - 1)
    if b not in _cache:
        _cache[b] = mmap.mmap(_fd, PAGE, mmap.MAP_SHARED,
                              mmap.PROT_READ | mmap.PROT_WRITE, offset=b)
    return _cache[b], addr - b


def rd(addr):
    m, o = _pg(addr)
    return struct.unpack("<I", m[o:o + 4])[0]


def wr(addr, val):
    m, o = _pg(addr)
    m[o:o + 4] = struct.pack("<I", val & 0xffffffff)
    return rd(addr)


def F(addr, shift, mask, val):
    """SENINF_BITS(): read-modify-write one field.

    `mask` is the UNSHIFTED field width (as in the vendor headers), so the
    register mask is mask << shift.  NOTE: passing a pre-shifted mask here is
    the classic bug -- it silently clears the field instead of setting it.
    """
    m = mask << shift
    v = rd(addr)
    v = (v & ~m) | ((val << shift) & m)
    return wr(addr, v)


# ---------------- addresses ---------------- #
ANA_BASE = 0x11C80000
A_A = ANA_BASE + 0x4000          # 0x11C84000  ANA A (CSI_PORT_2 / 2A)
A_B = ANA_BASE + 0x5000          # 0x11C85000  ANA B (CSI_PORT_2B)
DPHY = ANA_BASE + 0x6000         # 0x11C86000  DPHY_TOP
TOP = 0x1A010000
TOP_PHY = TOP + 0x48             # SENINF_TOP_PHY_CTRL_CSI(2) = 0x40 + 4*port
CTRL = 0x1A014200
CSI2 = 0x1A014A00

# ANA register offsets
ANA0, ANA1, ANA2, ANA3, ANA4, ANA5 = 0x00, 0x04, 0x08, 0x0c, 0x10, 0x14
ANA6, ANA7, ANA8 = 0x18, 0x1c, 0x20
ANA_SET0, ANA_SET1 = 0xf0, 0xf4

# ---------------- params ---------------- #
SENINF_CK = 273000000
CYCLE_MARGIN = 1
DPHY_SETTLE = 0x1C
DPHY_TRAIL_SPEC = 224
HS_TRAIL_EN_CONDITION = 1450000000
NUM_DATA_LANES = 4
BIT_PER_PIXEL = 10
MIPI_PIXEL_RATE = 548000000
DPHY_TRAIL_DT = 68          # ctx->csi_param.dphy_trail from the sensor DT

data_rate = MIPI_PIXEL_RATE * BIT_PER_PIXEL // NUM_DATA_LANES      # 1.37e9
cycles = 64 * SENINF_CK // data_rate + CYCLE_MARGIN                # 13
ui_224 = (DPHY_TRAIL_SPEC * 1000) // (data_rate // 1000000)        # 163
if DPHY_TRAIL_DT == 0 or DPHY_TRAIL_DT > ui_224:
    hs_trail = 0
else:
    t = (ui_224 - DPHY_TRAIL_DT) * SENINF_CK
    hs_trail = t // 1000000000 + (1 if t % 1000000000 else 0)      # 26
hs_trail_en = 1 if (DPHY_TRAIL_DT and hs_trail) else 0

DL_HS = (hs_trail << 8) | (DPHY_SETTLE << 16) | (hs_trail_en << 29)
CK_HS = (DPHY_SETTLE << 16)

# ======================================================================
def phase_phyA_init(base, tag):
    """csirx_phyA_init(): runs for A and B when is_4d1c."""
    F(base + ANA1, 0, 0x7, 4)         # RG_CSI0_BG_LPRX_VTL_SEL
    F(base + ANA1, 4, 0x7, 4)         # RG_CSI0_BG_LPRX_VTH_SEL
    F(base + ANA2, 24, 0x7, 4)        # RG_CSI0_BG_ALP_RX_VTL_SEL
    F(base + ANA2, 28, 0x7, 4)        # RG_CSI0_BG_ALP_RX_VTH_SEL
    F(base + ANA1, 8, 0xf, 8)         # RG_CSI0_BG_VREF_SEL
    F(base + ANA1, 16, 0x7, 2)        # RG_CSI0_CDPHY_EQ_DES_VREF_SEL
    # EQ defaults (overwritten later by phyA_setting, but the vendor does it)
    F(base + ANA5, 0, 0x3, 3)         # EQ_BW
    F(base + ANA5, 2, 0x3, 1)         # EQ_IS
    F(base + ANA5, 6, 0x1, 1)         # EQ_LATCH_EN
    F(base + ANA5, 4, 0x1, 1)         # EQ_DG0_EN
    F(base + ANA5, 5, 0x1, 1)         # EQ_DG1_EN
    F(base + ANA5, 8, 0xf, 0)         # EQ_SR0
    F(base + ANA5, 12, 0xf, 0)        # EQ_SR1
    # r50 termination codes = 0x10
    F(base + ANA2, 0, 0x1f, 0x10)     # L0P_T0A_HSRT_CODE
    F(base + ANA2, 8, 0x1f, 0x10)     # L0N_T0B_HSRT_CODE
    F(base + ANA3, 0, 0x1f, 0x10)     # L1P_T0C_HSRT_CODE
    F(base + ANA3, 8, 0x1f, 0x10)     # L1N_T1A_HSRT_CODE
    F(base + ANA4, 0, 0x1f, 0x10)     # L2P_T1B_HSRT_CODE
    F(base + ANA4, 8, 0x1f, 0x10)     # L2N_T1C_HSRT_CODE
    # not CPHY
    F(base + ANA0, 21, 0x1, 0)        # CPHY_T0_CDR_FIRST_EDGE_EN
    F(base + ANA0, 22, 0x1, 0)        # CPHY_T1_CDR_FIRST_EDGE_EN
    F(base + ANA2, 16, 0x1, 0)        # CPHY_T0_CDR_SELF_CAL_EN
    F(base + ANA2, 17, 0x1, 0)        # CPHY_T1_CDR_SELF_CAL_EN
    # CPHY CDR wave-shaping (harmless for D-PHY, vendor writes it)
    F(base + ANA6, 24, 0x3f, 4)       # T0_CDR_CK_DELAY
    F(base + ANA7, 24, 0x3f, 4)       # T1_CDR_CK_DELAY
    F(base + ANA6, 0, 0x3f, 9)        # T0_CDR_AB_WIDTH
    F(base + ANA6, 8, 0x3f, 9)        # T0_CDR_BC_WIDTH
    F(base + ANA6, 16, 0x3f, 9)       # T0_CDR_CA_WIDTH
    F(base + ANA7, 0, 0x3f, 9)        # T1_CDR_AB_WIDTH
    F(base + ANA7, 8, 0x3f, 9)        # T1_CDR_BC_WIDTH
    F(base + ANA7, 16, 0x3f, 9)       # T1_CDR_CA_WIDTH
    print("  phyA_init %s done: ANA1=%08x ANA2=%08x ANA5=%08x ANA6=%08x"
          % (tag, rd(base + ANA1), rd(base + ANA2), rd(base + ANA5),
             rd(base + ANA6)))


def phase_dphy_init():
    """csirx_dphy_init(): settle + prepare + trail + trail_en."""
    for off in (0x20, 0x24, 0x28, 0x2c):          # DATA_LANE0..3
        F(DPHY + off, 16, 0xff, DPHY_SETTLE)      # HS_SETTLE_PARAMETER
        F(DPHY + off, 0, 0xff, 0)                 # HS_PREPARE (__SMT=0 -> 0)
        F(DPHY + off, 8, 0xff, hs_trail)          # HS_TRAIL_PARAMETER
        F(DPHY + off, 29, 0x1, hs_trail_en)       # HS_TRAIL_EN
    for off in (0x10, 0x14):                      # CLOCK_LANE0/1
        F(DPHY + off, 16, 0xff, DPHY_SETTLE)      # HS_SETTLE_PARAMETER
    print("  dphy_init done: DL0=%08x DL1=%08x DL2=%08x DL3=%08x CLK0=%08x"
          % (rd(DPHY + 0x20), rd(DPHY + 0x24), rd(DPHY + 0x28), rd(DPHY + 0x2c),
             rd(DPHY + 0x10)))


def phase_seninf_setting():
    """csirx_seninf_setting(): csi2 first, then seninf."""
    F(CTRL + 0x10, 0, 0x1, 1)        # SENINF_CSI2_CTRL.RG_SENINF_CSI2_EN
    F(CTRL + 0x00, 0, 0x1, 1)        # SENINF_CTRL.SENINF_EN
    print("  seninf_setting done: CTRL=%08x CSI2CTRL=%08x"
          % (rd(CTRL), rd(CTRL + 0x10)))


def phase_csi2_setting():
    """csirx_seninf_csi2_setting(): D-PHY branch, __SMT=0, non-legacy."""
    F(CSI2 + 0xE0, 17, 0x1, 1)       # DBG_CTRL.RG_CSI2_DBG_PACKET_CNT_EN
    F(CSI2 + 0x10, 8, 0x1, 1)        # RESYNC_MERGE_CTRL.CYCLE_CNT_OPT
    F(CSI2 + 0x04, 0, 0x1, 0)        # CSI2_OPT.RG_CSI2_CPHY_SEL = 0
    wr(CSI2 + 0x00, (1 << NUM_DATA_LANES) - 1)   # CSI2_EN = 0xf
    F(CSI2 + 0x08, 0, 0xff, 0)       # HDR_MODE_0.RG_CSI2_HEADER_MODE
    F(CSI2 + 0x08, 8, 0x7, 0)        # HDR_MODE_0.RG_CSI2_HEADER_LEN
    wr(CSI2 + 0x10, 0x2020f106)      # RESYNC_MERGE_CTRL base value
    F(CSI2 + 0x10, 16, 0xfff, cycles)         # DMY_CYCLE = 13
    F(CSI2 + 0x10, 28, 0xf, 3)                # DMY_CNT   = 3
    # vendor: 0x3 only for a 2-lane sensor, 0xf otherwise (phy_3_0 :1608-1616)
    F(CSI2 + 0x10, 12, 0xf, 0x3 if NUM_DATA_LANES == 2 else 0xf)   # DMY_EN
    print("  csi2_setting done: EN=%08x OPT=%08x RESYNC=%08x DBG=%08x"
          % (rd(CSI2 + 0x00), rd(CSI2 + 0x04), rd(CSI2 + 0x10), rd(CSI2 + 0xE0)))


def phase_top_setting():
    """csirx_seninf_top_setting(): CSI_PORT_2 -> SENINF_TOP_PHY_CTRL_CSI2 = 0x48."""
    F(TOP_PHY, 8, 0x3, 0)            # RG_PHY_SENINF_MUX2_CPHY_MODE = 0 (4T)
    F(TOP_PHY, 1, 0x1, 0)            # PHY_SENINF_MUX2_CPHY_EN  = 0
    F(TOP_PHY, 0, 0x1, 1)            # PHY_SENINF_MUX2_DPHY_EN  = 1
    print("  top_setting done: TOP_PHY=%08x" % rd(TOP_PHY))


def phase_phyA_setting():
    """csirx_phyA_setting(): D-PHY + is_4d1c + __SMT=0, then power_on A and B."""
    # ---- AFIFO / async option on A only (baseA) ----
    F(A_A + ANA_SET1, 2, 0x1, 1)     # RG_AFIFO_DUMMY_VALID_EN
    F(A_A + ANA_SET1, 4, 0xf, 0x5)   # RG_CSI0_ASYNC_OPTION
    F(A_A + ANA_SET1, 16, 0xf, 0x4)  # RG_AFIFO_DUMMY_VALID_PREPARE_NUM
    F(A_A + ANA_SET1, 20, 0xf, 0x1)  # RG_AFIFO_DUMMY_VALID_NUM

    # ---- ANA_0 : clear clk-sel, set CKSEL, then clock lane = L2 (A only) ----
    for b, l2 in ((A_A, 1), (A_B, 0)):
        F(b + ANA0, 20, 0x1, 0)                       # RG_CSI0_CPHY_EN = 0
        F(b + ANA0, 12, 0x1, 0)                       # L0_CKMODE_EN = 0
        F(b + ANA0, 13, 0x1, 0)                       # L1_CKMODE_EN = 0
        F(b + ANA0, 14, 0x1, 0)                       # L2_CKMODE_EN = 0
        F(b + ANA0, 8, 0x1, 1)                        # L0_CKSEL = 1
        F(b + ANA0, 9, 0x1, 1)                        # L1_CKSEL = 1
        F(b + ANA0, 10, 0x1, 1)                       # L2_CKSEL = 1
        F(b + ANA0, 12, 0x1, 0)                       # L0_CKMODE_EN
        F(b + ANA0, 13, 0x1, 0)                       # L1_CKMODE_EN
        F(b + ANA0, 14, 0x1, l2)                      # L2_CKMODE_EN (A=1)
        F(b + ANA0, 6, 0x1, 1)                        # CPHY_T0_HSMODE_EN
        F(b + ANA0, 7, 0x1, 1)                        # CPHY_T1_HSMODE_EN

    # ---- ANA_5 : data_rate 1.37G < 2.5G -> 0x44 (BW=0 IS=1 LATCH=1) ----
    for b in (A_A, A_B):
        F(b + ANA5, 12, 0xf, 0)      # EQ_SR1
        F(b + ANA5, 8, 0xf, 0)       # EQ_SR0
        F(b + ANA5, 6, 0x1, 1)       # EQ_LATCH_EN
        F(b + ANA5, 5, 0x1, 0)       # EQ_DG1_EN
        F(b + ANA5, 4, 0x1, 0)       # EQ_DG0_EN
        F(b + ANA5, 2, 0x3, 1)       # EQ_IS
        F(b + ANA5, 0, 0x3, 0)       # EQ_BW

    print("  phyA_setting regs: A_ANA0=%08x B_ANA0=%08x A_ANA5=%08x B_ANA5=%08x "
          "A_SET1=%08x" % (rd(A_A + ANA0), rd(A_B + ANA0), rd(A_A + ANA5),
                           rd(A_B + ANA5), rd(A_A + ANA_SET1)))

    # ---- csirx_phyA_power_on(portA,1) then (portB,1) ----
    for b, tag in ((A_A, "A"), (A_B, "B")):
        F(b + ANA8, 16, 0x3f, 0)            # clear 6 EQ_OS_CAL_EN
        F(b + ANA0, 1, 0x1, 0)              # BG_LPF_EN  = 0
        F(b + ANA0, 0, 0x1, 0)              # BG_CORE_EN = 0
        time.sleep(0.0002)
        F(b + ANA0, 0, 0x1, 1)              # BG_CORE_EN = 1
        time.sleep(0.00003)
        F(b + ANA0, 1, 0x1, 1)              # BG_LPF_EN  = 1
        time.sleep(0.000001)
        F(b + ANA8, 16, 0x3f, 0x3f)         # set 6 EQ_OS_CAL_EN
        time.sleep(0.000001)
        print("  power_on %s done: ANA0=%08x ANA8=%08x"
              % (tag, rd(b + ANA0), rd(b + ANA8)))


def phase_dphy_setting():
    """csirx_dphy_setting(): is_4d1c lane select / lane enable / SPARE0."""
    F(DPHY + 0x04, 20, 0x7, 4)       # RG_DPHY_RX_LD3_SEL
    F(DPHY + 0x04, 16, 0x7, 0)       # RG_DPHY_RX_LD2_SEL
    F(DPHY + 0x04, 12, 0x7, 3)       # RG_DPHY_RX_LD1_SEL
    F(DPHY + 0x04, 8, 0x7, 1)        # RG_DPHY_RX_LD0_SEL
    F(DPHY + 0x04, 0, 0x7, 2)        # RG_DPHY_RX_LC0_SEL
    F(DPHY + 0x00, 8, 0x1, 1)        # DPHY_RX_LD0_EN
    F(DPHY + 0x00, 9, 0x1, 1)        # DPHY_RX_LD1_EN
    F(DPHY + 0x00, 10, 0x1, 1)       # DPHY_RX_LD2_EN
    F(DPHY + 0x00, 11, 0x1, 1)       # DPHY_RX_LD3_EN
    F(DPHY + 0x00, 0, 0x1, 1)        # DPHY_RX_LC0_EN
    F(DPHY + 0x00, 1, 0x1, 0)        # DPHY_RX_LC1_EN = 0
    F(DPHY + 0x04, 31, 0x1, 1)       # DPHY_RX_CK_DATA_MUX_EN
    wr(DPHY + 0xf0, 0xf1)            # DPHY_RX_SPARE0 (non-legacy)
    print("  dphy_setting done: LANE_EN=%08x LANE_SEL=%08x SPARE0=%08x"
          % (rd(DPHY + 0x00), rd(DPHY + 0x04), rd(DPHY + 0xf0)))


def dump(tag):
    print("[%s]" % tag)
    print("  ANA A: " + " ".join("+%02x=%08x" % (o, rd(A_A + o))
                                 for o in (0x00, 0x04, 0x08, 0x0c, 0x10, 0x14,
                                           0x18, 0x1c, 0x20, 0xf0, 0xf4)))
    print("  ANA B: " + " ".join("+%02x=%08x" % (o, rd(A_B + o))
                                 for o in (0x00, 0x04, 0x08, 0x0c, 0x10, 0x14,
                                           0x18, 0x1c, 0x20, 0xf0, 0xf4)))
    print("  DPHY : " + " ".join("+%02x=%08x" % (o, rd(DPHY + o))
                                 for o in (0x00, 0x04, 0x08, 0x10, 0x14, 0x20,
                                           0x24, 0x28, 0x2c, 0x30, 0x34, 0x8c,
                                           0xa0, 0xa4, 0xf0)))
    print("  TOP_PHY=%08x  CTRL=%08x CSI2CTRL=%08x  CSI2EN=%08x RESYNC=%08x "
          "PKT=%d IRQ=%08x"
          % (rd(TOP_PHY), rd(CTRL), rd(CTRL + 0x10), rd(CSI2),
             rd(CSI2 + 0x10), rd(CSI2 + 0xDC), rd(CSI2 + 0xC8)))


def sample(sec):
    print("---- sampling %ds (PKT/IRQ only counts) ----" % sec)
    n = 0
    t0 = time.time()
    while time.time() - t0 < sec:
        p = rd(CSI2 + 0xDC)
        i = rd(CSI2 + 0xC8)
        d = rd(DPHY + 0x34)
        c = rd(DPHY + 0x30)
        print("  t=%5.2f PKT=%-6d IRQ=%08x DATA_FSM=%08x CLK_FSM=%08x"
              % (time.time() - t0, p, i, d, c))
        n += 1
        time.sleep(0.5)


def main():
    sec = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    print("=== port2_rx71: vendor-exact IMX582 port2 D-PHY bring-up ===")
    print("  A_A=%08x A_B=%08x DPHY=%08x TOP_PHY=%08x CTRL=%08x CSI2=%08x"
          % (A_A, A_B, DPHY, TOP_PHY, CTRL, CSI2))
    print("params: data_rate=%d cycles=%d ui_224=%d hs_trail=%d hs_trail_en=%d "
          "DL_HS=%08x CK_HS=%08x" % (data_rate, cycles, ui_224, hs_trail,
                                     hs_trail_en, DL_HS, CK_HS))
    dump("BEFORE")

    print("-- 1. csirx_phy_init --")
    phase_phyA_init(A_A, "A")
    phase_phyA_init(A_B, "B")
    phase_dphy_init()

    print("-- 2. csirx_seninf_setting --")
    phase_seninf_setting()

    print("-- 3. csirx_seninf_csi2_setting --")
    phase_csi2_setting()

    print("-- 4. csirx_seninf_top_setting --")
    phase_top_setting()

    print("-- 5. csirx_phy_setting: phyA_setting (+power_on A,B) --")
    phase_phyA_setting()

    print("-- 6. csirx_phy_setting: dphy_setting --")
    phase_dphy_setting()

    dump("AFTER")
    sample(sec)
    dump("FINAL")


if __name__ == "__main__":
    main()
