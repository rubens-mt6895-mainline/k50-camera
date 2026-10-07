#!/bin/sh
# cam_load.sh - load camera module stack (order matters!)
# cam_ovl: runtime DT overlay (power-domains on 8 camsys clk syscons)
# cam_genpd: attach + power-on + HOLD all 6 camera MTCMOS domains
# cam_rails: hold GPIO rails 158/149/20/159/164 + RST(155) pulse
# cam_clk2: topckgen camtg0-7/seninf-mux/camtm clocks
# cam_clk: enable ALL camsys CG gates via clk framework (needs provider!)
insmod /tmp/cam_ovl.ko
insmod /tmp/cam_genpd.ko
insmod /tmp/cam_rails.ko
insmod /tmp/cam_clk2.ko
insmod /tmp/cam_clk.ko
dmesg | grep -E "cam_genpd: [0-9]+/|camclk: .*held|cam_clk2: .*held"
