#!/bin/sh
# zz_sensor_geom.sh - read IMX582 output geometry / timing registers (16-bit reg addr, 8-bit data)
B=10
A=0x10
rd() {
	hi=$1; lo=$2
	out=$(i2ctransfer -f -y $B w2@$A 0x$hi 0x$lo r1 2>/dev/null)
	echo "0x$hi$lo = $out"
}
echo "== ID / mode =="
rd 00 16; rd 00 17; rd 01 00; rd 01 01; rd 01 12; rd 01 14
echo "== timing =="
rd 03 40; rd 03 41; rd 03 42; rd 03 43; rd 03 50; rd 03 51; rd 03 07
echo "== output size X/Y =="
rd 03 4c; rd 03 4d; rd 03 4e; rd 03 4f
echo "== crop/start =="
rd 03 80; rd 03 81; rd 03 82; rd 03 83; rd 03 84; rd 03 85; rd 03 86; rd 03 87
echo "== readout / binning =="
rd 04 0c; rd 04 0d; rd 04 0e; rd 04 0f; rd 09 00; rd 09 01
echo "== lane / phy =="
rd 04 24; rd 04 25; rd 04 26; rd 04 27; rd 04 28; rd 04 29
echo "done"
