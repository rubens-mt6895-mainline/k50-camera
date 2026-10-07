#!/bin/bash
SCP="scp -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY}"
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SCP ${K50_REPO}/scripts/run_imx586_table.py root@${K50_HOST}:/root/run_imx586_table.py
$SSH '
mkdir -p /root/out
sh /root/cam_go.sh > /root/out/camgo_pre.log 2>&1
python3 /root/run_imx586_table.py
python3 /root/port1b_full.py' > ${K50_REPO}/out/imx586_test.log 2>&1
echo DONE
