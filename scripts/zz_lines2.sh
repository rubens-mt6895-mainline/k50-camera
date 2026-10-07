#!/bin/sh
# zz_lines2.sh - who drops the second half?  read back CAMSV regs + measure line/frame rates
IF=/proc/camcap
rd() { busybox devmem $1 32; }

echo "=== cfg 1 0 4000 0 6000 5000 6000 5000"
echo "cfg 1 0 4000 0 6000 5000 6000 5000" > $IF 2>/dev/null
sleep 1
echo "--- CAMSV regs after cfg"
echo "MODULE_EN   $(rd 0x1a110040)"
echo "FMT_SEL     $(rd 0x1a110044)"
echo "INT_EN      $(rd 0x1a110048)"
echo "INT_STATUS  $(rd 0x1a11004c)"
echo "CLK_EN      $(rd 0x1a110060)"
echo "PAK         $(rd 0x1a11007c)"
echo "TG_SEN_MODE $(rd 0x1a110100)"
echo "TG_VF_CON   $(rd 0x1a110104)"
echo "GRAB_PXL    $(rd 0x1a110108)"
echo "GRAB_LIN    $(rd 0x1a11010c)"
echo "TG_PATH_CFG $(rd 0x1a110110)"
echo "IMGO_BASE   $(rd 0x1a110700)"
echo "IMGO_BASE_M $(rd 0x1a110704)"
echo "IMGO_XSIZE  $(rd 0x1a110710)"
echo "IMGO_YSIZE  $(rd 0x1a110714)"
echo "IMGO_STRIDE $(rd 0x1a110718)"
echo "IMGO_BASIC  $(rd 0x1a11071c)"
echo "FRAME_SEQ   $(rd 0x1a11075c)"
echo "DMA_SEL     $(rd 0x1a110014)"
echo
echo "=== arm"
echo arm > $IF 2>/dev/null
sleep 1
echo "TG_VF_CON   $(rd 0x1a110104)"
echo "MODULE_EN   $(rd 0x1a110040)"
echo "IMGO_XSIZE  $(rd 0x1a110710)"
echo "IMGO_YSIZE  $(rd 0x1a110714)"
echo "IMGO_STRIDE $(rd 0x1a110718)"
echo "INT_STATUS  $(rd 0x1a11004c)"
echo
echo "=== rates over 3 s (CSI2 packet counter + CAMSV frame seq)"
p1=$(rd 0x1a014adc)
s1=$(rd 0x1a11075c)
sleep 3
p2=$(rd 0x1a014adc)
s2=$(rd 0x1a11075c)
echo "pkt $p1 -> $p2"
echo "seq $s1 -> $s2"
echo
echo "=== SENINF / CSI2 misc"
echo "CSI2_IRQ_STATUS  $(rd 0x1a014ac8)"
echo "CSI2_S0_DI_CTRL  $(rd 0x1a014a20)"
echo "CSI2_CH0_CTRL    $(rd 0x1a014a00)"
echo "CSI2_EN          $(rd 0x1a014a04)"
echo "SENINF_CTRL      $(rd 0x1a010000)"
echo
echo "--- info"
grep -E "vf_on|int_status|last_seq|last_result|arm_count" /proc/camcap_info
echo "--- done"
