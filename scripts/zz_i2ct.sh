#!/bin/sh
# zz_i2ct.sh - figure out why the i2ctransfer write inside a shell function failed
echo "--- printf/arith test"
V=0x1000
HI=$(printf "%02x" $(( (V >> 8) & 0xff )))
LO=$(printf "%02x" $(( V & 0xff )))
echo "HI=[$HI] LO=[$LO]"
echo "--- write with vars"
i2ctransfer -f -y 8 w4@0x10 0x02 0x02 $HI $LO
echo "rc=$?"
echo "--- write with literals"
i2ctransfer -f -y 8 w4@0x10 0x02 0x02 0x10 0x00
echo "rc=$?"
echo "--- readback reg 0x0202"
i2ctransfer -f -y 8 w2@0x10 0x02 0x02 r2@0x10
echo "rc=$?"
echo "--- readback reg 0x0200 (is there another coarse reg?)"
i2ctransfer -f -y 8 w2@0x10 0x02 0x00 r2@0x10
echo "rc=$?"
echo "--- read id 0x0000"
i2ctransfer -f -y 8 w2@0x10 0x00 0x00 r2@0x10
echo "rc=$?"
echo "--- i2ctransfer version"
i2ctransfer -V 2>&1 | head -2
echo "--- which sh"
ls -l /bin/sh
