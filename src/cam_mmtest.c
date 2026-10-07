// cam_mmtest.c - kernel-side probe of seninf MMIO region (0x1a010000+)
// vs /dev/mem discrepancies; applies CSI2 config and polls PKT.
#include <linux/module.h>
#include <linux/io.h>
#include <linux/delay.h>

#define SENINF_TOP  0x1a010000
#define SENINF_CTRL 0x1a014200
#define SENINF_CSI2 0x1a014a00

static void __iomem *top, *ctrl, *csi2;

static int __init cam_mmtest_init(void)
{
	u32 v;
	int i;
	u32 p1, p2;

	top  = ioremap(SENINF_TOP, 0x1000);
	ctrl = ioremap(SENINF_CTRL, 0x1000);
	csi2 = ioremap(SENINF_CSI2, 0x1000);
	if (!top || !ctrl || !csi2) { pr_err("cam_mmtest: ioremap fail\n"); return -ENOMEM; }

	pr_info("cam_mmtest: TOP[0x00]=%08x [0x60]=%08x [0x68]=%08x\n",
		readl(top), readl(top + 0x60), readl(top + 0x68));
	pr_info("cam_mmtest: CTRL[0x00]=%08x [0x10]=%08x\n",
		readl(ctrl), readl(ctrl + 0x10));
	pr_info("cam_mmtest: CSI2[0x00]=%08x [0x10]=%08x [0xdc]=%08x\n",
		readl(csi2), readl(csi2 + 0x10), readl(csi2 + 0xdc));

	/* write stickiness test, kernel side */
	writel(0x12345678, top + 0x68);
	wmb();
	pr_info("cam_mmtest: TOP[0x68] after write 0x12345678 -> %08x\n",
		readl(top + 0x68));

	/* CSI2 config (v21b values) */
	writel(0xf, csi2 + 0x00);              /* EN = (1<<4)-1 */
	writel((readl(csi2 + 0x04) & ~(1u << 8)), csi2 + 0x04); /* CPHY_SEL=0 */
	writel((1u << 17), csi2 + 0xe0);       /* DBG packet cnt en */
	writel(0x300df106, csi2 + 0x10);       /* RESYNC_MERGE_CTRL */
	writel(0, csi2 + 0x08);                /* HDR mode/len = 0 */
	writel(1, ctrl + 0x10);                /* RG_SENINF_CSI2_EN */
	writel(1, ctrl + 0x00);                /* SENINF_EN */
	writel((readl(top + 0x68) & ~0x30f) | 0x001, top + 0x68); /* DPHY_EN=1, mode=0 */
	wmb();
	usleep_range(1000, 2000);

	pr_info("cam_mmtest: after cfg CSI2 EN=%08x RESYNC=%08x DBG=%08x CTRL=%08x/%08x TOP68=%08x\n",
		readl(csi2), readl(csi2 + 0x10), readl(csi2 + 0xe0),
		readl(ctrl), readl(ctrl + 0x10), readl(top + 0x68));

	for (i = 0; i < 5; i++) {
		p1 = readl(csi2 + 0xdc);
		msleep(300);
		p2 = readl(csi2 + 0xdc);
		pr_info("cam_mmtest: PKT %08x -> %08x %s\n", p1, p2,
			p1 != p2 ? "<<< PACKETS!" : "(idle)");
	}
	return 0;
}

static void __exit cam_mmtest_exit(void)
{
	if (top) iounmap(top);
	if (ctrl) iounmap(ctrl);
	if (csi2) iounmap(csi2);
	pr_info("cam_mmtest: exit\n");
}

module_init(cam_mmtest_init);
module_exit(cam_mmtest_exit);
MODULE_LICENSE("GPL");
