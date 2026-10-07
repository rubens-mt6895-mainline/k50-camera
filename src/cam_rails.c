// SPDX-License-Identifier: GPL-2.0
// cam_rails.ko - hold all camera power rails ON via legacy gpio API
// (chardev one-shot loses output latch on process exit).
// Rails: 158 vcam_ldo, 149 avdd, 20 avdd2, 159 dvdd, 164 rt5133 EN
// RST: 155 pulse low->high (kept high while module loaded)
#include <linux/module.h>
#include <linux/gpio.h>
#include <linux/delay.h>

static const int rails[] = { 670, 661, 532, 671, 676 }; /* 512+pin */
static const char *names[] = { "vcam_ldo", "avdd", "avdd2", "dvdd", "rt5133en" };
static bool got[ARRAY_SIZE(rails)];
static bool got_rst;

static int __init camrails_init(void)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(rails); i++) {
		ret = gpio_request(rails[i], names[i]);
		pr_info("cam_rails: gpio_request(%d) = %d\n", rails[i], ret);
		if (ret)
			continue;
		got[i] = true;
		ret = gpio_direction_output(rails[i], 1);
		pr_info("cam_rails: gpio%d out(1) = %d read=%d\n",
			rails[i] - 512, ret, gpio_get_value(rails[i]));
	}

	ret = gpio_request(667, "cam_rst");
	pr_info("cam_rails: rst request = %d\n", ret);
	if (!ret) {
		got_rst = true;
		gpio_direction_output(667, 0);
		msleep(50);
		gpio_direction_output(667, 1);
		msleep(5);
		pr_info("cam_rails: rst pulsed, read=%d\n", gpio_get_value(667));
	}
	return 0;
}

static void __exit camrails_exit(void)
{
	int i;

	if (got_rst)
		gpio_free(667);
	for (i = ARRAY_SIZE(rails) - 1; i >= 0; i--)
		if (got[i])
			gpio_free(rails[i]);
	pr_info("cam_rails: rails released\n");
}

module_init(camrails_init);
module_exit(camrails_exit);
MODULE_LICENSE("GPL");
