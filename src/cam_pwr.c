// SPDX-License-Identifier: GPL-2.0
/* cam_pwr.ko - K50 camera power test via legacy gpio_request API.
 * insmod: requests GPIO158 (vcam_ldo) + GPIO164 (rt5133 EN), drives high.
 * rmmod: frees both (rails drop).  Every step logs its exact return code so
 * a failure pinpoints the layer (chardev validate vs gpiod vs pinctrl). */
#include <linux/module.h>
#include <linux/gpio.h>
#include <linux/delay.h>

static bool got158, got164;

static int __init cam_pwr_init(void)
{
	int ret;

	ret = gpio_request(670, "cam_pwr_vcam")  /* 512 base + local 158 */;
	pr_info("cam_pwr: gpio_request(158) = %d\n", ret);
	if (ret)
		return ret;
	got158 = true;

	ret = gpio_direction_output(670, 1);
	pr_info("cam_pwr: gpio158 direction_output(1) = %d\n", ret);
	if (ret)
		goto err;
	pr_info("cam_pwr: gpio158 readback = %d\n", gpio_get_value(670));

	ret = gpio_request(676, "cam_pwr_rt5133en")  /* 512 + 164 */;
	pr_info("cam_pwr: gpio_request(164) = %d\n", ret);
	if (ret)
		goto err;
	got164 = true;

	ret = gpio_direction_output(676, 1);
	pr_info("cam_pwr: gpio164 direction_output(1) = %d\n", ret);

	msleep(20);
	pr_info("cam_pwr: camera rails asserted\n");
	return 0;
err:
	if (got158)
		gpio_free(670);
	got158 = false;
	return ret;
}

static void __exit cam_pwr_exit(void)
{
	if (got164)
		gpio_free(676);
	if (got158)
		gpio_free(670);
	pr_info("cam_pwr: rails released\n");
}

module_init(cam_pwr_init);
module_exit(cam_pwr_exit);
MODULE_LICENSE("GPL");
