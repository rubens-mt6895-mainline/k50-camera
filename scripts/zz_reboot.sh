#!/bin/sh
# Reboot the K50 and wait until cam-camera.service has finished its bring-up.
# Rationale: after the alloc_contig_pages page fault the module is pinned by a
# task in D state (wchan vb2_fop_release) and rmmod/insmod is impossible; only
# a reboot clears it.  /sbin/reboot works, shutdown -h now did not recover.
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
O="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
H=root@${K50_HOST}

echo "== issuing reboot =="
timeout 20 ssh $O $H '/sbin/reboot' 2>&1 | grep -v Permanently
sleep 10

echo "== waiting for ssh =="
i=0
while [ $i -lt 40 ]; do
	i=$((i + 1))
	out=$(timeout 12 ssh $O $H 'uptime' 2>/dev/null)
	if echo "$out" | grep -q 'up'; then
		echo "up after $i attempts: $out"
		break
	fi
	sleep 10
done
if [ $i -ge 40 ]; then
	echo "STILL DOWN"
	exit 1
fi

echo "== waiting for cam-camera.service =="
i=0
while [ $i -lt 45 ]; do
	i=$((i + 1))
	st=$(timeout 15 ssh $O $H 'systemctl is-active cam-camera.service' 2>/dev/null)
	echo "  t=$((i * 10))s state=$st"
	if [ "$st" != "activating" ]; then
		break
	fi
	sleep 10
done

echo "== device state =="
timeout 30 ssh $O $H '
uptime
systemctl --no-pager -l status cam-camera.service 2>&1 | head -20
echo "--- dmesg camera ---"
dmesg | grep -E "cam_cap|cam_boot" | tail -40
echo "--- video0 ---"
ls -l /dev/video0 2>&1
'
