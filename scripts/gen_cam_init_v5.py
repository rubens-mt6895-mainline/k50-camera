#!/usr/bin/env python3
# gen_cam_init_v5.py - rebuild cam_init.sh from vendor tables by exact line ranges
import re, subprocess

H = '${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/rubensimx582mipiraw_Sensor.h'
r = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-c', 'cat -n ' + H],
                   capture_output=True, text=True, timeout=60)
lines = r.stdout.splitlines()
text = {}
for ln in lines:
    m = re.match(r'\s*(\d+)\t(.*)', ln)
    if m:
        text[int(m.group(1))] = m.group(2)

def parse(lo, hi):
    pairs = []
    for n in range(lo, hi + 1):
        m = re.match(r'\s*0x([0-9A-Fa-f]{2,4}),\s*0x([0-9A-Fa-f]{1,4}),?', text.get(n, ''))
        if m:
            pairs.append((int(m.group(1), 16), int(m.group(2), 16)))
    return pairs

init = parse(24, 137)      # rubensimx582_init_setting
preview = parse(144, 256)  # rubensimx582_preview_setting
print("init:", len(init), "preview:", len(preview))

# sanity: check preview contains expected key regs
pk = dict(preview)
for reg in (0x0112, 0x0114, 0x0340, 0x0342, 0x0306, 0x0307, 0x0901, 0x3246):
    print("  preview %04X=%02X" % (reg, pk.get(reg, -1)))

# streaming sequence (from Sensor.c streaming_control)
stream = [(0x0350, 0x01), (0x3020, 0x00), (0x0100, 0x01)]

m = {}
for reg, val in init + preview + stream:
    m[reg] = val

lines = ["#!/bin/sh",
         "# cam_init.sh v5 - exact vendor tables init(%d)+preview(%d)+streaming(3), %d unique" % (len(init), len(preview), len(m))]
for reg in sorted(m):
    hi, lo, v = (reg >> 8) & 0xFF, reg & 0xFF, m[reg] & 0xFF
    lines.append("i2ctransfer -f -y 10 w3@0x10 0x%02X 0x%02X 0x%02X" % (hi, lo, v))
lines.append("echo cam_init_v5 done: %d writes" % len(m))
with open(r'${K50_REPO}\scripts\cam_init.sh', 'w', newline='\n') as f:
    f.write('\n'.join(lines) + '\n')
print("written v5:", len(m), "unique regs")
