#!/bin/sh
cd ${KDIR} || exit 1
echo "== spmi.c EXPORT_SYMBOL =="
grep -n "EXPORT_SYMBOL" drivers/spmi/spmi.c
echo "== spmi.c of_reconfig / register_devices =="
grep -n "of_reconfig\|of_spmi_register\|spmi_device_alloc\|spmi_device_add\|of_platform" drivers/spmi/spmi.c
echo "== struct spmi_controller / ops head =="
sed -n '1,140p' include/linux/spmi.h
echo "== mt6315 of_match + ops =="
grep -n "of_match\|compatible\|struct regulator_ops\|\.enable\|\.disable\|\.is_enabled\|\.set_mode\|\.get_mode\|mt6315_set_mode\|mt6315_get_mode\|mt6315_set_voltage\|mt6315_get_voltage" drivers/regulator/mt6315-regulator.c
echo "== mt6315 register defines =="
grep -n "#define MT6315\|#define MT_BUCK\|MODESET\|_ELR\|_EN\b" drivers/regulator/mt6315-regulator.c
echo "== mfd mt6315/6319 core present? =="
ls drivers/mfd | grep -iE "6315|6319"
echo "== mt6319 strings in tree =="
grep -rn "mt6319" drivers/ include/ 2>/dev/null | head -20
