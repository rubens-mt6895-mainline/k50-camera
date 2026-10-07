#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
echo "===== uptime / if the box is up ====="
$H 'uptime; cat /proc/cmdline'

echo
echo "===== WRITE-PERSISTENCE TEST (rd / wr 0x5A5A5A5A / rd / wr 0xA5A5A5A5 / rd / restore) ====="
$H 'for a in 0x1a000000 0x1a100000 0x1a170000 0x1a010000 0x1a010008 0x1a014200 0x1a014a00 0x1a014adc 0x1a110000 0x1a130000 0x11c8a000 0x11c88000; do
  O=$(busybox devmem $a 32)
  busybox devmem $a 32 0x5A5A5A5A
  R1=$(busybox devmem $a 32)
  busybox devmem $a 32 0xA5A5A5A5
  R2=$(busybox devmem $a 32)
  busybox devmem $a 32 $O
  RC=$(busybox devmem $a 32)
  printf "%08x old=%s w5A->%s wA5->%s restore=%s\n" $a "$O" "$R1" "$R2" "$RC"
done'

echo
echo "===== seninf page 0x1a010000 offsets 0x00-0xFC (step 4, nonzero only) ====="
$H 'for o in $(seq 0 4 252); do a=$((0x1a010000+o)); v=$(busybox devmem $a 32); if [ "$v" != "0x00000000" ]; then printf "%08x = %s\n" $a "$v"; fi; done; echo "(end)"'

echo
echo "===== PDA page 0x1a100000 offsets 0x00-0xFC (nonzero only) ====="
$H 'for o in $(seq 0 4 252); do a=$((0x1a100000+o)); v=$(busybox devmem $a 32); if [ "$v" != "0x00000000" ]; then printf "%08x = %s\n" $a "$v"; fi; done; echo "(end)"'

echo
echo "===== camsv1 page 0x1a110000 offsets 0x00-0xFC (nonzero only) ====="
$H 'for o in $(seq 0 4 252); do a=$((0x1a110000+o)); v=$(busybox devmem $a 32); if [ "$v" != "0x00000000" ]; then printf "%08x = %s\n" $a "$v"; fi; done; echo "(end)"'

echo
echo "===== /proc/iomem (full) ====="
$H 'cat /proc/iomem'

echo
echo "===== dmesg: devapc / smmu / iommu / access errors ====="
$H 'dmesg | grep -iE "devapc|smmu|iommu|device access|access.*denied" | head -20'
