#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} '
echo "== uptime =="; uptime
echo "== dmesg head =="; dmesg | head -25
echo "== dmesg genpd/scpsys/pmdomain =="; dmesg | grep -iE "genpd|pmdomain|scpsys|XAGA|Failed to power|power-controller" | head -40
echo "== running DTB: soc children (scpsys/seninf/cam) =="
ls /proc/device-tree/soc@0/ 2>/dev/null | grep -iE "scpsys|power|seninf|syscon|cam|pda"
echo "== scpsys node compat/reg =="
for d in /proc/device-tree/soc@0/*scpsys* /proc/device-tree/soc@0/*power-controller*; do
  [ -d "$d" ] || continue
  echo "--- $d"; tr -d "\0" < $d/compatible 2>/dev/null; echo; echo -n "reg="; od -An -tx4 $d/reg 2>/dev/null
done
echo "== SPM PWR_CON cam/isp/mfg =="
for a in 1c001e24 1c001e28 1c001e2c 1c001e30 1c001e44 1c001e48 1c001e4c 1c001e50 1c001e54 1c001e58 1c001e6c 1c001ebc 1c001ec0 1c001f34 1c001f38; do printf "%s = " $a; busybox devmem 0x$a; done
echo "== regulator summary (cam rails) =="
head -45 /sys/kernel/debug/regulator/regulator_summary 2>/dev/null
echo "== pinctrl 158/159/20/149/155 =="
for f in /sys/kernel/debug/pinctrl/*/pinmux-pins; do echo "-- $f"; grep -E "pin (20|149|155|158|159|164) " $f; done 2>/dev/null
echo "== gpio banks 10005000 =="
for a in 10005000 10005040 10005050 10005100 10005140 10005150 10005200 10005240 10005250 10005420 10005430 10005440; do printf "%s = " $a; busybox devmem 0x$a; done
echo "== MMIO recheck =="
for a in 1a000000 1a000010 1a010000 1a014200 1a014a00 1a100000 1a110000 1a130000 1a170000 1c001000; do printf "%s = " $a; busybox devmem 0x$a; done
'
