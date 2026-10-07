#!/bin/sh
cd ${KDIR} || exit 1
echo "== pmif_spmi_read_cmd =="
sed -n '340,470p' drivers/spmi/spmi-mtk-pmif.c
echo "== spmi_read_cmd core =="
grep -n "SPMI_CMD" drivers/spmi/spmi.c | head -30
echo "== build scripts present =="
ls -la ${K50_REPO}/scripts/z_build_*.sh 2>/dev/null
ls -la ${K50_REPO}/scripts/*.sh 2>/dev/null | tail -30
