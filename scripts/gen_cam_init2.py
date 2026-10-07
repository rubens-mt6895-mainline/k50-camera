#!/usr/bin/env python3
# v2 generator - fresh file
import re, sys
H = '${HOME}/fp_work/cam/ksrc/drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/rubensimx582mipiraw_Sensor.h'
raw = open(H, 'rb').read()
print("bytes:", len(raw))
txt = raw.decode('utf-8', errors='replace')

def grab(name):
    pfx = 'static kal_uint16 ' + name + '[] = {'
    i = txt.find(pfx)
    if i < 0:
        print("NO HEADER:", name); return []
    j = txt.find('};', i)
    body = txt[i+len(pfx):j]
    pairs = re.findall(r'0x([0-9A-Fa-f]{4})\s*,\s*0x([0-9A-Fa-f]{4})', body)
    return [(int(a,16), int(b,16)) for a, b in pairs]

init = grab('rubensimx582_init_setting')
prev = grab('rubensimx582_preview_setting')
print("init:", len(init), "preview:", len(prev))
print("first init:", init[:3])
print("first prev:", prev[:3])

out = ['#!/bin/sh', '# cam_init.sh v2 - IMX582 init+preview+streaming', '']
for label, tbl in (('init_setting %d' % len(init), init), ('preview_setting %d' % len(prev), prev)):
    out.append('# ' + label)
    for r, v in tbl:
        out.append('i2ctransfer -f -y 10 w4@0x10 0x%02X 0x%02X 0x%02X 0x%02X' % ((r>>8)&0xff, r&0xff, (v>>8)&0xff, v&0xff))
out += ['# streaming on',
        'i2ctransfer -f -y 10 w4@0x10 0x03 0x50 0x00 0x01',
        'i2ctransfer -f -y 10 w4@0x10 0x30 0x20 0x00 0x00',
        'i2ctransfer -f -y 10 w4@0x10 0x01 0x00 0x00 0x01', '',
        'echo DONE']
open('${K50_REPO}/scripts/cam_init.sh', 'w').write('\n'.join(out) + '\n')
print("written, cmds:", len(init)+len(prev)+3)
