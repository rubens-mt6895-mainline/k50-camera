#!/bin/sh
# zz_pos2.sh -- capture a new scene at three digital-gain settings.
IF=/proc/camcap; I2C="i2ctransfer -f -y 10"
w16() { $I2C w4@0x10 0x02 $(printf '0x%02x 0x%02x 0x%02x' $1 $(( $2 >> 8 )) $(( $2 & 0xff ))) >/dev/null 2>&1; }

echo "waiting 25s for repositioning..."
sleep 25

# make sure the module carries the known-good routing params
want_dbl=$(cat /sys/module/cam_cap/parameters/dbl_data_bus 2>/dev/null)
want_pk=$(cat /sys/module/cam_cap/parameters/pak_mode 2>/dev/null)
echo "module: dbl=$want_dbl pak=$want_pk fb=$(cat /sys/module/cam_cap/parameters/frame_bytes 2>/dev/null)"
if [ "$want_dbl" != "2" ] || [ "$want_pk" != "130" ]; then
    /sbin/rmmod cam_cap 2>/dev/null; sleep 1
    insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 \
        route_pix_mode=2 frame_bytes=18874368
    echo "insmod rc=$?  dbl=$(cat /sys/module/cam_cap/parameters/dbl_data_bus)"
fi
if [ ! -f /tmp/.cam_routed ]; then echo route > $IF; touch /tmp/.cam_routed; echo "routed"; fi

w16 0x02 0x0380      # exposure 896 lines (~16 ms, the mode's integration ceiling)
w16 0x04 0x0300      # analog gain -- 0x0300 is the highest effective code
for dg in 0400 0800 1000; do
    w16 0x0e 0x$dg
    sleep 1
    echo "cfg 1 0 4000 0 3000 6000 3000 6000" > $IF 2>/dev/null
    echo arm > $IF 2>/dev/null
    sleep 4
    f=/tmp/pos2_$dg.bin
    dd if=$IF of=$f bs=1M count=19 2>/dev/null
    m=$(dd if=$f bs=1024 count=64 skip=9216 2>/dev/null | od -An -tu1 | awk '{for(i=1;i<=NF;i++){s+=$i;n++}} END{if(n)printf "%.1f",s/n}')
    echo "dgain=0x$dg  $(grep -E 'frame_ready|last_result' /proc/camcap_info | tr -s ' ' | tr '\n' ' ') mid-mean=$m  md5=$(md5sum $f | cut -c1-32)"
done
echo "--- done ---"
