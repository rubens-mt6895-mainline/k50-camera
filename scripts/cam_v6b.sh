#!/bin/sh
# cam_v6b.sh - SENINF RX full config + FSM probe (busybox devmem, 2026-10-05)
# per memory 9.4e: DPHY_TOP_1=0x11C86000, ANA1B=0x11C85000, 口1
LOG=/root/cam_v6b.log
: > $LOG
echo "=== cam_v6b $(date) ===" >> $LOG

D=0x11C86000   # DPHY_TOP_1
A=0x11C85000   # ANA1B

echo "--- write RX cfg ---" >> $LOG
busybox devmem $D 32 0xF01       >> $LOG 2>&1   # LANE_EN (0x0)
busybox devmem $((D+0x8)) 32 0xF01   >> $LOG 2>&1  # HS_RX_EN_SW (0x8)
busybox devmem $((D+0x10)) 32 0x30103402 >> $LOG 2>&1  # CLOCK_LANE LD0
busybox devmem $((D+0x180)) 32 0x7  >> $LOG 2>&1  # DPHYV21_CTRL
busybox devmem $A 32 0x1          >> $LOG 2>&1   # ANA RX enable

echo "--- readback DPHY ---" >> $LOG
for off in 0x00 0x04 0x08 0x10 0x40 0x44 0x48 0x4C 0x180; do
  echo "DPHY+$off = $(busybox devmem $((D+off)) 32)" >> $LOG
done

echo "--- readback ANA1B ---" >> $LOG
for off in 0x00 0x04 0x08; do
  echo "ANA+$off = $(busybox devmem $((A+off)) 32)" >> $LOG
done

echo "--- FSM sample x3 (1s apart) ---" >> $LOG
for i in 1 2 3; do
  echo "-- t$i --" >> $LOG
  for off in 0x40 0x44 0x48 0x4C 0x80 0x84 0x88 0x8C 0x100 0x104 0x108 0x10C; do
    echo "DPHY+$off = $(busybox devmem $((D+off)) 32)" >> $LOG
  done
  sleep 1
done

echo "=== done ===" >> $LOG
