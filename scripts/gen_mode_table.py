#!/usr/bin/env python3
"""Extract a vendor sensor mode table from src/rubensimx582_Sensor.h into a
plain text file the device can replay.

    python scripts/gen_mode_table.py                      # all non-empty tables
    python scripts/gen_mode_table.py src/rubensimx582_Sensor.h custom3 normal_video

Writes out/modes/mode_<name>.txt:

    # mode custom3 - 4000x2256, 111 pairs
    0x0112 0x0A
    0x0342 0x1E
    ...

scripts/imx582_bring.py replays such a file instead of the built-in preview
list when it is started as   IMX582_MODE=custom3 python3 /root/imx582_bring.py
(see also scripts/zz_mode.sh, which does the whole drill: mode table + driver
geometry + frame-rate measurement).
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import parse_modes as pm  # noqa: E402


def geometry(pairs):
    hts = pm.pair16(pairs, 0x0342, 0x0343)
    vts = pm.pair16(pairs, 0x0340, 0x0341)
    ow = pm.pair16(pairs, 0x034C, 0x034D)
    oh = pm.pair16(pairs, 0x034E, 0x034F)
    bin_mode = pm.val(pairs, 0x0900)
    return hts, vts, ow, oh, bin_mode


def main():
    argv = sys.argv[1:]
    header = argv[0] if argv and argv[0].endswith(".h") else "src/rubensimx582_Sensor.h"
    want = [a for a in argv if not a.endswith(".h")]

    outdir = pathlib.Path("out/modes")
    outdir.mkdir(parents=True, exist_ok=True)

    written = 0
    for name, pairs in pm.parse_tables(header):
        short = name.replace("rubensimx582_", "").replace("_setting", "")
        if not pairs:
            continue
        if want and short not in want:
            continue
        hts, vts, ow, oh, bmode = geometry(pairs)
        path = outdir / ("mode_%s.txt" % short)
        with path.open("w") as fh:
            fh.write("# mode %s - %s x %s, %d pairs, HTS %s VTS %s, bin_mode %s\n"
                     % (short, ow, oh, len(pairs), hts, vts, bmode))
            for reg, value in pairs:
                fh.write("0x%04X 0x%02X\n" % (reg, value))
        print("%-14s %4sx%-4s HTS %-5s VTS %-5s bin %-3s  %d pairs -> %s"
              % (short, ow, oh, hts, vts, bmode, len(pairs), path))
        written += 1
    if not written:
        print("no table written (unknown name? %s)" % " ".join(want))
        return 1
    return 0


sys.exit(main())
