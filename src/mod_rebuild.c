// SPDX-License-Identifier: GPL-2.0
// mod_rebuild.ko - destroy + recreate the modem platform device so its
// resources are re-parsed from the (now updated) DT node.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>

static int __init rebuild_init(void)
{
	struct device_node *np;
	struct platform_device *old = NULL;
	struct platform_device *new = NULL;
	int ret = 0;

	np = of_find_node_by_path("/soc@0/modem@10209000");
	if (!np) {
		pr_err("mod_rebuild: modem node not found\n");
		return -ENODEV;
	}
	old = of_find_device_by_node(np);
	if (old) {
		pr_info("mod_rebuild: destroying %s\n", dev_name(&old->dev));
		of_platform_device_destroy(&old->dev, NULL);
	}
	new = of_platform_device_create(np, NULL, NULL);
	if (new)
		pr_info("mod_rebuild: created %s\n", dev_name(&new->dev));
	else {
		pr_err("mod_rebuild: create failed\n");
		ret = -EIO;
	}
	of_node_put(np);
	return ret;
}

module_init(rebuild_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Rebuild modem platform device from updated DT node");

/* Native .modinfo vermagic (must be exact for camdtb kernel) */
__asm__(".section .modinfo,\"a\",@progbits\n\t"
	".asciz \"vermagic=7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64\"\n\t"
	".previous");
