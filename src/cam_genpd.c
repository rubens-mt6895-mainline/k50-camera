// SPDX-License-Identifier: GPL-2.0
// cam_genpd.ko - attach each camsys clk syscon device to its genpd
// (power-domains property added at runtime by cam_ovl.ko) and power the
// domains ON via PD_FLAG_ATTACH_POWER_ON. No rebind needed.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/pm_runtime.h>

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

static int match_of(struct device *dev, const void *data)
{
	return dev->of_node == data;
}

static int __init camgenpd_init(void)
{
	int i, ok = 0;

	for (i = 0; i < ARRAY_SIZE(compat); i++) {
		struct device_node *np = of_find_compatible_node(NULL, NULL, compat[i]);
		struct device *dev;
		int ret;

		if (!np) {
			pr_info("cam_genpd: %s no node\n", compat[i]);
			continue;
		}
		dev = bus_find_device(&platform_bus_type, NULL, np, match_of);
		of_node_put(np);
		if (!dev) {
			pr_info("cam_genpd: %s no device\n", compat[i]);
			continue;
		}
		ret = dev_pm_domain_attach(dev, PD_FLAG_ATTACH_POWER_ON |
					   PD_FLAG_DETACH_POWER_OFF);
		pr_info("cam_genpd: %s attach = %d\n", dev_name(dev), ret);
		if (ret == 0 || ret == -EEXIST) {
			pm_runtime_enable(dev);
			ret = pm_runtime_get_sync(dev);
			pr_info("cam_genpd: %s rpm_hold = %d\n", dev_name(dev),
				ret);
			ok++;
		}
		put_device(dev);
	}
	pr_info("cam_genpd: %d/%zu domains attached\n", ok, ARRAY_SIZE(compat));
	return 0;
}

static void __exit camgenpd_exit(void)
{
	pr_info("cam_genpd: exit\n");
}

module_init(camgenpd_init);
module_exit(camgenpd_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("MT6895 camsys genpd attach + power-on");
