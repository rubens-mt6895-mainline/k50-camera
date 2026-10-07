#!/bin/sh
# reproduce_build.sh [workdir] - build cam_cap.ko from a clean clone.
#
# Produces a module with the same srcversion and vermagic as the one shipped on
# the phone. See docs/REPRODUCIBLE_BUILD.md for what that does and does not
# guarantee.
#
# Needs: git, make, zcat, clang + ld.lld 18 (the phone's kernel was built with
# CONFIG_CC_IS_CLANG=y, LLVM=1), ~2 GB of disk for the kernel tree.
#
#   sh scripts/reproduce_build.sh /tmp/repro
#
# Environment overrides:
#   KERNEL_REPO  kernel clone URL      (default: rubens-mt6895-mainline/linux)
#   KERNEL_REF   kernel tag or commit  (default: k50-camera-base)
#   JOBS         make parallelism      (default: nproc)
set -eu

WORK=${1:-$(pwd)/.reproduce}
HERE=$(cd "$(dirname "$0")" && pwd)
KERNEL_REPO=${KERNEL_REPO:-https://github.com/rubens-mt6895-mainline/linux.git}
KERNEL_REF=${KERNEL_REF:-k50-camera-base}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}
SRC=${SRC:-$HERE/src}
OUT=${OUT:-$WORK/out}
TREE=$WORK/linux

echo "=== toolchain ==="
clang --version | head -1
make --version | head -1
echo "workdir     : $WORK"
echo "kernel repo : $KERNEL_REPO ($KERNEL_REF)"
echo "sources     : $SRC"

mkdir -p "$WORK"

if [ ! -d "$TREE/.git" ]; then
	echo "=== clone kernel tree ==="
	git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$TREE"
fi
cd "$TREE"
echo "kernel commit: $(git rev-parse HEAD)"
echo "kernel ref   : $(git describe --tags --always 2>/dev/null || true)"

# The phone's kernel was built from a dirty tree, so its release string ends in
# -dirty. setlocalversion only adds that for modified tracked files, and the
# module's vermagic has to carry the same string or insmod rejects it.
if [ -z "$(git status --porcelain)" ]; then
	echo "=== make the tree dirty (reproduce the phone's -dirty vermagic) ==="
	echo '# reproduce-build dirty marker' >> CREDITS
fi
git status --porcelain | head -3

echo "=== kernel config ==="
if [ ! -f .config ]; then
	zcat "$HERE/docs/k50_mainline_config.gz" > .config
fi
make ARCH=arm64 LLVM=1 olddefconfig
echo "release: $(make -s ARCH=arm64 LLVM=1 kernelrelease)"

echo "=== modules_prepare (a full kernel build is not needed) ==="
make ARCH=arm64 LLVM=1 -j"$JOBS" modules_prepare

echo "=== build the module ==="
cd "$HERE"
K="$TREE" SRC="$SRC" OUT="$OUT" sh scripts/z_build_camcap.sh

echo "=== result ==="
ls -l "$OUT/cam_cap.ko"
echo "srcversion: $(modinfo -F srcversion "$OUT/cam_cap.ko")"
echo "vermagic  : $(modinfo -F vermagic   "$OUT/cam_cap.ko")"
echo
echo "the shipped module reports"
echo "srcversion: 493F61FF760E440C2CC5AA7"
echo "vermagic  : 7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64"
