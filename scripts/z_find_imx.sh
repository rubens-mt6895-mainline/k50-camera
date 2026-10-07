#!/bin/bash
# search local trees for IMX582 driver / sensor init tables
# look in WSL fp_work and Windows ${K50_REPO}
SEARCH_DIRS="${HOME}/fp_work ${HOME}/work"
echo "=== search imx582 in WSL ==="
grep -rl -i "imx582\|rubensimx582" $SEARCH_DIRS 2>/dev/null | head -20
echo "=== search imx586 (same family) ==="
grep -rl -i "imx586" $SEARCH_DIRS 2>/dev/null | head -20
echo "=== search imgsensor driver dirs ==="
find $SEARCH_DIRS -type d -iname "*imgsensor*" 2>/dev/null | head
find $SEARCH_DIRS -type d -iname "*imx5*" 2>/dev/null | head
