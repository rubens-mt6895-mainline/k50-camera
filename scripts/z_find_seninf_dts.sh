#!/bin/bash
# find seninf node reg-names in vendor dts
python3 << 'EOF'
import re
d = open('${HOME}/bb_work/vendor_live.dts').read()
# find all seninf nodes
for m in re.finditer(r'seninf\s*:\s*seninf@([0-9a-f]+)', d):
    print("node @", m.group(1))
    i = m.start()
    seg = d[i:i+1800]
    print(seg)
    print("======")
# also try any node with seninf in name
for m in re.finditer(r'(\w+)\s*:\s*(\w+)@([0-9a-f]+)', d):
    if 'seninf' in (m.group(1)+m.group(2)).lower():
        print("cand:", m.group(1), m.group(2), m.group(3))
EOF
