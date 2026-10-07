#!/bin/sh
# pwr_isp_main.sh - manual MTK SCPD power-on for isp_main (ctl 0xE24)
CTL=0x1c004e24
STA=0x1c001f34
STA2=0x1c001f38

# 1. PWR_ON + PWR_ON_2ND (already set, ensure)
busybox devmem $CTL 32 0xC0F41F1F
# 2. clear ISO (bit1)
v=$(busybox devmem $CTL 32)
busybox devmem $CTL 32 $((v & 0xFFFFFFFD))
# 3. clear SRAM_PDN (bit8), wait ACK (bit12) clear
v=$(busybox devmem $CTL 32)
busybox devmem $CTL 32 $((v & 0xFFFFFEFF))
i=0
while [ $i -lt 100 ]; do
  v=$(busybox devmem $CTL 32)
  ack=$(( (v & 0x1000) >> 12 ))
  [ $ack -eq 0 ] && break
  i=$((i+1))
done
echo "sram-ack-wait=$i"
# 4. clear CLK_DIS (bit4)
v=$(busybox devmem $CTL 32)
busybox devmem $CTL 32 $((v & 0xFFFFFFEF))
# 5. set RST_B (bit0)
v=$(busybox devmem $CTL 32)
busybox devmem $CTL 32 $((v | 0x1))
echo "final ctl:"
busybox devmem $CTL 32
