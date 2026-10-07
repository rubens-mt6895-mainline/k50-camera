#!/bin/sh
echo "--- context around line 887 ---"
dmesg | sed -n '878,900p'
echo "--- what precedes each Call trace (2 lines before) ---"
dmesg | grep -n -B3 'Call trace:' | head -40
