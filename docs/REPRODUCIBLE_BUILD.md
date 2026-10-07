# Reproducible build

Can somebody clone this repository and build the same camera module that runs on
the phone? Yes, for the parts that matter: the rebuilt module reports the same
`srcversion` and the same `vermagic` as the shipped one, so it is the same code
and it loads on the phone. The `.ko` file is not byte-identical, see
[what differs](#what-differs).

`scripts/reproduce_build.sh` does all of this in one go.

## What the running module is

    srcversion: 493F61FF760E440C2CC5AA7
    vermagic:   7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64

`uname -r` on the phone is `7.2.0-g0b8dd2e87b3d-dirty`. The release string is
part of the module's vermagic, so the exact kernel revision and the dirty flag
both have to be reproduced, otherwise `insmod` refuses the module.

## Recipe

1. Kernel tree: `rubens-mt6895-mainline/linux`, tag `k50-camera-base`. That tag
   points at kernel commit `0b8dd2e87b3d` (Bluetooth: fill CONNAC local-commands
   table so LE scans see devices), which is the revision the phone runs. It sits
   on top of the branch that the in-tree driver is developed on, and it is not
   reachable from any branch, which is why it is published as a tag.

       git clone --depth 1 --branch k50-camera-base \
           https://github.com/rubens-mt6895-mainline/linux.git

2. Reproduce the dirty flag. The phone's tree was dirty when the kernel was
   built, and `setlocalversion` puts `-dirty` into the release string whenever a
   tracked file is modified. Append a line to any tracked file, `CREDITS` is as
   good as any:

       echo '# camera build marker' >> CREDITS

   A clean tree produces `7.2.0-g0b8dd2e87b3d` without `-dirty`, and the module
   then carries a vermagic the phone rejects.

3. Kernel configuration: `docs/k50_mainline_config.gz` in this repository is the
   `.config` the phone was built with.

       zcat docs/k50_mainline_config.gz > .config
       make ARCH=arm64 LLVM=1 olddefconfig

   Useful properties of that config: `# CONFIG_MODVERSIONS is not set` (no
   symbol CRCs) and `# CONFIG_MODULE_SIG is not set` (no module signing), so a
   module can be built without symbol versions and without the signing keys.

4. Prepare the tree for external modules. A full kernel build is not needed:

       make ARCH=arm64 LLVM=1 -j"$(nproc)" modules_prepare

5. Build the module with the script in this repository:

       K=<kernel tree> SRC=<this repo>/src OUT=<output dir> \
           sh scripts/z_build_camcap.sh

   `modpost` prints `Module.symvers is missing` and lists every undefined symbol
   of the module. That is expected for a tree that never linked `vmlinux`, and
   the module still links and loads.

6. Check the result:

       modinfo -F srcversion <output>/cam_cap.ko
       modinfo -F vermagic  <output>/cam_cap.ko

## Toolchain

The phone's kernel and module were compiled by clang (the config says
`CONFIG_CC_IS_CLANG=y`, `CONFIG_CC_VERSION_TEXT="Ubuntu clang version 18.1.3
(1ubuntu1)"`), and the module is built with `LLVM=1`, so `clang` and `ld.lld`
18.1.3 (the Ubuntu packages) are what reproduces it. Other clang releases will
build a working module, but the `srcversion` may differ because it hashes the
compiled code.

## What differs

* The `.ko` file is **not byte-identical**: `md5` differs. The bytes that differ
  are build-path dependent (the tree the module was built in is embedded in some
  sections). Everything that describes the code, `srcversion` and `vermagic`, is
  identical.
* A build from a tree without `Module.symvers` (step 4 only) links the module
  with the same undefined symbols as the shipped one, which is why the
  `srcversion` matches.
* `modpost` warnings about missing `Module.symvers` are expected; they do not
  affect the loaded module.

## Measured

A clean clone of `k50-camera-base`, the recipe above, clang 18.1.3, on a Debian
12 WSL2 machine:

    built module  : 915600 bytes, srcversion 493F61FF760E440C2CC5AA7
    shipped module: 909216 bytes, srcversion 493F61FF760E440C2CC5AA7
    vermagic      : identical, 7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64
