#!/usr/bin/env python3
"""Sharpness of a YUYV frame, measured off-device.

    python sharpness.py <file.yuyv> <width> <height> [frame]

Reads the *last* frame of the file by default (the first frame after a lens move
may still be the old one) and prints

    mean |dY|   the driver's own focus metric, times 256 (Q8)
    lap var     variance of the 4-neighbour Laplacian of Y
    lap energy  mean |Laplacian|

so the numbers can be compared between lens positions without trusting the
driver's own metric.
"""
import sys
import numpy as np


def main():
    path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    frame = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    fsz = w * h * 2
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // fsz
    if n == 0:
        print("%s: no complete frame (%d bytes for %d)" % (path, len(data), fsz))
        return 1
    idx = n - 1 if frame == 0 else min(frame, n) - 1
    buf = np.frombuffer(data[idx * fsz:(idx + 1) * fsz], dtype=np.uint8)
    y = buf[0::2].reshape(h, w).astype(np.int16)

    dcol = np.abs(np.diff(y, axis=1)).mean()
    drow = np.abs(np.diff(y, axis=0)).mean()
    lap = (4 * y[1:-1, 1:-1] - y[:-2, 1:-1] - y[2:, 1:-1]
           - y[1:-1, :-2] - y[1:-1, 2:])
    print("%-22s frame %d/%d  Y mean %5.1f  |dY| col %5.2f row %5.2f"
          "  lap var %9.1f  lap |.| %5.2f"
          % (path.split("/")[-1], idx + 1, n, y.mean(), dcol, drow,
             lap.var(), np.abs(lap).mean()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
