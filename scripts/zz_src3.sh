#!/bin/sh
cd ${KDIR} || exit 1
echo "== mt6315-regulator.h =="
cat include/linux/regulator/mt6315-regulator.h
echo "== spmi-mtk-pmif: drvdata / controller =="
grep -n "platform_set_drvdata\|dev_get_drvdata\|spmi_controller_alloc\|devm_spmi_controller_alloc\|spmi_controller_add\|read_cmd\|write_cmd" drivers/spmi/spmi-mtk-pmif.c | head -30
echo "== spmi.c device_alloc/device_add bodies =="
sed -n '55,100p' drivers/spmi/spmi.c
sed -n '405,435p' drivers/spmi/spmi.c
echo "== spmi.c of_spmi_register_devices =="
sed -n '478,560p' drivers/spmi/spmi.c
