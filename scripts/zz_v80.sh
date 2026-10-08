#!/bin/sh
# zz_v80.sh - serialized + niced full camera bring-up (post-reboot, 2026-10-06)
#
# Policy (after the 16:22 hang): ONE device-side task at a time, nice -n 19,
# NO background loops, short bounded sampling.  Never leave this detached.
#
# Correct values this time (HyperOS regulator_summary ground truth):
#   fan53870 LDO6 (0x09) = 0xbf  -> AFVDD  2.900 V  (old cam_go_v6 wrote 0x2c = 2.724 V)
#   fan53870 LDO7 (0x0a) = 0x36  -> DOVDD  1.804 V  (old cam_go_v6 wrote 0x18 = 1.564 V)
#   fan53870 ENABLE (0x03)= 0x60 -> only L6|L7    (old cam_go_v6 wrote 0x7f = all 7)
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
N="nice -n 19"

# Sensor mode.  IMX582_MODE=<name> replays the vendor table /root/mode_<name>.txt
# (generated on the PC by scripts/gen_mode_table.py from src/rubensimx582_Sensor.h);
# empty = the built-in preview list with VTS 3300.  MODE_W/MODE_H/MODE_STRIDE
# describe the frame that table puts on the wire, MODE_FRAME the buffer size.
export IMX582_MODE
MW=${MODE_W:-4000}
MH=${MODE_H:-3000}
MSTRIDE=${MODE_STRIDE:-6000}
MFRAME=${MODE_FRAME:-18874368}

echo "=== zz_v80: IMX582 + SENINF port2 full bring-up ==="
date; uptime

echo "--- 1. load camera module stack ---"
for m in cam_ovl cam_genpd cam_clk2 cam_clk cam_clk3 cam_rails; do
  if ! lsmod | grep -q "^$m "; then insmod /root/$m.ko 2>/dev/null; fi
  sleep 0.4
done
lsmod | grep -E "^cam_" | awk '{print "  "$1}'

echo "--- 2. camera rails high ---"
for pin in 149 20 159 158 164; do $G $pin 1 >/dev/null 2>&1; done
sleep 0.2
for pin in 149 20 159 158 164; do echo "  gpio$pin = $($G $pin get 2>/dev/null)"; done

echo "--- 3. MCLK pinmux GPIO152 -> CMMCLK2 func1 ---"
echo "GPIO152 func1" > $P 2>/dev/null
echo "  MODE152=$(busybox devmem 0x10005430 32 2>/dev/null)"
grep -E "camtg3_sel|camtg3_ck|cam_m_seninf_con" /sys/kernel/debug/clk/clk_summary 2>/dev/null | head -4 | sed 's/^/  /'

echo "--- 4. fan53870: LDO6(AFVDD)=0xbf  LDO7(DOVDD)=0x36  ENABLE=0x60 ---"
i2ctransfer -f -y 11 w2@0x35 0x09 0xbf 2>&1
i2ctransfer -f -y 11 w2@0x35 0x0a 0x36 2>&1
i2ctransfer -f -y 11 w2@0x35 0x03 0x60 2>&1
sleep 0.3
echo "  0x03=$(i2ctransfer -f -y 11 w1@0x35 0x03 r1 2>&1) 0x09=$(i2ctransfer -f -y 11 w1@0x35 0x09 r1 2>&1) 0x0a=$(i2ctransfer -f -y 11 w1@0x35 0x0a r1 2>&1)"
echo "  faults 0x16=$(i2ctransfer -f -y 11 w1@0x35 0x16 r1 2>&1) 0x18=$(i2ctransfer -f -y 11 w1@0x35 0x18 r1 2>&1) 0x1b=$(i2ctransfer -f -y 11 w1@0x35 0x1b r1 2>&1)"

echo "--- 5. reset pulse GPIO155 (low 50ms -> high) ---"
$G 155 0 >/dev/null 2>&1
sleep 0.05
$G 155 1 >/dev/null 2>&1
sleep 0.1

echo "--- 6. IMX582 id on i2c-10 @0x10 ---"
ID16=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1)
ID17=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1)
echo "  ID16=$ID16 ID17=$ID17"
if [ "$ID16" = "0x05" ] && [ "$ID17" = "0x82" ]; then echo "  IMX582 ALIVE"; else echo "  IMX582 DEAD"; fi

echo "--- 7. port2 DPHY/CSI2/SENINF/TOP config (port2_rx71.py, vendor-exact) ---"
$N python3 /root/port2_rx71.py 2>&1 | tail -25

echo "--- 8. IMX582 ${IMX582_MODE:-preview} init + mode table + 0x0100=0x01 (${MW}x${MH}) ---"
$N python3 /root/imx582_bring.py 2>&1 | tail -15

echo "--- 9. sensor readback ---"
for pair in "0x01 0x00:0x0100" "0x01 0x12:0x0112" "0x01 0x13:0x0113" "0x01 0x14:0x0114" "0x01 0x15:0x0115" "0x03 0x07:0x0307" "0x03 0x40:0x0340" "0x03 0x41:0x0341"; do
  a="${pair%%:*}"; r="${pair##*:}"
  echo "  $r = $(i2ctransfer -f -y 10 w2@0x10 $a r1 2>&1)"
done

echo "--- 10. CSI2 packet / IRQ sampling (8 x 0.5s) ---"
i=0
while [ $i -lt 8 ]; do
  printf "  [%d] PKT=%s IRQ=%s\n" $i "$(busybox devmem 0x1a014adc 32 2>&1)" "$(busybox devmem 0x1a014ac8 32 2>&1)"
  i=$((i+1))
  sleep 0.5
done

# --- 11. full-frame capture: 12-bit, 1.5 bytes/row per pixel, PAK_MODE=0x82 + DBL/PAK coupling ---
# (see docs/CAMERA_CAPTURE_WORKING.md; render locally with scripts/k50_shot.ps1)
echo "--- 11. CAMSV capture: complete 12-bit frame (${MW}x${MH}, ${MSTRIDE} B/row) ---"
# CAM_V80_NO_INSMOD=1: only do the sensor/receiver bring-up.  cam_boot.sh sets it
# so cam_cap is registered exactly once per boot, by zz_cam_up.sh.  Loading it
# here and again there makes udev/GStreamer see a device that was removed and
# re-added, which leaves duplicate "MT6895 CAMSV1 (IMX582)" rows in applications
# that keep a device monitor running (Cheese).
if [ -z "${CAM_V80_NO_INSMOD:-}" ]; then
  if ! lsmod | grep -q "^cam_cap "; then
    insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 \
        route_pix_mode=2 frame_bytes=$MFRAME
    echo "  insmod rc=$?"
  fi
else
  echo "  CAM_V80_NO_INSMOD set: leaving cam_cap to zz_cam_up.sh"
fi
echo route > /proc/camcap 2>/dev/null
touch /tmp/.cam_routed
i2ctransfer -f -y 10 w4@0x10 0x02 0x02 0x03 0x80 >/dev/null 2>&1   # exposure 0x0380 (~16 ms)
i2ctransfer -f -y 10 w4@0x10 0x02 0x04 0x03 0x00 >/dev/null 2>&1   # analog gain (highest effective)
i2ctransfer -f -y 10 w4@0x10 0x02 0x0e 0x04 0x00 >/dev/null 2>&1   # digital gain 0x0400 (recommended)
sleep 1
echo "cfg 1 0 $MW 0 $MH $MSTRIDE $MH $MSTRIDE" > /proc/camcap 2>/dev/null
echo arm > /proc/camcap 2>/dev/null
sleep 4
grep -E 'frame_ready|last_result|buffer_|mapping' /proc/camcap_info | sed 's/^/  /'
echo "  want: frame_ready 1 / last_result 0 / extent stops at 18,000,000 bytes"
echo "=== zz_v80 done ==="
