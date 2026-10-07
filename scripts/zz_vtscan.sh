#!/bin/sh
# zz_vtscan.sh <vts1> [vts2 ...] - run zz_vts1.sh over a list of VTS values.
for v in "$@"; do
	sh /root/zz_vts1.sh "$v" 8
done
echo "=== zz_vtscan done ==="
