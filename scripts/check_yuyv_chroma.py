#!/usr/bin/env python3
"""Model check for the optimised chroma path in cam_yuyv_pair().

cam_yuyv_pair() used to compute Cb and Cr for both pixels of a YUYV pair and
average them afterwards, with a chroma saturation scale applied to each.  It now
averages the tone-mapped taps first and runs the colour matrix once per pair:

	u = ((ua * (a0+a1) - 85 * (g0+g1) + ub * (d0+d1)) >> 9) + 128

which is the same value because the matrix is linear, differing only in the
rounding of the individual shifts.  This script transcribes both versions and
compares them over the tone table that the driver actually uses (12-bit -> 8-bit,
black level, white balance and the square-root gamma), for both rb_swap settings
and for a neutral and a boosted saturation, reporting the worst chroma delta.

Luma must match exactly; chroma may differ by at most one LSB.

Usage: python scripts/check_yuyv_chroma.py
"""

import math
import sys

BLACK = 248		# v4l2_black
WB_R, WB_B = 320, 434	# wb_r_q8, wb_b_q8 (Q8)
GAMMA = 0.45		# the driver's tone curve


def lut(dark=False):
	"""One tone table: black level, white balance, gamma, 0..255."""
	curves = []
	for gain in (WB_R, 256, WB_B):
		t = []
		for v in range(4096):
			s = v - BLACK
			if s < 0:
				s = 0
			s = (s * gain) >> 8
			if s > 4095:
				s = 4095
			t.append(int(round(255.0 * (s / 4095.0) ** GAMMA)))
		curves.append(t)
	return curves


def clamp(v, lo=0, hi=255):
	return lo if v < lo else (hi if v > hi else v)


def old_pair(r0, g0, b0, r1, g1, b1, sat, luts, rb_swap, gtab):
	lem, loo = (luts[2], luts[0]) if rb_swap else (luts[0], luts[2])
	ya, yb = (29, 77) if rb_swap else (77, 29)
	ua, ub = (128, -43) if rb_swap else (-43, 128)
	va, vb = (-21, 128) if rb_swap else (128, -21)
	a0, d0, gg0 = lem[r0], loo[b0], gtab[g0]
	a1, d1, gg1 = lem[r1], loo[b1], gtab[g1]
	ly0 = (ya * a0 + 150 * gg0 + yb * d0) >> 8
	ly1 = (ya * a1 + 150 * gg1 + yb * d1) >> 8
	u0 = ((ua * a0 - 85 * gg0 + ub * d0) >> 8) + 128
	u1 = ((ua * a1 - 85 * gg1 + ub * d1) >> 8) + 128
	v0 = ((va * a0 - 107 * gg0 + vb * d0) >> 8) + 128
	v1 = ((va * a1 - 107 * gg1 + vb * d1) >> 8) + 128
	u0 = ((u0 - 128) * sat) // 128 + 128
	u1 = ((u1 - 128) * sat) // 128 + 128
	v0 = ((v0 - 128) * sat) // 128 + 128
	v1 = ((v1 - 128) * sat) // 128 + 128
	return (clamp(ly1), clamp((u0 + u1) >> 1), clamp(ly0), clamp((v0 + v1) >> 1))


def new_pair(r0, g0, b0, r1, g1, b1, sat, luts, rb_swap, gtab):
	lem, loo = (luts[2], luts[0]) if rb_swap else (luts[0], luts[2])
	ya, yb = (29, 77) if rb_swap else (77, 29)
	ua, ub = (128, -43) if rb_swap else (-43, 128)
	va, vb = (-21, 128) if rb_swap else (128, -21)
	a0, d0, gg0 = lem[r0], loo[b0], gtab[g0]
	a1, d1, gg1 = lem[r1], loo[b1], gtab[g1]
	ly0 = (ya * a0 + 150 * gg0 + yb * d0) >> 8
	ly1 = (ya * a1 + 150 * gg1 + yb * d1) >> 8
	ar, ag, ab = a0 + a1, gg0 + gg1, d0 + d1
	u = ((ua * ar - 85 * ag + ub * ab) >> 9) + 128
	v = ((va * ar - 107 * ag + vb * ab) >> 9) + 128
	if sat != 128:
		u = ((u - 128) * sat) // 128 + 128
		v = ((v - 128) * sat) // 128 + 128
	return (clamp(ly1), clamp(u), clamp(ly0), clamp(v))


def main():
	luts = lut()
	gtab = lut()[1]
	worst = 0
	worst_case = None
	tested = 0
	# sweep the interesting corners plus a coarse grid of the middle
	grid = [0, 1, 200, 247, 248, 249, 512, 1024, 2048, 3000, 4095]
	for r0 in grid:
		for g0 in (0, 900, 2048, 4095):
			for b0 in grid:
				for r1 in (0, 1200, 4095):
					for g1 in (0, 910, 4095):
						for b1 in (0, 700, 4095):
							for rb_swap in (0, 1):
								for sat in (128, 160, 100):
									o = old_pair(r0, g0, b0, r1, g1, b1, sat,
						     luts, rb_swap, gtab)
									n = new_pair(r0, g0, b0, r1, g1, b1, sat,
						     luts, rb_swap, gtab)
									tested += 1
									if o[0] != n[0] or o[2] != n[2]:
										print("FAIL luma differs: %s vs %s (case %s)" %
										      (o, n, (r0, g0, b0, r1, g1, b1, sat, rb_swap)))
										return 1
									d = max(abs(o[1] - n[1]), abs(o[3] - n[3]))
									if d > worst:
										worst = d
										worst_case = (r0, g0, b0, r1, g1, b1, sat, rb_swap)
	if worst > 1:
		print("FAIL chroma delta %d at %s" % (worst, worst_case))
		return 1
	print("PASS %d pairs, luma exact, worst chroma delta %d (case %s)" %
	      (tested, worst, worst_case))
	return 0


if __name__ == "__main__":
	sys.exit(main())
