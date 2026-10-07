#!/bin/sh
# Pull the rb_swap=1 / rb_swap=0 A/B frames from the K50 to frames/.
# Written as a file because inline `wsl -- bash -lc "... for f ... done"` gets
# mangled by PowerShell (syntax error: unexpected end of file).
KEY=/tmp/${K50_KEY}
HOST=root@${K50_HOST}
DST=${K50_REPO}/frames

cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY"
chmod 600 "$KEY"

SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes $HOST"

echo "=== device side ==="
$SSH 'ls -l /root/rb*.yuyv 2>&1; md5sum /root/rb*.yuyv 2>&1; uname -r; /sbin/lsmod | grep cam_cap'

echo "=== pull ==="
for f in rb1 rb0; do
	timeout 180 scp -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o ConnectTimeout=10 "$HOST:/root/$f.yuyv" "$DST/$f.yuyv" >/dev/null 2>&1
	echo "$f rc=$?"
done

echo "=== local ==="
ls -l "$DST"/rb1.yuyv "$DST"/rb0.yuyv 2>&1
md5sum "$DST"/rb1.yuyv "$DST"/rb0.yuyv 2>&1
