#!/usr/bin/env python3
# run_imx586_table.py - extract imx586 init+preview tables and write to IMX582
import re, subprocess, time, sys

src = open('/root/imx586_Sensor.c', encoding='utf-8', errors='ignore').read()

def extract_table(name, src):
    m = re.search(r'static kal_uint16 %s\[\] = \{(.*?)\n\};' % name, src, re.S)
    if not m:
        print("table %s not found" % name); return None
    body = m.group(1)
    pairs = []
    for a, b in re.findall(r'0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{1,2})', body):
        pairs.append((int(a,16), int(b,16)))
    return pairs

def i2cset(reg, val):
    subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10',
                    '0x%02x'%((reg>>8)&0xff), '0x%02x'%(reg&0xff), '0x%02x'%(val&0xff)],
                   capture_output=True)
def i2cget(reg):
    r = subprocess.run(['i2ctransfer','-f','-y','10','w2@0x10',
                        '0x%02x'%((reg>>8)&0xff), '0x%02x'%(reg&0xff),'r1'],
                       capture_output=True, text=True)
    return r.stdout.strip()

init = extract_table('imx586_init_setting', src)
prev = extract_table('imx586_preview_setting', src)
print("init entries:", len(init) if init else 0, "preview entries:", len(prev) if prev else 0)

# write init (whole table, skip burst-mode-only registers? just write all)
if init:
    for reg, val in init:
        i2cset(reg, val)
    print("init table written")
time.sleep(0.3)
if prev:
    for reg, val in prev:
        i2cset(reg, val)
    print("preview table written")

# streaming sequence per IMX586
i2cset(0x0350, 0x01)
i2cset(0x3020, 0x00)
i2cset(0x0100, 0x01)
time.sleep(1.0)

fc = i2cget(0x0005)
print("framecnt:", fc)
print("0x0114:", i2cget(0x0114))
print("0x0111:", i2cget(0x0111))
print("0x0112:", i2cget(0x0112))
print("0x3C7E:", i2cget(0x3C7E))
