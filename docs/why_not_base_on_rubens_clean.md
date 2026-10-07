# 为什么不以 `port/rubens-clean` 作为我们的工作基线

状态：随修复一起提交给维护者时附上。
依据：我们在一台 Redmi K50（rubens, MT6895）上实测得到的结果，不是读代码猜的。

## 先说我们要什么

我们**不**申请把 rubens 分支合进 `7.2-mt6895-xiaomi-xaga`。我们接受 `port/rubens-clean` 就是
rubens 分支、修复应当提到那里。凡属于该分支范围的改动，我们都会 rebase 到它的 tip，按单目的提交发过去。

这里想解释的是另一件事：**为什么我们仍然保留自己这条分支**，而不是把日常驱动整体迁到
`port/rubens-clean` 上、把自己这条丢掉。

## 1. 我们这棵树的主机模式是坏的，而这恰恰是我们需要的功能

（先说明：作者已确认 OTG 主机模式在你们的分支上是可用的。所以下面这些是我们**这边的差异**，
不是 port 的缺陷：正因如此，我们打算对齐你们的配置，而不是自己另写一套 PHY 交接逻辑。）

我们的现象，接上一个设备后实测：

```
/sys/class/usb_role/11201000.usb0-role-switch/role   -> host
/sys/class/typec/port0/data_role                     -> host [device]
mt6375-chg: vbus_check: vbus=5068750 attach=1        -> 手机在输出 5V（OTG 升压是开的）
mtk-tphy  t-phy@11e40000: U2PHY set_mode(6)          -> 6 == PHY_MODE_USB_DEVICE
mtu3 11201000.usb0: gadget (high-speed) pullup D+    -> gadget 仍然占着 D+/D-
/sys/bus/usb/devices/                                -> 只有 usb1、usb2 两个 root hub
```

角色是 host、VBUS 也在输出，但 PHY 停在 device 模式，IDDIG 这个决定 D+/D- 走 xHCI 还是走
gadget 的开关没被翻过来，所以主机控制器一个设备都看不到。启动时还有一条真实的 probe 报错：

```
mtk-tphy: Failed to create device link (0x180) with supplier 11200000.xhci0
          for /soc@0/t-phy@11e40000/usb-phy@0
```

我们接下来要做的是**把 USB 相关的 DT 和配置与你们的分支逐项对比后对齐**，而不是在
PHY 里加自己的分支逻辑。如果你们能直接指出差异点（比如 role-switch 的默认模式、typec 口的
`power-role`、mtu3 的 `dr_mode`、t-phy 的 `#phy-cells` 与 xhci 的 consumer 关系），我们可以少走很多弯路。

这一条同时也是我们保留分支的理由：**主机模式是我们要长期使用的功能，我们得能随时复现和验证它。**

## 2. `chosen/bootargs` 覆盖了 bootloader 的 cmdline，而覆盖后的内容没有 `root=`、也没有串口控制台

rubens 的 DT 设置了 `chosen/bootargs`（分支里有注释说明）。按现在的写法，里面既没有 `root=`，
也没有给 gadget/UART 的 `console=`，只有 `console=tty0`。两个后果：

- 内核没法被告知 rootfs 在哪个分区，启动流程被绑死在分支自带的那套 initramfs（挂 "cust" 分区的那套）上；
- 显示还没起来的时候**完全没有控制台**，因为 `tty0` 需要一块能工作的面板。

我们修掉的整整一类 bug： 包括插上 USB 设备就让整个 SoC 卡死的那个 printk 死锁： **正是因为有控制台才发现的**。
为了迁就基线而放弃控制台，等于在我们最需要看日志的时候把眼睛蒙上。我们这条分支保留 bootloader 的 cmdline，只往上追加。

## 3. `panic_on_oops=1 softlockup_panic=1` 会把可调试的挂起变成黑屏重启

做刷机验证镜像时这样设置很合理。但在一个真的要用的设备上，一次瞬时卡顿就变成重启、现场全没了。
我们更希望默认关掉 panic 路径，需要抓问题的时候再显式打开。

## 4. rubens 是 include xaga 再加一串 `/delete-node/`

分支自己把这条标为 TODO。在它解决之前，xaga 的 DT 一改就会悄悄改到 rubens；而 review 一个 rubens 补丁
得把整条 delete-node 链重放一遍，才能弄清"生效的树"到底长什么样。我们自己的 DT 改动很小很局部，
不想让它依赖这条链。

## 5. 我们否则会一并继承的潜在隐患

下面每一条都是我们撞过或量过的，不是纸上推演：

- **`vusb33-supply = <&mt6368_vusb>` 选的是正确的轨，但没有任何地方约束它的电压。**
  我们机器上这路轨停在 **3000mV**，而 USB PHY 需要 3.3V。我们在触摸屏 AVDD 上撞过**一模一样**的坑：
  调节器一直停在 PMIC 上电默认值，直到把 `regulator-min-microvolt` 和 `regulator-max-microvolt`
  设成相等才被抬上去。在把 PHY 的偶发异常归咎于 PHY 之前，建议先把这路电压约束住。
- **触摸 SPI 的 pad 配置是 `drive-strength = <4>`，而总线跑在 12MHz。**
  那张 pad 表接受 2/4/6/8 mA，所以这里只用了 pad 一半的驱动能力：偏偏这条总线的冷启动裕量本来就是最难的部分。
  分支里的 CS 时序（`spi-cs-setup/hold/inactive-delay-ns`）是**正确**的修法，我们已经采纳；驱动强度也应该一并提上去。
- `BTIF_init()` 等平台 probe 是**死等**：这一条分支已经修了，我们正是从它得知这类问题确实存在。

## 6. 我们这条分支还承载着 port 里没有的集成工作

这不是质量问题，只是范围问题：我们这棵树同时是日常驱动（GPU 已启用、桌面在跑、相机 bring-up 在推进）。
把它整体迁到 port 上，意味着要在一套启动流程、配置片段、控制台策略全都不同的基线上重做一遍，
并且在这期间失去上机验证的能力。两条分支并存没有任何代价，而且能让我们发给你们的补丁是真正可 review 的。

## 我们打算往 `port/rubens-clean` 提什么

| 修复 | 为什么重要 |
|---|---|
| USB 主机模式：与你们的分支逐项对齐配置和 DT（对齐后若仍有需要提交的改动，会作为补丁发来） | 外部键盘/鼠标/扩展坞在我们这棵树上完全不能用 |
| 相机：四个相机 I2C 控制器（`0x11d01000/2000/5000/6000`）、wrap-S 的时钟门控、SCL/SDA 的 pad 复用 | 这个 port 的第一份相机支持；否则 IMX582/IMX596/S5K4H7/GC02M1 四颗传感器完全无法访问 |
| 触摸 FTS：`logError()` 是无级别的裸 `vprintk()`，而且每个触摸事件都会调用 | 在 gadget 串口控制台下，插上 USB 设备会死锁整个系统；它应该遵守控制台日志级别 |
| 触摸 SPI：在你们的 CS 时序之外，把 `drive-strength` 提到 `<8>` | 12MHz 下的冷启动裕量 |
| `vusb33` 的电压约束 | USB PHY 供电偏低 |

上面这些，怎么拆分、排序、取舍都听你们的；如果主机模式不在这个 port 的范围内，请告知，我们会把相关补丁留在本地。
