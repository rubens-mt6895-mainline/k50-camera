#!/bin/bash
# z_newko.sh - report the freshly built module and save the device's current one
cd ${K50_REPO} || exit 1
KO=out/camcap_0b8dd2e/cam_cap.ko
ls -l "$KO"
md5sum "$KO"
modinfo "$KO" 2>/dev/null | grep -E '^parm: *(af_|vcm_|v4l2_bin|v4l2_full_cache)' | head
echo "--- device: save the currently installed module as the A/B baseline"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} && chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} '
  ls -l /root/cam_cap.ko /root/cam_cap.ko.* 2>/dev/null
  cp -f /root/cam_cap.ko /root/cam_cap_v2.ko
  md5sum /root/cam_cap_v2.ko
  date; uptime
  grep -E "^af|^avg" /proc/camcap_info 2>/dev/null | head -3
'
