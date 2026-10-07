// SPDX-License-Identifier: GPL-2.0
// cam_ovl.ko - apply ovl_pwr.dtb to the LIVE device tree at runtime
// (CONFIG_OF_OVERLAY=y). No bootloader/partition changes involved.
// After this, unbind+bind the clk-mt6895-cam devices so driver core
// re-attaches (and powers on) the genpd domains via the new
// power-domains properties.
#include <linux/module.h>
#include <linux/of.h>

extern const char ovl_blob[];
extern const char ovl_blob_end[];

static int ovcs_id;

static int __init camovl_init(void)
{
	int ret;
	u32 size = ovl_blob_end - ovl_blob;

	ret = of_overlay_fdt_apply(ovl_blob, size, &ovcs_id, NULL);
	pr_info("cam_ovl: of_overlay_fdt_apply(%u bytes) = %d ovcs_id=%d\n",
		size, ret, ovcs_id);
	return 0;	/* never block module load */
}

module_init(camovl_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Runtime DT overlay: camsys clk syscon power-domains");
