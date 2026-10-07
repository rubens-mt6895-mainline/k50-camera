#!/bin/sh
# cam_cold.sh - full cold boot: unload all -> power off 3s -> power on -> mclk -> rst
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'for m in cam_clk3 cam_clk cam_clk2 cam_rails cam_genpd cam_ovl; do rmmod $m 2>/dev/null; done
sleep 3
# power off via direct GPIO (already module-free now)
python3 - <<PYEOF
import mmap, os, struct, time
f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
def rd(a):
    m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=a & ~0xfff)
    return struct.unpack_from("<I", m, a & 0xfff)[0]
def wr(a, v):
    m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=a & ~0xfff)
    struct.pack_into("<I", m, a & 0xfff, v)
B = 0x10005000
def gset(p, val):
    g = p//32; bit = p%32
    d = B + 0x10*g; w = B + 0x100 + 0x10*g
    dd = rd(d) | (1<<bit); ww = rd(w)
    ww = (ww | (1<<bit)) if val else (ww & ~(1<<bit))
    wr(d, dd); wr(w, ww)
for p in [20,149,158,159,164]: gset(p, 0)
gset(155, 0)
time.sleep(3)
for p in [20,149,158,159,164]: gset(p, 1)
print("power on done")
PYEOF
sleep 0.5
for m in cam_ovl cam_genpd cam_clk2 cam_clk cam_clk3 cam_rails; do insmod /root/$m.ko 2>&1 | head -1; sleep 0.5; done
sleep 0.5
E3=$(cat /sys/kernel/debug/clk/camtg3_ck/clk_enable_count 2>/dev/null); echo "camtg3 en=$E3"
# RST pulse after mclk stable
python3 - <<PYEOF
import mmap, os, struct, time
f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
def rd(a):
    m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=a & ~0xfff)
    return struct.unpack_from("<I", m, a & 0xfff)[0]
def wr(a, v):
    m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=a & ~0xfff)
    struct.pack_into("<I", m, a & 0xfff, v)
B = 0x10005000; p=155; g=p//32; bit=p%32
d = B + 0x10*g; w = B + 0x100 + 0x10*g
wr(d, rd(d) | (1<<bit)); wr(w, rd(w) & ~(1<<bit))
time.sleep(0.1)
wr(w, rd(w) | (1<<bit))
print("rst pulsed")
PYEOF
sleep 0.3
for i in 1 2 3; do echo -n "try$i: "; i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1; sleep 0.3; done
echo -n "id17: "; i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1' > ${K50_REPO}/out/cam_cold.log 2>/dev/null
echo DONE
