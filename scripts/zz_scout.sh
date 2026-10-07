#!/bin/sh
# zz_scout.sh <mode>... - run several mode drills back to back in ONE ssh
# session (m00471: one device task at a time, no polling) and print one
# compact report per mode.
set -u
[ $# -ge 1 ] || { echo "usage: zz_scout.sh <mode>..."; exit 2; }
for M in "$@"; do
  echo "############ $M"
  sh /root/zz_mode.sh "$M" 30 8 2>&1 | grep -E 'zz_mode:|registered /dev|^[0-9]+\.[0-9]+ fps|^avg|^dist|^ae |^stats|^awb|burst:|\[!!\]|ABORT|source:'
done
echo "### zz_scout done"
