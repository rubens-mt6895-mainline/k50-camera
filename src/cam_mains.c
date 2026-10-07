// SPDX-License-Identifier: GPL-2.0
// cam_mains.ko - power on all camsys MTCMOS domains via DT power-domains
// binding (added 2026-09-29), ungate every CG, probe SENINF bus.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/io.h>

static const char * const compat[] = {
	"mediatek,mt6895-cam_main_r1a",
	"mediatek,mt6895-camsys_rawa",
	"mediatek,mt6895-camsys_yuva",
	"mediatek,mt6895-camsys_rawb",
	"mediatek,mt6895-camsys_yuvb",
	"mediatek,mt6895-camsys_rawc",
	"mediatek,mt6895-camsys_yuvc",
	"mediatek,mt6895-camsys_mraw",
};

static struct device *devs[8];
static int ndev;

static int match_of(struct device *dev, const void *data)
{
	return dev->of_node == data;
}

static int __init cammains_init(void)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(compat); i++) {
		struct device_node *np = of_find_compatible_node(NULL, NULL, compat[i]);
		struct device *dev;
		int ret;

		if (!np) {
			pr_info("cam_mains: %s no node\n", compat[i]);
			continue;
		}
		dev = bus_find_device(&platform_bus_type, NULL, np, match_of);
		of_node_put(np);
		if (!dev) {
			pr_info("cam_mains: %s no device\n", compat[i]);
			continue;
		}
		ret = pm_runtime_get_sync(dev);
		pr_info("cam_mains: %s %s rpm_get=%d\n", compat[i], dev_name(dev), ret);
		if (ret >= 0)
			devs[ndev++] = dev;
		else
			put_device(dev);
	}

	/* ungate all CGs in each syscon: set_ofs = +0x4 */
	for (i = 0; i < ndev; i++) {
		struct resource *res = platform_get_resource(
			to_platform_device(devs[i]), IORESOURCE_MEM, 0);
		void __iomem *base;

		if (!res)
			continue;
		base = ioremap(res->start, resource_size(res));
		if (!base)
			continue;
		writel(0xffffffff, base + 4);
		wmb();
		pr_info("cam_mains: %s @%pap CG sta=%08x\n",
			dev_name(devs[i]), &res->start, readl(base));
		iounmap(base);
	}

	/* SENINF bus probe (cam_main domain) */
	{
		void __iomem *s = ioremap(0x1a010000, 0x100);

		if (s) {
			pr_info("cam_mains: SENINF[000]=%08x [004]=%08x [008]=%08x\n",
				readl(s + 0x0), readl(s + 0x4), readl(s + 0x8));
			iounmap(s);
		}
	}
	pr_info("cam_mains: %d devices powered\n", ndev);
	return 0;
}

static void __exit cammains_exit(void)
{
	while (ndev > 0)
		pm_runtime_put_sync(devs[--ndev]);
}

module_init(cammains_init);
module_exit(cammains_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("MT6895 camsys MTCMOS power-on via DT genpd binding");
