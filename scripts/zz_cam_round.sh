#!/bin/bash
# zz_cam_round.sh - 推 zz_cam_up.sh + zz_cam_app.sh 到设备，依次执行，最后复核
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
H=${K50_HOST}
S=${K50_REPO}/scripts

for s in zz_cam_up.sh zz_cam_app.sh; do
	sed -i 's/\r$//' "$S/$s"
	scp -q -i "$KEY" -o StrictHostKeyChecking=no "$S/$s" root@$H:/root/ || {
		echo "scp $s failed"
		exit 1
	}
	echo "scp $s rc=0"
done

echo
echo "################ zz_cam_up.sh ################"
ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H "nice -n 19 sh /root/zz_cam_up.sh" 2>&1

echo
echo "################ zz_cam_app.sh ################"
ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H "nice -n 19 timeout 90 sh /root/zz_cam_app.sh" 2>&1

echo
echo "################ final ################"
ssh -i "$KEY" -o StrictHostKeyChecking=no root@$H "pgrep -a cheese; uptime; grep -E 'arm_count|last_seq|frame_ready' /proc/camcap_info" 2>&1
