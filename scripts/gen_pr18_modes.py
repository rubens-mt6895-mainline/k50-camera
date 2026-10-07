#!/usr/bin/env python3
"""Splice IMX582 sensor modes into the MT6895-Mainline tree (PR #18).

Reads the vendor mode tables from src/rubensimx582_Sensor.h and rewrites a
checkout of drivers/media/i2c/imx582.c from
https://github.com/MT6895-Mainline/linux/pull/18 in the style that file already
uses: one byte register per line, one mode descriptor per mode, a link
frequency index per mode.

    python scripts/gen_pr18_modes.py [imx582.c] [outdir]

Outputs <outdir>/imx582.patched.c, <outdir>/mt6895-xiaomi-rubens.patched.dts and
<outdir>/pr18_modes.patch (git diff --no-index of both).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import parse_modes as pm  # noqa: E402

VENDOR = os.path.join(os.path.dirname(HERE), "src", "rubensimx582_Sensor.h")

# The link frequency menu is ordered ascending; index 0 is the existing
# 685 MHz entry of the PR, index 1 is the 982 MHz one added here.

# vendor table, C name, w, h, bin_h, bin_v, dcrop col, dcrop row, hts, vts,
# default frame length, pixel_rate, mipi Mbps, link_freq_index, comment
MODES = [
    ("normal_video", "imx582_4000x2256_regs", 4000, 2256, 2, 2, 0, 0,
     7872, 3658, 3658, 864000000, 1370, 0,
     "16:9 crop of the 8000x6000 array with 2x2 binning, from (0, 744).\n"
     " * Line length 7872, frame length 3658 (30 fps), 864 MHz pixel clock and\n"
     " * 1370 Mbit/s per lane. Vendor normal_video table, unchanged."),
    ("custom3", "imx582_4000x2256_60_regs", 4000, 2256, 2, 2, 0, 0,
     4592, 2560, 5120, 705600000, 1964, 1,
     "Same window and binning as above, but twice the line rate: line length\n"
     " * 4592, frame length 2560 (60 fps), 705.6 MHz pixel clock and 982 Mbit/s\n"
     " * per lane. Vendor custom3 table, unchanged. The default frame length\n"
     " * gives 30 fps; lower VBLANK for 60 fps."),
    ("hs_video", "imx582_1920x1080_240_regs", 1920, 1080, 4, 4, 40, 0,
     2912, 1236, 9889, 864000000, 1964, 1,
     "H4V4 binning of the 8000x4320 window from (0, 832), digital crop from\n"
     " * x = 40. Line length 2912, frame length 1236 (240 fps) and 982 Mbit/s\n"
     " * per lane: the shortest readout of the sensor, so the least rolling\n"
     " * shutter. Vendor hs_video table, unchanged. The default frame length\n"
     " * gives 30 fps; lower VBLANK for the full rate."),
]

# Register-range comments, mirroring the annotations of the existing tables.
NOTES = {
    0x0112: "RAW10 output, four data lanes",
    0x0202: "coarse integration time and gain defaults",
    0x0305: "PLL and MIPI rate",
    0x0340: "frame length",
    0x0342: "line length",
    0x0344: "analog crop",
    0x0408: "digital crop",
    0x040c: "output size",
    0x0900: "binning",
    0x4035: "vendor image quality registers",
}


def regs_of(vendor, name):
    pairs = dict(vendor)["rubensimx582_%s_setting" % name]
    return list(pairs)


def emit_table(cname, pairs):
    notes = dict(NOTES)
    out = ["static const struct cci_reg_sequence %s[] = {" % cname]
    for reg, val in pairs:
        if reg in notes:
            out.append("\t/* %s */" % notes.pop(reg))
        out.append("\t{ CCI_REG8(0x%04x), 0x%02x }," % (reg, val))
    out.append("};")
    return "\n".join(out)


def mode_entry(vendor, m, link=True):
    (vname, cname, w, h, bh, bv, dcol, drow, hts, vts, def_vts, prate, mipi,
     lidx, comment) = m
    g = dict(regs_of(vendor, vname))
    left = ((g[0x0344] << 8) | g[0x0345]) + dcol * bh
    top = ((g[0x0346] << 8) | g[0x0347]) + drow * bv
    head = """/*
 * %dx%d: %s
 */
""" % (w, h, comment)
    return head + emit_table(cname, regs_of(vendor, vname)) + "\n" + descriptor(
        w, h, bh, bv, left, top, prate, hts, vts, def_vts, lidx, cname, link)


def descriptor(w, h, bh, bv, left, top, prate, hts, vts, def_vts, lidx, cname,
               link=True):
    note = ""
    if def_vts != vts:
        note = ("\t\t/* %d fps at this frame length; the mode reaches %d fps */\n"
                % (round(prate / (hts * def_vts)), round(prate / (hts * vts))))
    linkline = "\t\t.link_freq_index = %d,\n" % lidx if link else ""
    return """	{
		.width = %d,
		.height = %d,
		.crop = {
			.left = %d,
			.top = %d,
			.width = %d,
			.height = %d,
		},
		.pixel_rate = %d,
		.line_length = %d,
		.frame_length_min = %d,
%s		.frame_length_def = %d,
		.exposure_def = %d,
%s		.regs = %s,
		.num_regs = ARRAY_SIZE(%s),
	},
""" % (w, h, left, top, w * bh, h * bv, prate, hts, vts, note, def_vts,
       vts - 48, linkline, cname, cname)


def entry_only(vendor, m, link=True):
    (vname, cname, w, h, bh, bv, dcol, drow, hts, vts, def_vts, prate, mipi,
     lidx, comment) = m
    g = dict(regs_of(vendor, vname))
    return descriptor(w, h, bh, bv,
                      ((g[0x0344] << 8) | g[0x0345]) + dcol * bh,
                      ((g[0x0346] << 8) | g[0x0347]) + drow * bv,
                      prate, hts, vts, def_vts, lidx, cname, link)


def splice(src, vendor, modes=None, link=None):
    with open(src, newline="") as fh:
        text = fh.read()

    modes = MODES if modes is None else modes
    if link is None:
        link = any(m[13] for m in modes)
    low_rate = any(m[11] < 734400000 for m in modes)
    print("modes  : %s" % ", ".join(m[0] for m in modes))
    print("plumbing: pixel-rate fix %s, second link frequency %s"
          % (low_rate, link))

    def sub(old, new, what):
        n = text.count(old)
        if n != 1:
            raise SystemExit("anchor %s: %d matches in %s" % (what, n, src))
        return text.replace(old, new)

    # 1. the pixel rate range has to reach the 705.6 MHz of custom3.
    if low_rate:
        text = sub("#define IMX582_PIXEL_RATE_MIN\t\t734400000",
                   "#define IMX582_PIXEL_RATE_MIN\t\t705600000\t/* custom3: 705.6 MHz */",
                   "pixel rate min")
    # 2..5 only matter when a mode needs the second link frequency.
    if link:
        # 2. second link frequency (982 Mbit/s per lane), ascending in the menu.
        text = sub("#define IMX582_LINK_FREQ\t\t(685 * HZ_PER_MHZ)",
                   "#define IMX582_LINK_FREQ\t\t(685 * HZ_PER_MHZ)\n"
                   "#define IMX582_LINK_FREQ_982MHZ\t\t(982 * HZ_PER_MHZ)",
                   "link freq define")
        text = sub("static const s64 imx582_link_freq_menu[] = {\n\tIMX582_LINK_FREQ,\n};",
                   "static const s64 imx582_link_freq_menu[] = {\n"
                   "\tIMX582_LINK_FREQ,\n\tIMX582_LINK_FREQ_982MHZ,\n};",
                   "link freq menu")
        # 3. keep the link frequency control around to program it per mode.
        text = sub("\tstruct v4l2_ctrl *pixel_rate;",
                   "\tstruct v4l2_ctrl *link_freq;\n\tstruct v4l2_ctrl *pixel_rate;",
                   "struct ctrl pointers")
        text = sub("\tif (ctrl)\n\t\tctrl->flags |= V4L2_CTRL_FLAG_READ_ONLY;",
                   "\tif (ctrl)\n\t\tctrl->flags |= V4L2_CTRL_FLAG_READ_ONLY;\n"
                   "\timx582->link_freq = ctrl;",
                   "link freq control store")
        # 4. the mode descriptor grows a link frequency index.
        text = sub("\tconst struct cci_reg_sequence *regs;\n\tunsigned int num_regs;\n};",
                   "\tconst struct cci_reg_sequence *regs;\n\tunsigned int num_regs;\n"
                   "\t/* Index into imx582_link_freq_menu, for this mode. */\n"
                   "\tu32 link_freq_index;\n};",
                   "mode struct")
        # 5. set it whenever the mode changes.
        text = sub("\tret = __v4l2_ctrl_s_ctrl_int64(imx582->pixel_rate, mode->pixel_rate);\n"
                   "\tif (ret)\n\t\treturn ret;\n",
                   "\tret = __v4l2_ctrl_s_ctrl_int64(imx582->pixel_rate, mode->pixel_rate);\n"
                   "\tif (ret)\n\t\treturn ret;\n"
                   "\n"
                   "\tret = __v4l2_ctrl_s_ctrl(imx582->link_freq, mode->link_freq_index);\n"
                   "\tif (ret)\n\t\treturn ret;\n",
                   "apply mode")

    # 6. the tables and the descriptors, before struct imx582_mode.
    tables = "\n".join(mode_entry(vendor, m, link) for m in modes)
    text = sub("struct imx582_mode {", tables + "\nstruct imx582_mode {",
               "table insertion")

    # 7. the descriptors, before the closing brace of imx582_modes[].
    entries = "".join(entry_only(vendor, m, link) for m in modes)
    marker = "\t\t.num_regs = ARRAY_SIZE(imx582_4000x3000_regs),\n\t},\n};"
    text = sub(marker, marker[:-2] + "\n" + entries.rstrip("\n") + "\n};",
               "mode array")
    return text


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = [s for s in a.split("=", 1)[1].split(",") if s]
    base = os.path.dirname(HERE)
    src = args[0] if len(args) > 0 else os.path.join(base, "out", "pr18", "imx582.c")
    outdir = args[1] if len(args) > 1 else os.path.dirname(src)
    vendor = pm.parse_tables(VENDOR)
    modes = MODES
    if only:
        names = [m[0] for m in MODES]
        unknown = [s for s in only if s not in names]
        if unknown:
            raise SystemExit("unknown modes: %s" % unknown)
        modes = [m for m in MODES if m[0] in only]
    patched = splice(src, vendor, modes)
    dst = os.path.join(outdir, "imx582.patched.c")
    with open(dst, "w", newline="") as fh:
        fh.write(patched)
    print("wrote %s (%d bytes, %d lines)" % (dst, len(patched), patched.count("\n")))

    # the DTS one-liner: allow both link frequencies on the main camera.
    dts = os.path.join(outdir, "rubens.dts")
    dpath = os.path.join(outdir, "mt6895-xiaomi-rubens.patched.dts")
    if os.path.exists(dts):
        old = "link-frequencies = /bits/ 64 <685000000>;"
        dt = open(dts, newline="").read()
        if dt.count(old) == 1:
            open(dpath, "w", newline="").write(
                dt.replace(old,
                           "link-frequencies = /bits/ 64 <685000000 982000000>;"))
            print("wrote %s" % dpath)
        elif dt.count(old) == 0:
            print("DTS: link-frequencies line not found")
        else:
            print("DTS: %d occurrences, not patched" % dt.count(old))

    # the patch itself, with kernel-style paths in the headers.
    pairs = [("drivers/media/i2c/imx582.c", src, dst)]
    if os.path.exists(dpath):
        pairs.append(("arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dts",
                      dts, dpath))
    patch = os.path.join(outdir, "pr18_modes.patch")
    with open(patch, "w", newline="") as fh:
        for path, fa, fb in pairs:
            out = subprocess.run(["git", "diff", "--no-index", "--no-color",
                                  "--unified=6", "--", fa, fb],
                                 capture_output=True, text=True).stdout
            body = "\n".join(line for line in out.splitlines()
                             if not line.startswith(("diff --git", "index ",
                                                     "--- ", "+++ ")))
            fh.write("diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n%s\n"
                     % (path, path, path, path, body))
    print("wrote %s (%d bytes)" % (patch, os.path.getsize(patch)))


if __name__ == "__main__":
    main()
