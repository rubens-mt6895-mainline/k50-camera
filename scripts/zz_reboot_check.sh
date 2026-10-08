#!/bin/sh
# zz_reboot_check.sh - reboot the phone and run the strict boot-path check.
# Closes the gap left by zz_bootpath.sh, which only re-ran cam_boot.sh by hand.
set -u
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
O="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
H=root@${K50_HOST}

echo "== pre-reboot state =="
timeout 20 ssh $O $H 'uptime; echo "boot_id $(cat /proc/sys/kernel/random/boot_id)"; md5sum /root/cam_cap.ko; echo "registered since boot: $(dmesg | grep -c "v4l2: registered")"' 2>&1 | grep -v Permanently

echo "== push the check script =="
timeout 25 scp $O ${K50_REPO}/out/re/zz_boot_check.sh "$H:/root/zz_boot_check.sh" 2>&1 | grep -v Permanently

echo "== issuing reboot =="
timeout 20 ssh $O $H '/sbin/reboot' 2>&1 | grep -v Permanently
sleep 15

echo "== waiting for ssh =="
i=0
while [ $i -lt 40 ]; do
	i=$((i + 1))
	out=$(timeout 12 ssh $O $H 'uptime' 2>/dev/null)
	if echo "$out" | grep -q 'up'; then
		echo "  back after $i attempts: $out"
		break
	fi
	sleep 8
done
if [ $i -ge 40 ]; then
	echo "STILL DOWN"
	exit 1
fi

echo "== waiting for the camera bring-up to settle =="
i=0
while [ $i -lt 32 ]; do
	i=$((i + 1))
	st=$(timeout 15 ssh $O $H 'systemctl is-active cam-camera.service' 2>/dev/null)
	vf=$(timeout 15 ssh $O $H 'grep -m1 "^vf_on" /proc/camcap_info 2>/dev/null' 2>/dev/null)
	echo "  t=$((i * 8))s service=$st $vf"
	if [ "$st" != "activating" ] && [ -n "$vf" ]; then
		break
	fi
	sleep 8
done
sleep 5

echo "== strict boot check =="
timeout 150 ssh $O $H 'sh /root/zz_boot_check.sh' 2>&1 | grep -v Permanently
echo "== zz_reboot_check done =="
