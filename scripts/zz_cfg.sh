#!/bin/sh
# Compare the RUNNING kernel's config with the build tree's config.
set -e
K=${KDIR}
OUT=${K50_REPO}/out
mkdir -p $OUT
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} 'zcat /proc/config.gz' > $OUT/device_config.txt
wc -l $OUT/device_config.txt $K/.config

echo "== diff summary =="
diff $OUT/device_config.txt $K/.config > $OUT/cfgdiff.txt || true
grep -c '^[<>]' $OUT/cfgdiff.txt || true
echo "-- first 60 differing lines --"
head -60 $OUT/cfgdiff.txt

echo "== struct-device-relevant options =="
for o in CONFIG_PM CONFIG_PM_SLEEP CONFIG_PM_SLEEP_SMP CONFIG_ACPI CONFIG_LOCKDEP \
         CONFIG_DEBUG_KMEMLEAK CONFIG_DPM_WATCHDOG CONFIG_PM_GENERIC_DOMAINS \
         CONFIG_PM_GENERIC_DOMAINS_OF CONFIG_ENERGY_MODEL CONFIG_NUMA CONFIG_SMP \
         CONFIG_HOTPLUG_CPU CONFIG_DEBUG_OBJECTS CONFIG_REGMAP CONFIG_REGMAP_SPMI \
         CONFIG_SPMI CONFIG_MFD_MTK_SPMI_PMIC CONFIG_REGULATOR_MT6315 \
         CONFIG_REGULATOR_MT6363 CONFIG_DEBUG_INFO_BTF CONFIG_CC_IS_CLANG CONFIG_CC_VERSION_TEXT; do
  a=$(grep -m1 "^$o=" $OUT/device_config.txt || echo "MISSING: $o")
  b=$(grep -m1 "^$o=" $K/.config || echo "MISSING: $o")
  if [ "$a" != "$b" ]; then echo "DIFF  $o"; echo "      device: $a"; echo "      tree  : $b";
  else echo "same  $a"; fi
done
