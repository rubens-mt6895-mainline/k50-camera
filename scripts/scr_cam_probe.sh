#!/bin/bash
KEY=$HOME/.ssh/${K50_KEY}
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=15"
ssh $OPTS root@${K50_HOST} '
echo "=== /dev/video* ==="
ls -l /dev/video* 2>&1
echo
echo "=== media devices ==="
ls -l /dev/media* 2>&1
echo
echo "=== v4l2 / media-ctl available? ==="
which v4l2-ctl media-ctl 2>&1
echo
echo "=== camera-related kernel modules / builtin ==="
zcat /proc/config.gz 2>/dev/null | grep -iE "CONFIG_VIDEO_(V4L2|FOTOFIX|CCS|IMX|OV|GC|S5K|MT9M|ROCKCHIP_ISP|MEDIA_CONTROLLER|VIDEOBUF2)" | head -40
echo
echo "=== dmesg: sensor / cci / cam / isp / ov / imx / gc ==="
dmesg 2>/dev/null | grep -iE "camera|sensor|cci|cam|isp|csi|imx|ov[0-9]|gc[0-9]|s5k|mclk|csid|rdma|seninf" | tail -40
'
