#!/usr/bin/env python3
"""Compare the two generated register-table sources used for a mode switch.

The driver replays tables compiled in from src/imx582_modes.h
(scripts/gen_modes_header.py), while the userspace bring-up replays
/root/mode_<name>.txt (scripts/gen_mode_table.py).  Both come from the same
vendor header, so they must agree register for register and in order; if they
do not, a mode switch through the driver configures the sensor differently
from the sequence that is known to work.

Usage: python scripts/check_mode_tables.py [src/imx582_modes.h] [out/modes]
"""
import os
import re
import sys

HDR = sys.argv[1] if len(sys.argv) > 1 else os.path.join("src", "imx582_modes.h")
MODES_DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.join("out", "modes")

ARRAY_RE = re.compile(r"cam_mode_reg\s+(\w+)\s*\[\s*\]\s*=\s*\{")
PAIR_RE = re.compile(r"\{\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\}")


def parse_header(path):
    """-> {array name: [(reg, val), ...]} for every cam_mode_reg array."""
    tables = {}
    name = None
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            m = ARRAY_RE.search(line)
            if m:
                name = m.group(1)
                tables[name] = []
                # an array may open and hold pairs on the same line
                for reg, val in PAIR_RE.findall(line):
                    tables[name].append((int(reg, 16), int(val, 16)))
                continue
            if name is not None:
                if "};" in line:
                    name = None
                    continue
                for reg, val in PAIR_RE.findall(line):
                    tables[name].append((int(reg, 16), int(val, 16)))
    return tables


def parse_mode_file(path):
    """-> [(reg, val), ...] from a '0xREG 0xVAL' table file."""
    pairs = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 2 and parts[0].startswith("0x"):
                pairs.append((int(parts[0], 16), int(parts[1], 16)))
    return pairs


def main():
    tables = parse_header(HDR)
    print(f"{HDR}: {len(tables)} cam_mode_reg arrays")
    for name in sorted(tables):
        print(f"  {name}: {len(tables[name])} pairs")

    rc = 0
    for array, pairs in sorted(tables.items()):
        suffix = array
        for prefix in ("cam_imx582_tbl_", "cam_imx582_"):
            if suffix.startswith(prefix):
                suffix = suffix[len(prefix):]
                break
        path = os.path.join(MODES_DIR, f"mode_{suffix}.txt")
        if not os.path.exists(path):
            print(f"[skip] {array}: no {path}")
            continue
        ref = parse_mode_file(path)
        if ref == pairs:
            print(f"[ OK ] {array} == {os.path.basename(path)} ({len(pairs)} pairs, same order)")
            continue
        rc = 1
        print(f"[FAIL] {array} != {os.path.basename(path)}: header {len(pairs)} pairs, file {len(ref)} pairs")
        n = max(len(pairs), len(ref))
        shown = 0
        for i in range(n):
            a = pairs[i] if i < len(pairs) else None
            b = ref[i] if i < len(ref) else None
            if a != b:
                fa = "0x%04x 0x%02x" % a if a else "-"
                fb = "0x%04x 0x%02x" % b if b else "-"
                print(f"       #{i:3d} header {fa}   file {fb}")
                shown += 1
                if shown >= 10:
                    print("       ...")
                    break
    return rc


if __name__ == "__main__":
    sys.exit(main())
