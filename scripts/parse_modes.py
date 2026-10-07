#!/usr/bin/env python3
"""Parse the vendor IMX582 (rubensimx582) and IMX586 mode tables and print what
each sensor mode actually is: binning, timing, output window, MIPI PLL, lanes.

Usage:  python scripts/parse_modes.py [src/rubensimx582_Sensor.h ...]

Why: the sensor's "recording specs" are exactly these tables.  Every mode is a
register list we can replay over I2C (that is what scripts/imx582_bring.py
already does for the preview mode), so this table is the work list for
supporting each recording format on the mainline port.
"""
import re
import sys
import pathlib

# IMX586 vendor timing (src/imx586_Sensor.c imgsensor_info) -- used to turn
# HTS/VTS into a frame rate for tables that do not carry a pclk themselves.
# name, out_w, out_h, pclk_hz, hts, vts
IMX586 = [
    ("pre",          4000, 3000, 1488.0e6, 7872, 3156),
    ("cap",          4000, 3000, 1728.0e6, 15744, 3658),
    ("normal_video", 4000, 2600,  883.2e6, 7872, 3738),
    ("hs_video",     1920, 1080,  960.0e6, 4496, 1778),
    ("slim_video",   4000, 2256,  883.2e6, 7872, 3738),
    ("custom1",      1920, 1080, 1728.0e6, 5376, 1338),
    ("custom2",      3840, 2160, 1152.0e6, 7872, 2384),
    ("custom3",      8000, 6000, 1728.0e6, 9440, 6142),
    ("custom4",      1280,  720, 1728.0e6, 5376, 1338),
]

KNOWN_REGS = {
    0x0100: "stream",
    0x0101: "mirror",
    0x0112: "fmt",
    0x0114: "lanes",
    0x0202: "exp_hi",
    0x0203: "exp_lo",
    0x0204: "again_hi",
    0x0205: "again_lo",
    0x020E: "dgain_hi",
    0x020F: "dgain_lo",
    0x0340: "vts_hi",
    0x0341: "vts_lo",
    0x0342: "hts_hi",
    0x0343: "hts_lo",
    0x034C: "ow_hi",
    0x034D: "ow_lo",
    0x034E: "oh_hi",
    0x034F: "oh_lo",
    0x0408: "cx_hi",
    0x0409: "cx_lo",
    0x040A: "cy_hi",
    0x040B: "cy_lo",
    0x040C: "cw_hi",
    0x040D: "cw_lo",
    0x040E: "ch_hi",
    0x040F: "ch_lo",
    0x0900: "bin_mode",
    0x0901: "bin_type",
    0x0902: "bin_weight",
    0x0305: "pll_mult",
    0x0306: "pll_pllck_hi",
    0x0307: "pll_pllck_lo",
    0x030D: "pll_mipi_hi",
    0x030E: "pll_mipi_mid",
    0x030F: "pll_mipi_lo",
    0x0310: "pll_mipi2",
}


def parse_tables(path):
    txt = pathlib.Path(path).read_text(errors="ignore")
    txt = re.sub(r"/\*.*?\*/", " ", txt, flags=re.S)
    txt = re.sub(r"//[^\n]*", " ", txt)
    out = []
    pat = re.compile(r"static\s+kal_uint16\s+(\w+)\s*(?:\[\s*\])?\s*=\s*\{(.*?)\}\s*;", re.S)
    for m in pat.finditer(txt):
        name, body = m.group(1), m.group(2)
        nums = [int(n, 0) for n in re.findall(r"0x[0-9A-Fa-f]+|\d+", body)]
        pairs = list(zip(nums[0::2], nums[1::2]))
        out.append((name, pairs))
    return out


def val(pairs, reg):
    """last write wins (arrays are replay order)"""
    got = None
    for r, v in pairs:
        if r == reg:
            got = v
    return got


def pair16(pairs, hi, lo):
    a, b = val(pairs, hi), val(pairs, lo)
    if a is None or b is None:
        return None
    return (a << 8) | b


def describe(name, pairs, source):
    fmt = val(pairs, 0x0112)
    lanes = val(pairs, 0x0114)
    hts = pair16(pairs, 0x0342, 0x0343)
    vts = pair16(pairs, 0x0340, 0x0341)
    ow = pair16(pairs, 0x034C, 0x034D)
    oh = pair16(pairs, 0x034E, 0x034F)
    cw = pair16(pairs, 0x040C, 0x040D)
    ch = pair16(pairs, 0x040E, 0x040F)
    bin = val(pairs, 0x0900)
    bint = val(pairs, 0x0901)
    binu = val(pairs, 0x0902)
    pllm = val(pairs, 0x0305)
    mipi = val(pairs, 0x030E)
    mipi2 = val(pairs, 0x030F)
    mult = val(pairs, 0x0307)

    fps = None
    pclk = None
    match = None
    pllcode = pair16(pairs, 0x0306, 0x0307)
    if pllcode:
        # IMX58x PLL code: 0x0306/0x0307 hold a 16-bit multiplier, and the
        # pixel clock is 4.8 MHz per count.  Checked against every mode of the
        # IMX586 vendor driver, whose imgsensor_info carries the pclk itself
        # (e.g. 0x0168 -> 360 -> 1728 MHz, 0x00b8 -> 184 -> 883.2 MHz) and
        # against our own measurement on the K50: the preview table's 0x00b4
        # (180 -> 864 MHz) with HTS 7872 / VTS 3300 gives the observed 30.09 ms
        # frame period (864e6 / (7872 * 3300) = 30.05 fps).
        pclk = 4.8e6 * pllcode
    if hts and vts and pclk:
        fps = pclk / (hts * vts)
    if hts and vts:
        for nm, w, h, kpclk, khts, kvts in IMX586:
            if hts == khts and vts == kvts:
                match = nm
                break
    print(f"--- {name}  ({len(pairs)} pairs)  [{source}]")
    print(f"    data format 0x0112 = {('0x%02x' % fmt) if fmt is not None else '?'}"
          f"   lanes 0x0114 = {lanes if lanes is not None else '?'}"
          f"   binning 0x0900={bin if bin is not None else '?'}"
          f" 0x0901={bint if bint is not None else '?'}"
          f" 0x0902={binu if binu is not None else '?'}")
    print(f"    timing  HTS {hts if hts is not None else '?'}  VTS {vts if vts is not None else '?'}"
          f"   pclk {('%.1f MHz' % (pclk / 1e6)) if pclk else '?'}"
          f"   -> {'%.2f' % fps if fps else '?'} fps"
          f"{'  (timing matches imx586 %s)' % match if match else ''}")
    print(f"    output  {ow if ow is not None else '?'} x {oh if oh is not None else '?'}"
          f"   crop {cw if cw is not None else '?'} x {ch if ch is not None else '?'}")
    print(f"    pll     0x0305={('0x%02x' % pllm) if pllm is not None else '?'}"
          f" 0x0306/07={('0x%04x' % pllcode) if pllcode is not None else '?'}"
          f" 0x030E={('0x%02x' % mipi) if mipi is not None else '?'}"
          f" 0x030F={('0x%02x' % mipi2) if mipi2 is not None else '?'}")
    if ow and oh:
        bpp = {0x0A: 1.25, 0x0B: 1.5}.get(fmt, 1.5) if fmt else 1.5
        mb = ow * oh * bpp / 1e6
        print(f"    raw frame on the wire ~{mb:.1f} MB"
              f"{'   (fits the 18 MB buffer)' if mb <= 18.9 else '   <-- needs a bigger buffer'}")


def main():
    files = sys.argv[1:] or ["src/rubensimx582_Sensor.h", "src/imx586_Sensor.c"]
    for f in files:
        p = pathlib.Path(f)
        if not p.exists():
            print(f"missing {f}")
            continue
        print(f"===== {f} =====")
        for name, pairs in parse_tables(p):
            describe(name, pairs, p.name)
        print()


if __name__ == "__main__":
    main()
