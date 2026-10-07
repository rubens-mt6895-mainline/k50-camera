#!/bin/sh
# Is the build tree the one the running kernel came from?  Does the device
# expose BTF / config so we can compare struct layouts?
K=${KDIR}
echo "== tree timestamps (build artifacts vs config) =="
ls -l --time-style=full-iso $K/.config $K/include/generated/autoconf.h \
      $K/include/config/auto.conf $K/include/generated/utsrelease.h \
      $K/vmlinux $K/Module.symvers $K/System.map 2>&1
echo "== utsrelease =="
cat $K/include/generated/utsrelease.h 2>&1
echo "== localversion / git =="
git -C $K log -1 --format=%H%n%cd 2>&1
echo "-- dirty files --"
git -C $K status --short 2>&1 | head -30
echo "== other trees =="
for t in ${HOME}/work/mt6895-mainline ${HOME}/work/cac2c-bisect; do
  echo "--- $t"
  ls -l --time-style=full-iso $t/vmlinux $t/.config $t/include/generated/utsrelease.h 2>&1
  cat $t/include/generated/utsrelease.h 2>&1
done

echo "== device: config / BTF / kallsyms =="
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} '
echo "--- uptime"; uptime
echo "--- lsmod"; lsmod | head -20
echo "--- config sources"; ls -l /proc/config.gz /boot/config* /sys/kernel/btf/vmlinux 2>&1
echo "--- debugfs kmemleak/regmap"; ls /sys/kernel/debug 2>&1 | head -30
echo "--- spmi sysfs"; ls -l /sys/bus/spmi/devices/ 2>&1
echo "--- parent of an spmi dev"; cat /sys/bus/spmi/devices/0-04/uevent 2>&1
echo "--- controller dir"; ls -l /sys/bus/spmi/devices/spmi-0/ 2>&1
'
