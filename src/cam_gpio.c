// SPDX-License-Identifier: GPL-2.0
// cam_gpio.ko - raise ONE gpio by module param pin=N, hold it
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/gpio.h>
#include <linux/delay.h>

static int pin = -1;
module_param(pin, int, 0644);
MODULE_PARM_DESC(pin, "GPIO number to raise (512+pin)");

static int __init camgpio_init(void)
{
	int ret;
	if (pin < 0) {
		pr_info("cam_gpio: no pin given, doing nothing\n");
		return 0;
	}
	ret = gpio_request(512 + pin, "cam_gpio_one");
	pr_info("cam_gpio: gpio_request(%d)=%d\n", 512 + pin, ret);
	if (ret)
		return 0;
	ret = gpio_direction_output(512 + pin, 1);
	pr_info("cam_gpio: gpio%d out(1)=%d read=%d\n", pin, ret, gpio_get_value(512 + pin));
	return 0;
}

static void __exit camgpio_exit(void)
{
	pr_info("cam_gpio: exit\n");
}
module_init(camgpio_init);
module_exit(camgpio_exit);
MODULE_LICENSE("GPL");
