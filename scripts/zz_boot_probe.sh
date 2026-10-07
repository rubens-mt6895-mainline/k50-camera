#!/bin/sh
# Reboot the K50 (clear the oops'd module table), bring up the cam stack,
# then run the calibrated m6315 probe.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST}"

echo "== reboot =="
$H 'sync; /sbin/reboot' >/dev/null 2>&1
sleep 8
ok=0
for i in $(seq 1 45); do
  if $H 'uptime' >/dev/null 2>&1; then ok=1; echo "ssh back after ~$((i*8))s"; break; fi
  sleep 8
done
[ $ok = 1 ] || { echo "DEVICE DID NOT COME BACK"; exit 1; }
$H 'uptime; lsmod | head -5'

echo "== cam stack (cam_go_v6.sh) =="
$H 'sh /root/cam_go_v6.sh' 2>&1 | tail -22

echo "== m6315 act=0 =="
$H 'lsmod | grep -c m6315; dmesg -C; insmod /root/m6315.ko act=0; sleep 1; dmesg | grep -E "m6315:|Internal error|pc :|Call trace"' 2>&1

echo "== still alive =="
$H 'uptime'
