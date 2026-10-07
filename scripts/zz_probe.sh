#!/bin/sh
TREE=${KDIR}
echo "######## mtk-scpsys-bringup.c ########"
cat $TREE/drivers/soc/mediatek/mtk-scpsys-bringup.c 2>/dev/null
echo "######## mtk-pm-domain-disable-unused.c ########"
cat $TREE/drivers/soc/mediatek/mtk-pm-domain-disable-unused.c 2>/dev/null
echo "######## clk_summary lines 700-800 (cam_m block + cam_lp) ########"
sed -n '640,700p;760,800p' /dev/null 2>/dev/null
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} '
echo "== uptime =="; uptime
echo "== /root ko files =="; ls -l /root/*.ko 2>/dev/null
echo "== lsmod =="; lsmod
echo "== scpsys/power platform drivers =="; ls /sys/bus/platform/drivers/ | grep -iE "scpsys|power|pm-domain"
echo "== dmesg bringup/scpsys =="; dmesg | grep -iE "scpsys|XAGA|bringup|isp_main" | tail -25
echo "== clk_summary: cam_lp context =="; grep -n -B3 -A1 "cam_lp-" /sys/kernel/debug/clk/clk_summary
echo "== SPM/MMIO BEFORE =="
for a in 1c001e24 1c001e28 1c001e2c 1c001e44 1c001f34 1a000000 1a010000 1a014200 1a014a00 1a100000 1a110000 1a170000; do printf "%s = " $a; busybox devmem 0x$a; done
'
