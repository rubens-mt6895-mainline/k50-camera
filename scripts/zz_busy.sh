#!/bin/sh
# Who is holding /dev/video0 right now?
echo "=== fuser ==="
fuser -v /dev/video0 2>&1
echo "=== lsof-ish via /proc ==="
for p in /proc/[0-9]*; do
  pid=${p#/proc/}
  hit=0
  for f in "$p"/fd/*; do
    t=$(readlink "$f" 2>/dev/null)
    case "$t" in *video0*) hit=1;; esac
  done
  if [ "$hit" = 1 ]; then
    printf 'pid %s: %s\n' "$pid" "$(tr -d '\0' < "$p/cmdline" | tr '\0' ' ')"
  fi
done
echo "=== cheese procs ==="
ps -eo pid,pcpu,etime,args | grep -i '[c]heese'
echo "=== camcap ==="
grep -E 'arm_count|vf_on|frame_ready|last_result' /proc/camcap_info
echo "=== done ==="
