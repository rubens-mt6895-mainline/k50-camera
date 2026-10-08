#!/bin/sh
# local_pull_sharp.sh - keep only the last frame of each /root/sharp_<p>.yuyv on
# the device and pull those (6 MB each) into frames/sharp/ for measuring.
set -u
H=root@${K50_HOST}
K=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$K" && chmod 600 "$K"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $K $H"
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $K"

$SSH 'for p in 0 256 512 768 1023; do tail -c 6000000 /root/sharp_$p.yuyv > /root/last_$p.yuyv; done; ls -l /root/last_*.yuyv'

mkdir -p ${K50_REPO}/frames/sharp
for p in 0 256 512 768 1023; do
	$SCP "$H:/root/last_$p.yuyv" "${K50_REPO}/frames/sharp/last_$p.yuyv"
done
ls -l ${K50_REPO}/frames/sharp/
