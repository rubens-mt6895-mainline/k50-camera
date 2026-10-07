#!/bin/bash
W=${HOME}/fp_work/cam
echo "=== cci / cam i2c / sensor child nodes in vendor.dts ==="
grep -inE "cci|cammcu|i2c@|cam.*sensor|sensor@|0x1a$|0x10$|pwdn|rst|reset-gpio|mclk" $W/vendor.dts | grep -iE "cci|cammcu|sensor|pwdn|mclk|cam.*i2c|i2c.*cam" | head -40
echo
echo "=== context around cam_main_r1a (line 5220) ==="
sed -n '5215,5290p' $W/vendor.dts
