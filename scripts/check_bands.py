# check_bands.py - does the parallel converter leave a seam at its row bands?
#
# The converter splits the output into equal row bands (4 threads -> 375 rows
# each).  A missing or duplicated band would show up as an abnormal jump in the
# row-mean luma profile exactly at a band boundary, so compare the jump at those
# rows against the distribution of all row-to-row jumps.
import sys

import numpy as np

W, H = 2000, 1500
BAND = 4


def row_mean(path: str) -> np.ndarray:
    raw = open(path, "rb").read(W * H * 2)
    a = np.frombuffer(raw, dtype=np.uint8).reshape(H, W // 2, 4)
    y = np.empty((H, W), dtype=np.float32)
    y[:, 0::2] = a[:, :, 0]
    y[:, 1::2] = a[:, :, 2]
    return y.mean(axis=1)


def main() -> int:
    for path in sys.argv[1:]:
        m = row_mean(path)
        d = np.abs(np.diff(m))
        print(f"{path}: row mean {m.min():.2f}..{m.max():.2f}, "
              f"row-step median {np.median(d):.3f}, p99 {np.percentile(d, 99):.3f}, "
              f"max {d.max():.3f}")
        seams = [H * i // BAND for i in range(1, BAND)]
        for s in seams:
            v = d[s - 1]
            pct = float((d < v).mean() * 100.0)
            flag = "  <-- OUTLIER" if v > np.percentile(d, 99.5) else ""
            print(f"   seam y={s:4d}: |dmean|={v:7.3f}  above {pct:5.1f}% of row steps{flag}")
        big = np.sort(d)[::-1][:5]
        print(f"   five largest row steps: {[round(float(x), 2) for x in big]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
