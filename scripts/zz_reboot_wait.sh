#!/bin/bash
# zz_reboot_wait.sh - reboot the phone, wait for it to come back, verify the module table is clean.
# Invoke: wsl -- bash -lc "bash ${K50_REPO}/scripts/zz_reboot_wait.sh"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2"
H=root@${K50_HOST}

echo "=== pre-reboot state ==="
timeout 30 ssh $OPTS $H "date; uptime; grep cam_cap /proc/modules; echo '---'"

echo "=== issuing reboot ==="
timeout 20 ssh $OPTS $H "nohup sh -c 'sleep 1; /sbin/reboot' >/dev/null 2>&1 &" 2>&1
echo "reboot command sent rc=$?"

echo "=== waiting for the device to go away ==="
for i in $(seq 1 12); do
	sleep 5
	if ! timeout 6 ssh $OPTS $H "true" >/dev/null 2>&1; then
		echo "  down after $((i*5))s"
		break
	fi
done

echo "=== waiting for the device to come back ==="
UP=0
for i in $(seq 1 45); do
	sleep 10
	if timeout 8 ssh $OPTS $H "true" >/dev/null 2>&1; then
		echo "  UP after $((i*10))s"
		UP=1
		break
	fi
	echo "  still down ($((i*10))s)"
done

if [ "$UP" = "1" ]; then
	echo "=== post-reboot state ==="
	timeout 40 ssh $OPTS $H "date; uptime; nproc; echo '--- modules ---'; lsmod; echo '--- cam_cap in /proc/modules (should be empty) ---'; grep cam_cap /proc/modules; echo '--- tooling ---'; ls /root/*.py /root/*.sh 2>/dev/null | head -40; echo '--- ko present ---'; ls -l /root/cam_cap.ko"
else
	echo "!!! DEVICE DID NOT COME BACK AFTER 450s - needs a physical power cycle"
fi
