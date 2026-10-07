#!/bin/sh
# Build m6315.ko against the running-kernel tree, deploy and run.
set -e
K=${KDIR}
SRC=${K50_REPO}
OUT=${K50_REPO}/out/m6315
mkdir -p $OUT

echo "== spmi helper prototypes =="
grep -n "spmi_ext_register_readl\|spmi_ext_register_writel\|spmi_find_device_by_of_node" $K/include/linux/spmi.h

cp -f $SRC/m6315.c $OUT/m6315.c
cat > $OUT/Makefile <<'EOF'
obj-m := m6315.o
EOF

echo "== build =="
make -C $K M=$OUT ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules 2>&1 | grep -vE "^(  )?(CC|LD|GEN|AR|Checking|MODPOST|WARNING: modpost)" | tail -30
ls -l $OUT/m6315.ko
strings $OUT/m6315.ko | grep -m1 vermagic || true

echo "== deploy =="
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no $OUT/m6315.ko root@${K50_HOST}:/root/ && echo scp-ok

echo "== run (read-only first) =="
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} 'rmmod m6315 2>/dev/null; dmesg -C; insmod /root/m6315.ko act='${1:-0}'; sleep 1; dmesg'
