// SPDX-License-Identifier: GPL-2.0
// cam_probe.ko - debug: enumerate of_clk provider results for camsys
#include <linux/module.h>
#include <linux/of.h>
#include <linux/clk.h>
#include <linux/clk-provider.h>

static int __init camprobe_init(void)
{
	struct device_node *np;
	int i;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6895-camsys_rawa");
	if (!np) {
		pr_info("cam_probe: no rawa node\n");
		return 0;
	}
	pr_info("cam_probe: rawa np=%p full=%s phandle=%u\n", np, np->full_name,
		np->phandle);
	for (i = 0; i < 10; i++) {
		struct of_phandle_args a = { .np = np, .args_count = 1 };
		struct clk *c;

		a.args[0] = i;
		c = of_clk_get_from_provider(&a);
		if (IS_ERR(c))
			pr_info("cam_probe: rawa[%d] err=%ld\n", i, PTR_ERR(c));
		else {
			pr_info("cam_probe: rawa[%d] = %s\n", i,
				__clk_get_name(c));
			clk_put(c);
		}
	}
	of_node_put(np);
	return 0;
}

module_init(camprobe_init);
MODULE_LICENSE("GPL");
