# clip_compare.py - quantify blown highlights before/after the gain fix.
import sys

import numpy as np

W, H = 2000, 1500


def stats(path: str) -> None:
    raw = open(path, "rb").read(W * H * 2)
    a = np.frombuffer(raw, dtype=np.uint8).reshape(H, W // 2, 4)
    y = np.empty((H, W), dtype=np.float32)
    y[:, 0::2] = a[:, :, 0]
    y[:, 1::2] = a[:, :, 2]
    u = np.repeat(a[:, :, 1], 2, axis=1).astype(np.float32) - 128.0
    v = np.repeat(a[:, :, 3], 2, axis=1).astype(np.float32) - 128.0
    r = np.clip(y + 1.402 * v, 0, 255)
    g = np.clip(y - 0.344136 * u - 0.714136 * v, 0, 255)
    b = np.clip(y + 1.772 * u, 0, 255)
    print(f"{path}")
    print(f"  Y  mean {y.mean():7.2f}  std {y.std():6.2f}  p1 {np.percentile(y,1):5.1f}  "
          f"p50 {np.percentile(y,50):5.1f}  p99 {np.percentile(y,99):5.1f}")
    print(f"  blown: Y>=250 {100.0*(y>=250).mean():5.2f}%   Y==255 {100.0*(y>=255).mean():5.2f}%"
          f"   RGB any==255 {100.0*((r>=255)|(g>=255)|(b>=255)).mean():5.2f}%")
    print(f"  RGB mean  R {r.mean():6.2f}  G {g.mean():6.2f}  B {b.mean():6.2f}")


for p in sys.argv[1:]:
    stats(p)
