// SPDX-License-Identifier: GPL-2.0
/* cam_cap.ko - enable cam_main power domain + camsys clocks by
 * finding the camsys_rawa device and doing pm_runtime_get. */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/io.h>

static struct device *cam_dev;
static void __iomem *seninf_base;

static int __init cam_cap_init(void)
{
	struct device_node *np;
	struct platform_device *pdev;
	struct device *dev;
	void __iomem *regs;
	u32 v;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6895-camsys_rawa");
	if (!np) {
		pr_err("cam_cap: camsys_rawa node not found\n");
		return -ENODEV;
	}
	pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!pdev) {
		pr_err("cam_cap: no platform device for camsys_rawa\n");
		return -ENODEV;
	}
	dev = &pdev->dev;
	pr_info("cam_cap: found device %s (driver: %s)\n", dev_name(dev),
		dev->driver ? dev->driver->name : "none");

	pm_runtime_enable(dev);
	ret = pm_runtime_get_sync(dev);
	if (ret < 0) {
		pr_err("cam_cap: pm_runtime_get_sync = %d\n", ret);
		pm_runtime_disable(dev);
		put_device(dev);
		return ret;
	}
	pr_info("cam_cap: pm_runtime_get OK - power domain on\n");
	cam_dev = dev;

	regs = ioremap(0x1a010000, 0x100);
	if (IS_ERR(regs)) {
		pr_err("cam_cap: ioremap seninf failed\n");
		return PTR_ERR(regs);
	}
	seninf_base = regs;
	v = readl(regs);
	pr_info("cam_cap: SENINF[0x000] = 0x%08x\n", v);
	v = readl(regs + 4);
	pr_info("cam_cap: SENINF[0x004] = 0x%08x\n", v);
	pr_info("cam_cap: camera subsystem alive!\n");
	return 0;
}

static void __exit cam_cap_exit(void)
{
	if (cam_dev) {
		pm_runtime_put_sync(cam_dev);
		pm_runtime_disable(cam_dev);
		put_device(cam_dev);
	}
	if (seninf_base)
		iounmap(seninf_base);
	pr_info("cam_cap: exit\n");
}

module_init(cam_cap_init);
module_exit(cam_cap_exit);
MODULE_LICENSE("GPL");
