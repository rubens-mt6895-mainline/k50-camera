#!/bin/sh
cd ${KDIR} || exit 1
echo "== every spmi_read_cmd mention =="
grep -n "spmi_read_cmd\|spmi_write_cmd" drivers/spmi/spmi.c
echo "== bodies =="
sed -n '95,150p' drivers/spmi/spmi.c
echo "== spmi_dev_type / spmi_ctrl_type names =="
grep -n "spmi_dev_type\|spmi_ctrl_type\|\.name.*spmi" drivers/spmi/spmi.c | head -20
sed -n '20,58p' drivers/spmi/spmi.c
