#!/usr/bin/env python3
# Robust line-based parser: extract init+preview tables
H = '${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/rubensimx582mipiraw_Sensor.h'
lines = open(H).read().splitlines()

def extract(name):
    pairs = []
    in_tbl = False
    for ln in lines:
        if not in_tbl:
            if ln.strip().startswith('static kal_uint16 ' + name + '[]'):
                in_tbl = True
            continue
        s = ln.strip().rstrip(',')
        if s == '};':
            break
        m = re.match(r'0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{4})', s)
        if m:
            pairs.append((int(m.group(1),16), int(m.group(2),16)))
    return pairs

import re
init = extract('rubensimx582_init_setting')
preview = extract('rubensimx582_preview_setting')
print("init pairs:", len(init), "preview pairs:", len(preview))

lines_out = ['#!/bin/sh', '# cam_init.sh - IMX582 init+preview+streaming (vendor rubensimx582mipiraw_Sensor.h)', '']
def add_cmd(pairs, label):
    lines_out.append('# ' + label)
    for reg, val in pairs:
        lines_out.append('i2ctransfer -f -y 10 w4@0x10 0x%02X 0x%02X 0x%02X 0x%02X' %
                         ((reg>>8)&0xff, reg&0xff, (val>>8)&0xff, val&0xff))
add_cmd(init, 'init_setting (%d)' % len(init))
add_cmd(preview, 'preview_setting (%d)' % len(preview))
lines_out.append('# streaming on')
lines_out.append('i2ctransfer -f -y 10 w4@0x10 0x03 0x50 0x00 0x01')
lines_out.append('i2ctransfer -f -y 10 w4@0x10 0x30 0x20 0x00 0x00')
lines_out.append('i2ctransfer -f -y 10 w4@0x10 0x01 0x00 0x00 0x01')
lines_out.append('')
lines_out.append('echo DONE')
open('${K50_REPO}/scripts/cam_init.sh', 'w').write('\n'.join(lines_out) + '\n')
print("total cmds:", len(init)+len(preview)+3, "written")
