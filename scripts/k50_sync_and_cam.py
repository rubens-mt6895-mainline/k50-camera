#!/usr/bin/env python3
"""1) sync upstream's rubens.config (we are a strict subset -> take theirs)
   2) survey the current camera DT state in the worktree"""
import os, re, subprocess, urllib.request

UP = "MT6895-Mainline/linux"
BR = "port/rubens-clean"
WT = "${K50_REPO}/rubens-clean-wt"
OPENER = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": "http://127.0.0.1:7897",
                                 "https": "http://127.0.0.1:7897"}))

def raw(path):
    url = "https://raw.githubusercontent.com/%s/%s/%s" % (UP, BR, path)
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    return OPENER.open(req, timeout=90).read()

# --- 1. sync the config ---
cfg = raw("arch/arm64/configs/rubens.config")
dst = os.path.join(WT, "arch/arm64/configs/rubens.config")
old = open(dst, "rb").read()
open(dst, "wb").write(cfg)
print("rubens.config: %d -> %d bytes (upstream tip)" % (len(old), len(cfg)))
r = subprocess.run(["git", "-C", WT, "diff", "--stat", "--",
                    "arch/arm64/configs/rubens.config"],
                   capture_output=True, text=True)
print("  git diff --stat:", r.stdout.strip() or "(no change vs HEAD)")
print()

# --- 2. camera survey ---
DSI = "arch/arm64/boot/dts/mediatek/mt6895.dtsi"
txt = open(os.path.join(WT, DSI), "rb").read().decode("utf-8", "replace")
print("=== camera-related nodes in mt6895.dtsi ===")
for m in re.finditer(r"^\t+([a-z0-9_,.-]*(?:cam|CAM|mclk|sensor|imx|ov|s5k)[a-z0-9_,.-]*)\s*(?::[^;{]*)?\s*\{",
                     txt, re.M):
    print("   " + m.group(1))
print()
print("=== i2c_cam blocks (address / status / child nodes) ===")
for m in re.finditer(r"i2c_cam_[a-d]: i2c@([0-9a-f]+) \{(.*?)\n\t\t\};", txt, re.S):
    addr, body = m.group(1), m.group(2)
    kids = re.findall(r"^\t+([a-z0-9_,.-]+@[0-9a-f]+) \{", body, re.M)
    st = re.search(r'status = "(\w+)"', body)
    print("   i2c_cam @0x%s  status=%s  children=%s"
          % (addr, st.group(1) if st else "?", kids or "none"))
print()
print("=== any camera pinctrl / mclk / reset / regulator hooks ===")
for pat in ("cam_mclk", "cam_rst", "cam_ldo", "CAM_", "sc8551", "fan53870",
            "imx", "ov0", "regulator-cam"):
    hits = len(re.findall(pat, txt, re.I))
    print("   %-16s %d" % (pat, hits))
print()
print("=== is there a separate camera dtsi / dts in the worktree? ===")
r = subprocess.run(["bash", "-lc",
                    "ls ${K50_REPO}/rubens-clean-wt/arch/arm64/boot/dts/mediatek/ | grep -iE 'cam|imx|rubens'"],
                   capture_output=True, text=True)
print(r.stdout.strip() or "   (none)")
print("SYNC_CAM_DONE")