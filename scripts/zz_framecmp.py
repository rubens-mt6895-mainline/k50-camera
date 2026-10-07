#!/usr/bin/env python3
"""Per-plane statistics for YUYV frame dumps, run ON the device (no numpy).

The full-size frames are 4-24 MB apiece and the USB gadget link is slow, so
measuring them where they already are beats pulling them.  YUYV is
Y0 Cb Y1 Cr: bytes 0 and 2 are luma, byte 1 is Cb, byte 3 is Cr.

  usage: python3 zz_framecmp.py <file> [file...]

Per file: size, mean/min/max of Y, U and V, plus the dark (Y<24) and clipped
(Y>240) luma fractions.  Two frames of the same scene differ only by sensor
noise, so the means are what has to match; a swapped chroma slot would trade U
and V, and a wrong Bayer parity would move the colour means by tens of codes.
With exactly two files of equal size it also reports how many 4 KiB chunks are
byte-identical.
"""

import os
import sys


def stats(name, path):
	with open(path, "rb") as fh:
		data = fh.read()
	y = data[0::2]
	u = data[1::4]
	v = data[3::4]
	my = sum(y) / len(y) if y else 0
	mu = sum(u) / len(u) if u else 0
	mv = sum(v) / len(v) if v else 0
	dark = sum(y.count(b) for b in range(24))
	clip = sum(y.count(b) for b in range(241, 256))
	print("%-30s %9d B  Y %6.2f (min %3d max %3d)  U %6.2f  V %6.2f  dark %4.1f%%  clip %4.1f%%"
	      % (name, len(data), my, min(y), max(y), mu, mv,
		 100.0 * dark / len(y), 100.0 * clip / len(y)))
	return data


def main():
	if len(sys.argv) < 2:
		print(__doc__)
		return
	frames = [(os.path.basename(p), stats(os.path.basename(p), p))
		  for p in sys.argv[1:]]
	if len(frames) == 2 and len(frames[0][1]) == len(frames[1][1]):
		a, b = frames[0][1], frames[1][1]
		chunks = (len(a) + 4095) // 4096
		same = sum(1 for i in range(0, len(a), 4096)
			   if a[i:i + 4096] == b[i:i + 4096])
		print("identical 4 KiB chunks: %d / %d" % (same, chunks))


if __name__ == "__main__":
	main()
