#!/bin/bash
# z_lookup596.sh - where are the imx596 tables, and what do they set for exposure?
cd ${K50_REPO} || exit 1
echo "--- out/sensors ---"
ls out/sensors/ 2>&1 | head
echo "--- tables on device ---"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} && chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} \
  'ls /root/*.txt; echo "=== exposure regs in imx596 tables ==="; grep -iE "0x0200|0x0202|0x0204|0x020e|0x0100" /root/imx596_init.txt /root/imx596_2592x1952.txt'
