#!/bin/bash
echo "=== search kernel trees with release files ==="
find ${HOME} -maxdepth 4 -name "kernel.release" -exec sh -c 'echo "$1 : $(cat "$1")"' _ {} \; 2>/dev/null | head -10
echo "=== search overlay.c ==="
find ${HOME} -maxdepth 5 -path "*drivers/of/overlay.c" 2>/dev/null | head -5
echo "=== search mt6895 trees ==="
ls -d ${HOME}/work/*/ 2>/dev/null
ls -d ${HOME}/*/ 2>/dev/null | head -20
