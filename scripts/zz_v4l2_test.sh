#!/bin/sh
# zz_v4l2_test.sh - load the V4L2-enabled cam_cap.ko and capture one YUYV frame
# through the standard /dev/videoN interface (vb2 READ path).
D=/root/v4l2

echo "=== pre: loaded stack ==="
grep -E '^(cam_cap|mc|videodev|videobuf2[-_][a-z0-9]+) ' /proc/modules

echo "=== ensure the v4l2 base stack is loaded ==="
for m in mc videodev videobuf2-common videobuf2-memops videobuf2-vmalloc videobuf2-dma-contig videobuf2-v4l2; do
	u=$(echo "$m" | tr '-' '_')
	if grep -q "^$u " /proc/modules; then
		echo "--- $m : already loaded"
		continue
	fi
	out=$(insmod $D/$m.ko 2>&1)
	echo "--- $m : insmod rc=$? $out"
done

echo "=== reload cam_cap with v4l2_enable=1 ==="
rmmod cam_cap 2>&1
if [ $? -ne 0 ]; then
	echo "ABORT: cam_cap will not unload"
	exit 1
fi
dmesg -c >/dev/null 2>&1
insmod /root/cam_cap.ko v4l2_enable=1
echo "insmod rc=$?"
sleep 1

echo "=== effective parameters ==="
for p in v4l2_enable out_width out_height dbl_data_bus pak_mode pak_dbl route_pix_mode single_mode frame_bytes; do
	printf '%-16s = %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>&1)"
done

echo "=== /dev/video* ==="
ls -l /dev/video* 2>&1
for v in /sys/class/video4linux/*; do
	[ -e "$v" ] && printf '%s -> name="%s"\n' "$v" "$(cat $v/name 2>/dev/null)"
done

echo "=== dmesg after insmod ==="
dmesg | tail -12

echo "=== capture #1 through /dev/video0 (READ) ==="
rm -f /tmp/v1.yuyv
timeout 25 head -c 6000000 /dev/video0 > /tmp/v1.yuyv 2>/tmp/v1.err
echo "head rc=$? (124 = timeout)"
cat /tmp/v1.err 2>/dev/null
ls -l /tmp/v1.yuyv
md5sum /tmp/v1.yuyv

echo "=== capture #2 (must differ: proves frames are live) ==="
rm -f /tmp/v2.yuyv
timeout 25 head -c 6000000 /dev/video0 > /tmp/v2.yuyv
echo "head rc=$?"
md5sum /tmp/v2.yuyv

echo "=== Y sample (first 32 bytes) ==="
od -An -tu1 -N 32 /tmp/v1.yuyv 2>/dev/null

echo "=== Y brightness histogram over the first MB (stride 2) ==="
dd if=/tmp/v1.yuyv bs=1000000 count=1 2>/dev/null | od -An -tu1 -v | awk '{for(i=1;i<=NF;i++){n++; if(n%2==1){h[int($i/32)]++}}} END{for(b=0;b<8;b++) printf "%3d-%3d: %d\n", b*32, b*32+31, h[b]+0}'

echo "=== camcap_info ==="
head -20 /proc/camcap_info

echo "=== dmesg tail ==="
dmesg | tail -15
echo "=== done ==="
