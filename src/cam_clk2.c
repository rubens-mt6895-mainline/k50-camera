// SPDX-License-Identifier: GPL-2.0
// cam_clk2.ko - enable all topckgen clocks the vendor seninf/imgsensor
// stack needs for main-camera MCLK + CSI: camtg0-7 sel, seninf muxes,
// camtm, cam_sel. of_clk_get_from_provider works for topckgen (provider
// registered); the camsys CG syscons have no provider (EEXIST at boot).
#include <linux/module.h>
#include <linux/of.h>
#include <linux/clk.h>
#include <linux/clk-provider.h>

static struct clk *keep[32];
static int nkeep;

/* mt6895-clk.h indices */
static const int top_idx[] = {
	20, 21, 22, 23, 24, 25, 26,	/* CAMTG_SEL .. CAMTG7_SEL */
	41, 42, 43, 44, 45,		/* SENINF, SENINF1-4 */
	74,				/* CAMTM_SEL */
};

static int __init camclk2_init(void)
{
	struct device_node *np;
	int i;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6895-topckgen");
	if (!np) {
		pr_info("cam_clk2: no topckgen node\n");
		return -ENODEV;
	}

	for (i = 0; i < (int)ARRAY_SIZE(top_idx); i++) {
		struct of_phandle_args a = { .np = np, .args_count = 1 };
		struct clk *c;
		int ret;

		a.args[0] = top_idx[i];
		c = of_clk_get_from_provider(&a);
		if (IS_ERR(c)) {
			pr_info("cam_clk2: top[%d] get = %ld\n", top_idx[i],
				PTR_ERR(c));
			continue;
		}
		ret = clk_prepare_enable(c);
		pr_info("cam_clk2: top[%d] enable = %d rate=%lu name=%s\n",
			top_idx[i], ret, clk_get_rate(c), __clk_get_name(c));
		if (ret == 0 && nkeep < (int)ARRAY_SIZE(keep))
			keep[nkeep++] = c;
		else
			clk_put(c);
	}
	of_node_put(np);
	pr_info("cam_clk2: %d clocks held\n", nkeep);
	return 0;
}

static void __exit camclk2_exit(void)
{
	while (nkeep > 0)
		clk_disable_unprepare(keep[--nkeep]);
}

module_init(camclk2_init);
module_exit(camclk2_exit);
MODULE_LICENSE("GPL");
