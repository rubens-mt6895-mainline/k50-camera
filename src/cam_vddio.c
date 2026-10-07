// SPDX-License-Identifier: GPL-2.0
// cam_vddio.ko - brute-force raise GPIO 145..200 to find rt5133 EN / IOVDD rail
#include <linux/module.h>
#include <linux/gpio.h>
#include <linux/delay.h>

static int __init camvddio_init(void)
{
	int i, ret;
	pr_info("cam_vddio: brute force gpio 145..200 HIGH\n");
	for (i = 145; i <= 200; i++) {
		ret = gpio_request(512 + i, "vddio_try");
		if (ret) {
			pr_info("  gpio%d request=%d\n", i, ret);
			continue;
		}
		ret = gpio_direction_output(512 + i, 1);
		pr_info("  gpio%d out(1)=%d read=%d\n", i, ret, gpio_get_value(512 + i));
		/* keep requested: hold high; gpios stay in use */
	}
	/* pulse RST 155 low->high again */
	ret = gpio_request(667, "cam_rst2");
	if (!ret) {
		gpio_direction_output(667, 0);
		msleep(50);
		gpio_direction_output(667, 1);
		pr_info("cam_vddio: rst re-pulsed\n");
	}
	return 0;
}

static void __exit camvddio_exit(void)
{
	pr_info("cam_vddio: exit (gpios stay latched until rmmod? releasing)\n");
}
module_init(camvddio_init);
module_exit(camvddio_exit);
MODULE_LICENSE("GPL");
