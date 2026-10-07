#!/bin/sh
# zz_sw_probe.sh [mode] - why does a driver-side mode switch yield no frames?
#
# The driver can pick a vendor mode and replay its table by itself now, the
# receiver is retimed for the new link rate, and still not a single packet
# arrives.  This walks the candidates apart in one session:
#
#   A  known-good preview bring-up
#   B  driver-side switch, power-on table replayed  -> frames?
#   C  receiver-only recovery (port2_rx71.py, sensor untouched)      -> frames?
#   D  sensor-only recovery (module out, imx582_bring.py for the same mode,
#      module back in: the driver never replays tables at load)       -> frames?
#   E  full userspace bring-up again (known good)
#   F  driver-side switch with mode_init_replay=0 (the vendor flow)   -> frames?
#   G  and back to preview with the same setting (round trip)
#
# Liveness is read from the driver's own CAMSV path ("arm" + /proc/camcap_info),
# never from a userspace streamer: a streamer that gets no frames loops in DQBUF
# and then the module cannot be unloaded without rebooting the phone.
set -u
M=${1:-custom2}
W=/dev/video0
P=/sys/module/cam_cap/parameters
PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=4 pipeline=1"

probe() {	# probe <label>
	echo arm > /proc/camcap 2>/dev/null
	sleep 2
	echo "  --- $1"
	grep -E '^(frame_ready|last_result|arm_count|last_seq|int_status)' \
		/proc/camcap_info 2>/dev/null | sed 's/^/        /'
	dmesg | grep -E 'cam_cap: (mode:|rx:|arm seq)' | tail -3 | sed 's/^/        /'
}

bringup() {	# full userspace bring-up: reset + receiver + sensor tables
	MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
		sh /root/zz_v80.sh 2>&1 | grep -E 'frame_ready|last_result|zz_v80 done'
	CAM_CAP_PARAMS="$PARAMS" sh /root/zz_cam_up.sh 2>&1 |
		grep -E 'mode: |frame_ready|arm_count|last_result|\[!!\]'
	sleep 1
}

free_cam() {
	pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; sleep 1; }
	fuser -k $W 2>/dev/null
	sleep 0.5
}

echo "=== A. known-good preview bring-up ==="
free_cam
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap || { echo "ABORT: cam_cap still in use"; exit 1; }
fi
bringup
probe "A known good (expect frame_ready 1)"
out=$(nice -n 10 timeout -k 3 15 v4l2-ctl -d $W --stream-mmap --stream-count=20 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1)
echo "  app path: ${out:-NO FRAMES}"
pkill -9 -x v4l2-ctl 2>/dev/null

echo
echo "=== B. driver-side switch to $M, power-on table replayed (current default) ==="
echo "mode $M 1" > /proc/camcap
sleep 1
probe "B after driver switch"

echo
echo "=== C. receiver-only: run port2_rx71.py, leave the sensor alone ==="
nice -n 19 python3 /root/port2_rx71.py 2>&1 | tail -3 | sed 's/^/  /'
sleep 1
probe "C after receiver re-programming only"

echo
echo "=== D. sensor-only: module out, userspace replays $M, module back in ==="
rmmod cam_cap 2>&1 | sed 's/^/  /'
IMX582_MODE=$M nice -n 19 python3 /root/imx582_bring.py 2>&1 | tail -4 | sed 's/^/  /'
insmod /root/cam_cap.ko v4l2_enable=1 $PARAMS 2>&1 | sed 's/^/  /'
sleep 1
probe "D after userspace replay of the same mode"

echo
echo "=== E. full userspace bring-up again (known good) ==="
free_cam
rmmod cam_cap 2>/dev/null
bringup
probe "E known good again (expect frame_ready 1)"

echo
echo "=== F. driver-side switch to $M with mode_init_replay=0 ==="
echo 0 > $P/mode_init_replay
dmesg -c >/dev/null
echo "mode $M 1" > /proc/camcap
sleep 1
probe "F switch without the power-on table"

echo
echo "=== G. back to preview 2000x1500 (bin 2), still no power-on table ==="
dmesg -c >/dev/null
echo "mode preview 2" > /proc/camcap
sleep 1
probe "G round trip to preview"

echo
echo "=== H. health ==="
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
echo "  mode_init_replay=$(cat $P/mode_init_replay) rx_rate=$(cat $P/rx_rate)"
fuser -v $W 2>&1 | sed 's/^/  /'
free -m | head -2
uptime
echo "### zz_sw_probe done"
