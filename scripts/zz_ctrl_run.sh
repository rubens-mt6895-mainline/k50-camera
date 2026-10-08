#!/bin/bash
# zz_ctrl_run.sh <device-script> - push cam_cap.ko + the script, then run it.
# usage: bash zz_ctrl_run.sh zz_ctrl1.sh [extra args...]
S=${1:-zz_ctrl1.sh}
shift
ARGS=$*
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
KO=${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko
echo "=== ko ==="
ls -l "$KO"
timeout 120 scp $OPTS "$KO" "$H:/root/cam_cap.ko" >/dev/null 2>&1
echo "scp ko rc=$?"
# Runtime DT overlays built by z_build_ovl6.sh (one .ko per attempt; a module
# with no exit function cannot be rmmod'ed, so a retry gets a new name).
# Only pushed when they exist, so the helper stays harmless before the build.
for OVL in ${K50_REPO}/out/mod_ovl6/*.ko; do
	[ -f "$OVL" ] || continue
	b=$(basename "$OVL")
	timeout 60 scp $OPTS "$OVL" "$H:/root/$b" >/dev/null 2>&1
	echo "scp $b rc=$?"
done
sed -i 's/\r$//' "${K50_REPO}/scripts/$S"
timeout 60 scp $OPTS "${K50_REPO}/scripts/$S" "$H:/root/$S" >/dev/null 2>&1
echo "scp $S rc=$?"
# The sensor bring-up lives in python + shell helpers; push them too so a local
# edit to the mode table (e.g. VTS) actually reaches the device.
for f in imx582_bring.py port2_rx71.py csirx_bring.py sensor_bring.py zz_v80.sh zz_cam_up.sh zz_mode.sh zz_full.sh zz_full2.sh zz_framecmp.py zz_vts1.sh zz_vtscan.sh zz_ylines.sh zz_who.sh zz_af_up.sh zz_af_sweep.sh zz_af_auto.sh zz_af_check.sh zz_af_wobble.sh zz_af_rate.sh zz_shutdown.sh zz_offlog.sh zz_sfmt.sh zz_sfmt_perf.sh zz_restore.sh zz_modechk.sh zz_sw_test.sh zz_c3.sh zz_b60.sh zz_ct4.sh zz_accept.sh zz_front_cap.sh zz_macro_cap.sh zz_macro_grab.sh zz_ct3.sh zz_sync.sh zz_slot.sh zz_rates.sh zz_uw2.sh zz_af_fix.sh zz_afnow.sh zz_afdiag.sh zz_afsharp.sh zz_field.sh zz_cheese_test.sh zz_devmon.sh cam_boot.sh cam_reset.sh; do
	if [ -f "${K50_REPO}/scripts/$f" ]; then
		sed -i 's/\r$//' "${K50_REPO}/scripts/$f"
		timeout 60 scp $OPTS "${K50_REPO}/scripts/$f" "$H:/root/$f" >/dev/null 2>&1
		echo "scp $f rc=$?"
	fi
done
# Vendor sensor mode tables (one file per IMX582 mode, see gen_mode_table.py);
# imx582_bring.py loads /root/mode_<name>.txt when IMX582_MODE is set.
for f in ${K50_REPO}/out/modes/mode_*.txt; do
	[ -f "$f" ] || continue
	b=$(basename "$f")
	timeout 60 scp $OPTS "$f" "$H:/root/$b" >/dev/null 2>&1
	echo "scp $b rc=$?"
done
# Sensor tables extracted from the upstream drivers by gen_sensor_tables.py;
# pushed as <sensor>_<table>.txt (e.g. imx596_init.txt).
for d in ${K50_REPO}/out/sensors/*/; do
	[ -d "$d" ] || continue
	s=$(basename "$d")
	for f in "$d"*.txt; do
		[ -f "$f" ] || continue
		b="${s}_$(basename "$f")"
		timeout 60 scp $OPTS "$f" "$H:/root/$b" >/dev/null 2>&1
		echo "scp $b rc=$?"
	done
done
echo "=== run $S $ARGS ==="
timeout 900 ssh $OPTS $H "sh /root/$S $ARGS" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
