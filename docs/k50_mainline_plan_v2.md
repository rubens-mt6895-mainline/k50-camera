# K50 Mainline Linux 移植：完整规划 v2.0

## 一、诊断结论（设备现状）

### 设备当前状态

| 分区                     | 当前状态                                     | 与官方对比            |
| ---------------------- | ---------------------------------------- | ---------------- |
| boot\_a                | **自定义 kernel (15.5MB)**，为 droidspaces 定制 | ✗ 非官方            |
| boot\_b                | **另一自定义 kernel**（可能是早期测试）                | ✗ 非官方            |
| vendor\_boot\_a/b      | 官方 (67MB)                                | ✓ MATCH          |
| vbmeta\_a/b            | **已恢复官方 vbmeta (8KB)**                   | ✓ MATCH（用官方包恢复后） |
| vbmeta\_system\_a/b    | 官方 (4KB)                                 | ✓ MATCH          |
| vbmeta\_vendor\_a/b    | 官方 (4KB)                                 | ✓ MATCH          |
| super                  | 官方 HyperOS 3.0.7.0 (9GB)                 | ✓ MATCH          |
| lk\_a/b                | 设备有修改（与官方 SHA1 不同）                       | ✗ 非官方            |
| 其他 (dtbo, tee, logo 等) | 设备有修改                                    | ✗ 非官方            |

### droidspaces 的问题

- `com.droidspaces.app` 是 Xiaomi 官方容器技术，在 Android 内核上跑 Debian 容器

- Android 网络栈限制（NAT/bridge/cgroup）导致网络频繁出错

- 内核 5.10.260-GDDHD059 是 Xiaomi 定制版，有 Android 特定机制

### 结论

设备目前是：**droidspaces 定制 kernel + 官方 HyperOS 3.0.7.0** 的稳定状态。

***

## 二、目标

**在 K50 上直接跑裸机独立 Debian，不依赖 Android droidspaces。**

目标状态：

- 启动流程：LK → custom boot.img (mainline kernel + initramfs) → Debian rootfs

- 控制台：USB gadget serial (ttyGS0) 或 UART 串口

- 存储：Debian rootfs 在 UFS 分区

- 硬件支持（按优先级）：

  1. ✅ USB gadget serial console（必须）
  2. ✅ 调试串口 UART
  3. ⚠️ simplefb 显示输出
  4. ⚠️ WiFi（mediatek MT7921，需要固件）
  5. ❌ 触控、音频、Modem（低优先级）

***

## 三、刷机前提（必须条件）

### 1. vbmeta 必须禁用

```bash
fastboot --disable-verity --disable-verification flash vbmeta_a images/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_b images/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system_a images/vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_system_b images/vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor_a images/vbmeta_vendor.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor_b images/vbmeta_vendor.img
```

**原因**：AVB 校验会拒绝未签名或哈希不匹配的 boot/system/vendor 分区。

### 2. super 分区必须存在

裸机 Debian 不需要 Android system/vendor，但：

- 设备固件依赖（WiFi 固件、基带固件）在 super 里

- 部分硬件初始化依赖 vendor 分区

- **最低要求**：保留官方 super（或精简版），不删除

### 3. boot 镜像结构

```
boot.img (64MB):
├── kernel (mainline Linux, ~10-15MB)
├── device tree (rubens-k50 dtb, ~200KB)
└── initramfs (debian bootstrap, ~5-10MB)
    └── /init → switch_root → Debian
```

### 4. rootfs 位置

- **方案 A**（推荐）：在 userdata 分区末尾写入 rootfs.ext4（约 2-5GB）

  - 需要调整分区表或用 losetup

- **方案 B**：在 super 分区里留空（用 sparse image）

- **方案 C**：直接用 UFS 的某个空闲块设备

***

## 四、刷机步骤（待确认）

### Phase 0：备份（只读）

- [x] adb pull 获取 boot\_a / boot\_b 当前镜像

- [ ] 获取设备上所有关键分区的 SHA1（已完成）

- [ ] 确认 vbmeta 恢复状态

### Phase 1：构建自定义 boot.img

- [ ] 确认 kernel 源码和配置
  - 需要基于哪个 kernel 版本？（主线 6.x？）

  - 需要哪些 DTB？（rubens/dtbo）

- [ ] 配置 kernel：
  - `CONFIG_USB_G_SERIAL=y`（USB gadget serial）

  - `CONFIG_FB_SIMPLE=y`（simplefb）

  - `CONFIG_DEVTMPFS=y`

  - `CONFIG_CGROUPS=y`

  - 禁用不需要的 Android 特定选项

- [ ] 编译 kernel + dtb

- [ ] 构建 initramfs（包含：busybox, e2fsck, losetup, switch\_root）

- [ ] 用 mkbootimg 打包为 boot.img

### Phase 2：构建 Debian rootfs

- [ ] 使用 debootstrap 构建 Debian sid arm64 基础系统

- [ ] 安装必要软件包：
  - `openssh-server`, `sudo`, `network-manager`, `linux-image-arm64`

  - USB 网络驱动（如果需要）

- [ ] 打包为 rootfs.ext4

### Phase 3：安全刷入

- [ ] 刷入 vbmeta（--disable-verity --disable-verification）

- [ ] 刷入 boot.img（自定义 kernel）

- [ ] 刷入 vendor\_boot.img（如需要）

- [ ] 写入 Debian rootfs 到 userdata 分区

### Phase 4：验证

- [ ] 从 USB gadget serial 连接

- [ ] 观察 kernel 启动日志

- [ ] 验证 Debian 成功启动

***

## 五、回滚方案

如果启动失败：

1. **进入 fastboot**：音量下 + 电源
2. **刷回官方 boot**：

   ```bash
   fastboot flash boot boot/boot.img  # 官方 HyperOS boot
   ```
3. **恢复 vbmeta**：

   ```bash
   fastboot --disable-verity --disable-verification flash vbmeta_a images/vbmeta.img
   fastboot --disable-verity --disable-verification flash vbmeta_b images/vbmeta.img
   ```
4. **重启**：`fastboot reboot`

***

## 六、方案 C 调研结果（已完成）

### 6.1 MT6890/Dimensity 8100 主线支持现状

| 组件                   | 主线支持  | 说明                                |
| -------------------- | ----- | --------------------------------- |
| CPU (Cortex-A78/A55) | ✅ 良好  | ARM64 SMP 主线支持                    |
| 内存 (LPDDR5)          | ✅ 基本  | 正常识别                              |
| GPU (Mali-G610)      | ⚠️ 部分 | Panthor DRM 驱动 upstream 中，性能有限    |
| Display/DSI          | ⚠️ 基础 | Mediatek DSI 上游存在，K50 特定面板可能需额外工作 |
| USB Type-C / PD      | ⚠️ 部分 | 基础 OTG 支持，USB PD 可能需要额外工作         |
| 电源管理 / PMIC          | ⚠️ 部分 | 基础可用                              |
| 存储 (UFS)             | ✅ 良好  | UFS 驱动上游支持                        |
| NPU (APU)            | ❌ 无   | 无主线支持                             |
| ISP / Camera         | ❌ 无   | 无主线支持                             |
| 指纹                   | ❌ 无   | 无主线支持                             |

**关键发现**：

- **MT6893** (Dimensity 1200) 的主线支持在 6.16 kernel 持续推进（mfd, pinctrl, mailbox, phy, display bindings）

- **MT6890** (Dimensity 8100) **没有专门的 DTB 文件**，需要参考 MT8195/MT6893 的 DTB 进行移植

- 已有 fork 项目：[MT6893-Mainline/linux](https://github.com/MT6893-Mainline/linux) 基于 Infinix X6710，可作参考

### 6.2 MT7921 WiFi 驱动状态

| 组件                    | 主线支持 | 内核版本    |
| --------------------- | ---- | ------- |
| MT7921 PCIe (MT7921E) | ✅    | 5.12+   |
| MT7921 USB            | ✅    | 5.18+   |
| MT7922 (RZ616)        | ✅    | 5.16+   |
| MT7925                | ✅    | 6.7+    |
| MT7902                | ⚠️   | 提交中，未合并 |

**注意事项**：

- MT7921 驱动在 **6.8-6.19 内核有多个已知 bug**（mutex 死锁、竞态条件）

- 社区有 `mt76-mt7925-dkms` 补丁包可改善稳定性

- 固件文件：`mt7921pr2.bin`、`mt7921_rom_patch.bin` 需要在 `/lib/firmware/mediatek/`

- K50 使用的 MT7921 型号 `14c3:7961`

**WiFi 结论**：主线内核可驱动，但需要固件 + 可能需要社区补丁。

### 6.3 Display / AMOLED 面板

- Mediatek DRM 驱动上游支持 DSI 控制器

- K50 使用 Samsung AMOLED 2K 面板（120Hz）

- 主线内核可能需要额外的面板 DTB 或固件

- 初始阶段可能只有基础 framebuffer 输出

### 6.4 现有 K50 主线移植项目

| 项目                                                                                    | 状态              | 来源                 |
| ------------------------------------------------------------------------------------- | --------------- | ------------------ |
| [MT6893-Mainline/linux](https://github.com/MT6893-Mainline/linux)                     | Fork, 未完成       | 基于 Infinix X6710   |
| [ProjectRubens/android\_device\_xiaomi\_rubens-wip](https://github.com/ProjectRubens) | LineageOS 21 移植 | 非主线内核              |
| [Redmi-K50/device\_xiaomi\_rubens](https://github.com/Redmi-K50/device_xiaomi_rubens) | LineageOS 19.1  | 非主线内核              |
| hexdump0815/linux-mainline-mediatek-mt81xx-kernel                                     | ✅ 活跃            | mt8183/mt8186 主流支持 |

**重要结论**：**K50 (rubens) 还没有成功的主线 Linux 移植先例**，我们是先驱者。

### 6.5 综合可行性评估

| 功能                       | 可行性   | 优先级 |
| ------------------------ | ----- | --- |
| 基本启动 (UART/shell)        | ✅ 高   | 1   |
| 存储 (UFS)                 | ✅ 高   | 1   |
| USB OTG / Gadget         | ✅ 高   | 1   |
| USB 网络 (RNDIS)           | ✅ 高   | 1   |
| WiFi 上网                  | ✅ 中   | 2   |
| 基础 Display (framebuffer) | ⚠️ 中  | 3   |
| 触控                       | ⚠️ 中  | 3   |
| 声音                       | ⚠️ 中低 | 4   |
| 5G/4G Modem              | ❌ 低   | -   |
| 摄像头/指纹/NPU               | ❌ 不可行 | -   |

### 6.6 推荐策略

**推荐分阶段实施**：

1. **阶段 1（最重要）**：用主线内核 + 极简 initramfs，先验证 K50 能否启动到 shell
2. **阶段 2**：加 USB Gadget Serial / RNDIS 网络，建立控制通道
3. **阶段 3**：加 WiFi 驱动和固件
4. **阶段 4**：尝试 Display（可能需要 vendor 提取的 panel DTB）
5. **阶段 5**：功能完善

### 6.7 资源参考

- [postmarketOS Mainlining Guide](https://wiki.postmarketos.org/wiki/Mainlining_Guide)

- [mt76 mainline driver](https://wireless.docs.kernel.org/en/latest/en/users/drivers/mediatek.html)

- [Collabora MTK kernel 6.16 contributions](https://www.collabora.com/news-and-blog/news-and-events/kernel-6.16-fine-tuning-the-details.html)

- [linuxvox - Linux on a Phone](https://linuxvox.com/blog/linux-on-a-phone/)

- [Mercusys MB520-5G MT6890 OpenWrt DTS](https://forum.openwrt.org/t/mercusys-mb520-5g-mt6890-initial-hardware-investigation-and-dts/252498)：MT6890 DTS 参考案例

***

## 八、编译环境选型结果

### 8.1 内核版本推荐：6.12 LTS（兼顾稳定与新硬件）

| 版本           | 类型            | 支持期               | MT6890 支持          | 结论         |
| ------------ | ------------- | ----------------- | ------------------ | ---------- |
| **6.12 LTS** | **LTS**       | **至 2028 年 12 月** | **Collabora 持续推进** | **✅ 强烈推荐** |
| 6.18         | LTS (2025 新选) | 至 2028 年          | 最新，但太新             | ⚠️ 可考虑     |
| 6.6          | LTS           | 至 2026\~2027      | 可能缺少新驱动            | ❌ 不推荐      |

**选 6.12 LTS 的理由**：

- Android 16 使用 6.12，Debian 13 也用 6.12，社区稳定

- MT6893 的 pinctrl/clkmfd 等驱动上游工作以 6.16 为主，但 6.12 也有足够的基础支持

- 工具链成熟（gcc-aarch64-linux-gnu）

- 不新不旧，风险可控

### 8.2 工具链推荐：gcc-aarch64-linux-gnu（简单可靠）

**选项 1（推荐）：系统包管理器安装**

```bash
# Ubuntu/Debian
sudo apt install gcc-aarch64-linux-gnu build-essential libncurses-dev bison flex libssl-dev libelf-dev bc cpio kmod

# Fedora/RHEL
sudo dnf install gcc-aarch64-linux-gnu

# 验证
aarch64-linux-gnu-gcc --version
```

**选项 2：Linux 内核官方交叉编译器（最新）**

- 下载地址：`https://mirrors.edge.kernel.org/tools/crosstool/`

- 当前最新版：`gcc 15.x`（2025-08-10）

- 下载文件：`arm64-gcc-15.2.0-nolibc-aarch64-linux.tar.xz`（42MB）

**选项 3：ARM 官方 LLVM 工具链（ACfL 替代品）**

- 面向 Neoverse 优化，适合 HPC/AI 负载

- 仅限原生 ARM Linux 主机（不是交叉编译器）

**推荐**：选项 1 最简单，Ubuntu 24.04 提供 GCC 15。

### 8.3 DTB/DTS 方案：参考 MT8195/Mt6893 + 自创建

**主线内核现状**：

- MT6890 (Dimensity 8100) **没有现成的 DTB**

- MT6893 (Dimensity 1200) 有 pinctrl/clk bindings 上游中（6.16 cycle）

- MT8195 有较完整的 DTS 支持

**参考来源**：

```
arch/arm64/boot/dts/mediatek/
├── mt8183-kukui.dtsi      (ChromeOS 平板，参考价值高)
├── mt8195-evk.dts          (Genio 1200，MTK 官方评估板)
└── 参考MT6893-Mainline项目  (https://github.com/MT6893-Mainline/linux)
```

**Mercusys MB520-5G 参考**：

- 已有 MT6890 DTS 在 OpenWrt 论坛（OpenWrt 路由器 SoC）

- 链接：<https://forum.openwrt.org/t/mercusys-mb520-5g-mt6890-initial-hardware-investigation-and-dts/252498>

- 可作为 DDR/时钟/存储部分的重要参考

### 8.4 最小启动内核配置

基于 `arch/arm64/configs/defconfig` 开始，**必须启用**：

```
# CPU/ARM64 基础
CONFIG_ARCH_MEDIATEK=y
CONFIG_ARM64=y
CONFIG_ARCH_MTK_MT6890=y          # 需要创建
CONFIG_ARCH_MULTI_V7=n
CONFIG_ARCH_MULTI_V8=y

# 串口控制台（最关键！）
CONFIG_SERIAL_AMBA_PL011=y
CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
CONFIG_TTY=y

# 电源管理
CONFIG_ARM_PSCI_FW=y
CONFIG_POWER_RESET=y
CONFIG_POWER_RESET_SYSCON=y

# 中断/时钟
CONFIG_ARM_GIC=y
CONFIG_ARM_GIC_V3=y
CONFIG_ARM_ARCH_TIMER=y

# 存储
CONFIG_BLK_DEV=y
CONFIG_MTD=y
CONFIG_MTK_UFS_PHY=y               # UFS 物理层
CONFIG_SCSI=y
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFS_MEDIATEK=y         # MTK UFS 主机控制器

# USB
CONFIG_USB=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_MUSB_HDRC=y             # MTK USB PHY
CONFIG_USB_ROLE_SWITCH=y

# 网络
CONFIG_NET=y
CONFIG_NETDEVICES=y
CONFIG_USB_RTL8152=y               # USB 网卡备选
# PCIe WiFi 需要先有 PCIe 支持

# 文件系统
CONFIG_EXT4_FS=y
CONFIG_F2FS_FS=y                   # 手机常用
CONFIG_ISO9660_FS=y                # CD-ROM
CONFIG_VFAT_FS=y                   # FAT32 (boot 分区)
CONFIG_EFIVAR_FS=y                 # UEFI 变量

# initramfs
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_RD_LZ4=y

# 调试
CONFIG_PRINTK=y
CONFIG_PRINTK_TIME=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_FS=y

# USB Gadget（建立 ADB/Serial 控制通道）
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_SERIAL=y
CONFIG_USB_CONFIGFS_ACM=y           # ACM 串口
CONFIG_USB_CONFIGFS_ECM=y          # USB 以太网
CONFIG_USB_CONFIGFS_RNDIS=y        # RNDIS (Windows 兼容)
CONFIG_USB_GADGET=y
CONFIG_USB_MTU3=y                  # MTK USB3.0 PHY
```

### 8.5 构建命令

```bash
# 1. 下载内核源码
git clone --depth=1 --branch linux-6.12.y https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git ~/linux-6.12

# 2. 创建 MT6890 defconfig
cd ~/linux-6.12
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
# 然后用 menuconfig 调整

# 3. 编译内核
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image

# 4. 编译 DTB（等 DTB 创建后）
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) dtbs

# 输出文件：
# arch/arm64/boot/Image          (~15-20MB)
# arch/arm64/boot/dts/mediatek/*.dtb
```

### 8.6 QEMU 验证（不依赖真机，提前验证）

```bash
# 安装 QEMU
sudo apt install qemu-system-arm

# 下载 ARM64 Ubuntu Cloud Image
curl -LO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img

# 用主线内核启动（使用 vexpress-aarch64 模拟）
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a57 \
  -m 2G \
  -kernel arch/arm64/boot/Image \
  -append "console=ttyAMA0 root=/dev/vda ro" \
  -drive if=none,file=noble-server-cloudimg-arm64.img,id=hd \
  -device virtio-blk-device,drive=hd \
  -netdev user,id=eth0 \
  -device virtio-net-device,netdev=eth0 \
  -nographic
```

**注意**：QEMU vexpress/virt 不等于 MT6890，但可以验证内核编译正确、能跑起来。

***

## 九、当前最大挑战（需要解决的）

| 挑战                    | 影响      | 可能的解决方案                                 |
| --------------------- | ------- | --------------------------------------- |
| **MT6890 无现成 DTB**    | 🔴 核心障碍 | 参考 MT8195/MT6893/Mercusys MB520 DTS 自己写 |
| **Display 面板无支持**     | 🟡 限制体验 | 先用串口/shell；未来尝试提取 vendor DTB            |
| **WiFi 需要 PCIe + 固件** | 🟡 需要固件 | 从设备提取或下载；mt76 驱动主线已有                    |
| **USB Gadget 配置复杂**   | 🟡 需要测试 | 参考 Android 的 USB 配置                     |
| **initramfs 打包**      | 🟡 需要工具 | mkbootimg / abootimg                    |

***

## 十一、环境调研最终结论

### 11.1 实际发现

**重大发现 1：SoC 型号确认**

- 设备 DTS `compatible = "mediatek,MT6895";` `model = "MT6895Z/TCZA"`

- **MT6895 = MediaTek Dimensity 8100 内部命名**

- 之前理解有误。MT6895 在主线内核**完全无 DTB**，但 DTS 现成可用！

**重大发现 2：完整 vendor DTB 已提取**

- 文件：`${K50_REPO}\out\orig_live.dtb` (408KB, 14245 行 DTS)

- MD5: `93dadcbc9d6ccc60b4ba9b8887131e9f`

- 来源：从设备 `/proc/device-tree` 提取（已成功反编译为 `orig_live.dts`）

**重大发现 3：WSL2 Ubuntu 完整工具链已就绪**

| 工具                     | 状态                 | 用途          |
| ---------------------- | ------------------ | ----------- |
| WSL2 Ubuntu            | ✅ 已安装              | 编译环境        |
| aarch64-linux-gnu-gcc  | ✅ 13.3.0           | ARM64 交叉编译  |
| gcc                    | ✅ 13.3.0           | 本地编译        |
| dtc                    | ✅ 1.7.0            | DTB 编译/反编译  |
| mkbootimg              | ✅ 来自 android-tools | boot.img 打包 |
| abootimg               | ✅ 来自 android-tools | boot.img 操作 |
| git, make, bison, flex | ✅ 全部               | 内核编译        |
| python3                | ✅ 3.12.3           | 辅助脚本        |

**硬件资源**（WSL2）

- 8 CPU 核

- 7.7 GB RAM

- 162 GB 可用磁盘（/mnt/d）

### 11.2 vendor DTB 关键信息提取

| 节点                | 地址         | 类型          | 主线支持                  |
| ----------------- | ---------- | ----------- | --------------------- |
| `serial@11001000` | 0x11001000 | UART (8250) | ✅ 主线支持 mt6577-uart    |
| `gic500@0c000000` | 0x0c000000 | GIC v3      | ✅ 主线支持                |
| `ufshci@112b0000` | 0x112b0000 | UFS HCI     | ✅ 主线支持（mt8183-ufshci） |
| `usb0@11201000`   | 0x11201000 | USB 3.0     | ✅ 主线支持 ssusb          |
| `usb1@11211000`   | 0x11211000 | USB 2.0     | ✅ 主线支持                |
| `dsi@14017000`    | 0x14017000 | DSI Display | ⚠️ 需面板驱动              |
| `iommu@1e802000`  | 0x1e802000 | SMMU        | ✅ 主线支持                |

**bootargs 完整内容**（已抓到原厂）：

```
console=tty0 root=/dev/ram 8250.nr_uarts=4
rcupdate.rcu_expedited=1 transparent_hugepage=never
vmalloc=400M swiotlb=noforce
firmware_class.path=/vendor/firmware
console=tty0 root=/dev/ram loop.max_part=7
panel-l11a-38-0a-0a-dsc-cmd.oled_wp=01f20bb90c4f
arm64.nopauth mtk_printk_ctrl.disable_uart=1
log_buf_len=2M
ramoops.mem_address=0x48090000 ramoops.mem_size=0xe0000
hwid.sku=rubens hwid.country=CN hwid.level=MP1
```

### 11.3 项目推进策略（已确定）

**最优方案：基于 vendor DTB + 主线内核**

由于已经有完整且可信的 vendor DTB（从运行中设备提取），策略变为：

1. **使用 vendor DTB 作为基础**： 不必从零写 DTB
2. **主线内核构建**： 仅替换 kernel 部分
3. **保留 vendor 提供的所有设备节点**： 减少工作量
4. **目标**：让 K50 跑主线内核 + Debian rootfs，保留硬件兼容性

**好处**：

- 大幅降低 DTB 工作量（数月 → 数天）

- 设备节点完整，所有外设都能识别

- 可以利用 vendor 已经验证的 initramfs 思路

**风险**：

- vendor DTB 引用了 vendor-only compatible 字符串（如 `mediatek,clk-disable-unused`）

- 主线内核可能不支持这些节点 → 需要标记为 `status = "disabled"`

- 部分 pinctrl 节点可能在主线驱动里字段名不同

### 11.4 下一步具体行动

**第一步：DTB 兼容性预处理**

- 把 vendor DTB 中所有 `status` 字段缺省/okay 的节点逐个检查

- 标记 vendor-only 节点为 `status = "disabled"`

- 保留主线内核可识别的节点为 `status = "okay"`

**第二步：编译第一个测试内核**

- 下载 linux-6.12.y stable 分支

- 配置 CONFIG\_ 启用 MTK SoC 基础支持

- 用预处理过的 DTB 编译

- 在 QEMU 模拟 ARM64 环境下验证能启动

**第三步：构建 initramfs + boot.img**

- 用 mkbootimg 打包

- 包含测试 rootfs（极简 busybox）

**第四步：刷入测试 boot**

- 仅刷 boot\_a（保留 boot\_b 不动）

- 验证能否进入 initramfs shell

***

## 十二、立即可执行：测试编译
