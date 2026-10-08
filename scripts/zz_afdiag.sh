#!/bin/sh
# Autofocus diagnostic.  Sweeps the VCM manually and reads the live contrast
# metric at every position, then hands the lens back to the search and watches
# whether it settles.  Moves the lens (the search already does), no reload.
info() {
  sed -n 's/^af *:.*state=\([a-z]*\) pos=\([0-9]*\) metric=\([0-9]*\) y=\([0-9]*\).*/\1 \2 \3 \4/p' /proc/camcap_info
}
sample() {	# five samples at the current position -> "<metric> <y>"
  i=0; sum=0; ys=0; n=0
  while [ $i -lt 5 ]; do
    set -- $(info)
    if [ -n "$3" ]; then sum=$((sum + $3)); ys=$((ys + $4)); n=$((n + 1)); fi
    sleep 0.2
    i=$((i + 1))
  done
  if [ $n -gt 0 ]; then echo "$((sum / n)) $((ys / n))"; else echo "0 0"; fi
}
echo "=== live state ==="
sed -n -e '/^af *:/p' -e '/^stats *:/p' -e '/^ae *:/p' -e '/^avg *:/p' /proc/camcap_info
echo "=== manual sweep: pos -> metric (mean of 5 frames), y ==="
echo "af off" > /proc/camcap
for p in 0 128 256 384 448 512 576 640 768 896 1023; do
  echo "af pos $p" > /proc/camcap
  sleep 0.4
  set -- $(sample)
  echo "pos $p  metric $1  y $2"
done
echo "=== video: give the search 25 s and see whether it settles ==="
echo "af auto" > /proc/camcap
sleep 25
sed -n -e '/^af *:/p' -e '/^avg *:/p' /proc/camcap_info
echo "=== dmesg cam_af tail ==="
dmesg | grep -E 'cam_cap: cam_af|af manual' | tail -30
echo "=== health ==="
uptime
