#!/bin/sh
# zz_atomic.sh - is the CAMSV IMGO DMA atomic (one frame per arm) or continuous?
M=/proc/camcap
nice -n 19 sh -c '
echo "--- module params ---"
for f in dbl_data_bus pak_mode pak_dbl route_pix_mode frame_bytes; do
  printf "  %-16s %s\n" "$f" "$(cat /sys/module/cam_cap/parameters/$f)"
done
echo "--- cfg + arm ---"
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
echo arm > /proc/camcap
sleep 2
a=$(dd if=/proc/camcap bs=1M count=19 2>/dev/null | md5sum | cut -d" " -f1)
sleep 1
b=$(dd if=/proc/camcap bs=1M count=19 2>/dev/null | md5sum | cut -d" " -f1)
sleep 1
c=$(dd if=/proc/camcap bs=1M count=19 2>/dev/null | md5sum | cut -d" " -f1)
echo "  t+2s : $a"
echo "  t+3s : $b"
echo "  t+4s : $c"
if [ "$a" = "$b" ] && [ "$b" = "$c" ]; then
  echo "VERDICT: buffer STABLE -> IMGO DMA stopped by itself (atomic capture)"
else
  echo "VERDICT: buffer CHANGING -> TG keeps writing, SINGLE_MODE needed"
fi
echo "--- status ---"
head -20 /proc/camcap_info
'
