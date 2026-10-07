#!/usr/bin/env python3
"""csirx_bring.py - vendor-exact CSI receiver bring-up for any CSI port.

    csirx_bring.py [port] [link_freq_mhz] [sample_seconds] [lanes] [trail_ns]

Reuses port2_rx71.py (the verified port 2 sequence) with the address block and
all link-rate derived values rewritten for the requested port:

    port 0 -> 4D1C, ANA 0x11c80000, SENINF intf 0, TOP_PHY_CTRL_CSI0
    port 1 -> 2D1C, ANA 0x11c90000, SENINF intf 2, TOP_PHY_CTRL_CSI1
    port 2 -> 4D1C, ANA 0x11c84000, SENINF intf 4   (the original)
    port 3 -> 2D1C, ANA 0x11c94000, SENINF intf 6, TOP_PHY_CTRL_CSI3
    port 4 -> 4D1C, ANA 0x11c88000, SENINF intf 8

The phase functions of port2_rx71.py read its module globals at call time, so
patching them here retargets the whole sequence.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "port2_rx71.py")
if not os.path.exists(SRC):
    SRC = "/root/port2_rx71.py"

# ANA node base per physical CSI port (mt6895.dtsi: mipi_csiN_rx)
PHY_NODE = {0: 0x11C80000, 1: 0x11C90000, 2: 0x11C84000,
            3: 0x11C94000, 4: 0x11C88000}
PORT_NAME = {0: "csi0 4D1C", 1: "csi1 2D1C", 2: "csi2 4D1C",
             3: "csi3 2D1C", 4: "csi4 4D1C"}


def load(path):
    spec = importlib.util.spec_from_file_location("rx71", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    link = int(sys.argv[2]) if len(sys.argv) > 2 else 685
    sec = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    lanes = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    trail_ns = int(sys.argv[5]) if len(sys.argv) > 5 else 68
    if port not in PHY_NODE:
        print("unknown port %u (0..4)" % port)
        return 2
    if lanes not in (1, 2, 3, 4):
        print("unsupported lane count %u" % lanes)
        return 2

    if not os.path.exists(SRC):
        print("cannot find port2_rx71.py")
        return 2
    rx = load(SRC)

    node = PHY_NODE[port]
    intf = 2 * port
    rx.A_A = node
    rx.A_B = node + 0x1000
    rx.DPHY = node + 0x2000
    rx.TOP_PHY = rx.TOP + 0x40 + 4 * port
    rx.CTRL = rx.TOP + 0x0200 + 0x1000 * intf
    rx.CSI2 = rx.TOP + 0x0a00 + 0x1000 * intf

    # lane count and D-PHY trail come from the sensor's DT data-lanes and
    # mediatek,hs-trail-ps (ps -> ns): main 4/68, front 4/69, ultrawide 4/78,
    # macro 1/92.
    rx.NUM_DATA_LANES = lanes
    rx.DPHY_TRAIL_DT = trail_ns

    # The device tree link-frequencies value is the DDR clock, i.e. half the
    # data rate:  data_rate = 2 * link_freq  =>  pixel_rate = 2*link*lanes/bpp
    rx.MIPI_PIXEL_RATE = (link * 1000000 * 2 * rx.NUM_DATA_LANES
                          // rx.BIT_PER_PIXEL)
    rx.data_rate = rx.MIPI_PIXEL_RATE * rx.BIT_PER_PIXEL // rx.NUM_DATA_LANES
    rx.cycles = 64 * rx.SENINF_CK // rx.data_rate + rx.CYCLE_MARGIN
    rx.ui_224 = (rx.DPHY_TRAIL_SPEC * 1000) // (rx.data_rate // 1000000)
    if rx.DPHY_TRAIL_DT == 0 or rx.DPHY_TRAIL_DT > rx.ui_224:
        rx.hs_trail = 0
    else:
        t = (rx.ui_224 - rx.DPHY_TRAIL_DT) * rx.SENINF_CK
        rx.hs_trail = t // 1000000000 + (1 if t % 1000000000 else 0)
    rx.hs_trail_en = 1 if (rx.DPHY_TRAIL_DT and rx.hs_trail) else 0
    rx.DL_HS = (rx.hs_trail << 8) | (rx.DPHY_SETTLE << 16) | (rx.hs_trail_en << 29)
    rx.CK_HS = rx.DPHY_SETTLE << 16

    print("=== csirx_bring: port %u (%s), link %u MHz/lane, %u lane(s), trail %u ns ==="
          % (port, PORT_NAME[port], link, lanes, trail_ns))
    print("  ANA node %#x (A %#x B %#x DPHY %#x), intf %u, TOP_PHY_CTRL_CSI%u %#x"
          % (node, rx.A_A, rx.A_B, rx.DPHY, intf, port, rx.TOP_PHY))
    print("  CTRL %#x CSI2 %#x  data_rate %u cycles %u ui_224 %u hs_trail %u"
          % (rx.CTRL, rx.CSI2, rx.data_rate, rx.cycles, rx.ui_224, rx.hs_trail))

    sys.argv = [sys.argv[0], str(sec)]
    rx.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
