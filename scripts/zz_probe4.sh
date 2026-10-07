#!/bin/sh
TREE=${KDIR}
echo "######## WSL: mt6315 regulator driver present? ########"
ls $TREE/drivers/regulator/ | grep -iE "6315|6363"
echo "######## WSL: mt6315 nodes in DTS ########"
grep -rn "mt6315" $TREE/arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dts $TREE/arch/arm64/boot/dts/mediatek/mt6895.dtsi 2>/dev/null | head -30
echo "######## WSL: 6_vbuck / vmm strings in rubens dts ########"
grep -n "vbuck\|vmm\|cam\|isp" $TREE/arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dts 2>/dev/null | head -40
echo "######## WSL: scpsys node in rubens dts ########"
grep -n -A12 "mt6895-scpsys\|power-controller@1c001000" $TREE/arch/arm64/boot/dts/mediatek/mt6895*.dts* 2>/dev/null | head -40
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} '
echo "== our regulators: vbuck / 6315 =="
grep -iE "vbuck|6315|mt63" /sys/kernel/debug/regulator/regulator_summary
echo "== regulator_summary total lines =="; grep -c . /sys/kernel/debug/regulator/regulator_summary
echo "== platform drivers reg ==="; ls /sys/bus/platform/drivers/ | grep -iE "regulator|6315|6363|spmi"
echo "== DT nodes with 6315/6363 =="; ls /proc/device-tree/ | head -40
find /proc/device-tree -maxdepth 3 -name "*6315*" -o -maxdepth 3 -name "*6363*" 2>/dev/null | head
echo "== spmi =="; ls /sys/bus/spmi/devices 2>/dev/null; ls /sys/class/regulator/ | head -40
'
