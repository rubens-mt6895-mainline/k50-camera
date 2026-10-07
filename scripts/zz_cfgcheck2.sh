#!/bin/bash
K=${KDIR}
echo "=== device kernel config: media / v4l2 ==="
zcat ${K50_REPO}/docs/k50_mainline_config.gz | grep -E '^CONFIG_(MEDIA_SUPPORT|MEDIA_CONTROLLER|VIDEO_DEV|VIDEO_V4L2|VIDEO_V4L2_SUBDEV_API|VIDEOBUF2_CORE|VIDEOBUF2_V4L2|VIDEOBUF2_MMAP|VIDEOBUF2_DMA_CONTIG|VIDEOBUF2_DMA_SG|VIDEOBUF2_VMALLOC|V4L2_FWNODE|V4L2_ASYNC|DMA_SHARED_BUFFER|VIDEO_CAMERA_SENSOR|VIDEO_MEDIATEK|VIDEO_MTK|DRM)' | sort
echo
echo "=== disabled media bits ==="
zcat ${K50_REPO}/docs/k50_mainline_config.gz | grep -E '^# CONFIG_(MEDIA|VIDEO|V4L2)[A-Z0-9_]* is not set' | head -20
echo
echo "=== MTK media platform drivers in tree ==="
ls $K/drivers/media/platform/mediatek/ 2>&1
echo
echo "=== imx5xx sensor drivers in tree ==="
ls $K/drivers/media/i2c/ 2>/dev/null | grep -iE 'imx5|imx2|ov' | head -12
echo
echo "=== videodev / videobuf2 objects built? ==="
ls $K/drivers/media/v4l2-core/*.o 2>/dev/null | head -12
echo
echo "=== does the tree have a camsys/seninf/smi media driver? ==="
ls $K/drivers/media/platform/ 2>/dev/null
grep -rl "mt6895" $K/drivers/media/ 2>/dev/null | head -10
echo "=== done ==="
