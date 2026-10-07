#!/bin/sh
# zz_cam_up.sh - 一条命令把 K50 的 V4L2 相机栈拉起来（重启后也能用）
#   V4L2 地基模块（/root/v4l2）+ cam_cap.ko v4l2_enable=1
# 用法: sh /root/zz_cam_up.sh
BASE=/root/v4l2
KO=/root/cam_cap.ko

mod_loaded() {
	# /proc/modules 里的名字把 '-' 写成 '_'
	tr '-' '_' < /proc/modules | grep -q "^$1 "
}

echo "=== 0. 抢占 /dev/video0 的应用（cheese 会持有模块引用，必须先停）==="
if pgrep -x cheese >/dev/null 2>&1; then
	echo "stopping cheese ..."
	pkill -x cheese
	sleep 2
fi
pgrep -x cheese >/dev/null 2>&1 && echo "WARN: cheese 仍在运行"

echo
echo "=== 1. V4L2 地基模块 ==="
for m in mc videodev videobuf2_common videobuf2_memops videobuf2_vmalloc \
	 videobuf2_dma_contig videobuf2_v4l2; do
	# 模块文件名可能是下划线（内核模块名）或连字符（kbuild 输出名），两种都试
	f="$BASE/$m.ko"
	[ -f "$f" ] || f="$BASE/$(echo "$m" | tr '_' '-').ko"
	if mod_loaded "$m"; then
		echo "  [ok] $m already loaded"
		continue
	fi
	if [ ! -f "$f" ]; then
		echo "  [!!] missing $f"
		exit 1
	fi
	insmod "$f" 2>&1 | sed "s/^/  [$m] /"
	mod_loaded "$m" && echo "  [ok] $m loaded" || { echo "  [!!] $m failed"; exit 1; }
done
grep -q ' video4linux' /proc/devices && echo "  [ok] /proc/devices: 81 video4linux"

echo
echo "=== 2. cam_cap (v4l2_enable=1) ==="
# CAM_CAP_PARAMS 追加/覆盖模块参数，用来切传感器模式的几何，例如：
#   CAM_CAP_PARAMS="exp_hsize=1920 exp_vsize=1080 out_width=960 out_height=540" sh /root/zz_cam_up.sh
if mod_loaded cam_cap; then
	if ! rmmod cam_cap 2>&1; then
		echo "  [!!] rmmod cam_cap 失败（多半有应用正打开 /dev/video0）"
		echo "       先停掉应用再试： pkill -x cheese"
		exit 1
	fi
	echo "  [ok] old cam_cap removed"
fi
echo "  extra params: ${CAM_CAP_PARAMS:-(none)}"
insmod "$KO" v4l2_enable=1 $CAM_CAP_PARAMS || { echo "  [!!] insmod 失败"; exit 1; }

echo
echo "=== 3. 等待 /dev/video0 ==="
i=0
while [ $i -lt 20 ]; do
	[ -c /dev/video0 ] && break
	i=$((i + 1))
	sleep 0.25
done
if [ -c /dev/video0 ]; then
	ls -l /dev/video0
	echo "  name: $(cat /sys/class/video4linux/video0/name 2>/dev/null)"
else
	echo "  [!!] /dev/video0 没出现"
fi

echo
echo "=== 4. 有效参数 ==="
for p in v4l2_enable out_width out_height frame_bytes single_mode \
	 exp_hsize exp_vsize v4l2_src_stride v4l2_bin v4l2_full_cache exp_max rb_swap \
	 conv_threads pipeline pak_mode pak_dbl dbl_data_bus route_pix_mode \
	 v4l2_black v4l2_gain_q8 wb_r_q8 wb_b_q8; do
	v=$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)
	echo "  $p = $v"
done

echo
echo "=== 5. dmesg (最后 12 行) ==="
dmesg | tail -12

echo
echo "=== 6. /proc/camcap_info ==="
grep -E 'frame_ready|arm_count|last_seq|last_result' /proc/camcap_info 2>/dev/null

if command -v v4l2-ctl >/dev/null 2>&1; then
	echo
	echo "=== 7. v4l2-ctl --list-devices ==="
	v4l2-ctl --list-devices 2>&1
fi
echo
echo "=== done. 起相机软件: sh /root/zz_cam_app.sh ==="
