#!/bin/bash
python3 -c "
import mmap, os, struct, time

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
# SCPSYS base = 0x1c001000
SCPSYS = 0x1c001000
m = mmap.mmap(f, 0x2000, mmap.MAP_SHARED, SCPSYS)

def rd(off):
    return struct.unpack_from('<I', m, off)[0]
def wr(off, val):
    struct.pack_into('<I', m, off, val)

# CAM_MAIN: ctl_offs=0xE44, sram_pdn=BIT(8), sram_pdn_ack=BIT(12)
CTL = 0xE44
cur = rd(CTL)
print('CAM_MAIN CTL[0x%04x] = 0x%08x' % (CTL, cur))

# PWR_ON = BIT(14), PWR_ON_2ND = BIT(15) (MTK SCPD convention for 6s gen)
PWR_ON = (1 << 14)
PWR_ON_2ND = (1 << 15)
SRAM_PDN = (1 << 8)
SRAM_PDN_ACK = (1 << 12)

# Check if already powered (status bits 30-31)
# Try setting PWR_ON
wr(CTL, cur | PWR_ON)
time.sleep(0.01)
wr(CTL, rd(CTL) | PWR_ON_2ND)
time.sleep(0.05)
# Wait for status
for i in range(100):
    v = rd(CTL)
    # status might be in the same or different register
    if (v & PWR_ON) and (v & PWR_ON_2ND):
        break
    time.sleep(0.01)

# Clear SRAM PDN
v = rd(CTL)
wr(CTL, v & ~SRAM_PDN)
time.sleep(0.05)
v = rd(CTL)
print('CAM_MAIN CTL after power-on: 0x%08x' % v)
print('SRAM_PDN_ACK bit12 =', (v >> 12) & 1)

# Check bus protection: need INFRACFG_AO
# BUS_PROT: MT6895_TOP_AXI_PROT_EN_MMSYS2_CAM_MAIN
# INFRACFG_AO base = 0x10001000 (typical)
m.close()

# Try INFRACFG bus protection release
m2 = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, 0x10001000)
# From bp_table: IFR_TYPE,Sta=0x0C34,En=0x0C38,Clr=0x0C30,Mask=MT6895_TOP_AXI_PROT_EN_MMSYS2_CAM_MAIN
# Read STA first
sta = struct.unpack_from('<I', m2, 0x0C34)[0]
print('INFRACFG_AO STA[0x0C34] = 0x%08x' % sta)
# Set EN (0x0C38) to release protection
val = struct.unpack_from('<I', m2, 0x0C38)[0]
print('INFRACFG_AO EN[0x0C38] = 0x%08x (before)' % val)
m2.close()
os.close(f)
print('done')
" 2>&1
