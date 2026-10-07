#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"

echo "===== broad CAMSYS/ISP/CCU/DPHY accessibility scan (read-only) ====="
$H 'for b in 0x1a000000 0x1a001000 0x1a002000 0x1a003000 0x1a004000 0x1a005000 0x1a006000 0x1a007000 0x1a008000 0x1a009000 0x1a00a000 0x1a00b000 0x1a00c000 0x1a00d000 0x1a010000 0x1a012000 0x1a014000 0x1a016000 0x1a030000 0x1a04f000 0x1a050000 0x1a06f000 0x1a070000 0x1a08f000 0x1a090000 0x1a0af000 0x1a0b0000 0x1a0cf000 0x1a0d0000 0x1a0ef000 0x1a100000 0x1a110000 0x1a120000 0x1a130000 0x1a140000 0x1a150000 0x1a160000 0x1a170000 0x1a180000 0x1b080000 0x15000000 0x11c80000 0x11c86000 0x11c88000 0x11c89000 0x11c8a000; do
  a=$(busybox devmem $((b+0))   32); b2=$(busybox devmem $((b+4)) 32); c=$(busybox devmem $((b+8)) 32); d=$(busybox devmem $((b+12)) 32)
  printf "%08x : +0=%s +4=%s +8=%s +c=%s\n" $b "$a" "$b2" "$c" "$d"
done 2>/dev/null'
