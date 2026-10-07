#!/bin/bash
echo "=== cam_pwr_mod Makefile + cmd ==="
cat ${HOME}/fp_work/cam_pwr_mod/Makefile 2>&1
grep -oE "make -C [^ ]+" ${HOME}/fp_work/cam_pwr_mod/.cam_genpd.ko.cmd 2>&1 | head -2
grep -oE "/home/[^ ]+|/mnt/[^ ]+" ${HOME}/fp_work/cam_pwr_mod/.cam_genpd.ko.cmd 2>&1 | grep -iE "linux|kernel|src" | head -4
echo "=== all cmd files listing ==="
ls ${HOME}/fp_work/cam_pwr_mod/ 2>&1 | head -30
echo "=== cam_genpd.c source ==="
ls ${HOME}/fp_work/cam_pwr_mod/*.c 2>&1
head -30 ${HOME}/fp_work/cam_pwr_mod/cam_genpd.c 2>&1
