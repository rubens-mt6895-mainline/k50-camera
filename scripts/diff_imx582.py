#!/usr/bin/env python3
# diff_imx582.py - compare vendor table vs cam_init.sh
import re, sys

def parse_ref(paths):
    """parse {0xREG, 0xVAL,} pairs"""
    pairs = []
    for p in paths:
        txt = open(p, encoding='utf-8', errors='ignore').read()
        vals = re.findall(r'0x([0-9A-Fa-f]{2,4}),\s*0x([0-9A-Fa-f]{1,2})', txt)
        for reg, val in vals:
            pairs.append((int(reg, 16), int(val, 16)))
    return pairs

def parse_sh(path):
    """parse i2ctransfer w3 lines: 0xHH 0xLL 0xDATA -> reg(16bit), val"""
    pairs = []
    for line in open(path, encoding='utf-8', errors='ignore'):
        m = re.search(r'w3@0x10\s+(0x[0-9A-Fa-f]{2})\s+(0x[0-9A-Fa-f]{2})\s+(0x[0-9A-Fa-f]{1,2})', line)
        if m:
            hi, lo, val = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16)
            pairs.append(((hi << 8) | lo, val))
    return pairs

ref = parse_ref([r'${K50_REPO}\out\ref_preview_part1.txt',
                 r'${K50_REPO}\out\ref_preview_part2.txt'])
sh = parse_sh(r'${K50_REPO}\scripts\cam_init.sh')
refmap = dict(ref)
shmap = dict(sh)

print("ref table entries:", len(ref), " cam_init.sh entries:", len(sh))
only_ref = [r for r in ref if r[0] not in shmap]
only_sh = [r for r in sh if r[0] not in refmap]
diff_val = [(r, refmap[r], shmap[r]) for r in refmap if r in shmap and refmap[r] != shmap[r]]
print("\n--- in ref but MISSING in cam_init.sh (%d) ---" % len(only_ref))
for reg, val in sorted(only_ref):
    print("  %04X = %02X  (missing)" % (reg, val))
print("\n--- in cam_init.sh but NOT in ref table (%d) ---" % len(only_sh))
for (reg, val) in sorted(only_sh):
    print("  %04X = %02X  (extra)" % (reg, val))
print("\n--- value differs (%d) ---" % len(diff_val))
for reg, rv, sv in sorted(diff_val):
    print("  %04X: ref=%02X cam_init=%02X" % (reg, rv, sv))
