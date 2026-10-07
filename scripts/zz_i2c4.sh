#!/bin/sh
# zz_i2c4.sh - apply the ovl_i2c4 DT overlay (adds the camera I2C4 controller at
# 0x11d03000), power the macro camera's rails/clock/reset, and check that the
# new bus answers the GC02M1 at 0x37 (id 0x02f0/e0).
echo "=== before ==="
ls /dev/i2c-* 2>/dev/null | tr '\n' ' '; echo
BEFORE=$(ls /dev/i2c-* 2>/dev/null | tr '\n' ' ')

echo "=== (re)insmod ovl_i2c4b ==="
if lsmod | grep -q '^ovl_i2c4b'; then
	rmmod ovl_i2c4b; echo "rmmod rc=$?"
fi
insmod /root/ovl_i2c4b.ko; echo "insmod rc=$?"
sleep 2
dmesg | grep -iE 'ovl_i2c4|11d03000' | tail -10

echo "=== DT node ==="
if [ -d /proc/device-tree/soc@0/i2c@11d03000 ]; then
	echo "DT node present"
else
	echo "DT node MISSING"
fi

AFTER=$(ls /dev/i2c-* 2>/dev/null | tr '\n' ' ')
echo "=== after: $AFTER"
NEW=""
for d in $AFTER; do
	case " $BEFORE " in
		*" $d "*) ;;
		*) NEW="$NEW $d" ;;
	esac
done
echo "new buses:$NEW"

echo "=== macro rails: fan53870 l5 (avdd) + l7 (dovdd) ==="
i2ctransfer -y -f 11 w1@0x35 0x03 r1
i2ctransfer -y -f 11 w2@0x35 0x08 0xb3 2>&1
i2ctransfer -y -f 11 w2@0x35 0x0a 0x36 2>&1
i2ctransfer -y -f 11 w2@0x35 0x03 0x50 2>&1
echo "--- read back l5 / l7 / enable ---"
i2ctransfer -y -f 11 w1@0x35 0x08 r1
i2ctransfer -y -f 11 w1@0x35 0x0a r1
i2ctransfer -y -f 11 w1@0x35 0x03 r1
/root/gpiotoolG 158 1 2>/dev/null; echo "vcam GPIO158 high rc=$?"
/root/gpiotoolG 144 1 2>/dev/null; echo "macro dovdd GPIO144 high rc=$?"

echo "=== macro mclk + i2c pads ==="
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
echo "GPIO151 func1" > $P/pinmux-select 2>/dev/null || echo "GPIO151 mux failed"
echo "GPIO137 func1" > $P/pinmux-select 2>/dev/null || echo "GPIO137 mux failed"
echo "GPIO138 func1" > $P/pinmux-select 2>/dev/null || echo "GPIO138 mux failed"
grep -E 'pin 151|pin 137|pin 138|pin 144|pin 154' $P/pinmux-pins 2>/dev/null

echo "=== macro reset (GPIO154, active low) ==="
/root/gpiotoolG 154 0 2>/dev/null; sleep 0.05
/root/gpiotoolG 154 1 2>/dev/null; sleep 0.05

echo "=== probe 0x37 on every bus ==="
for d in $AFTER; do
	b=${d#/dev/i2c-}
	id=$(timeout 5 i2ctransfer -y -f "$b" w1@0x37 0xf0 r1 2>/dev/null | head -1)
	if [ -n "$id" ]; then
		id2=$(timeout 5 i2ctransfer -y -f "$b" w1@0x37 0xf1 r1 2>/dev/null | head -1)
		echo "  $d @0x37: 0xf0=$id 0xf1=$id2"
	fi
done
echo "=== dmesg tail ==="
dmesg | grep -iE 'i2c|mtk-i2c|11d03000' | tail -8
echo "=== zz_i2c4 done ==="
