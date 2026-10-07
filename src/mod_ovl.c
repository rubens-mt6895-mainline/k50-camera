// SPDX-License-Identifier: GPL-2.0
// mod_ovl.ko - apply ovl_modem.dtb to the LIVE device tree at runtime
// (CONFIG_OF_OVERLAY=y). No bootloader/partition changes involved.
// Adds modem@10209000 so ccci_md.ko can probe the modem.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/printk.h>
#include <linux/slab.h>

extern const char _binary_ovl_modem_dtb_start[];
extern const char _binary_ovl_modem_dtb_end[];

static int ovcs_id;

static int __init modovl_init(void)
{
	int ret;
	u32 size = _binary_ovl_modem_dtb_end - _binary_ovl_modem_dtb_start;
	/* fdt_check_header() requires the blob be 8-byte aligned. The
	 * _binary_ symbol may not be aligned in .data; copy to kmalloc
	 * buffer (guaranteed ARCH_KMALLOC_MINALIGN aligned).
	 */
	void *aligned = kmalloc(size, GFP_KERNEL);

	if (!aligned)
		return -ENOMEM;
	memcpy(aligned, _binary_ovl_modem_dtb_start, size);
	ret = of_overlay_fdt_apply(aligned, size, &ovcs_id, NULL);
	pr_info("mod_ovl: of_overlay_fdt_apply(%u bytes) = %d ovcs_id=%d\n",
		size, ret, ovcs_id);
	kfree(aligned);
	return 0;	/* never block module load */
}

module_init(modovl_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Runtime DT overlay: modem@10209000 for ccci_md");

/* Native .modinfo vermagic (no KBUILD_MODNAME prefix, must be exact) */
__asm__(".section .modinfo,\"a\",@progbits\n\t"
	".asciz \"vermagic=7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64\"\n\t"
	".previous");
