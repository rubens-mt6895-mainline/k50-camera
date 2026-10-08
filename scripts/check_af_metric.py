#!/usr/bin/env python3
"""Why the old focus metric went blind in a lit room, and what the new one does.

The 2x2 converter path used to feed the search

    c = clamp(((77*r + 150*g + 29*b) >> 8), 0, 255)

i.e. a linear grey-world luma of the raw taps.  The taps are 12 bit and the AE
keeps the frame at a normal level, so  (77r + 150g + 29b) >> 8  is essentially
the mean raw level: far above 255 for anything but a very dark frame.  Both
samples of every pair then clamp to the same 255, the sum of |dY| collapses to
0, the search reads the scene as flat and stops looking -- which is exactly the
"no text, will not focus" report.  The full-size path meanwhile used the LUT'd
(gamma) luma and did not have the bug, so behaviour also depended on the mode.

The new metric is a green tap through that same gamma table (WB never scales
green) and is reported relative to the frame level, in contrast per mille.

Run:  python scripts/check_af_metric.py
"""
import math

RAW_MAX = 4095
BLACK = 248


def gamma_lut(black, gain_q8=256, gamma=1.0):
    """Stand-in for the driver's cam_lut_g[]: raw -> 0..255 bytes."""
    lut = []
    for v in range(RAW_MAX + 1):
        x = (v - black) * gain_q8 / 256.0
        if x < 0:
            x = 0.0
        y = 255.0 * (x / (RAW_MAX - black)) ** (1.0 / gamma)
        lut.append(int(max(0, min(255, y))))
    return lut


def old_metric(level, texture, n=1000):
    """Linear grey-world luma on raw taps, clamped to a byte: the old code."""
    fv = fv_n = 0
    for i in range(n):
        t = texture if (i & 1) else -texture
        g = max(0, min(RAW_MAX, level + t))
        c = max(0, min(255, (77 * g + 150 * g + 29 * g) >> 8))
        if i:
            fv += abs(c - prev)
        prev = c
        fv_n += 1
    return fv * 256 / max(1, fv_n)


def new_metric(level, texture, lut, n=1000, min_level=6):
    """Gamma'd green, reported as |dY| per mille of the frame level."""
    fv = fv_y = fv_n = 0
    for i in range(n):
        t = texture if (i & 1) else -texture
        g = max(0, min(RAW_MAX, level + t))
        c = lut[g]
        if i:
            fv += abs(c - prev)
            fv_y += c + prev
        prev = c
        fv_n += 1
    if fv_y / (2 * fv_n) < min_level:      # black frame: noise is not contrast
        return 0.0
    return 1000.0 * fv / max(1, fv_y)


def main():
    lut = gamma_lut(BLACK)
    print(f"{'raw level':>10} {'texture':>8} {'old metric':>11} {'new (per-mille)':>16}")
    for level, texture in [(120, 20), (300, 40), (600, 80), (1200, 120),
                           (2400, 200), (3600, 250)]:
        print(f"{level:>10} {texture:>8} {old_metric(level, texture):>11.1f} "
              f"{new_metric(level, texture, lut):>16.1f}")
    print()
    print("old metric is |dY| in 1/256 byte units, to compare with af_floor=200:")
    print("  any scene above ~256 raw units reports 0.0, i.e. 'no contrast at all'.")


if __name__ == "__main__":
    main()
