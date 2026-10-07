#!/bin/sh
# zz_cap2.sh - cam_cap.ko load (buffer fallback) + SENINF routing smoke test.
# NO 'arm' yet: this validates buffer allocation and the route, nothing else.
echo "=== cam_cap load + route smoke test ==="
date; uptime

rmmod cam_cap 2>/dev/null
sleep 0.2

insmod /root/cam_cap.ko dbl_data_bus=1
echo "insmod rc=$?"
lsmod | grep -E "cam_cap" | sed 's/^/  /'

echo "--- module params ---"
for p in /sys/module/cam_cap/parameters/*; do
  echo "  $(basename $p)=$(cat $p 2>&1)"
done

echo "--- sensor still streaming? CSI2_PACKET_CNT (0x1a014adc) x3 ---"
for i in 1 2 3; do
  echo "  PKT=$(busybox devmem 0x1a014adc 32)  IRQ=$(busybox devmem 0x1a014ac8 32)"
  sleep 0.3
done

echo "--- SENINF/CAM_MUX BEFORE ---"
echo "  TOP_MUX_CTRL_0 = $(busybox devmem 0x1a010010 32)"
echo "  mux1_ctrl_0    = $(busybox devmem 0x1a011d00 32)"
echo "  mux1_ctrl_1    = $(busybox devmem 0x1a011d04 32)"
echo "  mux1_opt       = $(busybox devmem 0x1a011d08 32)"
echo "  gcsr_ctrl      = $(busybox devmem 0x1a010300 32)"
echo "  cam_mux3_ctrl  = $(busybox devmem 0x1a010460 32)"
echo "  cam_mux3_opt   = $(busybox devmem 0x1a010464 32)"
echo "  cam_mux3_chk   = $(busybox devmem 0x1a010474 32)"

echo "--- cfg (static config only, no DMA) ---"
echo 'cfg 1 0 4000 0 3000 5000 3000 5000' > /proc/camcap
echo "  cfg rc=$?"

echo "--- route ---"
echo 'route' > /proc/camcap
echo "  route rc=$?"

echo "--- SENINF/CAM_MUX AFTER ---"
echo "  TOP_MUX_CTRL_0 = $(busybox devmem 0x1a010010 32)"
echo "  mux1_ctrl_0    = $(busybox devmem 0x1a011d00 32)"
echo "  mux1_ctrl_1    = $(busybox devmem 0x1a011d04 32)"
echo "  mux1_opt       = $(busybox devmem 0x1a011d08 32)"
echo "  gcsr_ctrl      = $(busybox devmem 0x1a010300 32)"
echo "  cam_mux3_ctrl  = $(busybox devmem 0x1a010460 32)"
echo "  cam_mux3_opt   = $(busybox devmem 0x1a010464 32)"
echo "  cam_mux3_irq   = $(busybox devmem 0x1a01046c 32)"
echo "  cam_mux3_chk   = $(busybox devmem 0x1a010474 32)"
echo "  cam_mux3_chkres= $(busybox devmem 0x1a010478 32)"
echo "  cam_mux3_errres= $(busybox devmem 0x1a01047c 32)"
echo "  CHK_RES again  = $(busybox devmem 0x1a010478 32)"
echo "  CSI2_S0_DI     = $(busybox devmem 0x1a014a20 32)"
echo "  CSI2_CH0_CTRL  = $(busybox devmem 0x1a014a60 32)"

echo "--- dmesg tail ---"
dmesg | tail -45

echo "--- /proc/camcap_info ---"
cat /proc/camcap_info 2>&1 | sed 's/^/  /'

echo "=== zz_cap2 done (module left loaded, not armed) ==="
