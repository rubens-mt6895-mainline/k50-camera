#!/usr/bin/env python3
import re
src = open('${K50_REPO}/src/imx586_Sensor.c', encoding='utf-8', errors='ignore').read()
m = re.search(r'static kal_uint16 imx586_init_setting\[\] = \{(.*?)\n\};', src, re.S)
body = m.group(1)
pairs = re.findall(r'0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{1,2})', body)
print('total', len(pairs))
for a, b in pairs[-15:]:
    print('0x%04X = 0x%02X' % (int(a,16), int(b,16)))
# also check preview table tail
m2 = re.search(r'static kal_uint16 imx586_preview_setting\[\] = \{(.*?)\n\};', src, re.S)
p2 = re.findall(r'0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{1,2})', m2.group(1))
print('preview total', len(p2))
for a, b in p2[-10:]:
    print('0x%04X = 0x%02X' % (int(a,16), int(b,16)))
