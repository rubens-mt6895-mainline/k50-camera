#!/bin/bash
# zz_pull.sh <remote-path> [local-path]  -- pull a file from the K50 to ${K50_REPO}
set -u
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" && chmod 600 "$KEY"
R="${1:?remote path required}"
L="${2:-${K50_REPO}/logs/$(basename "$R")}"
scp -q -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@${K50_HOST}:$R" "$L"
echo "pulled $R -> $L ($(stat -c %s "$L") bytes)"
