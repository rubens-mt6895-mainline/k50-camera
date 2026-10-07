// SPDX-License-Identifier: GPL-2.0
// cam_clk.ko - enable every camsys clock gate (bringup brute force)
// Enables all gates from cam_main_r1a + camsys_rawa/b/c + yuva/b/c + mraw
// so camtg (MCLK output), seninf and camsv blocks are all clocked.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/clk.h>
#include <linux/clk-provider.h>

static struct clk *keep[512];
static int nkeep;

static const char * const compat[] = {
	"mediatek,mt6895-cam_main_r1a",
	"mediatek,mt6895-camsys_rawa",
	"mediatek,mt6895-camsys_rawb",
	"mediatek,mt6895-camsys_rawc",
	"mediatek,mt6895-camsys_yuva",
	"mediatek,mt6895-camsys_yuvb",
	"mediatek,mt6895-camsys_yuvc",
	"mediatek,mt6895-camsys_mraw",
};

static int __init camclk_init(void)
{
	int c, i;

	for (c = 0; c < ARRAY_SIZE(compat); c++) {
		struct device_node *np = of_find_compatible_node(NULL, NULL, compat[c]);
		int base = nkeep;

		if (!np) {
			pr_info("camclk: %s not found\n", compat[c]);
			continue;
		}
		{
			struct of_phandle_args a = { .np = np, .args_count = 1 };
			struct clk *t;

			a.args[0] = 0;
			t = of_clk_get_from_provider(&a);
			pr_info("camclk: %s first get = %ld\n", compat[c],
				PTR_ERR(t));
			if (!IS_ERR(t))
				clk_put(t);
		}
		for (i = 0; i < 48 && nkeep < (int)ARRAY_SIZE(keep); i++) {
			struct of_phandle_args a = { .np = np, .args_count = 1 };
			struct clk *clk;

			a.args[0] = i;
			clk = of_clk_get_from_provider(&a);
			if (IS_ERR(clk))
				break;
			keep[nkeep++] = clk;
		}
		of_node_put(np);
		for (i = base; i < nkeep; i++) {
			int ret = clk_prepare_enable(keep[i]);

			pr_info("camclk: enable %s (%s) -> %d rate=%lu\n",
				__clk_get_name(keep[i]), compat[c], ret,
				clk_get_rate(keep[i]));
		}
	}
	pr_info("camclk: done, %d clocks held\n", nkeep);
	return 0;
}

static void __exit camclk_exit(void)
{
	while (nkeep > 0)
		clk_disable_unprepare(keep[--nkeep]);
}

module_init(camclk_init);
module_exit(camclk_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("MT6895 camsys clock brute-enable for camera bringup");
