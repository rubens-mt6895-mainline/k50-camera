#!/usr/bin/env python3
"""Parse the Android 'super' (liblp) layout of a raw super.img and extract partitions.

No external tools needed. Set SUPER to the image to read. Usage:
    SUPER=/path/to/super.img python3 lp.py table        # print the partition table
    python3 lp.py extract vendor odm                    # dd named partitions into OUTDIR
    python3 lp.py list vendor                           # debugfs-listing root of a partition
    python3 lp.py cat vendor /lib64/x.so /tmp/x.so
"""
import os, struct, subprocess, sys

SUPER = os.environ.get("SUPER", "")
OUTDIR = os.environ.get("OUTDIR", "${K50_REPO}/out/re/parts")
GEOM_MAGIC = 0x616C4467
HDR_MAGIC = 0x414C5030
RESERVED = 4096
GEOM_SIZE = 4096


def read_at(f, off, size):
    f.seek(off)
    return f.read(size)


class Extent:
    __slots__ = ("num_sectors", "target_type", "target_data", "target_source")


def parse(verbose=False):
    with open(SUPER, "rb") as f:
        geom = read_at(f, RESERVED, 52)
        magic, struct_size, _cksum, meta_max, slot_count, lb_size = struct.unpack("<II32sIII", geom[:52])
        assert magic == GEOM_MAGIC, "bad geometry magic %#x" % magic
        # Empirical layout of this image: reserved(4096) | geometry(4096) | geometry backup(4096)
        # | metadata slots (metadata_max_size each). Locate the first metadata header.
        hdr_off = None
        probe = read_at(f, 0, 4096 + 3 * 4096 + 4096)
        for cand in range(RESERVED + 2 * GEOM_SIZE, len(probe) - 4, 4):
            if probe[cand:cand + 4] == struct.pack("<I", HDR_MAGIC):
                hdr_off = cand
                break
        assert hdr_off is not None, "no metadata header found"
        if verbose:
            print("metadata header at %#x, metadata_max_size=%d, slots=%d, lb=%d" % (
                hdr_off, meta_max, slot_count, lb_size))
        hdr = read_at(f, hdr_off, 256)
        hmagic, major, minor, hsize = struct.unpack("<IHHI", hdr[:12])
        assert hmagic == HDR_MAGIC, "bad header magic %#x" % hmagic
        (tables_size,) = struct.unpack("<I", hdr[44:48])
        desc_parts = struct.unpack("<III", hdr[80:92])
        desc_exts = struct.unpack("<III", hdr[92:104])
        tables = read_at(f, hdr_off + hsize, tables_size)

        def table(offset, num, esize):
            return [tables[offset + i * esize: offset + (i + 1) * esize] for i in range(num)]

        parts_raw = table(*desc_parts)
        exts_raw = table(*desc_exts)

        exts = []
        for e in exts_raw:
            x = Extent()
            x.num_sectors, x.target_type, x.target_data, x.target_source = struct.unpack("<QIQI", e[:24])
            exts.append(x)

    parts = []
    for p in parts_raw:
        name = p[:36].split(b"\0")[0].decode()
        attr, first, num, grp = struct.unpack("<IIII", p[36:52])
        parts.append((name, first, num))
    return parts, exts, dict(major=major, minor=minor, lb_size=lb_size)


def extents_of(first, num, exts):
    return [exts[first + i] for i in range(num)]


def cmd_table():
    parts, exts, info = parse()
    print("super: %s (%.2f GB), metadata v%d.%d, logical block %d" % (
        SUPER, os.path.getsize(SUPER) / 1e9, info["major"], info["minor"], info["lb_size"]))
    total = 0
    print("%-16s %10s %10s  %s" % ("name", "size", "sectors", "extents (start_sector+len)"))
    for name, first, num in parts:
        ex = extents_of(first, num, exts)
        secs = sum(x.num_sectors for x in ex)
        total += secs
        loc = " ".join("%d+%d" % (x.target_data, x.num_sectors) for x in ex[:4])
        if len(ex) > 4:
            loc += " (+%d more)" % (len(ex) - 4)
        print("%-16s %10d %10d  %s" % (name, secs * 512, secs, loc))
    print("total in partitions: %.2f GB" % (total * 512 / 1e9))


def extract(names):
    parts, exts, _ = parse()
    idx = {n: (f, c) for n, f, c in parts}
    os.makedirs(OUTDIR, exist_ok=True)
    with open(SUPER, "rb") as src:
        for n in names:
            if n not in idx:
                print("no such partition: %s" % n)
                continue
            first, num = idx[n]
            ex = extents_of(first, num, exts)
            path = os.path.join(OUTDIR, n + ".img")
            written = 0
            with open(path, "wb") as dst:
                for x in ex:
                    if x.target_type != 0:
                        dst.write(b"\0" * (x.num_sectors * 512))
                        written += x.num_sectors * 512
                        continue
                    src.seek(x.target_data * 512)
                    left = x.num_sectors * 512
                    while left:
                        chunk = src.read(min(left, 1 << 24))
                        if not chunk:
                            break
                        dst.write(chunk)
                        left -= len(chunk)
                        written += len(chunk)
                    print("  %s: +%.1f MB (total %.1f MB)" % (n, x.num_sectors * 512 / 1e6, written / 1e6))
            print("%s -> %s (%.1f MB)" % (n, path, written / 1e6))


def debugfs(name, cmd):
    img = os.path.join(OUTDIR, name + ".img")
    if not os.path.exists(img):
        print("extract %s first" % name)
        return 1
    return subprocess.call(["debugfs", "-R", cmd, img])


if __name__ == "__main__":
    if not SUPER:
        sys.exit("SUPER is not set: SUPER=/path/to/super.img python3 lp.py table")
    what = sys.argv[1] if len(sys.argv) > 1 else "table"
    if what == "table":
        cmd_table()
    elif what == "extract":
        extract(sys.argv[2:])
    elif what == "list":
        rc = debugfs(sys.argv[2], "ls -l /" + (sys.argv[3] if len(sys.argv) > 3 else ""))
        sys.exit(rc)
    elif what == "dump":
        rc = debugfs(sys.argv[2], "dump %s %s" % (sys.argv[3], sys.argv[4]))
        sys.exit(rc)
    else:
        print(__doc__)
