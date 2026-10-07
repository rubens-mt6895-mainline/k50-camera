#!/usr/bin/env python3
# gen_cam_init_v4.py - rebuild cam_init.sh from vendor rubensimx582 tables
import re, subprocess, os

SENSOR_H = '${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/rubensimx582mipiraw_Sensor.h'
SENSOR_C = '${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/rubensimx582mipiraw_Sensor.c'

def get_wsl(path):
    r = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-c', 'cat ' + path],
                       capture_output=True, text=True, timeout=60)
    return r.stdout

def parse_pairs(txt, start_marker, end_marker):
    """extract {reg, val} pairs between markers; vals may be 8 or 16 bit."""
    s = txt.index(start_marker)
    e = txt.index(end_marker, s)
    body = txt[s+len(start_marker):e]
    vals = re.findall(r'0x([0-9A-Fa-f]{2,4}),\s*0x([0-9A-Fa-f]{1,4})', body)
    pairs = []
    for reg, val in vals:
        rv = int(reg, 16)
        vv = int(val, 16)
        # vendor table: some entries are 16-bit values written via 2x 8bit
        # (reg, val) pairs where val > 0xFF happen when kal_uint16 data
        pairs.append((rv, vv))
    return pairs

txt = get_wsl(SENSOR_H)
print("sensor.h length:", len(txt))

# init table
init_pairs = parse_pairs(txt, 'rubensimx582_init_setting[] = {', 'static kal_uint16')
print("init entries:", len(init_pairs))

# preview table: from 'rubensimx582_preview_setting[] = {' to next '};'
preview_pairs = parse_pairs(txt, 'rubensimx582_preview_setting[] = {', '};')
print("preview entries:", len(preview_pairs))

# streaming sequence from Sensor.c
sc = get_wsl(SENSOR_C)
stream_pairs = [(0x0350, 0x01), (0x3020, 0x00), (0x0100, 0x01)]

all_pairs = init_pairs + preview_pairs + stream_pairs
# dedupe keeping last
m = {}
for reg, val in all_pairs:
    m[reg] = val

lines = ["#!/bin/sh", "# cam_init.sh v4 - regenerated from vendor rubensimx582mipiraw tables", "# init(%d) + preview(%d) + streaming(3)" % (len(init_pairs), len(preview_pairs))]
for reg in sorted(m):
    hi = (reg >> 8) & 0xFF
    lo = reg & 0xFF
    v = m[reg] & 0xFF
    lines.append("i2ctransfer -f -y 10 w3@0x10 0x%02X 0x%02X 0x%02X" % (hi, lo, v))
lines.append("echo cam_init_v4 done: %d writes" % len(m))

with open(r'${K50_REPO}\scripts\cam_init.sh', 'w', newline='\n') as f:
    f.write('\n'.join(lines) + '\n')
print("written cam_init.sh v4 with %d unique regs" % len(m))
