#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} '
echo "==debugfs spmi/pmic/regmap=="
ls /sys/kernel/debug/ | grep -iE "spmi|pmic|regmap|6315|mfd"
echo "==find spmi/pmic under debugfs=="
find /sys/kernel/debug -maxdepth 2 \( -iname "*spmi*" -o -iname "*pmic*" -o -iname "*regmap*" \) 2>/dev/null
echo "==spmi devices=="
ls /sys/bus/spmi/devices
echo "==spmi device attrs=="
for d in /sys/bus/spmi/devices/*; do echo "--- $d"; ls $d 2>/dev/null | tr "\n" " "; echo; done
echo "==platform drivers spmi/pmic/debug=="
ls /sys/bus/platform/drivers | grep -iE "spmi|pmic|debug"
echo "==mfd devices=="
ls /sys/bus/platform/devices | grep -iE "spmi|pmic|mt6"
'
