#!/usr/bin/env python3
"""Extract the camera wiring from the live vendor DTS: fan53870's bus+address,
and each sensor's bus/address/reset/mclk/rails."""
import os, re

F = "${K50_REPO}/out/orig_live.dts"
if not os.path.exists(F):
    raise SystemExit("missing " + F)
txt = open(F, "r", errors="replace").read()
lines = txt.splitlines()
print("vendor DTS: %d lines" % len(lines))

print("\n=== nodes whose compatible mentions a camera part ===")
pat = re.compile(r"compatible\s*=\s*\"[^\"]*(imx|imgsensor|fan53870|camera|ov[0-9]|s5k|hi8|sc[0-9]{3}|sony|onsemi)[^\"]*\"", re.I)
for i, l in enumerate(lines):
    if pat.search(l):
        # walk back to the enclosing node name
        name = ""
        for j in range(i, max(0, i - 25), -1):
            m = re.match(r"^\s*([a-z0-9_,.+-]+@[0-9a-f]+)\s*\{", lines[j])
            if m:
                name = m.group(1)
                break
        print("  line %-7d %-34s %s" % (i + 1, name, l.strip()[:70]))

print("\n=== fan53870 node and its parent i2c bus ===")
for i, l in enumerate(lines):
    if "fan53870" in l and "compatible" in l:
        print("  line %d: %s" % (i + 1, l.strip()))
        for j in range(i, max(0, i - 40), -1):
            if re.match(r"^\s*i2c@[0-9a-f]+\s*\{", lines[j]):
                print("     parent bus: %s (line %d)" % (lines[j].strip(), j + 1))
                break
        for j in range(i, min(len(lines), i + 30)):
            if re.match(r"^\s*reg\s*=", lines[j]):
                print("     %s" % lines[j].strip())
                break
        break

print("\n=== i2c buses in the vendor DTS (address + which sensors hang off them) ===")
for i, l in enumerate(lines):
    m = re.match(r"^\s*(i2c@[0-9a-f]+)\s*\{", l)
    if not m:
        continue
    bus = m.group(1)
    kids = []
    depth = 0
    for j in range(i, min(len(lines), i + 400)):
        depth += lines[j].count("{") - lines[j].count("}")
        if j > i:
            km = re.match(r"^\s*([a-z0-9_,.+-]+@[0-9a-f]+)\s*\{", lines[j])
            if km and depth <= 2:
                kids.append(km.group(1))
        if depth <= 0 and j > i:
            break
    if kids:
        print("  %-16s %s" % (bus, kids))
print("CAMEXTRACT_DONE")