#!/usr/bin/env python3
"""Extract sensor register tables from an upstream driver into plain files.

The mt6895-mainline sensor drivers keep their mode tables as
`struct cci_reg_sequence` arrays of byte registers:

    static const struct cci_reg_sequence imx596_init_regs[] = {
            { CCI_REG8(0x0136), 0x18 },
            ...
    };

Our bring-up scripts replay `0xREG 0xVAL` lines over i2ctransfer, so this
tool converts one such array (or all of them) into that format.

Usage:
    gen_sensor_tables.py <driver.c> <outdir> [table ...]

With no table names all `*_regs[]` arrays are written.  CCI_REG16 entries are
expanded into their two byte registers (big endian), which is what the sensor
expects on the wire.
"""
import os
import re
import sys

ENTRY_RE = re.compile(
    r"\{\s*CCI_REG(?P<width>8|16)\(\s*(?P<reg>0x[0-9a-fA-F]+)\s*\)"
    r"\s*,\s*(?P<val>0x[0-9a-fA-F]+)\s*\}")
ARRAY_RE = re.compile(
    r"static const struct cci_reg_sequence\s+(?P<name>\w+)\s*\[\s*\]\s*=\s*"
    r"\{(?P<body>.*?)\n\};", re.S)


def parse(path):
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    tables = []
    for m in ARRAY_RE.finditer(text):
        pairs = []
        for e in ENTRY_RE.finditer(m.group("body")):
            reg = int(e.group("reg"), 16)
            val = int(e.group("val"), 16)
            if e.group("width") == "16":
                pairs.append((reg, (val >> 8) & 0xff))
                pairs.append((reg + 1, val & 0xff))
            else:
                pairs.append((reg, val & 0xff))
        tables.append((m.group("name"), pairs))
    return tables


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, outdir = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3:]
    os.makedirs(outdir, exist_ok=True)
    total = 0
    for name, pairs in parse(src):
        if wanted and name not in wanted:
            continue
        if not pairs:
            continue
        short = re.sub(r"^(imx|gc|s5k)\w*?_", "", name)
        short = re.sub(r"_regs$", "", short)
        dst = os.path.join(outdir, "%s.txt" % short)
        with open(dst, "w", newline="\n") as f:
            f.write("# %s -> %s (%d byte writes)\n" % (name, short, len(pairs)))
            for reg, val in pairs:
                f.write("0x%04x 0x%02x\n" % (reg, val))
        print("%-34s %4d writes  %s" % (name, len(pairs), dst))
        total += 1
    print("%d table(s) written" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
