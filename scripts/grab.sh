#!/bin/bash
# Copy the AF-relevant stock camera binaries into the workspace for offline analysis.
V=/mnt/rom/vendor_a
L=$V/lib64/mt6895
D=/mnt/rom/vendor_dlkm_a/lib/modules
O=${K50_REPO}/out/re/rom
mkdir -p $O/lib64 $O/modules $O/etc
for f in lib3a.af.so lib3a.af.core.so lib3a.af.assist.so lib3a.af.assist.utils.so \
         lib3a.af.assist.models1d.so lib3a.af.assist.models2d.so \
         lib3a.ae.so lib3a.ae.core.so lib3a.awb.core.so lib3a.stat.so \
         libcam.afmgr.so libcam.hal3a.lensdrv.so libcam.hal3a.oisdrv.so libcam.hal3a.afassitmgr.so \
         libcam.hal3a.so libcam.hal3a.ctrl.so libcam.hal3a.policy.so libcam.hal3a.utils.so \
         libcam.hal3a.v3.sensor.v4l2.so libcam.hal3a.v3.nvram.v4l2.so libcam.hal3a.v3.stt_v4l2.so \
         libcam.hal3a.v3.ai3a_v4l2.so libcam.hal3a.v3.ae.v4l2.so libcam.hal3a.v3.awb_v4l2.so \
         libcam.hal3a.cctsvr.v4l2.so libcam.3a_isp.utils.so libcam.halisp.TuningDataProvider.so ; do
    if [ -f "$L/$f" ]; then cp -L "$L/$f" "$O/lib64/$f" && printf '%-45s %8d\n' "$f" "$(stat -c%s "$L/$f")"; else echo "MISSING $f"; fi
done
for m in dw9800v.ko dw9800w.ko ak7375c.ko ak7377a.ko bu64253gwz.ko camera_af_media.ko camera_eeprom.ko; do
    [ -f "$D/$m" ] && cp -L "$D/$m" "$O/modules/$m" || echo "MISSING $m"
done
cp -L $V/etc/camera/xiaomi/*.json $O/etc/ 2>/dev/null
echo '=== copied ==='
du -sh $O; ls -1 $O/lib64 | wc -l; ls -1 $O/modules | wc -l
