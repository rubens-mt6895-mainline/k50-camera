// SPDX-License-Identifier: GPL-2.0
// cam_clk3.ko - enable TOPCKGEN CK outputs for seninf TG / TESTMDL path:
//   CAMTG..CAMTG7 (202-208), SENINF..SENINF4 (224-228), CAMTM (260)
// cam_clk2 only enabled the *_SEL parents; the *_ck gates were still off,
// so TESTMDL had no pixel clock and PIX_CNT stayed 0.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/clk.h>
#include <linux/clk-provider.h>

static struct clk *keep[24];
static int nkeep;

/* mt6895-clk.h: CLK_TOP_CAMTG..CAMTG7, CLK_TOP_SENINF..SENINF4, CLK_TOP_CAMTM */
static const int top_ck_idx[] = {
	202, 203, 204, 205, 206, 207, 208,	/* CAMTG .. CAMTG7 */
	224, 225, 226, 227, 228,		/* SENINF .. SENINF4 */
	260,					/* CAMTM */
};

static int __init camclk3_init(void)
{
	struct device_node *np;
	int i;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6895-topckgen");
	if (!np) {
		pr_info("cam_clk3: no topckgen node\n");
		return -ENODEV;
	}

	for (i = 0; i < (int)ARRAY_SIZE(top_ck_idx); i++) {
		struct of_phandle_args a = { .np = np, .args_count = 1 };
		struct clk *c;
		int ret;

		a.args[0] = top_ck_idx[i];
		c = of_clk_get_from_provider(&a);
		if (IS_ERR(c)) {
			pr_info("cam_clk3: top[%d] get = %ld\n", top_ck_idx[i],
				PTR_ERR(c));
			continue;
		}
		ret = clk_prepare_enable(c);
		pr_info("cam_clk3: top[%d] enable = %d rate=%lu name=%s\n",
			top_ck_idx[i], ret, clk_get_rate(c), __clk_get_name(c));
		if (ret == 0 && nkeep < (int)ARRAY_SIZE(keep))
			keep[nkeep++] = c;
		else
			clk_put(c);
	}
	of_node_put(np);
	pr_info("cam_clk3: %d clocks held\n", nkeep);
	return 0;
}

static void __exit camclk3_exit(void)
{
	while (nkeep > 0)
		clk_disable_unprepare(keep[--nkeep]);
}

module_init(camclk3_init);
module_exit(camclk3_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("MT6895 topckgen seninf/camtg CK enable for TESTMDL");
