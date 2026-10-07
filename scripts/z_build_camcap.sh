#!/bin/bash
# z_build_camcap.sh - out-of-tree build of cam_cap.ko (MT6895 CAMSV1 single-frame capture).
# Modeled on z_build_ovl5.sh: same `make -C <tree> M=<dir> ... modules` invocation.
# Run from Windows with:
#   wsl -- bash -lc "sed -i 's/\r$//' ${K50_REPO}/scripts/z_build_camcap.sh; bash ${K50_REPO}/scripts/z_build_camcap.sh"
#
# Kernel tree selection:
#   default K=${HOME}/work/cac2c-bisect  (the tree z_build_ovl5.sh uses)
#   override: K=${KDIR} bash z_build_camcap.sh
#
# WHY THE OVERRIDE MATTERS:
#   ${HOME}/work/cac2c-bisect has NO Module.symvers, so modpost can resolve
#   nothing and produces ~37 "undefined!" warnings, and its vermagic is
#   7.2.0-gcac2c2fc0d2c.
#   ${KDIR} HAS Module.symvers (982 KB) and matches the
#   running phone kernel 7.2.0-g0b8dd2e87b3d-dirty.  Build the .ko you actually
#   insmod against that tree.

K=${K:-${HOME}/work/cac2c-bisect}
# The source tree was tidied into scripts/ + src/ (see m03079); cam_cap.c now
# lives in src/.  Keep SRC overridable for the odd one-off build.
SRC=${SRC:-${K50_REPO}/src}
OUT=${OUT:-${K50_REPO}/out/camcap}

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT" || exit 1

cp "$SRC/cam_cap.c" cam_cap.c || exit 1
# Generated sensor-mode tables (scripts/gen_modes_header.py); the driver
# includes it by name, so it has to sit next to cam_cap.c.
cp "$SRC/imx582_modes.h" imx582_modes.h || exit 1

cat > Makefile <<'EOF'
obj-m := cam_cap.o
# The converters are the frame-rate ceiling (see docs/V4L2_CAMERA.md 15.7): let
# clang optimise this one object harder than the kernel default -O2.
CFLAGS_cam_cap.o := -O3
EOF

echo "=== kernel tree ==="
echo "K=$K  (kernelversion $(make -s -C "$K" kernelversion 2>/dev/null))"
if [ -f "$K/Module.symvers" ]; then
	echo "Module.symvers: present ($(wc -l < "$K/Module.symvers") symbols)"
else
	echo "Module.symvers: MISSING -> modpost will warn about every symbol"
fi

# The kernel tree was built with clang 18 (CONFIG_CC_IS_CLANG=y), so build the
# module with clang as well via LLVM=1.  That matches the kernel exactly and
# avoids both "the compiler differs from the one used to build the kernel" and
# the unrecognized-clang-option diagnostics a gcc build emits.
# GCC is only a fallback when the LLVM toolchain is missing.
if command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
	MAKE_ARGS=(ARCH=arm64 LLVM=1)
	echo "using: $(clang --version | head -1)"
else
	MAKE_ARGS=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
	echo "using: $(aarch64-linux-gnu-gcc --version | head -1)  [LLVM toolchain not found]"
fi

echo "=== make ==="
make -C "$K" M="$OUT" "${MAKE_ARGS[@]}" KBUILD_MODPOST_WARN=1 modules
RC=$?
echo "=== make exit code: $RC ==="

if [ -f cam_cap.ko ]; then
	ls -l cam_cap.ko
	echo "=== modinfo ==="
	modinfo cam_cap.ko 2>/dev/null || echo "modinfo not installed"
	echo "=== modinfo (params) ==="
	modinfo -p cam_cap.ko 2>/dev/null
else
	echo "!!! cam_cap.ko not produced"
fi

exit $RC
