// SPDX-License-Identifier: GPL-2.0
// ovl_i2c4.ko - add the camera I2C4 controller (0x11d03000, "I2C wrap S") to
// the LIVE device tree at runtime (CONFIG_OF_OVERLAY=y).  Our Mediatek
// mt6895.dtsi never declared this controller, so the overlay creates the node
// rather than enabling it; the macro camera's GC02M1 (address 0x37) is the
// only device on that bus.  Kernel-side counterpart of the userspace bring-up
// scripts, and the first step towards the fourth camera.
//
// The overlay blob is embedded by ovl_blob.S (.incbin), so the module is
// self-contained: insmod applies the overlay, the mt6895 i2c driver probes the
// new controller and /dev/i2c-N appears.
#include <linux/module.h>
#include <linux/of.h>

extern const char ovl_i2c4_blob_start[];
extern const char ovl_i2c4_blob_end[];

static int ovcs_id;

static int __init ovl_i2c4_init(void)
{
	u32 size = ovl_i2c4_blob_end - ovl_i2c4_blob_start;
	int ret = of_overlay_fdt_apply(ovl_i2c4_blob_start, size, &ovcs_id, NULL);

	pr_info("ovl_i2c4: of_overlay_fdt_apply(%u bytes) = %d ovcs_id=%d\n",
		size, ret, ovcs_id);
	if (ret)
		ovcs_id = 0;	/* nothing applied, nothing to remove */
	return 0;	/* never block module load */
}

static void __exit ovl_i2c4_exit(void)
{
	int ret;

	if (!ovcs_id)
		return;
	ret = of_overlay_remove(&ovcs_id);
	pr_info("ovl_i2c4: of_overlay_remove() = %d\n", ret);
}

module_init(ovl_i2c4_init);
module_exit(ovl_i2c4_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Runtime DT overlay: camera I2C4 controller (0x11d03000)");
