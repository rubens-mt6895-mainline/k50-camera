#!/usr/bin/env python3
# gen_cam_init_v6.py - vendor tables in ORIGINAL ORDER (init -> preview -> streaming)
import re, subprocess

H = '${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/rubensimx582mipiraw_Sensor.h'
r = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-c', 'cat -n ' + H],
                   capture_output=True, text=True, timeout=60)
text = {}
for ln in r.stdout.splitlines():
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

init = parse(24, 137)
preview = parse(144, 256)
stream = [(0x0350, 0x01), (0x3020, 0x00), (0x0100, 0x01)]

seq = init + preview + stream
lines = ["#!/bin/sh",
         "# cam_init.sh v6 - vendor tables original order init(%d)+preview(%d)+streaming(%d)" % (len(init), len(preview), len(stream))]
for reg, val in seq:
    hi, lo, v = (reg >> 8) & 0xFF, reg & 0xFF, val & 0xFF
    lines.append("i2ctransfer -f -y 10 w3@0x10 0x%02X 0x%02X 0x%02X" % (hi, lo, v))
lines.append("echo cam_init_v6 done: %d writes" % len(seq))
with open(r'${K50_REPO}\scripts\cam_init.sh', 'w', newline='\n') as f:
    f.write('\n'.join(lines) + '\n')
print("v6 written:", len(seq), "writes in original order; first:", lines[2], "; last:", lines[-2])
