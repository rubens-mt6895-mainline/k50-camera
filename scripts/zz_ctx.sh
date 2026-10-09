#!/bin/sh
# What are the boot-time Call traces at t=22.9 s (not cam_cap)?
set -u
echo "=== dmesg 178-200 ==="
dmesg | sed -n '178,200p'
echo "=== dmesg 230,250 ==="
dmesg | sed -n '230,250p'
