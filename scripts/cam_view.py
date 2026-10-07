#!/usr/bin/env python3
# cam_view.py - IMX582 streaming visual viewer (K50)
# 全屏实时显示：帧计数/帧率/streaming 状态/CSI2 5 路接口统计
# 用法: python3 /root/cam_view.py    (Ctrl-C 退出)
import subprocess, time, sys

IF_BASE = 0x1A010000

def rd(reg16_hi, reg16_lo):
    try:
        r = subprocess.run(['i2ctransfer','-f','-y','10','w2@0x10',
                            '0x%02X'%reg16_hi,'0x%02X'%reg16_lo,'r1'],
                           capture_output=True, text=True, timeout=2)
        return int(r.stdout.strip(), 16) if r.stdout.strip().startswith('0x') else None
    except Exception:
        return None

def mmap32(addr):
    try:
        import mmap, struct, os
        f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        pg = addr & ~0xfff
        m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
        return struct.unpack_from('<I', m, addr & 0xfff)[0]
    except Exception:
        return 0

def main():
    # 检查是否终端
    is_tty = sys.stdout.isatty()
    try:
        if is_tty:
            import curses
            curses.setupterm()
            sys.stdout.write("\033[?1049h\033[2J\033[H")  # alt screen
    except Exception:
        is_tty = False

    prev = None
    prev_t = time.time()
    print("IMX582 CAM VIEW - Ctrl-C 退出\n")
    try:
        while True:
            fc = rd(0x00, 0x05)
            fh = rd(0x00, 0x06)
            st = rd(0x01, 0x00)
            now = time.time()
            fps = 0.0
            if prev is not None and fc is not None and prev != fc and now > prev_t:
                dt = now - prev_t
                if dt > 0:
                    diff = (fc - prev) & 0xFF
                    fps = diff / dt
            prev, prev_t = fc, now
            bar = ''
            if fc is not None:
                w = (fc % 40) + 1
                bar = '#' * w + '.' * (40 - w)

            stream = "STREAMING" if st == 0x01 else "standby"
            if st == 0x01:
                stream = "\033[32mSTREAMING\033[0m"
            elif st == 0x00:
                stream = "\033[33mstandby\033[0m"
            else:
                stream = "\033[31mUNKNOWN(0x%02X)\033[0m" % st

            lines = [
                "\033[H",
                "\033[36m╔══════════════════════════════════════════════════╗\033[0m",
                "\033[36m║\033[0m  IMX582 主摄 实时状态          %s  \033[36m║\033[0m" % time.strftime('%H:%M:%S'),
                "\033[36m╠══════════════════════════════════════════════════╣\033[0m",
                "\033[36m║\033[0m  streaming(0x0100): %s            \033[36m║\033[0m" % stream,
                "\033[36m║\033[0m  framecnt(0x0005): 0x%02X  帧率: %.1f fps       \033[36m║\033[0m" % (fc if fc is not None else 0, fps),
                "\033[36m║\033[0m  framecnt hi(0x06): 0x%02X                    \033[36m║\033[0m" % (fh if fh is not None else 0),
                "\033[36m║\033[0m  %s \033[36m║\033[0m" % bar,
                "\033[36m╠══════════════════════════════════════════════════╣\033[0m",
                "\033[36m║\033[0m  CSI2 接口统计 (0x1A010000+0xA00+0x1000*i)   \033[36m║\033[0m",
            ]
            for i in range(5):
                b = IF_BASE + 0xA00 + 0x1000 * i
                pkt = mmap32(b + 0xD4)
                cnt = mmap32(b + 0xDC)
                irq = mmap32(b + 0xC8)
                flag = ' ' if pkt or cnt else '·'
                lines.append("\033[36m║\033[0m  if%d %s pkt=0x%08X cnt=0x%08X irq=0x%08X   \033[36m║\033[0m" % (i, flag, pkt, cnt, irq))
            lines.append("\033[36m╚══════════════════════════════════════════════════╝\033[0m")
            sys.stdout.write('\n'.join(lines) + '\n')
            sys.stdout.flush()
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            if is_tty:
                sys.stdout.write("\033[?1049l")  # leave alt screen
        except Exception:
            pass
        print("\ndone")

if __name__ == '__main__':
    main()
