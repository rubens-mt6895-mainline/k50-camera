#!/bin/sh
cd ${KDIR} || exit 1
echo "== spmi.c spmi_read_cmd / spmi_write_cmd =="
grep -n "static int spmi_read_cmd" -A 25 drivers/spmi/spmi.c
grep -n "static int spmi_write_cmd" -A 25 drivers/spmi/spmi.c
echo "== regmap-spmi.c read/write ops =="
grep -n "spmi_ext_register\|spmi_register\|regmap_spmi_ext\|regmap_spmi_base" drivers/base/regmap/regmap-spmi.c
echo "== spmi_ext_register_readl body =="
grep -n "spmi_ext_register_readl\|spmi_ext_register_writel\|spmi_ext_register_read\b\|spmi_ext_register_write\b" -A 6 drivers/spmi/spmi.c | sed -n '1,80p'
echo "== spmi_controller_alloc body =="
grep -n "int spmi_controller_alloc\|struct spmi_controller \*spmi_controller_alloc" -A 40 drivers/spmi/spmi.c | head -50
