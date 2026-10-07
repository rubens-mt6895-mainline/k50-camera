#!/bin/bash
# z_build_ovl6.sh - build ovl_i2c4.ko, the runtime DT overlay that adds the
# camera I2C4 controller (0x11d03000) to the live device tree.
#
# The blob is embedded with .incbin instead of "ld -r -b binary" because the
# kernel is built with LLVM and lld has no "-b binary"; the absolute path in
# .incbin keeps the assembler's working directory irrelevant.
#
# The blob must start on an 8-byte boundary: the kernel's fdt_check_header()
# rejects the overlay with "Invalid overlay_fdt header" (fdt_check_header()
# returns -FDT_ERR_ALIGNMENT) otherwise.
#
# MOD selects the module name.  A module whose init only applies an overlay and
# has no exit function cannot be rmmod'ed, so a follow-up attempt needs a new
# name (MOD=ovl_i2c4b ...).
set -u
K=${K:-${KDIR}}
SRC=${SRC:-${K50_REPO}}
OUT=${OUT:-${K50_REPO}/out/mod_ovl6}
MOD=${MOD:-ovl_i2c4}
OBJ=${OBJ:-$MOD}

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT" || exit 1

# No -@: the live tree has no /__symbols__, and an overlay carrying a
# __symbols__ node is rejected with "symbols in overlay, but not in live tree"
# (-EINVAL).  Phandles are therefore written as raw numbers in the .dts.
dtc -q -I dts -O dtb "$SRC/dt/ovl_i2c4.dts" -o ovl_i2c4.dtb || exit 1
cp "$SRC/src/ovl_i2c4.c" ovl_i2c4_main.c || exit 1

cat > ovl_blob.S <<EOF
	.section .rodata
	.balign 8
	.global ovl_i2c4_blob_start
ovl_i2c4_blob_start:
	.incbin "$OUT/ovl_i2c4.dtb"
	.global ovl_i2c4_blob_end
ovl_i2c4_blob_end:
EOF

cat > Makefile <<EOF
obj-m := $MOD.o
$MOD-objs := ovl_i2c4_main.o ovl_blob.o
EOF

make -C "$K" M="$OUT" ARCH=arm64 LLVM=1 KBUILD_MODPOST_WARN=1 modules 2>&1 | tail -6
ls -l "$MOD.ko" 2>/dev/null
modinfo "$MOD.ko" 2>/dev/null | grep -E 'vermagic|name|description'
echo "=== blob dtb ==="
ls -l ovl_i2c4.dtb
echo "=== blob alignment (first byte offset in .rodata must be 8-byte aligned) ==="
aarch64-linux-gnu-nm "$MOD.ko" 2>/dev/null | grep blob
