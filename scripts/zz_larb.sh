#!/bin/sh
# zz_larb.sh - inspect (and optionally clear) the SMI larb MMU_EN bits.
# SMI_LARB_NONSEC_CON(id) = larb_base + 0x380 + id*4, bit0 = F_MMU_EN
# larb bases: 0=14021000 1=14022000 2=1f002000 3=1f802000 4=1602e000 8=17810000 20=14421000 21=14422000
echo "=== zz_larb: SMI_LARB_NONSEC_CON[0..31] bit0 (MMU_EN) ==="
date; uptime
for entry in "0:14021000" "1:14022000" "2:1f002000" "3:1f802000" "4:1602e000" "8:17810000" "20:14421000" "21:14422000"; do
	id="${entry%%:*}"; base="${entry##*:}"
	printf "larb%-2s @%s: " "$id" "$base"
	i=0
	while [ $i -lt 32 ]; do
		addr=$((0x$base + 0x380 + i*4))
		v=$(busybox devmem $(printf 0x%08x $addr) 32 2>/dev/null)
		if [ -n "$v" ] && [ $((0x$(echo $v | sed 's/^0x//') & 1)) -ne 0 ]; then
			printf "p%d=%s " "$i" "$v"
		fi
		i=$((i+1))
	done
	echo
done
echo "=== cam_cap state ==="
grep cam_cap /proc/modules
cat /proc/camcap_info 2>/dev/null | grep -E 'vf_on|frame_ready|last_result|mapping'
echo "=== last iommu faults ==="
dmesg | grep -c "mtk-iommu-mt6895"
dmesg | grep "mtk-iommu-mt6895" | tail -4
echo "=== zz_larb done ==="
