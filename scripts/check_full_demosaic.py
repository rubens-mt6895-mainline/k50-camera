#!/usr/bin/env python3
"""Model equivalence check for the two full-size (v4l2_bin=1) converters.

cam_cap.c has two implementations of the same conversion:

  cam_v4l2_convert_full_ref()   per output pixel, decodes its neighbours again
                                through cam_bayer_px()  (reference, fallback)
  cam_v4l2_convert_full_fast()  expands each raw row once into u16 scratch rows
                                and rotates a three row window (default)

The tone tables (cam_lut_*) and the YUYV packing (cam_yuyv_pair) are shared, so
the only things that can differ are the six tap values fed to cam_yuyv_pair and
the accumulated statistics.  This script transcribes both kernels, runs them
over the same synthetic RAW10 frame, and compares exactly those.

The frame carries distinct per-CFA-class levels (so a parity swap shows up), an
asymmetric gradient (so a wrong neighbour shows up), a clipped band and a black
band (so clip/dark counters are exercised).  Band splits are compared too: the
fast path inits its window from `first`, so a band starting mid frame must give
the same taps as the single pass.

Usage: python scripts/check_full_demosaic.py [rw] [rh]
"""

import sys

BLACK = 248		# v4l2_black
CLIP = 4000		# CAMCAP_CLIP_LEVEL
ROW_STEP = 4		# CAMCAP_STATS_ROW_STEP


def make_samples(rw, rh):
	base = {0: 1200, 1: 900, 2: 910, 3: 700}	# R, Gr, Gb, B
	rows = []
	for y in range(rh):
		row = []
		for x in range(rw):
			cls = (0 if (x & 1) == 0 else 1) + (0 if (y & 1) == 0 else 2)
			v = base[cls] + ((x * 7 + y * 13) % 61) - 30
			if 4 <= y < 8:
				v = 4050		# clipped band
			if y >= rh - 6:
				v = 20			# black band
			row.append(max(0, min(4095, v)))
		rows.append(row)
	return rows


def pack_rows(rows, stride):
	"""12-bit samples -> MTK RAW10 bytes (2 px per 3 B), one line per row."""
	out = []
	for row in rows:
		buf = bytearray(stride)
		for i in range(0, len(row) - 1, 2):
			p0, p1 = row[i], row[i + 1]
			j = (i >> 1) * 3
			buf[j + 0] = p0 & 0xff
			buf[j + 1] = ((p0 >> 8) & 0x0f) | ((p1 & 0x0f) << 4)
			buf[j + 2] = (p1 >> 4) & 0xff
		out.append(bytes(buf))
	return out


def unpack_row(line, n):
	"""cam_unpack_row()"""
	out = [0] * n
	for i in range(0, n - 1, 2):
		j = (i >> 1) * 3
		b0, b1, b2 = line[j], line[j + 1], line[j + 2]
		out[i] = b0 | ((b1 & 0x0f) << 8)
		out[i + 1] = (b1 >> 4) | (b2 << 4)
	return out


def px_clamp(row, col, w):
	"""cam_px_clamp()"""
	if col < 0:
		col = 0
	elif col >= w:
		col = w - 1
	return row[col]


def bayer_px(samples, x, y, w):
	"""cam_bayer_px(): RGGB, (even,even) = R."""
	rh = len(samples)
	lm = samples[y - 1] if y else samples[0]
	l0 = samples[y]
	lp = samples[y + 1] if y + 1 < rh else samples[y]
	own = l0[x]
	xm, xp = x - 1, x + 1
	if not (x & 1):
		if not (y & 1):			# R
			r = own
			g = (px_clamp(l0, xm, w) + px_clamp(l0, xp, w) +
			     px_clamp(lm, x, w) + px_clamp(lp, x, w)) >> 2
			b = (px_clamp(lm, xm, w) + px_clamp(lm, xp, w) +
			     px_clamp(lp, xm, w) + px_clamp(lp, xp, w)) >> 2
		else:				# Gb
			g = own
			r = (px_clamp(lm, x, w) + px_clamp(lp, x, w)) >> 1
			b = (px_clamp(l0, xm, w) + px_clamp(l0, xp, w)) >> 1
	else:
		if not (y & 1):			# Gr
			g = own
			r = (px_clamp(l0, xm, w) + px_clamp(l0, xp, w)) >> 1
			b = (px_clamp(lm, x, w) + px_clamp(lp, x, w)) >> 1
		else:				# B
			b = own
			g = (px_clamp(l0, xm, w) + px_clamp(l0, xp, w) +
			     px_clamp(lm, x, w) + px_clamp(lp, x, w)) >> 2
			r = (px_clamp(lm, xm, w) + px_clamp(lm, xp, w) +
			     px_clamp(lp, xm, w) + px_clamp(lp, xp, w)) >> 2
	return r, g, b


def stats_add(st, y, r0, g0, g1, b1, rb_swap):
	"""the statistics block both paths carry, same counters"""
	sum_r, sum_g, sum_b, count, clip, dark, min_g, max_g = st
	if not (y & 1):				# even row: R, Gr
		gg = g1
		if rb_swap:
			sum_b += r0
		else:
			sum_r += r0
		sum_g += gg
		count += 1
	else:					# odd row: Gb, B
		gg = g0
		if rb_swap:
			sum_r += b1
		else:
			sum_b += b1
		sum_g += gg
	clip += (gg >= CLIP)
	dark += (gg <= BLACK)
	min_g = min(min_g, gg)
	max_g = max(max_g, gg)
	return (sum_r, sum_g, sum_b, count, clip, dark, min_g, max_g)


def ref_convert(samples, rw, rh, first, last, rb_swap):
	st = (0, 0, 0, 0, 0, 0, 0xffff, 0)
	taps = []
	for y in range(first, last):
		st_on = not ((y >> 1) & (ROW_STEP - 1))
		for x in range(0, rw - 1, 2):
			r0, g0, b0 = bayer_px(samples, x, y, rw)
			r1, g1, b1 = bayer_px(samples, x + 1, y, rw)
			taps.append((y, x, r0, g0, b0, r1, g1, b1))
			if st_on:
				st = stats_add(st, y, r0, g0, g1, b1, rb_swap)
	return taps, st


def fast_convert(packed, rw, rh, first, last, rb_swap):
	st = (0, 0, 0, 0, 0, 0, 0xffff, 0)
	taps = []
	lm = unpack_row(packed[first - 1 if first else 0], rw)
	l0 = unpack_row(packed[first], rw)
	lp = None
	for y in range(first, last):
		st_on = not ((y >> 1) & (ROW_STEP - 1))
		lp = unpack_row(packed[y + 1 if y + 1 < rh else y], rw)
		for x in range(0, rw - 1, 2):
			xm = x - 1 if x else 0
			xp = x + 1
			xpp = x + 2 if x + 2 < rw else rw - 1
			if not (y & 1):
				r0 = l0[x]
				g0 = (l0[xm] + l0[xp] + lm[x] + lp[x]) >> 2
				b0 = (lm[xm] + lm[xp] + lp[xm] + lp[xp]) >> 2
				g1 = l0[xp]
				r1 = (l0[x] + l0[xpp]) >> 1
				b1 = (lm[xp] + lp[xp]) >> 1
			else:
				g0 = l0[x]
				r0 = (lm[x] + lp[x]) >> 1
				b0 = (l0[xm] + l0[xp]) >> 1
				b1 = l0[xp]
				g1 = (l0[x] + l0[xpp] + lm[xp] + lp[xp]) >> 2
				r1 = (lm[x] + lm[xpp] + lp[x] + lp[xpp]) >> 2
			taps.append((y, x, r0, g0, b0, r1, g1, b1))
			if st_on:
				st = stats_add(st, y, r0, g0, g1, b1, rb_swap)
		lm, l0, lp = l0, lp, lm
	return taps, st


def merge(acc, st):
	"""acc-> counters after one more band: add the sums, and fold min/max only
	when that band measured anything (the C does it under `if (count)`)."""
	sr = acc[0] + st[0]
	sg = acc[1] + st[1]
	sb = acc[2] + st[2]
	cnt = acc[3] + st[3]
	clip = acc[4] + st[4]
	dark = acc[5] + st[5]
	mn, mx = acc[6], acc[7]
	if st[3]:
		mn = min(acc[6], st[6])
		mx = max(acc[7], st[7])
	return (sr, sg, sb, cnt, clip, dark, mn, mx)


def check(rw, rh, splits, rb_swap):
	samples = make_samples(rw, rh)
	stride = rw * 3 // 2
	packed = pack_rows(samples, stride)

	# decode(pack(v)) == v, i.e. the fast path really sees the same samples
	for y in range(rh):
		if unpack_row(packed[y], rw) != samples[y]:
			print("FAIL raw round trip at row %d" % y)
			return False

	ref_taps, ref_st = ref_convert(samples, rw, rh, 0, rh, rb_swap)
	fast_taps, fast_st = fast_convert(packed, rw, rh, 0, rh, rb_swap)

	if ref_taps != fast_taps:
		for a, b in zip(ref_taps, fast_taps):
			if a != b:
				print("FAIL tap mismatch (single band) y=%d x=%d" % (a[0], a[1]))
				print("     ref  %s" % (a,))
				print("     fast %s" % (b,))
				return False
	if ref_st != fast_st:
		print("FAIL stats mismatch (single band): ref %s fast %s" % (ref_st, fast_st))
		return False

	# band splits: same taps, and the merged counters must equal the single pass
	for first, last in splits:
		rt, rs = ref_convert(samples, rw, rh, first, last, rb_swap)
		ft, fs = fast_convert(packed, rw, rh, first, last, rb_swap)
		want = [t for t in ref_taps if first <= t[0] < last]
		if ft != want:
			for a, b in zip(want, ft):
				if a != b:
					print("FAIL tap mismatch band (%d,%d) y=%d x=%d" % (first, last, a[0], a[1]))
					print("     ref  %s" % (a,))
					print("     fast %s" % (b,))
					return False
		if rs != fs:
			print("FAIL stats mismatch band (%d,%d): ref %s fast %s" % (first, last, rs, fs))
			return False

	# the merged statistics of a true partition must equal the single pass
	part = [(0, rh)]
	step = max(1, rh // 4)
	part = [(b, min(b + step, rh)) for b in range(0, rh, step)]
	mr, mf = (0, 0, 0, 0, 0, 0, 0xffff, 0), (0, 0, 0, 0, 0, 0, 0xffff, 0)
	for first, last in part:
		_, rs = ref_convert(samples, rw, rh, first, last, rb_swap)
		_, fs = fast_convert(packed, rw, rh, first, last, rb_swap)
		mr = merge(mr, rs)
		mf = merge(mf, fs)
	if mr != ref_st or mf != fast_st:
		print("FAIL merged stats: ref %s/%s fast %s/%s" % (mr, ref_st, mf, fast_st))
		return False

	print("PASS %dx%d rb_swap=%d: %d taps, stats %s" %
	      (rw, rh, rb_swap, len(ref_taps), ref_st))
	return True


def main():
	rw = int(sys.argv[1]) if len(sys.argv) > 1 else 64
	rh = int(sys.argv[2]) if len(sys.argv) > 2 else 16
	ok = True
	for rb_swap in (0, 1):
		splits = [(0, rh), (0, 1), (0, rh // 2), (rh // 2, rh), (3, rh - 3)]
		splits = sorted(set((first, last) for first, last in splits
				    if 0 <= first < last <= rh))
		ok = check(rw, rh, splits, rb_swap) and ok
	sys.exit(0 if ok else 1)


if __name__ == "__main__":
	main()
