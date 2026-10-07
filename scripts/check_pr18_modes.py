#!/usr/bin/env python3
"""Syntax and value check for the generated PR #18 mode additions.

Rebuilds exactly the text gen_pr18_modes.py splices into imx582.c, puts it in a
translation unit with the struct definitions stubbed, compiles it with clang and
checks the numbers:
  - against the vendor tables it names,
  - against the two descriptors the PR already ships (same crop rule, pixel
    clock and frame length, so the rule is validated by their own code).

    python scripts/check_pr18_modes.py [imx582.c]
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pr18_modes as G  # noqa: E402
import parse_modes as pm  # noqa: E402

STUBS = """#include <stdint.h>
#include <stddef.h>

typedef uint32_t u32;
typedef uint64_t u64;

struct v4l2_rect {
	int left;
	int top;
	u32 width;
	u32 height;
};

struct cci_reg_sequence {
	u32 reg;
	u64 val;
};

#define CCI_REG8(reg) ((u32)(reg))
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

struct imx582_mode {
	u32 width;
	u32 height;
	struct v4l2_rect crop;
	u64 pixel_rate;
	u32 line_length;
	u32 frame_length_min;
	u32 frame_length_def;
	u32 exposure_def;
	const struct cci_reg_sequence *regs;
	unsigned int num_regs;
	u32 link_freq_index;
};
"""

# The rule: crop is the window in sensor pixels, the register pair holds one
# byte each, the frame length is the frame length minimum of the vendor table.
def rule(g, w, h, bh, bv, dcol, drow):
    p16 = lambda hi, lo: (g[hi] << 8) | g[lo]
    return dict(width=w, height=h,
                left=p16(0x0344, 0x0345) + dcol * bh,
                top=p16(0x0346, 0x0347) + drow * bv,
                crop_w=w * bh, crop_h=h * bv,
                line_length=p16(0x0342, 0x0343),
                frame_length=p16(0x0340, 0x0341),
                pixel_rate=int(4.8e6 * p16(0x0306, 0x0307)),
                mipi=p16(0x030e, 0x030f),
                bin=(g[0x0901] >> 4, g[0x0901] & 0xf))


def existing_modes(path):
    """The descriptors the PR already has, as (width, height, crop, rate, line,
    frame_min)."""
    text = open(path, newline="").read()
    body = text[text.index("static const struct imx582_mode imx582_modes[]"):]
    out = []
    for m in re.finditer(r"\.width = (\d+),\s*\.height = (\d+),\s*"
                         r"\.crop = \{\s*\.left = (-?\d+),\s*\.top = (-?\d+),\s*"
                         r"\.width = (\d+),\s*\.height = (\d+),\s*\},\s*"
                         r"\.pixel_rate = (\d+),\s*\.line_length = (\d+),\s*"
                         r"\.frame_length_min = (\d+),", body, re.S):
        out.append(tuple(int(x) for x in m.groups()))
    return out


def main():
    vendor = pm.parse_tables(G.VENDOR)
    tables = "\n".join(G.emit_table(m[1], G.regs_of(vendor, m[0])) for m in G.MODES)
    entries = "".join(G.entry_only(vendor, m) for m in G.MODES)
    src = (STUBS + "\n" + tables +
           "\nstatic const struct imx582_mode imx582_modes[] = {\n" + entries +
           "};\n\nint main(void) { return (int)imx582_modes[ARRAY_SIZE(imx582_modes) - 1]"
           ".link_freq_index + (int)ARRAY_SIZE(imx582_modes) - %d; }\n"
           % len(G.MODES))
    tmp = tempfile.mkdtemp(prefix="pr18chk")
    path = os.path.join(tmp, "modes.c")
    with open(path, "w", newline="") as fh:
        fh.write(src)
    cc = subprocess.run(["clang", "-std=gnu11", "-Wall", "-Wextra", "-Werror",
                         "-c", path, "-o", os.path.join(tmp, "modes.o")],
                        capture_output=True, text=True)
    print("clang        : rc=%d%s" % (cc.returncode,
                                      "" if not cc.stderr.strip() else " " + cc.stderr.strip()))
    if cc.returncode != 0:
        return 1

    ok = True

    # 1. the existing descriptors must come out of the same rule.
    base = os.path.dirname(HERE)
    pr = os.path.join(base, "out", "pr18", "imx582.c")
    print("\n-- the rule applied to the two modes the PR already has --")
    want = {("preview", 2, 2, 0, 0): (4000, 3000),
            ("custom2", 4, 4, 40, 0): (1920, 1080)}
    for name, bh, bv, dcol, drow in [("preview", 2, 2, 0, 0), ("custom2", 4, 4, 40, 0)]:
        g = dict(G.regs_of(vendor, name))
        w, h = want[(name, bh, bv, dcol, drow)]
        r = rule(g, w, h, bh, bv, dcol, drow)
        print("%-10s %4dx%-4d -> crop { %d, %d, %d, %d }, line %d, frame %d, "
              "rate %d" % (name, w, h, r["left"], r["top"], r["crop_w"],
                           r["crop_h"], r["line_length"], r["frame_length"],
                           r["pixel_rate"]))
    if os.path.exists(pr):
        have = existing_modes(pr)
        print("PR entries    : %s" % (have,))
        for name, bh, bv, dcol, drow in [("preview", 2, 2, 0, 0), ("custom2", 4, 4, 40, 0)]:
            g = dict(G.regs_of(vendor, name))
            w, h = want[(name, bh, bv, dcol, drow)]
            r = rule(g, w, h, bh, bv, dcol, drow)
            match = [e for e in have if e[0] == w and e[1] == h and
                     e[6] == r["pixel_rate"]]
            if not match:
                print("  no PR entry for %dx%d @ %d" % (w, h, r["pixel_rate"]))
                ok = False
                continue
            e = match[0]
            got = (r["left"], r["top"], r["crop_w"], r["crop_h"], r["pixel_rate"],
                   r["line_length"])
            if got != e[2:8] or r["frame_length"] != e[8]:
                print("  MISMATCH %s: rule %s frame %d, PR %s frame %d"
                      % (name, got, r["frame_length"], e[2:8], e[8]))
                ok = False
            else:
                print("  %-10s matches PR entry %dx%d: crop {%d, %d, %d, %d}, "
                      "line %d, frame %d, rate %d"
                      % (name, e[0], e[1], e[2], e[3], e[4], e[5], e[7], e[8],
                         e[6]))

    # 2. the added descriptors against their vendor tables.
    print("\n-- the added modes --")
    for m in G.MODES:
        (vname, cname, w, h, bh, bv, dcol, drow, hts, vts, def_vts, prate, mipi,
         lidx, comment) = m
        g = dict(G.regs_of(vendor, vname))
        r = rule(g, w, h, bh, bv, dcol, drow)
        fps = r["pixel_rate"] / (r["line_length"] * r["frame_length"])
        print("%-13s %4dx%-5d crop { %d, %d, %d, %d } line %d frame %d "
              "rate %d (%.1f MHz) mipi %d link %d bin %dx%d %.2f fps regs %d"
              % (vname, w, h, r["left"], r["top"], r["crop_w"], r["crop_h"],
                 r["line_length"], r["frame_length"], r["pixel_rate"],
                 r["pixel_rate"] / 1e6, r["mipi"], lidx, r["bin"][0], r["bin"][1],
                 fps, len(G.regs_of(vendor, vname))))
        print("              frame_length_def %d (%.1f fps), exposure_def %d, "
              "frame_length_max 0xffff" % (def_vts, r["pixel_rate"] /
                                           (r["line_length"] * def_vts), vts - 48))
        checks = [("line_length", hts, r["line_length"]),
                  ("frame_length_min", vts, r["frame_length"]),
                  ("pixel_rate", prate, r["pixel_rate"]),
                  ("mipi", mipi, r["mipi"]),
                  ("bin", (bh, bv), r["bin"]),
                  ("crop_w", w * bh, r["crop_w"]),
                  ("crop_h", h * bv, r["crop_h"]),
                  ("regs", 111, len(G.regs_of(vendor, vname)))]
        for label, got, exp in checks:
            if got != exp:
                print("  MISMATCH %s: %s != %s" % (label, got, exp))
                ok = False
        if def_vts < vts or def_vts > 0xffff:
            print("  MISMATCH frame_length_def %d: outside [%d, 65535]"
                  % (def_vts, vts))
            ok = False
        if (r["mipi"] >= 1964) != (lidx == 1):
            print("  MISMATCH link_freq_index %d for %d Mbit/s" % (lidx, r["mipi"]))
            ok = False
    print("\nVALUES %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
