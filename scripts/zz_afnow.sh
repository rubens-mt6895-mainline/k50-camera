#!/bin/sh
# Read-only: what is the loaded cam_cap doing about focus right now?
P=/sys/module/cam_cap/parameters
echo "=== module params (AF/AE/mode) ==="
for k in af_enable af_auto af_pos af_min af_max af_step vcm_enable vcm_addr \
         ae_enable awb_enable conv_threads pipe_slots sync_parallel v4l2_bin \
         exp_hsize exp_vsize out_width out_height route_intf dphy_base i2c_bus i2c_addr; do
  [ -e "$P/$k" ] && printf '%-12s %s\n' "$k" "$(cat "$P/$k")"
done
echo "=== /proc/camcap_info (af/avg/timing/stats lines) ==="
sed -n -e '/^af *:/p' -e '/^avg *:/p' -e '/^timing *:/p' -e '/^stats *:/p' \
       -e '/^mode *:/p' -e '/^v4l2 *:/p' -e '/^route *:/p' /proc/camcap_info
echo "=== dmesg: recent cam_af / vcm / mode lines ==="
dmesg | grep -E 'cam_cap: (cam_af|af|vcm|mode|rx)' | tail -20
echo "=== holders of /dev/video0 ==="
fuser -v /dev/video0 2>&1 | head -6
echo "=== processes ==="
ps -eo pid,stat,etime,args | grep -E 'cheese|guvcview|v4l2-ctl|cam_cap' | grep -v grep
echo "=== health ==="
grep -cE 'Oops|BUG:|panic|watchdog' /var/log/dmesg 2>/dev/null || dmesg | grep -cE 'Oops|BUG:|panic|watchdog'
uptime; free -m | head -2
