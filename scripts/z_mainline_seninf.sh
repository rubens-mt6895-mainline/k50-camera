#!/bin/bash
K=${HOME}/work/mt6895-mainline/linux
echo "=== seninf in mainline ==="
find $K -iname "*seninf*" -o -iname "*seninf*" -type f 2>/dev/null | head -20
echo "=== test model / tm_ in mainline seninf ==="
grep -rn -iE "test_model|TESTMDL|tm_size|TM_SIZE|testmdl" $K/drivers/media/platform/mediatek 2>/dev/null | head -15
echo "=== 0x600 in seninf sources ==="
grep -rn "0x600\|0x60c\|0x610\|0x618" $K/drivers/media/platform/mediatek 2>/dev/null | grep -i seninf | head -15
