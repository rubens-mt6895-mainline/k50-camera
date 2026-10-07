#!/bin/bash
echo "=== 1. MCLK verify ==="
grep -E "camtg_sel|camtg_ck|camtg2" /sys/kernel/debug/clk/clk_summary 2>/dev/null | head -6
echo "=== 2. Power rails ==="
/root/gpiotoolG 158 1
/root/gpiotoolG 149 1
/root/gpiotoolG 20 1
/root/gpiotoolG 159 1
/root/gpiotoolG 164 1
echo "=== 3. fan53870 LDO enable ==="
i2ctransfer -f -y 11 w2@0x35 0x03 0x60
i2ctransfer -f -y 11 w2@0x35 0x09 0xB3
i2ctransfer -f -y 11 w2@0x35 0x0A 0xB3
echo "=== 4. MCLK pinmux ==="
echo "GPIO152 func1" > /sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select 2>&1 && echo "mclk-mux OK"
echo "=== 5. RST pulse ==="
/root/gpiotoolG 155 0
sleep 0.05
/root/gpiotoolG 155 1
sleep 0.5
echo "=== 6. Sensor init (232 regs) ==="
sh /root/cam_init.sh 2>&1 | grep -c "Error" && echo "init had errors" || echo "init clean"
echo "=== 7. Streaming check ==="
S=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>/dev/null)
echo "0x0100 = $S (0x01 = streaming)"
echo "=== 8. Full bus scan ==="
i2cdetect -y -r 10 2>&1
echo "=== 9. SENINF probe via /dev/mem ==="
python3 -c "
import mmap, os, struct
try:
    f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
    m = mmap.mmap(f, 0x100, mmap.MAP_SHARED, 0x1a010000)
    for off in (0x000, 0x004, 0x100):
        v = struct.unpack_from('<I', m, off)[0]
        print('SENINF+0x%03x = 0x%08x' % (off, v))
    m.close(); os.close(f)
except Exception as e:
    print('SENINF mmap failed:', e)
" 2>&1
