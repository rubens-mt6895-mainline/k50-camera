#!/bin/bash
# zz_v4l2_run.sh - push the V4L2-enabled cam_cap.ko + the test script, then run it.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
timeout 90 scp $OPTS ${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko "$H:/root/cam_cap.ko"
echo "scp ko rc=$?"
timeout 60 scp $OPTS ${K50_REPO}/scripts/zz_v4l2_test.sh "$H:/root/zz_v4l2_test.sh"
echo "scp sh rc=$?"
timeout 300 ssh $OPTS $H "sh /root/zz_v4l2_test.sh" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
mkdir -p ${K50_REPO}/frames
for f in v1 v2; do
	timeout 120 scp $OPTS "$H:/tmp/$f.yuyv" "${K50_REPO}/frames/v4l2_$f.yuyv" >/dev/null 2>&1
	echo "pulled v4l2_$f.yuyv rc=$?"
done
ls -l ${K50_REPO}/frames/v4l2_*.yuyv 2>&1
