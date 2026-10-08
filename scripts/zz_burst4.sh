#!/bin/sh
# zz_burst4.sh - run all four zz_burst variants (needs /root/zz_burst.sh pushed).
set -u
for V in a b c d; do
	sh /root/zz_burst.sh $V 600 2>&1 | grep -E '^###|lines:|frame ready|timeouts|wall:|^(avg|timing|dist)|crashes:|rmmod failed|ABORT|\[!!\]'
	echo "----- variant $V done"
done
echo "files: $(ls /root/burst_*.txt 2>/dev/null | tr '\n' ' ')"
echo "### zz_burst4 ALLDONE"
