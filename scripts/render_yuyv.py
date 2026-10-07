# render_yuyv.py - decode a /dev/video0 YUYV dump into PNGs.
#
# The driver already does the 12-bit decode, 2x2 binning, RGGB debayer, white
# balance, tone curve and the 180 degree flip, so this script is deliberately
# dumb: YUYV -> RGB (BT.601 full range) and save.  Run with the Windows Python
# (numpy + PIL), e.g.:
#   python scripts\render_yuyv.py frames\v4l2_v1.yuyv
#   python scripts\render_yuyv.py frames\mode_custom2.yuyv 960 540
#
# The output size defaults to the preview 2000x1500; every other capture mode
# halves its sensor mode, so pass that geometry as the second and third
# argument (zz_mode.sh prints the exact numbers).
import sys
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 2000, 1500
if len(sys.argv) >= 4:
    W, H = int(sys.argv[2]), int(sys.argv[3])
VW, VH = W // 2, H // 2


def main() -> int:
    path = Path(sys.argv[1])
    tag = path.stem
    raw = path.read_bytes()
    need = W * H * 2
    if len(raw) < need:
        print(f"{path}: only {len(raw)} bytes, need {need}")
        return 1
    a = np.frombuffer(raw[:need], dtype=np.uint8).reshape(H, W // 2, 4)

    y = np.empty((H, W), dtype=np.uint8)
    y[:, 0::2] = a[:, :, 0]
    y[:, 1::2] = a[:, :, 2]
    u = np.repeat(a[:, :, 1], 2, axis=1).astype(np.float32) - 128.0
    v = np.repeat(a[:, :, 3], 2, axis=1).astype(np.float32) - 128.0
    yf = y.astype(np.float32)

    # BT.601, full range (the driver declares V4L2_QUANTIZATION_FULL_RANGE)
    r = yf + 1.402 * v
    g = yf - 0.344136 * u - 0.714136 * v
    b = yf + 1.772 * u
    rgb = np.clip(np.stack([r, g, b], axis=-1), 0, 255).astype(np.uint8)

    out = path.with_name(f"{tag}_color.png")
    Image.fromarray(rgb, "RGB").save(out)

    view = np.asarray(Image.fromarray(rgb, "RGB").resize((VW, VH), Image.BILINEAR))
    vout = path.with_name(f"{tag}_view.png")
    Image.fromarray(view, "RGB").save(vout)

    lum = y.astype(np.float32)
    print(f"{path.name}: {len(raw)} bytes")
    print(f"  Y mean {lum.mean():7.2f}  min {lum.min():6.1f}  max {lum.max():6.1f}  "
          f"p1 {np.percentile(lum, 1):6.1f}  p99 {np.percentile(lum, 99):6.1f}")
    print(f"  U mean {a[:, :, 1].mean():7.2f}   V mean {a[:, :, 3].mean():7.2f}")
    print(f"  RGB means  R {rgb[..., 0].mean():6.1f}  G {rgb[..., 1].mean():6.1f}  "
          f"B {rgb[..., 2].mean():6.1f}")
    print(f"  wrote {out}")
    print(f"  wrote {vout}")

    # terminal brightness map: 24 columns x 12 rows of the luma plane
    hh, ww = H // 12, W // 24
    blocks = lum[: 12 * hh, : 24 * ww].reshape(12, hh, 24, ww).mean(axis=(1, 3))
    chars = " .:-=+*#%@"
    print("  luma map (0-255 -> ' .:-=+*#%@'):")
    for row in blocks:
        print("   " + "".join(chars[min(9, int(v * 10 / 256))] for v in row))
    return 0


if __name__ == "__main__":
    sys.exit(main())
