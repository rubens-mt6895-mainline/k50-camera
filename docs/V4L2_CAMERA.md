# 把 K50 的相机接到系统相机软件（Cheese）： `/dev/video0` 实装记录

> 文档目的：回答 m03706 的前半句「你能把这玩意接到系统的相机软件吗（如果系统没有相机软件可以装 gnome 的相机）」。
> **答案：已经接上了。** 设备上装了 **Cheese 43.0**，它打开 `/dev/video0` 就能出图，并且它自己录下来的 webm
> 与直读 `/dev/video0` 的画面**同画面、同方向**（相关性 +0.591，见 §6）。
> ISP 那一半见 [docs/ISP_FEASIBILITY.md](ISP_FEASIBILITY.md)。

---

## 1. 一句话架构

```
IMX582(CSI port2, I²C bus10 @0x10)
   │ MIPI CSI2 4-lane
   ▼
SENINF_TOP 0x1a010000 → port2 page 0x1a014200 → intf4 → mux1(0x1a011d00)
   ▼
CAM_MUX 3 (0x1a010460) → camsv1@1a110000  (CAMSV = 简单通路)
   ▼ IMGO DMA（IOMMU IOVA 0x10000000 ↔ 物理 0xfa500000，18 874 368 B）
   ▼
cam_cap.ko 内核侧管线：12bit 解包 → 2×2 binning → 黑电平 → 白平衡 → √gamma
                       → RGGB 反马赛克 → BT.601 全范围 YUYV → FLIP180
   ▼
/dev/video0  （2000×1500 YUYV，6 000 000 B/帧，mmap / dmabuf / read 三种模式）
   ▼
Cheese 43.0 / v4l2-ctl / 任何 V4L2 应用
```

这里**没有 ISP**：色彩全部由 `cam_cap.ko` 在 CPU 上做（原因见 ISP 文档）。

---

## 2. 上机：一次把相机变成"系统相机"

### 2.1 依赖模块（V4L2 地基）

> **现在不用手动做了**：`cam-camera.service`（§10.3）开机 20 秒内自己跑完下面全部步骤，
> 包括传感器上电。手动路径留作排障 / 改参数用：`sh /root/zz_cam_up.sh` 或 `sh /root/cam_reset.sh`。

设备**没有** `/lib/modules`（我们是自编译内核，没装模块树），所以 V4L2 根基是**手工装载**的，
文件都在设备 `/root/v4l2/`：

```sh
# 顺序不能变（后者依赖前者的符号）
cd /root/v4l2
insmod mc.ko                 # 必须先有它：videodev 的 media_* 符号来自这里
insmod videodev.ko           # /proc/devices 里出现 "81 video4linux"
insmod videobuf2-common.ko
insmod videobuf2-memops.ko
insmod videobuf2-vmalloc.ko
insmod videobuf2-dma-contig.ko
insmod videobuf2-v4l2.ko
```

> 这些 `.ko` 是从 WSL 里用 `make ARCH=arm64 LLVM=1 M=$K/drivers/media/{v4l2-core,common/videobuf2,mc} modules`
> 编出来的（脚本：[scripts/wsl_build_v4l2.sh](../scripts/wsl_build_v4l2.sh)、[scripts/wsl_build_mc.sh](../scripts/wsl_build_mc.sh)、
> [scripts/wsl_v4l2_stage.sh](../scripts/wsl_v4l2_stage.sh)），vermagic 与设备内核一致
> （`7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64`）。
> **坑**：这份配置里 `CONFIG_MEDIA_SUPPORT=m` ⇒ 媒体控制器核心 **`mc.ko` 也是模块**，
> 少了它 `videodev.ko` 会报 26 个 `media_*` 符号 `Unknown symbol`。

### 2.2 相机模块（一条命令）

```sh
rmmod cam_cap 2>/dev/null
insmod /root/cam_cap.ko v4l2_enable=1
```

`v4l2_enable=1` 会自动把抓帧所需的全部参数**强制**成已验证的组合，不用再手写一长串：

| 参数 | 被强制成的值 | 为什么 |
|---|---|---|
| `pak_mode` | `0x82` | PAK/DBL 必须成对：`dbl_data_bus=2` ↔ `pak_dbl=2` + `pak_mode=0x82` |
| `pak_dbl` | `2` | 同上 |
| `dbl_data_bus` | `2` | 同上 |
| `route_pix_mode` | `2` | 12-bit 输出（1.5 B/像素） |
| `route_en` / `single_mode` | `1` / `1` | 自动配 SENINF 路由；SINGLE_MODE 让硬件自己停帧（防下一帧覆盖缓冲头） |
| `frame_bytes` | `≥ 18 874 368` 且**页对齐** | DMA 缓冲大小，见下面的坑 |

### 2.3 ★ 一个真实踩过的坑：IOMMU 要求页对齐

`frame_bytes` 必须能被 4 KiB 整除。曾经把它设成"正好一帧"的 `18 000 000`（不是 4096 的倍数），结果：

```
iommu: unaligned: iova 0x10000000 pa 0xfa500000 size 0x112a880 min_pagesz 0x1000
cam_cap: iommu_map(iova 0x10000000, pa 0xfa500000, 18000000) = -22
mtk-iommu-mt6895 1e802000.iommu: fault type=0x5 iova=0xfa52e000 pa=0x0 larb=0 port=2 layer=0 write
```

模块**静默退回物理寻址**，CAMSV 往物理地址写 → 触发 IOMMU fault → 抓到的一帧**全 0**（Y=0，U=V=128），
但 `/dev/video0` 能打开、`arm` 还报 FRAME READY（"看起来正常"的黑帧，最难查）。
现在源码里写死了 `CAMCAP_FRAME_BYTES = 18874368UL`（= 0x1200000 = 18 MiB），并且在 `v4l2_enable` 时
**IOMMU 映射失败会直接让 insmod 失败**并打印 `cannot stream through the IOMMU with a %lu-byte buffer; aborting`。

### 2.4 加载成功的标志

```
dmesg | tail:
  mtk_iommu: MTK-DOWN-IOMMU map iova=0x10000000 pa=0xfa500000 size=0x100000 count=0x12
  cam_cap: iommu_map: iova 0x10000000 -> pa 0xfa500000, 18874368 bytes
  cam_cap: v4l2: registered /dev/video0, 2000x1500 YUYV, 6000000 bytes/frame

ls -l /dev/video0          → crw-rw---- 1 root video 81, 0
cat /sys/class/video4linux/video0/name   → cam_cap
```

（刚 `insmod` 完的那一瞬间会看到 `crw------- root root`：那时 udev 还没跑规则；一两秒后就是 `root:video`。）

`/dev/video0` 的权限是 `root:video`，而桌面用户 **k50 属于 `video` 组（44）**，所以**不需要改权限**，
也不需要 root 就能打开/预览（Cheese 与 `v4l2-ctl` 都已实测通过）。

### 2.5 一个脚本搞定（推荐）

| 脚本 | 作用 |
|---|---|
| [scripts/zz_cam_up.sh](../scripts/zz_cam_up.sh) | **一条命令拉整栈**：停掉占用设备的应用 → 幂等加载 V4L2 地基 → `rmmod/insmod cam_cap v4l2_enable=1` → 等 `/dev/video0` → 打印有效参数/dmesg/`camcap_info` |
| [scripts/zz_cam_app.sh](../scripts/zz_cam_app.sh) | 在 k50 的 Wayland 会话里起 Cheese，并复核帧计数/日志 |
| [scripts/zz_v4l2_test.sh](../scripts/zz_v4l2_test.sh) | 抓帧验证：两次 `head -c 6000000 /dev/video0` + md5 + 亮度直方图 + dmesg |

从 PC 上跑：`bash scripts/zz_v4l2_run.sh`（scp `.ko` 与脚本 → ssh 执行 → 拉回 `frames/v4l2_v{1,2}.yuyv`）。

---

## 3. 怎么用（三种方式）

### 3.1 `v4l2-ctl`（已装 v4l-utils 1.22.1）

```sh
v4l2-ctl --list-devices
#   MT6895 CAMSV1 (IMX582) (platform:cam_cap):  /dev/video0

v4l2-ctl -d /dev/video0 --all
#   Driver name   : cam_cap
#   Card type     : MT6895 CAMSV1 (IMX582)
#   Capabilities  : 0x85200001  (Video Capture, Streaming, Extended Pix Format, Device Caps)
#   Device Caps   : 0x05200001
#   [fmt] 2000x1500  YUYV (Y′CbCr 4:2:2), Bytes per Line 4000, Size Image 6000000
#            Colorspace sRGB, YCbCr Encoding ITU-R 601, Quantization Full Range

# 抓 3 帧看看（每帧 6 MB）
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3 --stream-to=/tmp/f.yuyv
```

### 3.2 直接读（最快验证）

```sh
head -c 6000000 /dev/video0 > /tmp/f.yuyv     # 每帧正好 6 000 000 字节
```
PC 上渲染：`python scripts\render_yuyv.py frames\v4l2_v1.yuyv`（Windows Python + numpy/PIL；
WSL 与设备上**都没有 numpy**）→ 出 `_color.png`(2000×1500) / `_view.png`(1000×750)。

### 3.3 Cheese（系统相机软件）

设备原仓库里没有 GNOME Snapshot / gnome-camera，**Cheese 可用**（`cheese 43.0-1`，含 `libcheese8`、`libcheese-gtk25`）：

```sh
# 关键：必须进 k50 的桌面会话（KDE Plasma Wayland），不能用 root 的纯 ssh 环境
runuser -u k50 -- env \
  XDG_RUNTIME_DIR=/run/user/1000 \
  WAYLAND_DISPLAY=wayland-0 \
  DISPLAY=:0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  setsid cheese >/tmp/cheese.log 2>&1 </dev/null &
```

* 起来后 Cheese 界面里就是相机画面；它默认还会**录像**到 `/home/k50/.gnome2/cheese/media/*.webm`。
* 设备上有 `kamoso`（KDE 的相机程序，22.12.3）也可以，但 Cheese 已经验证可用。
* **注意**：如果从 ssh 里 `&` 起 GUI，后台进程会继承 ssh 的 stdout/通道，导致**那条 ssh 不回包**
  （脚本要么重定向到文件+`setsid`，要么用 `nohup`/`disown`；[scripts/zz_cam_app.sh](../scripts/zz_cam_app.sh) 已处理好）。
* **坑：Cheese 实例可能"假活"**。实测遇到过一次：Cheese 进程在、3 个 `/dev/video0` fd 也在、`streaming` 日志也有，
  但只取了 **6 帧**就再也不排队缓冲了（`arm_count` 卡住不动，`cam_cap_v4l2` CPU 掉到 2.5%）。
  同一次实验里：
  * `gst-launch-1.0 v4l2src device=/dev/video0 num-buffers=20 ! fakesink`（**以 k50 身份**）→ `arm_count 6 → 27`，正常出帧；
  * `pkill -x cheese` 后**重新起一个 Cheese** → `arm_count 48 → 91`，**2.15 fps** 稳定出帧。

  ⇒ 这是那个 Cheese 实例自身卡住了（不是驱动问题）。**处理办法就是杀掉重启**：`pkill -x cheese` 后再跑
  [scripts/zz_cam_app.sh](../scripts/zz_cam_app.sh)。判断"是否真的在出帧"永远看 `arm_count` 是否增长，不要只看进程在不在。

---

## 4. 驱动参数一览（`/sys/module/cam_cap/parameters/`）

| 参数 | 默认 | 说明 |
|---|---|---|
| `v4l2_enable` | `N` | 打开 V4L2 采集设备（同时强制 §2.2 那套参数）。**现在设备上是 `Y`** |
| `out_width` / `out_height` | `2000` / `1500` | 输出分辨率。**必须等于 `cam_src_w/h ÷ v4l2_bin`**（不满足只警告并回落到该值）。默认 2000×1500 = 4000×3000 做 2×2 binning 的结果 |
| `v4l2_bin` | `2` | 输出 binning：`2` = 每 2×2 原始块平均成一个输出像素，`1` = **满尺寸**（每个原始像素一个输出像素），走 bilinear 反马赛克（§13）。`1` 只对 **binned 模式**（`0x0900=1`：preview / normal_video / custom3 / custom2 / hs_video）正确；custom4 8000×6000 与 custom5 的 Bayer 周期是 2（Quad-Bayer 未 binning），只能用 `2` |
| `v4l2_full_cache` | `Y` | 满尺寸转换器的取样方式：`Y` = 每条原始行只解包一次到 u16 暂存行（三行滚动窗口），`N` = 逐像素重复解包（**参考实现**，分配失败时的回退）。两者输出逐字节相同（`scripts/check_full_demosaic.py` 证明），差别只在速度（§13.2） |
| `v4l2_src_stride` | `0` | 采集缓冲里每条原始行的字节数；`0` = 由 `exp_hsize` 推 `1.5×`。换 sensor 模式（几何变化）时用 |
| `v4l2_black` | `248` | 黑电平（12-bit），先减掉再做增益 |
| `v4l2_gain_q8` | `256` | 线性预增益（Q8，256 = 1.0×），**加在 sqrt 色调曲线之前**。旧默认 768 = 3.0× 会把亮部整片推成 255 = 过曝（§10.1）；暗场景才需要再放大 |
| `wb_r_q8` / `wb_b_q8` | `320` / `434` | 红/蓝白平衡**初值**（Q8）。开 AWB 后这两个只是起点，运行值由 `cam_isp_governor()` 每帧迭代。默认值是 RGGB 的灰世界解（原始 tap 均值 R=802/G=1001/B=591，§11.4） |
| `frame_bytes` | `18874368` | DMA 缓冲大小（**必须页对齐**，§2.3） |
| `single_mode` | `1` | CAMSV TG 单帧模式（`v4l2_enable` 会强制） |
| `camsv_base` | `0x1a110000` | camsv1 基址 |
| `seninf_base` / `route_intf` / `route_mux` / `cammux` | `0x1a010000` / `4` / `1` / `3` | SENINF 路由（port2 → intf4 → mux1 → cam_mux3） |
| `sensor_ctl` | `Y` | 允许驱动自己写传感器 I²C（AE/手动控件都靠它） |
| `i2c_bus` / `i2c_name` / `i2c_addr` | `10` / `i2c-mt65xx` / `0x10` | 传感器总线。**`i2c_name` 要匹配 adapter 名，不是设备树节点名**（§9.3 坑 1） |
| `ae_enable` / `awb_enable` | `Y` / `Y` | 开机时 AE / AWB 环的初始开关（之后由 V4L2 控件接管） |
| `ae_target` / `ae_band` / `ae_clip_pct` | `1000` / `120` / `2` | AE 目标 raw 绿均值 / 死区半宽 / 过曝参考百分比（`ae_target` 从 1200 降到 1000 也是过曝修复的一部分，§10.1） |
| `awb_rate` / `awb_min_level` | `2` / `200` | AWB 每帧只走 `1/2^rate` 的误差；绿均值低于 `min_level` 时冻结 |
| `exp_max` / `again_max` / `dgain_max` | `0x0c64` / `0x03a0` / `0x1000` | AE 的三个上限（也是对应 V4L2 控件的 max，§9.2）。**`exp_max` 必须 ≤ bring-up 写的 VTS − 128**：曝光到达 VTS 时传感器会把帧周期拉长（旧默认 0x3000 会掉到 ~9 fps）。当前配 VTS 3300 ⇒ `0x0c64` = 3172 行，留 30 fps 以上余量（§11.3） |
| `out_brightness` / `out_contrast` / `out_saturation` | `0` / `128` / `128` | 色调曲线参数（对比度绕中灰 2048，亮度加性 `×16`，饱和度只作用 U/V） |
| `ae_trace` | `N` | 每次 AE 修正往 dmesg 打一行（排障用；**默认关**，否则 0.7 行/秒） |
| `conv_threads` | `4` | 输出转换的并行线程数：`1` = 单线程内联（最保守），`2..8` = 分带 worker 池。缓存别名（cached alias）修好后 4 线程 20 ms、8 线程 18.4 ms；**帧周期由 arm 决定**，所以 4→8 只有 32.5→33.3 fps 的小幅收益（§11.3） |
| `pipeline` | `Y` | 双缓冲流水线：arm 线程只负责把下一帧 DMA 打起来，`cam_cap_conv` 线程转换上一帧，两者重叠。这是 30 fps 的关键（串行结构封顶在 ~20 fps，§11.2） |
| `rb_swap` | `N` | `N` = (0,0) tap 是红、(1,1) 是蓝（RGGB，**本传感器**，厂商 `SENSOR_OUTPUT_FORMAT_RAW_4CELL_HW_BAYER_R` + 强色偏物理实验都指向它）；`Y` = 相反（BGGR）。它同时翻 Bayer 标签、亮度系数和色度槽，两个取值都自洽；运行期可改（sysfs），AWB 几帧内重新收敛（§11.4） |
| `route_once` | `Y` | SENINF/CAM_MUX 路由每次载入只配一次（而不是每帧重写 + 一次 cam_mux SW_RST）。`/proc/camcap` 的 `reroute` 命令可强制重配 |
| `arm_trace` | `N` | 每次 arm 打一行（地址/状态）到 dmesg，排障用 |

`/proc/camcap_info` 给状态：

```
frame_ready  : 1
arm_count    : 3551        # 已完成的 arm 次数（Cheese 在跑时会持续增长）
last_seq     : 3551
last_result  : 0           # 0 = 成功，-110 = 超时
```

`/proc/camcap`（无 `_info`）是**裸 18 MB 缓冲转储**（`dd if=/proc/camcap bs=1M count=18`），调试 12-bit 原始数据用。

---

## 5. 内核侧管线（`src/cam_cap.c`，约 3956 行）

细节与常量见 [docs/ISP_FEASIBILITY.md](ISP_FEASIBILITY.md) §6，这里只列**改代码时最容易踩的三个点**：

1. **12-bit 打包**：每 3 字节 2 像素（`px0 = b0|((b1&0xf)<<8)`，`px1 = (b1>>4)|(b2<<4)`）；
   一行 4000 px = **6000 字节**，不是 RAW10 的 5000 字节。
2. **FLIP180 必须在反马赛克之后**：对 Bayer 原始网格做 180° 翻转会把 RGGB 静默变成 BGGR（颜色就错了）。
3. **`wait_prepare`/`wait_finish` 在本内核树里不存在**（`include/media/videobuf2-core.h` 没有这俩字段），
   `vb2_ops` 里不能设；`vb2_queue` 用的是 `min_queued_buffers`（不是 `min_buffers_needed`）。

队列用 **`vb2_vmalloc_memops`**（mmap/dmabuf/read 三种都开了），转换在 `cam_cap_v4l2` 内核线程里做；
CAMSV 则始终往那块**固定 CMA 缓冲**（物理 `0xfa500000`，IOVA `0x10000000`）写：两者解耦，
所以"应用层要多大缓冲"和"硬件往哪写"互不干扰。

**重建**（在 WSL 里，`$K = ${KDIR}`）：

```sh
bash ${K50_REPO}/scripts/zz_build_camcap.sh   # → out/camcap_0b8dd2e/cam_cap.ko
```

---

## 6. 验证证据（都是可复算的数字，不是"看起来对"）

### 6.1 设备自述

`v4l2-ctl -d /dev/video0 --all` 的输出（§3.1）与 `dmesg` 的注册行一致：
`2000x1500 YUYV, 6000000 bytes/frame`，`/dev/video0` = `81,0`，名字 `cam_cap`。

### 6.2 帧是"活的"

同一配置下连续两次 `head -c 6000000 /dev/video0`，md5 **不同**：

| 帧 | md5 |
|---|---|
| `frames/v4l2_v1.yuyv` | `ebbb7e1755af79dac4b98b6a83cc498a` |
| `frames/v4l2_v2.yuyv` | `e167ccb0135fa457a7e9dddbb9b166a4` |

Y 直方图（首 MB，步长 2）：`0-31:74 522 / 32-63:199 197 / 64-95:186 692 / 96-127:39 589`
： 暗场景的典型形状，**不是全黑**（全黑就是 §2.3 那个 bug）。

### 6.3 方向/视野与已验证的 RAW 渲染一致

[scripts/check_v4l2_orient.py](../scripts/check_v4l2_orient.py)（缩到 500×375 算亮度相关系数，比较原方向 vs 转 180°）：

| 参考图 | same | rot180 |
|---|---|---|
| `frames/room1_view.png`（已验证的 12-bit RAW 渲染） | **+0.552** | +0.162 |
| `frames/color_wb_gray_view.png` | +0.494 | −0.024 |
| `frames/pos2_0400_view.png` | +0.275 | +0.052 |

⇒ 新通路与原通路**同方向、同视野**。

### 6.4 ★ 决定性证据：Cheese 自己录的画面

Cheese 录了两段 webm（`/home/k50/.gnome2/cheese/media/2026-10-06-201246.webm` 510 777 B、
`…-201401.webm` 922 847 B）。用 gstreamer 解出**头部帧**（`identity eos-after=4`，
脚本 [scripts/zz_webm_head.sh](../scripts/zz_webm_head.sh)）：

| 帧 | 对 `frames/v4l2_v1_view.png` 的相关系数 |
|---|---|
| `frames/hd_2026-10-06-201401_000.png`（第 0 帧） | **same +0.591 / rot180 −0.185** |
| `frames/hd_2026-10-06-201401_003.png` | same +0.407 |
| `frames/hd_2026-10-06-201246_003.png` | rot180 +0.417（且亮度均值 96.8，明显更亮）|

最后一行**不是 bug**：那是 20:12 那一两分钟手机朝向变了（对着更亮的方向、俯仰不同），
所以那一帧与我们的参考帧不同向；12×24 亮度图的亮斑位置可以复现这一点。
**结论：相机软件里显示的，就是我们直读 `/dev/video0` 得到的同一幅画面，方向正确。**

> 教训：验 webm 一定要取**头部**帧。取尾部帧时（`multifilesink max-files=3`）拿到的是
> "录制被中断"的糊帧，与参考图相关性只有 +0.085…+0.113，会得出完全错误的结论。

### 6.5 负载安全（不违反 m01938 的教训）

Cheese 持续取帧时的实测（[scripts/zz_stream_cpu.sh](../scripts/zz_stream_cpu.sh)）：

| 指标 | 值 |
|---|---|
| 帧率 | **2.15 fps**（`arm_count` 124 → 167 / 20 s） |
| `cam_cap_v4l2` 内核线程 | **88.1% 的单个核**（top 采样；另一次测得 87.6%） |
| cheese / kwin / plasmashell | 6.9% / 4.0% / 4.0% |
| `load average` | **1.10 / 1.16 / 1.15**（8 核） |

⇒ **总共只吃约 1 个核**，不会重演 m01938 那种"多任务吃满 5 个核导致整机卡死"。检查脚本
[scripts/zz_st2.sh](../scripts/zz_st2.sh)、[scripts/zz_stream_cpu.sh](../scripts/zz_stream_cpu.sh)。

---

## 7. 已知限制（诚实清单）

| 限制 | 说明 |
|---|---|
| 分辨率 | 2000×1500（4000×3000 做 2×2 binning）。全分辨率请改 `out_width=4000 out_height=3000`，CPU 时间 ~4×，帧率掉到 ~2 fps |
| 帧率 | 约 8 fps 上限（受 CAMSV 单帧流程 + CPU 转换限制）；Cheese 里约 2 fps |
| 曝光 | **`0x0202` 是完整 16 位积分时间**，实测到 `0x6000` 仍线性（旧笔记"`0x0380` 封顶"是错的，见 §9.2）。上限由 `exp_max` 控制，默认 `0x3000` |
| 增益 | **`0x0204` 只保留低 10 位（掩码 `0x3ff`）**，可用 `0x0100..0x03f0`（≈0.5×..4.9×）；但 `0x03a0` 以上码→光量的曲线很陡（`0x03c0`≈2.0×，`0x03f0`≈4.9×），所以 AE 上限默认压在 `0x03a0`。`0x0f00`/`0x3f00` 会被静默截成 `0x0300` |
| 自动控制 | **AE/AWB 闭环已在驱动内实现**（§9）；没有 ISP，仍是纯软件 |
| 画质算法 | 无 LSC、CCM、去噪、锐化、HDR（ISP 才有，见 ISP 文档）；反马赛克后没有专门的降噪 |
| 缓冲 | 只申请一块 18 MiB CMA（32 MiB 池），所以**不要把 `frame_bytes` 设得更大**，也不要加载第二份 |
| 重启后 | V4L2 地基模块与 `cam_cap` **都需要重新 insmod**（没有 `/lib/modules` 自动加载） |
| 画质算法 | 无 LSC、CCM、去噪、锐化、HDR（ISP 才有，见 ISP 文档） |
| 缓冲 | 只申请一块 18 MiB CMA（32 MiB 池），所以**不要把 `frame_bytes` 设得更大**，也不要加载第二份 |
| 重启后 | V4L2 地基模块与 `cam_cap` **都需要重新 insmod**（没有 `/lib/modules` 自动加载） |

---

## 8. 相关文件与脚本

| 路径 | 作用 |
|---|---|
| [src/cam_cap.c](../src/cam_cap.c) | CAMSV + V4L2 采集驱动 + 驱动内 AE/AWB（约 3620 行） |
| [out/camcap_0b8dd2e/cam_cap.ko](../out/camcap_0b8dd2e/cam_cap.ko) | 当前 `.ko`（728 112 B） |
| [out/v4l2/](../out/v4l2/) | `mc.ko` / `videodev.ko` / `videobuf2-*.ko` |
| [scripts/zz_v4l2_test.sh](../scripts/zz_v4l2_test.sh) · [zz_v4l2_run.sh](../scripts/zz_v4l2_run.sh) | 设备侧/PC 侧一键测试 |
| [scripts/zz_v4l2_state.sh](../scripts/zz_v4l2_state.sh) | 只读状态勘察（模块、`/dev/video*`、CMA、内存） |
| [scripts/zz_cheese_install.sh](../scripts/zz_cheese_install.sh) · [zz_cheese_run.sh](../scripts/zz_cheese_run.sh) | 装/起 Cheese |
| [scripts/render_yuyv.py](../scripts/render_yuyv.py) · [check_v4l2_orient.py](../scripts/check_v4l2_orient.py) | 渲染与方向校验（Windows Python） |
| [scripts/zz_app_run.sh](../scripts/zz_app_run.sh) · [zz_ctrl_run.sh](../scripts/zz_ctrl_run.sh) | 通用"把脚本推到设备上执行"的跑腿脚本（后者同时推 `.ko`） |
| [scripts/zz_cal1.sh](../scripts/zz_cal1.sh) · [zz_cal2.sh](../scripts/zz_cal2.sh) | 传感器响应标定（`point <exp> <again> <dgain>`，直写 I²C + `/proc/camcap`） |
| [scripts/zz_plant.sh](../scripts/zz_plant.sh) | 关掉 AE 做单步响应测量（被控对象是否平滑单调） |
| [scripts/zz_ae6.sh](../scripts/zz_ae6.sh) · [zz_ae7.sh](../scripts/zz_ae7.sh) | AE/AWB 验收（重载 + 收敛 + 改目标 + AWB 开关 + 存帧） |
| [scripts/zz_i2cdiag.sh](../scripts/zz_i2cdiag.sh) | I²C 适配器名/`dmesg` 诊断 |
| [docs/ISP_FEASIBILITY.md](ISP_FEASIBILITY.md) | ISP 可行性评估（结论：接不上，附三条硬证据） |
| [docs/CAMERA_CAPTURE_WORKING.md](CAMERA_CAPTURE_WORKING.md) | CAMSV 抓帧全流程与 12-bit 规范 |

---

## 9. 驱动内 AE/AWB 闭环 + V4L2 控件（2026-10-06 晚）

> 目标：让相机在**没有 ISP** 的前提下自己把亮度/白平衡调好，并把旋钮暴露给应用
> （`v4l2-ctl`、Cheese 之类）。所有代码在 [src/cam_cap.c](../src/cam_cap.c)，
> 全部改动都能只重编模块、不需要重编内核。

### 9.1 十个 V4L2 控件（`v4l2-ctl -d /dev/video0 --list-ctrls` 实测）

| 控件 | 范围 | 开机值 | 作用 |
|---|---|---|---|
| `brightness` | -128..128 | 0 | 色调曲线上的**加性**偏置（`×16` 个 12-bit 码） |
| `contrast` | 0..255 | 128 | 绕中灰 2048 的对比度（128 = 不变） |
| `saturation` | 0..255 | 128 | 只作用在 YUYV 的 U/V 上 |
| `white_balance_automatic` | 0..1 | 1 | 1 = AWB 闭环；0 = 用手动 `red/blue_balance` |
| `red_balance` / `blue_balance` | 128..1024 | 263 / 614 | Q8 白平衡（128 = 0.5×，256 = 1×，1024 = 4×）；**AWB 在跑时这两个会被驱动每帧回写** |
| `auto_exposure` | menu 0..3 | 0 (Auto) | 1 = 手动（`V4L2_EXPOSURE_MANUAL`） |
| `exposure_time_absolute` | 16..12288 | 896 | 直接写 `0x0202`（积分时间，单位 = 行） |
| `analogue_gain` | 256..928 | 768 | 直接写 `0x0204`（低 10 位） |
| `digital_gain` | 256..4096 | 1024 | 直接写 `0x020e` |

接线方式：`cam_ctrl_init()` 建 handler 并把 `c->vdev.ctrl_handler` 指过去：
`v4l2-dev.c` 注册时会自己取用（`if (vdev->ctrl_handler == NULL) vdev->ctrl_handler = vdev->v4l2_dev->ctrl_handler;`），
`v4l2-ioctl.c` 的 QUERYCTRL/G_CTRL/S_CTRL 也就跟着能用了。

**回调里绝不能调公共 `v4l2_ctrl_*`**：`s_ctrl` 回调是在持有 handler 锁的情况下被调用的，
再调 `v4l2_ctrl_s_ctrl()` 会自死锁。回调只改影子状态 + 置 `cam_lut_dirty`，
真正的 I²C 写和 4096×3 的查表重建都放到采集内核线程里做。

### 9.2 传感器上限（标定定案，推翻了旧笔记）

| 寄存器 | 旧结论 | 实测结论 |
|---|---|---|
| `0x0202` 曝光 | "`0x0380`（≈16 ms）封顶" | **完整 16 位**：`0x0020→260`、`0x0380→386`、`0x0d00→736`、`0x2000→1315`、`0x6000→2638`（clip 31%）：到 `0x6000` 仍线性 |
| `0x0204` 模拟增益 | "`0x0300` 是天花板，`0x0f00` 被截断" | **只保留低 10 位（掩码 `0x3ff`）**：`0x0300→385`、`0x0320→404`、`0x0340→429`、`0x0380→516`、`0x03a0→599`、`0x03c0→764`、`0x03f0→1903`。`0x0f00 & 0x3ff = 0x0300`、`0x3f00 & 0x3ff = 0x0300` ⇒ 那两条"怪现象"只是掩码 |
| `0x020e` 数字增益 | — | 15 位线性乘子（`0x0100`=0.25×、`0x0400`=1×、`0x1000`=4×），扣掉 ~240 基座后很干净 |

⇒ 默认 `exp_max=0x3000`、`again_max=0x03a0`（模拟增益比数字增益干净，但 `0x03a0` 以上曲线陡增，
配合死区会振荡）、`dgain_max=0x1000`。

**AE 关掉时的被控对象是平滑单调的**（[zz_plant.sh](../scripts/zz_plant.sh)，每点稳 4 帧）：

```
数字增益 @ exp=0x3000 again=0x0300:  0x0100→699  0x0155→834  0x0200→1080  0x0300→1414
                                     0x0400→1721 0x0600→2242 0x0800→2623 0x0c00→3065 0x1000→3340
曝光     @ again=0x0300 dgain=0x0200: 0x0300→311  0x0600→366  0x0c00→476  0x1800→696
                                     0x2000→830  0x2800→954  0x3000→1073
```
（请求 `digital_gain=0x40/0x80` 时打印出来还是 `0x0100`：那是 V4L2 控件的 min 钳掉的，不是硬件）

### 9.3 ★ 三个真 bug（都很贵）

1. **I²C adapter 名写成了设备树节点名**。`i2c_name` 原默认 `"11d05000"`，而总线 10 的 adapter 名是
   **`i2c-mt65xx`**（设备上 8 条 mtk 总线全叫这个名）⇒ `strstr(adap->name, i2c_name)` 永远失败，
   `cam_sensor_apply()` 静默 return。症状极具迷惑性：**AE 把旋钮拧到天花板、`frames` 一直涨，
   但 `hw=(0x0000,0x0000,0x0000)`、`stats` 一动不动**（dmesg 原文
   `cam_cap: adapter 10 is 'i2c-mt65xx', which does not contain '11d05000'`）。
   已改成默认 `"i2c-mt65xx"` + 只告警一次（原来每帧刷一行）。
2. **AWB 目标公式把当前增益又乘了一遍**：`tr = cam_wb_r_cur * mean_g / mean_r` ⇒ 每帧再乘 ~1.07，
   指数跑飞，实测 `wb_r/wb_b` 一路顶到 4.00。正确式子是**去基座的绝对目标**
   `tr = 256 * (G-black) / (R-black)`。基座这件事量级极大：本场景 `r/g/b = 359/385/309`、基座 248 ⇒
   `(R-black)=111、(G-black)=137、(B-black)=61` ⇒ `tr=316、tb=575`，正好接近手工调好并被验收的 263/614。
   **这就是旧笔记里"蓝通道要吃 2.40× 增益"的来源：基座占了红信号本身的 69%。**
3. **AE 极限环**：`clip > ae_clip_pct` 曾经是个硬覆盖：只要有过曝就强制回退，哪怕均值已经在死区里。
   本机上**一个模拟增益码换来的光量远大于死区宽度**（`again=0x032c` → 均值 783，`again=0x03a0` → 均值 1296），
   于是 `0x032c ↔ 0x03a0` 无限对跳。用 `ae_trace=1` 抓到的原始证据：

   ```
   cam_ae: mean=1296 clip=4 ... f=224 up=0 again 0x03a0->0x032c
   cam_ae: mean=783  clip=1 ... f=455 up=1 again 0x032c->0x03a0
   cam_ae: mean=1297 clip=4 ... f=224 up=0 again 0x03a0->0x032c
   ```
   修法：**过曝只在均值超出死区时才有资格推动环**（它只决定回退的幅度，不再决定方向）。
   另外还有一条：传感器寄存器只对"写入之后才开始积分"的那一帧生效，而帧周期很长
   （积分时间本身可到 12288 行）⇒ 每帧都纠正等于控制一个滞后一环的对象。
   现在每次改动后**跳过 `CAMCAP_AE_SETTLE`(=2) 帧不再纠正**（`cam_sensor_apply()` 仍然每帧做，幂等）。

### 9.4 控制律

* 先换到**去基座信号域**：`sig = mean_g - 248`，`tgt = ae_target - 248`，`f = tgt/sig`（Q8 期望倍率）。
* **死区** `[ae_target-ae_band, ae_target+ae_band]` 内不动（`ae_band` 默认 120 ≈ ±10%）。
* 每帧**只动一个旋钮**；升序 **曝光 → 模拟增益 → 数字增益**（积分时间不损 SNR，数字增益最差），降序相反。
* 步长按误差比例，并按旋钮封顶：曝光 ≤ ×2，增益 ≤ ×1.25；回退方向每步 ≤ -20%。
* 跳帧：改动后 2 帧不纠正（§9.3 的滞后）。
* AWB：灰世界，每帧只走误差的 `1/2^awb_rate`，钳 128..1024，`mean_g < awb_min_level` 时冻结。

### 9.5 闭环实测（[scripts/zz_ae6.sh](../scripts/zz_ae6.sh) / [zz_ae7.sh](../scripts/zz_ae7.sh)）

从"手动压到最暗"（`exp=0x0040 again=0x0100 dgain=0x0100`）交给 AE，它走
`0x0040→0x0080→0x0100→…→0x3000`（曝光一路翻倍）→ 再爬模拟增益 `0x0100→0x0140→…→0x03a0`：

| 检查 | 结果 |
|---|---|
| 收敛后是否还在动 | `frames=14` 在 **120 帧**里**一次没变** ✅ |
| 改目标 1800 | 落到 `again=0x03a0 dgain=0x018a`，均值 **1739**（死区 1680..1920）✅ |
| 改目标 700 | 落到 `again=0x032c`，均值 **787**（死区 580..820）✅ |
| 改回 1200 | 落到 `again=0x03a0 dgain=0x0100`，均值 **1304**（死区 1080..1320）✅ |
| AWB 关 → 开 | `wb 1.00/1.00` → `1.15/2.00` → `1.19/2.22` 重新收敛 ✅ |
| 存一帧渲染 | `Y mean 186.6`，RGB 均值 **180/189.5/184**（对比：旧手调固定参数那版只有 63/61/53）✅ |

⇒ 收敛不需要"外挂脚本反复调"；开机就是 Auto，改目标/改控件立刻跟随。

### 9.6 怎么用

```sh
# 看现状
v4l2-ctl -d /dev/video0 --list-ctrls
grep -E '^(ae|awb|stats)' /proc/camcap_info

# 手动曝光（先关 AE）
v4l2-ctl -d /dev/video0 -c auto_exposure=1 -c exposure_time_absolute=3000 -c analogue_gain=768

# 交回 AE，40 帧看它收敛（1 帧 ≈ 0.47 s）
v4l2-ctl -d /dev/video0 -c auto_exposure=0
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=40

# 排障：打印每次修正（默认关）
insmod /root/cam_cap.ko v4l2_enable=1 ae_trace=1
dmesg | grep cam_ae | tail -20
```

**判"闭环成立"的唯一标准是 `ae: … frames=` 不再增长**，不是画面看起来稳：
`/proc/camcap_info` 的 `stats` 行给的是每帧 93 750 个 2×2 块的 RGB 均值/最值/clip%/dark%。

---

## 10. 2026-10-06 深夜 II：过曝修复 + 4 线程并行转换 + 开机自起

用户 m05019 的三项要求（①②③）在这一节收尾。三项都有**可复算的数字**，不是"看起来好了"。

### 10.1 ① 过曝：两个原因，各修一处

| 原因 | 旧值 | 新值 | 为什么这就是过曝 |
|---|---|---|---|
| `v4l2_gain_q8` | `768`（3.0×） | `256`（1.0×） | 这是一个**加在 sqrt 色调曲线之前**的线性前置增益：3.0× 先把亮部顶到 4095，后面 sqrt/clamp 再压也回不来 |
| `ae_target` | `1200` | `1000` | 目标本身落在亮部，和上面的 3.0× 叠加 |

定量判据（[scripts/clip_compare.py](../scripts/clip_compare.py)，都按 2000×1500 YUYV 统计）：

| 帧 | Y 均值 | Y std | Y==255 占比 | Y≥250 占比 | RGB 任一 ==255 |
|---|---|---|---|---|---|
| 旧（`frames/v4l2_ae.yuyv`） | 186.55 | 60.37 | **19.43 %** | 26.21 % | 高 |
| 新（`frames/settled.yuyv`） | 95.92 | 45.40 | **0.00 %** | 1.87 % | 0.03 % |

⇒ **一个 255 都没了**（最亮的窗格也只到 250）。**别再拿"看着亮不亮"判断，用 `Y==255` 占比。**

### 10.2 ③ 多核均衡解码：2.25 → 4.36 fps

一帧输出被按行切成 `nconv` 段，每个 worker 独立跑完整的 **fused** 转换（2×2 binning + RGGB 反马赛克 +
三条 LUT + 饱和度 + FLIP180 + YUYV 打包），`cam_convert_frame()` 等齐 `nconv` 个 completion 才交帧。

| `conv_threads` | `conv` | `period` | fps（20 帧/点） |
|---|---|---|---|
| 1（内联） | 401.3 ms | 444.3 ms | 2.25 |
| 2 | 204.8 ms | 296.4 ms | 3.37 |
| **4** | **106.7 ms** | **218.7 ms** | **4.57** |
| 8 | 114.3 ms | 217.0 ms | 4.60 |

⇒ **4 是拐点**：8 线程 `conv` 反而更慢（≈114 ms）：**超过 4 就已经是内存/延迟受限，不是算力受限**。
`arm`（硬件等待 ≈53–70 ms）与 `gov`（AE/AWB 统计 ≈53–66 ms）是**串行**开销，所以 4 线程时
`period ≈ arm + conv + gov`。Cheese 实测 `avg fps=4.36`（旧版 2.15）。

**正确性（无接缝）**：相同手动参数下 `conv_threads=1` 与 `=4` 各抓一帧，
分带边界 y=375/750/1125 处的行均值跳变是 **0.113 / 0.163 / 0.189**，
而全图行跳变中位数 0.140、p99 1.210（对照组 0.311/0.267/0.351）⇒ 边界完全淹没在噪声里。
判据脚本 [scripts/check_bands.py](../scripts/check_bands.py)。

**安全**：worker 全部 `set_user_nice(task, 10)`；`cam_convert_frame()` 用
`wait_for_completion_timeout(2*HZ)`，超时就 `pr_warn_once` + 内联兜底（相机不会永久挂住）。
4 线程满载时 `/proc/loadavg` 0.29–0.93（8 核）、`top` 80–87 % idle，plasma/kwin 照常。

**这一节踩的两个真 bug（代价 = 两次把机器搞到重启，务必看）**：

1. `cam_convert_frame()` 只等了**一个** completion，但 `nconv` 个 worker 各完成一次 ⇒
   拿着只转好一部分的 buffer 就交给用户态，并且**上一帧还在跑就发布下一帧**，
   整池变成常驻满速负载，把 sshd 饿死。
   **症状是"ping 得通但 ssh 超时"**（不是死机）：用 `ping` 区分。
   修法：`for (i = 0; i < c->nconv; i++) wait_for_completion(&c->conv_done);`
   （`reinit_completion()` 把 `done` 置 1，等 nconv 次后计数正好回到 1，前后自洽）。
   为此每个 worker 还要 `set_user_nice(..., 10)` 兜底，保证 8 核全忙时 ssh/桌面仍有时间片。
2. **`c->conv_wq` 从来没有 `init_waitqueue_head()`** ⇒ 第一个 worker 进 `wait_event_interruptible`
   就在 `prepare_to_wait_event()` 里踩 NULL 链表头：
   ```
   Unable to handle kernel paging request at virtual address ffffffffffffffe8
   ESR = 0x0000000096000006   FSC = 0x06: level 2 translation fault
   CPU: 0  PID: 2401  Comm: cam_conv/0
   pc : prepare_to_wait_event+0x84/0xfc
   Call trace: cam_conv_thread+0x74/0x11c [cam_cap] → kthread → ret_from_fork
   ```
   故障地址正好是 `NULL-24`、`x0=x1=0`。**两次崩溃都是它**（8 线程那次 Oops 没来得及落盘就被硬复位，
   所以第一次看起来像"说不清的卡死"）。修法：`cam_v4l2_register()` 里
   `init_waitqueue_head(&c->conv_wq);` + `init_completion(&c->conv_done);`。

⇒ 教训：**`kzalloc` 清零的 `wait_queue_head` 不是"空队列"，是一个坏掉的链表头**；
任何 `kthread` 等的事件对象都必须在注册路径上显式初始化，不能靠 BSS 默认值。

### 10.3 ② Cheese「无法连接摄像头」：开机自起 + 一键复位

"无法连接"只有两个成因，都堵掉了：

| 成因 | 现象 | 现在的处理 |
|---|---|---|
| 重启后模块没了 | `/dev/video0` 根本不存在；手工 `insmod cam_cap.ko` 报 `Unknown symbol vb2_*` | `cam-camera.service` 开机自动跑完整 bring-up |
| 有进程还占着 `video0` | 新实例 `Device or resource busy`（测试流、上一次 cheese 都算） | 服务启动时先放掉旧占用；`cam_reset.sh` 手动一键复位 |

**单元** `/etc/systemd/system/cam-camera.service`（`enable` 已置）：

```ini
[Unit]
Description=K50 IMX582 camera bring-up (sensor rails + V4L2 stack)
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/cam_boot.sh
TimeoutStartSec=240
Nice=10

[Install]
WantedBy=multi-user.target
```

`After=multi-user.target` 是故意的：桌面先起来，相机栈跟在后面，**再慢也不拖登录**；
`oneshot` + 240 s 上限意味着即使 bring-up 卡住也只是这一个单元超时，不会拖住启动。

`/root/cam_boot.sh` 做四件事：等 `debugfs-pinctrl` 与 `/dev/i2c-10/11` → 放掉 `video0` 旧占用 →
`zz_v80.sh`（导轨/MCLK/fan53870 LDO6/7/reset/DPHY/CSI2/IMX582 init）→ `zz_cam_up.sh`（V4L2 地基 + `cam_cap`）。
日志 `/var/log/cam_boot.log`。失败**不阻塞**：桌面照常，`sh /root/cam_reset.sh --full` 重试。

**冷启动演练**（[scripts/zz_coldboot_test.sh](../scripts/zz_coldboot_test.sh)，不必真重启）：
把 cam_cap + 7 个地基模块 + 厂商 `cam_*` 全部 `rmmod`（确认 `/dev/video0` 消失、cam 模块计数 0），
然后跑 `sh /root/cam_boot.sh`：

```
=== 6. IMX582 id on i2c-10 @0x10 ---   IMX582 ALIVE
cam_boot took 20 s
RESULT: ok  /dev/video0 cam_cap
conv_threads = 4   v4l2_enable = Y   frame_bytes = 18874368
capture: <<<<<< 4.61 fps   stats n=93750 r=848 g=981 b=557 clip=2%
```

⇒ 这一步覆盖了真实开机的全部软件动作（唯一没覆盖的是 systemd 自己的启动时序；
因为单元已 `enable`、`ExecStart` 就是同一个脚本、执行时间 20 s 远小于 240 s 上限）。

**一键复位** `/root/cam_reset.sh`：

```sh
sh /root/cam_reset.sh          # 快路径：重载 V4L2 栈（传感器已经上电）
sh /root/cam_reset.sh --full   # 连传感器 bring-up 一起重做（画面全黑/刚重启过）
```

### 10.4 分辨率与"假活"的两个判据（别再上当）

- **帧率**看 `/proc/camcap_info` 的 `avg` 行（`fps=XX.YY`，由实测 period 反算），
  不要靠秒表数画面。
- **Cheese 是否真在跑**只看 `arm_count` 是否持续增长：Cheese 有一种"假活"状态
  （进程/fd/`streaming` 都在，但 6 帧后不再排队，CPU 掉到 2.5 %）。判据脚本
  [scripts/zz_cheese_check.sh](../scripts/zz_cheese_check.sh) 采样 8 次 `arm_count`。
  重启 Cheese 即恢复。

### 10.5 本节新增的文件

| 文件 | 作用 |
|---|---|
| `scripts/cam_boot.sh` | 设备 `/root/cam_boot.sh`：开机 bring-up（服务 ExecStart） |
| `scripts/cam_reset.sh` | 设备 `/root/cam_reset.sh`：一键复位（`--full` 连传感器） |
| `scripts/zz_install_service.sh` | 写单元文件 + enable + start + 自检 |
| `scripts/local_install_cam_service.sh` | 推送 ko/脚本并安装服务 |
| `scripts/zz_coldboot_test.sh` | 全卸载 → 跑 cam_boot.sh → 抓帧的冷启动演练 |
| `scripts/zz_cheese_check.sh` | Cheese 活性（`arm_count` 增长）+ 负载 |
| `scripts/zz_perf5.sh` / `local_perf_matrix.sh` | 帧率矩阵（逐点重载 `conv_threads`） |
| `scripts/zz_load4.sh` | 流中负载采样 |
| `scripts/zz_verify.sh` / `check_bands.py` | 分带无接缝取证 |
| `scripts/clip_compare.py` | 过曝定量（`Y==255` 占比） |
| `scripts/zz_settle_shot.sh` | 60 帧长跑 + AE 收敛帧 |

---

## 11. 2026-10-06/07 深夜 III：双缓冲流水线 → **30 fps 达标** + 红蓝真凶（色度槽顺序）

### 11.1 结果（真机实测，200 帧 / 100 帧长跑）

| 场景 | 帧率 | 备注 |
|---|---|---|
| 冷启动，`conv_threads=4`，200 帧 | **32.73 fps** | `avg : period=30782us arm=30420us conv=20028us gov=30us fps=32.48 frames=200 pipe=200` |
| 同上 `conv_threads=6` / `8` | 32.52 / **33.27 fps** | 8 线程把 conv 压到 18.4 ms，收益有限 |
| 重载后 100 帧（两轮） | **32.47 / 33.18 fps** | `dist : clean(<32ms)=95 late(32-40ms)=4 slip(40-58ms)=3 lost(>=58ms)=0` |
| **暗房复核**（`dark=37%`，AE 三档全顶格 `exp=0x0c64 again=0x03a0 dgain=0x1000`） | **32.5 fps 不掉** | 旧故障模式（曝光顶到 VTS）会掉到 ~9 fps |

帧周期 = 传感器原生周期（VTS 3300 ⇒ 30.2 ms），20 ms 的转换**完全藏进**传输窗口，转换线程不再是瓶颈
（串行结构下 arm 50.6 ms + conv 33.6 ms 只能到 ~20 fps，见 §10.2）。

### 11.2 结构：arm 与 convert 解耦

- `pipeline=1`：两个 18 MB 槽。arm 线程只做"武装下一帧 + 等 IMGO_DONE"，`cam_cap_conv` 线程拿上一帧做转换，
  两者重叠；`pipe_frames` 在 `/proc/camcap_info` 的 `avg` 行可见（应等于总帧数）。
- 第二个槽 `cam_slot1_alloc()`：`alloc_contig_pages()` 拿物理页 + 在 CMA 的 IOVA 空间里 `iommu_map`
  （第一块仍是 `dma_alloc_coherent`，两块的物理地址与 IOVA 都会打进 dmesg 的 `pipeline:` 行）。
- 帧完成 → `cam_v4l2_finish_slot()` 里 `cam_convert_frame()` 之后**立刻** `s->busy = false; wake_up(&c->pipe_wq)`
  （比放在转换线程里早 ~1.5 ms，正好是抢下一帧起点所需的余量）。
- arm 内部改成细粒度 `usleep_range` 轮询：arm 从 50.6 ms 降到 30.1 ms（原来一等多等一个完整周期）。
- 排障：`/proc/camcap` 的 `probe` 与 `burst <n>` 命令（burst = 连续 arm、不转换、打均值/min/max 上限）。

### 11.3 ★ 帧率的真正杠杆是 VTS（不是转换线程数）

| VTS（行） | 寄存器 | 实测 fps | 备注 |
|---|---|---|---|
| 3658 | `0x0e4a` | 30.2（burst 上限 28.74，有双周期停顿） | 贴着 30 这条线，机器一忙就掉下去 |
| 3570 | `0x0df2` | 30.9 | |
| 3500 | `0x0dac` | 32.2 | 曾经选定 |
| **3300** | **`0x0ce4`** | **32.5–33.3** | **当前选定**：周期 30.2 ms、天花板 33.5 fps，余量最足 |
| 3400 | `0x0d48` | 32.0 | 再往下没有收益（地板 ~31 ms） |

- 行时间 ≈ **9.04 µs/行**（7872 HTS / 864 MHz pclk），所以周期 ≈ VTS × 9.04 µs。
- **`exp_max` 必须 = VTS − 128**（当前 `0x0c64` = 3172）。曝光 > VTS 时传感器把帧周期拉长到曝光时间，
  这就是旧默认 `0x3000` 下暗房只有 9 fps 的原因。bring-up（`scripts/imx582_bring.py:52`）与驱动默认值**必须一起改**。
- 手动曝光扫描（20 帧/档，`exp` 从 `0x0dac` 扫到 `0x0380`）**不单调**：fps 26.5–33.1 ⇒ 抖动主要来自
  调度/循环，而不是简单的 stretch；同状态下两次 60 帧长跑就有 ±2 fps 的差异。
- `/proc/camcap_info` 的 `dist` 行是帧周期直方图：`clean(<32ms)` / `late(32-40ms)` / `slip(40-58ms)` / `lost(>=58ms)`
  ⇒ 用来看"平均 fps 还行但其实在丢帧"的情况（当前 ~93 % clean、~3 % slip）。
- ⚠️ **只在 30 fps 一族里 VTS 才是主要杠杆**：短帧模式（1080p120/240、4K60）的真正下限曾经是我们自己的
  `msleep()` 轮询量化，见 [§12.2](#122--上一节高帧率档只有标称-23是自己造的假象msleep5-的-jiffy-量化)。

### 11.4 ★ 红蓝互换的真凶：YUYV 色度槽顺序（不是 Bayer 相位）

**现象**：整幅 R↔B 互换（青绿变金色）。先排除的两个假设：

- **不是 RYYB**：两个"绿" tap 的均值只差 1.6 %（433.6 vs 430.9），RYYB 会让两个 Y(R+G) tap ≈ 2× R。
- **不是 Bayer 相位**：单纯翻 Bayer 标签在灰世界上几乎不可见（gray-world AWB 把增益一致地镜像过去，
  落在同一物理 tap 上的有效增益完全相同）：本地两帧逐字节对比 RGB 平均只差 6.4（≈2.5 %）。

**真 bug**：为 180° 翻转，代码把一对里的**亮度**字节写反（`q[0]=y1, q[2]=y0`，这一条没错），
但色度槽固定写成 `q[1]=v(Cr), q[3]=u(Cb)`。YUYV 的一对里只有**一个 Cb 一个 Cr**，
**byte1 必须永远是 Cb、byte3 永远是 Cr**，与哪个 Y 在前无关。旧代码在 `rb_swap=0` 时
（u=Cb、v=Cr）就把 byte1 写成了 Cr ⇒ **真正的 Cb/Cr 互换**，正是用户看到的现象；
`rb_swap=1`（系数矩阵反过来）时 u 恰好是 Cr、v 是 Cb，歪打正着写对了，所以它看起来"正常"。

**修复**（代数上完全保画面 ⇒ 不改变用户已确认"正常"的那个画面）：

1. 色度槽跟着 `rb_swap` 一起翻，两个取值都自洽；
2. `rb_swap` 默认改 `N`（与厂商 `src/imx586_Sensor.c:256` 的 `SENSOR_OUTPUT_FORMAT_RAW_4CELL_HW_BAYER_R` = RGGB、
   `.mirror = IMAGE_NORMAL` 一致）；
3. `wb_r_q8`/`wb_b_q8` 默认改 `320`/`434`（RGGB 的灰世界解）。

**独立物理定案 (0,0) tap = 红（RGGB）**：AWB 关 + 已知色偏，看 wire 的 byte1/byte3 谁越过 128：

| 帧 | 构建 | 物理操作 | byte1 (Cb) | byte3 (Cr) | RGB 均值 |
|---|---|---|---|---|---|
| `old_rb1_physR` | 旧（`rb_swap=1`） | `blue_balance=512` ⇒ 物理 R ×2 | 99.4 | **152.6** | R 166.8 G 124.5 B 81.6 |
| `new_rb0_physR` | 新（`rb_swap=0`） | `red_balance=512` ⇒ 物理 R ×2 | 96.6 | **148.1** | R 175.4 G 143.5 B 91.5 |
| `new_rb1_physB` | 新（`rb_swap=1`） | `red_balance=512` ⇒ 物理 B ×2 | 122.5 | 124.7 | R 93.0 G 102.0 B 87.9 |

前两行都给出 `byte3 > 128 > byte1`、画面发红 ⇒ wire 顺序正确，且**同一物理操作在修复前后特征一致**
（修复保画面）；第三行说明 `rb_swap` 确实切换了色度矩阵（不是空操作）。
另外一个副作用修好了：旧构建里"加红"要用 `blue_balance`，现在 `red_balance` 名副其实是红。

### 11.5 本节新增/更新的脚本

| 文件 | 作用 |
|---|---|
| `scripts/zz_vts.sh` | VTS 扫描（`i2ctransfer -y -f 10 w4@0x10 <reg_hi> <reg_lo> <d_hi> <d_lo>`，**必须一次 4 字节**） |
| `scripts/zz_period.sh` | 手动曝光扫描 + 稳态 60 帧 |
| `scripts/zz_coldstart.sh` | rmmod → `zz_v80.sh` → `zz_cam_up.sh` → 读 VTS → 40 帧 + burst |
| `scripts/zz_reload30.sh` | 只重载模块 + 100 帧 + `dist` + 崩溃扫描 |
| `scripts/zz_final30.sh` | 冷启动 + 200 帧 × 4/6/8 线程 + 直方图 + 存帧 |
| `scripts/zz_rbfix.sh` | 强色偏无眼判别（关 AWB + 已知色偏 + 抓帧） |
| `scripts/zz_state.sh` | 只读状态检查（模块/进程/kthread/loadavg），排障第一步 |
| `scripts/imx582_bring.py` | 第 52 行写 HTS 7872 + **VTS 3300** |

### 11.6 诚实限制

- 30 fps 是**这个传感器模式**（4000×3000 RAW10 进、2000×1500 YUYV 出）的上限；再快只能换模式
  （vendor 表里有 1920×1080@120、4K@60 等，但要重做整条 bring-up，风险最大）。
- 输出仍是 2000×1500（CAMSV 2×2 binning），不是全分辨率。
- 暗光下 AE 三档全顶格时画面仍然偏暗（想更亮可以抬 `again_max`/`dgain_max`，用噪声换亮度）。
- 帧率随机器负载有 ±2 fps 抖动（`slip` 桶 ~3 %）。

---

## 12. 2026-10-07 凌晨 IV：**7 个 sensor 模式全部跑通** + 一个被自己造出来的假"帧率地板"

这一节回答 m06738「所有录制规格能不能都做出来」：先给结论，再给证据，最后给还差什么。

### 12.1 结论（真机实测，每个模式都是独立一次 bring-up）

| 录制规格 | sensor 模式 | 表里标称 | **实测出流** | burst 下限⇒传感器真实上限 | 驱动输出 |
|---|---|---|---|---|---|
| 4K30（4000×3000 4:3） | `preview`（VTS 改 3300） | 30 | **32.6–33.6 fps** | 30.1 ms ⇒ 33.2 | 2000×1500 |
| 4K30（4000×2256 16:9） | `normal_video` | 30 | **30.7 fps** | 32.8 ms ⇒ 30.5 | 2000×1128 |
| 4K30（1:1 裁切） | `custom5` | 30 | **30.3 fps** | 34.1 ms ⇒ 29.3 | 2000×1500 |
| **4K60** | `custom3` | 60 | **54.9–55.8 fps** | **16.06 ms ⇒ 62.3** | 2000×1128 |
| **1080p120** | `custom2` | 120 | **120.3 fps** | **7.96 ms ⇒ 125.6** | 960×540 |
| **1080p240** | `hs_video` | 240 | **167.0 fps** | **4.02 ms ⇒ 248.7** | 960×540 |
| 48MP 静态 | `custom4` | 15 | ✗ 未跑（60 MB/帧 > CMA 32 MB） | — | — |

- `capture`/`slim_video`/`custom1`/`custom6` 四张 vendor 表是空的 ⇒ 这块 IMX582 **只有这 7 个模式**。
- 每个模式的寄存器都是**照表生效**的（`scripts/zz_regs.sh` 复核 HTS/VTS/输出窗/crop/PLL/MIPI 全部一致）。
- 帧率模型：`pclk = 4.8 MHz × ((0x0306<<8)|0x0307)`、`周期 = HTS×VTS/pclk`。**非 binning 模式精确成立**
  （preview 864 MHz ⇒ 9.11 µs/行、custom5 30.0 fps），binned 模式只在 VTS 大于传感器读出地板时成立。

### 12.2 ★ 上一节"高帧率档只有标称 2/3"是**自己造的假象**：`msleep(5)` 的 jiffy 量化

第一遍测 custom3/custom2/hs_video 时，实测只有 40.6 / 75.0 / 83.0 fps，而且**把 VTS 从 1236 改到 2472
帧周期一动不动（都是 12.0 ms）**，看起来像"传感器有 12 ms 读出地板"。

真因在 `cam_cap_arm_addr()` 的完成轮询里：

```c
else if (elapsed < 20000000LL)
        msleep(CAMCAP_ARM_POLL_MS);   /* = 5，HZ=250 ⇒ 一觉一个 jiffy 4 ms 起 */
```

- `msleep()` 按 jiffy 向上取整 ⇒ 完成时刻被量化到 tick 的整数倍。30 fps 模式的帧（30 ms）比 tick 长得多，
  所以只损失零点几毫秒；但 1080p240 的帧只有 4.2 ms、4K60 只有 16.7 ms，**整个帧都落在粗睡窗口里** ⇒
  测到的是"tick 周期"，不是传感器周期。VTS 怎么改都不动，因为 tick 与 VTS 无关。
- 修复：完成轮询**一律亚 jiffy**： `usleep_range(150, 250)`（删掉 `msleep` 与 20 ms 分段，删掉
  `CAMCAP_ARM_POLL_MS`）。每次轮询只多两次 MMIO 读（~1 µs），CPU 代价可忽略。

| 模式 | 修复前出流 | **修复后出流** | burst 最小周期 |
|---|---|---|---|
| `custom3` 4K60 | 40.64 | **54.9 / 55.8** | 16.06 ms（62.3 fps，标称 16.7 ms） |
| `custom2` 1080p120 | 75.01 | **120.30** | 7.96 ms（125.6 fps，标称 8.33 ms） |
| `hs_video` 1080p240 | 82.98 | **166.95** | 4.02 ms（248.7 fps，标称 4.17 ms） |
| `preview` 4K30 | 32.75 | 32.93（无回归） | 29.8 ms |
| `normal_video` 4K30 | 30.85 | 30.70（无回归） | 28.9 ms |
| `custom5` 4K30 | 29.31 | 30.31（无回归） | 33.0 ms |

**教训（值得写下来）**：凡是"地板/上限不随寄存器变化"的现象，先怀疑**自己的等待与计时**（msleep、jiffy、
轮询、调度），再怀疑硬件；否则会花一整轮去给传感器编一个不存在的"读出地板"。

### 12.3 还差什么（诚实清单）

1. ~~**输出永远是半尺寸**~~ → **已在 §13 解决**（`v4l2_bin=1` 满尺寸 bilinear）。当时的估计是
   "1080p 全尺寸 ≈ 20 ms/帧；4K 全尺寸 ≈ 87 ms/帧 ⇒ 11 fps ⇒ 必须上 NEON"，
   **实测 4K 全尺寸只用 21.3 ms（4000×2256）/ 28.0 ms（4000×3000）**，估计高估约 4 倍，见 §13.4。
2. **240 fps 是"传感器能跑、软件跟不上"**：`hs_video` 传感器下限 4.02 ms（248.7 fps），但出流 167 fps，
   因为 960×540 的转换本身要 3.8 ms（8 线程，还要和 arm 线程抢核）。4.02 ms 的帧留给软件的时间太薄。
3. **48MP（`custom4`）受阻于 CMA**：RAW10 一帧 60 MB，`dma_alloc_coherent` 只有 32 MiB 池
   （`CmaTotal 32768 kB`）⇒ 需要加 `cma=` bootarg/改 DT，或分段读。
4. **切换模式还是"重放表 + 重载模块"**（~20 s），不是运行期 `S_FMT`：`scripts/zz_mode.sh <mode>` 现在是
   唯一入口；要进相机软件得再做 `enum_frameintervals`/`S_FMT` 与运行期重配 CAMSV/缓冲。
5. **颜色需要白天目视复核**：本节所有证据帧都是在全黑房间拍的（`Y mean 16–18`、`U/V ≈ 128`），
   只能证明"没有错色偏"，证明不了画面好看。§11.4 的 R/B 定案靠的是代数 + 强色偏实验，不受影响。

### 12.4 本节新增/更新

| 文件 | 作用 |
|---|---|
| `scripts/parse_modes.py` | 解析 vendor 模式表 + **PLL 定标规则** `pclk = 4.8 MHz × 0x0306/07` + fps 预测 |
| `scripts/gen_mode_table.py` | 把某张 vendor 表导出成 `out/modes/mode_<name>.txt`（`0xREG 0xVAL`） |
| `scripts/imx582_bring.py` | 新增 `IMX582_MODE=<name>` / `--mode <name>` ⇒ 重放该表（表在 stream off 状态下写，PLL 才会生效） |
| `scripts/zz_mode.sh <mode> [帧] [线程]` | 一个模式一条命令：清模块 → 重放表 → 装 V4L2 → 测 fps/burst/存帧 |
| `scripts/zz_scout.sh <mode>...` | 一次 ssh 里连跑多个模式（遵守"一次只做一个设备任务"） |
| `scripts/zz_regs.sh` / `zz_pre.sh` | 只读复核寄存器 / 只读体检（cam_cap 持有 I²C 时也安全） |
| `scripts/render_yuyv.py <file> [W H]` | 现在可指定尺寸（默认仍是 2000×1500） |
| `src/cam_cap.c` | 运行期几何（`v4l2_src_stride`、`cam_src_w/h/stride`）+ **亚 jiffy 完成轮询** |

---

## 13. 2026-10-07 凌晨 V：**满尺寸输出**（bin=1 全分辨率 bilinear debayer）

§12.3 第 1 条的"输出永远半尺寸"已经解决：`v4l2_bin` 变成运行期参数，`v4l2_bin=1` 走一条满分辨率
bilinear debayer，输出 `cam_src_w × cam_src_h`（4K 模式就是真 4000×2256 / 4000×3000，1080p 模式就是真 1920×1080）。

### 13.1 实测（真机，8 线程，每个模式独立 bring-up）

| sensor 模式 | 满尺寸输出 | 逐像素版 `v4l2_full_cache=0` | **逐行解包版 `=1`（默认）** | conv 耗时 | burst 下限 ⇒ 上限 |
|---|---|---|---|---|---|
| `custom2` 1080p120 | 1920×1080 | 65.23 fps（conv 9 804 µs） | **91.17 fps**（conv 7 010 µs） | **7.0 ms** | 122.19（arm 7.66 ms） |
| `hs_video` 1080p240 | 1920×1080 | 65.38 fps（conv 11 011 µs） | **93.35 fps**（conv 6 887 µs） | **6.9 ms** | 216.83（arm 4.61 ms） |
| `normal_video` 4K30 16:9 | **4000×2256** | 22.87 / 23.45 fps（conv 36 271 µs） | **29.78 / 29.94 fps**（conv 21 338 µs） | **21.3 ms** | 29.84 ⇒ **arm 受限** |
| `preview` 4K30 4:3 | **4000×3000** | 19.36 fps（conv 51 675 µs） | **24.91 / 24.92 fps**（conv 28 033 µs） | **28.0 ms** | 30.24（arm 31.1 ms） |
| `custom3` 4K60 | **4000×2256** | — | **38.95 fps**（conv 17 506 µs，arm 17 250 µs） | **17.5 ms** | 57.96（arm 17.25 ms） |

- **4K30 满尺寸 = 真 4000×2256 @ 29.9 fps**，转换已经不再是瓶颈（`arm 33.3 ms` = 传感器周期）。
- **1080p 满尺寸 = 真 1920×1080 @ 91–93 fps**（`custom2` 与 `hs_video` 两个 sensor 模式都是），
  足够 1080p30 / 60 / 90；**满尺寸 1080p120 还差一点**（见 13.4）。
- 满尺寸 4K60（`custom3`）实测 **38.95 fps**（conv 17.5 ms、arm 17.3 ms、`dist clean=58/61`）：转换与读出几乎打平，
  但周期 25.5 ms 大于两者 ⇒ **到不了 60 fps**。
- 缓冲/输出尺寸自动正确：`registered /dev/video0, 1920x1080 YUYV, 4147200 bytes/frame`、
  `4000x2256 YUYV, 18048000 bytes/frame`、`4000x3000 YUYV, 24000000 bytes/frame`，
  raw 缓冲分别 `3145728` / `13631488` / `18874368`（= `ALIGN(stride×h, 1 MiB)`）。

### 13.2 设计：满尺寸 bilinear 与 2×2 平均的关系

- 新增两个模块参数：
  - `v4l2_bin`（默认 **2**）：2 = 每 2×2 raw 块出一个输出像素（原有、已验证的画质线）；1 = 满尺寸 bilinear。
  - `v4l2_full_cache`（默认 **1**）：1 = 每行只解包一次 12-bit（快路径）；0 = 逐像素 `cam_bayer_px()`（参考实现，留作回退与对照）。**两者逐字节相同**，只差速度。
- **`v4l2_bin=1` 只对 binned 模式正确**：`0x0900=1` 的 vendor 模式（preview / normal_video / custom3 /
  custom2 / hs_video）每个输出像素就是一个**逻辑** Bayer 像素，周期 1、RGGB、(0,0)=R，且裁剪列起点全为偶数
  ⇒ 相位不变。`0x0900=0` 的 4-cell 模式（`custom4` 8000×6000、`custom5` 4000×3000）一像素 = 一个光敏元、
  Bayer 周期 2 ⇒ **必须保持 `v4l2_bin=2`**（它的逻辑分辨率本来就只有 2000×1500）。
- 快路径 `cam_v4l2_convert_full_fast()`：`cam_unpack_row()` 把一行 1.5 B/px 解成 `u16`，**三行滚动窗**
  （`lm/l0/lp`，循环尾 `tmp=lm; lm=l0; l0=lp; lp=tmp`）⇒ 每个 raw 采样只解包一次（逐像素版要解包约 8 次）。
  RGGB 四个相位各自"own tap + 4 正交邻居均值 + 4 对角均值"全在 **raw 12-bit** 上做。
- **为什么必须在 raw 上平均**：`cam_lut_build()` 的链是 黑电平减 → WB 增益 → 对比度（绕 2048）→ 预增益
  → 亮度 → **`int_sqrt` 开方 gamma**，非线性 ⇒ 先查表后平均会把暗部抬起来。
- YUYV 字节序/色度矩阵只在 `cam_yuyv_pair()` 里有一份（`q[0]=Y(x+1), q[1]=Cb, q[2]=Y(x), q[3]=Cr`），
  2×2 路径保留原来的内联副本不动（设备上已验证的画质线，最小改动原则）。
- 统计口径与 2×2 路径完全一致：每输出像素 **1 个 G**，`count` 只在偶数行推进 ⇒ `count=#R=#B`、
  `sum_g` 覆盖 `2*count` 个绿。**这里踩过一个坑**：行门一开始写成 `!(y & (STEP-1))` 只放行 y≡0(mod 4)，
  于是奇数行（Gb/B）分支永不执行 ⇒ `stats b=0 g=一半`。改成按行对 `!((y >> 1) & (STEP-1))` 后四个模式
  r/g/b 全部齐平。

### 13.3 等价性证明（两条独立证据）

1. **模型逐字节等价**：`scripts/check_full_demosaic.py` 把参考实现与快路径（含 `cam_unpack_row`）逐行
   转写成 Python，在同一张合成 RAW10 帧（每 CFA 类不同基准电平 + 非对称梯度 + 过曝带 + 全黑带，
   多种分带与合并方式）上比较**喂给 `cam_yuyv_pair()` 的 6 个 tap** 与**统计累加量**，
   `rb_swap` 两种取值都测：**`PASS 64x16`（512 taps）/ `PASS 66x10` / `PASS 1920x8`（7680 taps）**。
2. **真机 A/B**：同一暗场下 `v4l2_full_cache=0/1` 各存一帧，设备侧 `scripts/zz_framecmp.py` 量平面统计：

   | 模式 | Y mean | U mean | V mean |
   |---|---|---|---|
   | `custom2` cache0 / cache1 | 15.96 / 16.10 | 127.42 / 127.38 | 127.30 / 127.37 |
   | `normal_video` cache0 / cache1 | 15.56 / 15.58 | 127.93 / 127.11 | 127.82 / 128.26 |

   `/proc/camcap_info` 的 `stats` 三通道也一致（custom2 `r=262 g=263 b=263` vs `r=261 g=263 b=263`；
   normal_video `r=257 g=258 b=257` vs `r=256 g=259 b=258`）⇒ 同一幅画、无奇偶错位。

### 13.4 §12.3 第 1 条的估计错在哪（诚实更正）

§12.3 曾写"4K 全尺寸 ≈ 87 ms/帧 ⇒ 11 fps"。**实测 4000×2256 只用 21.3 ms、4000×3000 用 28.0 ms**
⇒ 那个估计高估了约 4 倍。原因：它假设"每个输出像素 8 个邻居各自解包 12-bit"（逐像素版确实是），
而一行只解包一次就把这笔开销摊掉了： 逐像素 36.3 ms → 21.3 ms（**−41%**）、51.7 → 28.0 ms（**−46%**）。
**教训：先量，再下"必须上 NEON/硬件"的结论。**

### 13.5 还差什么（满尺寸线）

1. **满尺寸 4K60 到不了 60 fps**（实测 **38.95 fps**）⇒ 要么 NEON/SIMD，要么走 MDP/硬件缩放。
2. **满尺寸 1080p120/240 到不了 120/240 fps**：转换只要 6.9–7.0 ms，但实测周期 10.7–11.0 ms
   ⇒ 有约 3.3–4 ms 没有和 arm 重叠（`arm 7.66 ms` + 转换 7.0 ms 没有完全并行），
   下一步该查流水线的交接点（slot 释放时机 / 完成轮询延迟 / 8 核上 arm 与 8 个转换线程抢核）。
3. **48MP（`custom4`）仍受阻于 CMA 32 MiB**（一帧 60 MB）。
4. **颜色仍需白天目视复核**：所有证据帧都是全黑房间（`Y mean 15.6–16.1`、`U/V ≈ 127.3`）。
5. **模式切换仍是"重放表 + 重载模块"**（~20 s），还没有 `S_FMT`/`enum_frameintervals` 运行期重配。

### 13.6 本节新增/更新

| 文件 | 作用 |
|---|---|
| `src/cam_cap.c` | `v4l2_bin` / `v4l2_full_cache`；`cam_yuyv_pair()`、`cam_unpack_row()`、`cam_v4l2_convert_full_{ref,fast}()`；统计行门按行对；`.ko` **826 592 B** |
| `scripts/check_full_demosaic.py` | 参考实现 vs 快路径的逐字节等价性模型证明 |
| `scripts/zz_fullab.sh` | 一次 ssh 跑 custom2/normal_video × cache0/1 的 A/B |
| `scripts/zz_full2.sh` | 补 preview / hs_video 的满尺寸数字 + 清理大帧文件 |
| `scripts/zz_framecmp.py` | **设备侧**量 Y/U/V 平面统计（大帧不拉回本地） |
| `scripts/zz_mode.sh <mode> [帧] [线程] [bin] [nc] [extra=…]` | 第 4/5/6 个参数：bin、存帧数、任意附加模块参数 |


## 14. 2026-10-07 傍晚 VI：**AE 呼吸修复 + VCM(DW9800V) 对焦 + 果冻读出时间**

用户三项现场反馈：①"AE 一下亮一下正常"②"0.5 m 处没对焦，0.4 m 可以"③"果冻"。本节是这三条的收尾。
`.ko` **872 432 B**，vermagic 不变，崩溃计数 0。

### 14.1 ① AE 呼吸：比例环非对称 + 单帧噪声直驱

`cam_ae_step()` 原本向下每帧最多 **−20%**（`f` 下限 205）而向上可达 **2×**（上限 512）⇒ 一次 2× 过冲要
约 3.1 个向下步才拉回，形成慢极限环；同时修正量由**单帧** `mean_g` 直接算出（无平滑），被摄物又比
修正晚 1 帧（`CAMCAP_AE_SETTLE`）⇒ 手抖、屏幕刷新都能驱动一次曝光跳变。

四处修改（`src/cam_cap.c`）：

| 改动 | 内容 |
|---|---|
| 对数域半步 | `f = int_sqrt((u64)f << 8); if (f < 1) f = 1;` 放在 clip 回退之后 |
| 上下限互为倒数 | `CAMCAP_AE_UP_MAX 384`(1.5×) / `CAMCAP_AE_DOWN_MIN 171`(0.667×)，增益分支 `CAMCAP_AE_GAIN_MAX 320`(1.25×) |
| 绿色均值 IIR | `cam_ae_mean_s += ((int)st.mean_g - (int)cam_ae_mean_s + (1 << 1)) >> 2`（`CAMCAP_AE_SMOOTH_SHIFT 2`；开流/切 auto 清零） |
| 稳定帧加长 | `CAMCAP_AE_SETTLE` 2 → 3 |

真机（暗房，目标 1000 / band 120）：`ae : auto ... frames=10 mean_s=1035`、另两次 `mean_s=1057` / `1061`
⇒ 收敛后停在带内不再来回。`/proc/camcap_info` 的 `ae` 行新增 `mean_s=` 字段。

### 14.2 ② 对焦：DW9800V VCM 起振 + 对比度搜索

**硬件**：VCM 在 I²C **0x0c**（bus 10），读回 **id 0xeb**（与 vendor dmesg 完全相同）；寄存器映射直接取
主线 `drivers/media/i2c/dw9768.c`：`0x03` = DAC[9:8]、`0x04` = DAC[7:0]（时序与
`i2c_smbus_write_word_swapped(client, 0x03, val)` 等价）、`0x02` = PD/AAC 使能、`0x06` = AAC 模式+分频、
`0x07` = Tvib。初始化写序与 vendor 一字不差：
`0x02<=0x01` →1 ms→ `0x02<=0x00` → `0x02<=0x02`(AAC3) → `0x06<=0x40`(AAC3+分频2) → `0x07<=0x01`
⇒ Tvib = (6.3 + 0.1) × 2 = **12.8 ms**。

**手动扫描（权威曲线）**：DAC → 平均 |dY|（Q8），峰在 **512**（785），峰宽 ±128，两端是机械限位平台
（547 / 431）。**搜索**：coarse（step 128，9 点）→ fine（2 轮，±64 / ±32）→ hold；每点 = 1 跳过 + 2 采样
= 3 帧，整轮 13 点 ≈ **39 帧 ≈ 1.3 s**。第二次独立扫描复现同一结论：
`coarse 0:713 128:713 256:714 384:722 512:729 640:723 768:722 896:720 1023:721` →
`fine 448:728 576:728 480:731` ⇒ 选中 **480** ✓。

**⚠️ 失败记录（不要再做）**：曾把 metric 改成"单位亮度对比度"（`(fv<<9)/fv_y`）以求曝光无关： 真机
全程平坦 **7–8**。原因：|dY| 均值本身约 700(Q8) ≈ 2.7 个 8-bit 级，除以平均亮度 ≈100 只剩个位数，
**整数除法把 1.8× 的对比度差压成一个计数**，搜索从此选到哪算哪。已回退为原始
`(st->fv * 256) / st->fv_n`；曝光不变性改由**冻结 AE** 保证（`cam_af_scanning()` 为真时 governor 不修正
曝光，IDLE 分支等 `cam_ae_settle` 归零才开扫）。`fv_y` 保留，只作诊断字段 `y=`。

**跟踪 wobble**：无纹理场景对比度曲线平坦，"掉到 70% 才重扫"永远不触发；所以每
`CAMCAP_AF_WOBBLE_FRAMES 240`（≈8 s）重测 `[base−64, base, base+64]`，只有**赢过持有值 >1%**
（`CAMCAP_AF_WOBBLE_GAIN_PCT 101`）才移动 ⇒ 真机 3 次 wobble 全部 `held`（858 vs 859、858 vs 863），
镜头不被噪声带走。

**接口**：`/proc/camcap` 的 `af show | on | off | hold | init | scan | wobble | pos <n>`；
V4L2 侧 `focus_absolute`（0..1023）与 `focus_automatic_continuous`（`--list-ctrls` 实测：
`focus_absolute ... value=480`、`focus_automatic_continuous ... value=1`）。
**坑**：`/proc/camcap` 必须写整条指令： `echo "auto"` 得到 `I/O error`，要写 `echo "af auto"`。
**坑**：Cheese 会自动重启并抢 `/dev/video0`（v4l2-ctl 只拿到 5 帧就退出）⇒ 测量脚本先 `pkill -x cheese` + sleep。

**已知限制**：暗房/无纹理场景对比度信噪低（本例峰只高于肩部 3–4%），白天有纹理时应更陡： 待目视复核。

### 14.3 ③ 果冻：读出时间是传感器事实，驱动改不了

读出 = 行数 × HTS / pclk：

| 模式 | 行时间 | 读出 | 备注 |
|---|---|---|---|
| `preview` 4000×3000 | 9.111 µs | **27.3 ms** | Cheese 默认走的就是这个（≈0.8 帧周期） |
| `normal_video` 4000×2256 | 9.111 µs | 20.6 ms | |
| `custom3` 4000×2256@60 | 6.508 µs | 14.7 ms | |
| `custom2` 1920×1080@120 | 3.965 µs | **4.28 ms** | 少 6.4× skew |
| `hs_video` 1920×1080@240 | 3.370 µs | **3.64 ms** | 少 7.5× skew |
| `custom5` 4000×3000 | 10.63 µs | 31.9 ms | |
| `custom4` 8000×6000 | 10.63 µs | 63.8 ms | |

⇒ **修法就是换低读出模式**（1080p 少 6–7 倍 skew），代价是曝光上限变短：custom2 的 VTS 2100 ⇒
`exp ≤ 1972` 行 = 7.8 ms，而 preview 是 28.7 ms，**少 3.7× 光** ⇒ 暗光噪声 vs 果冻的权衡，
正是下一步 S_FMT 要暴露给用户的旋钮。

### 14.4 本节新增/更新

| 文件 | 作用 |
|---|---|
| `src/cam_cap.c` | AE 对称 log 半步 + IIR；VCM/AF 子系统（`cam_vcm_*`、`cam_af_*`、`cam_af_info()`）；`fv`/`fv_n`/`fv_y` 统计与三条转换器接线；`y=` 诊断字段；`.ko` **872 432 B** |
| 新参数 | `vcm_addr=0x0c` `vcm_enable=true` `af_enable=1` `af_min=0` `af_max=1023` `af_step=128` `af_pos=0` `af_auto=true` `af_trace=true` |
| `scripts/zz_af_up.sh [参数…]` | 重载模块并打印 VCM/af 行（先 `pkill -x cheese`） |
| `scripts/zz_af_sweep.sh [位置…]` | 手动 DAC 扫描（每点 3 采样，带 `ae=`/`y=` 监视） |
| `scripts/zz_af_check.sh` | 自动搜索验收：等 `state=hold` + 打 `cam_af` 轨迹 |
| `scripts/zz_af_wobble.sh [n]` | 搜索完成后强制 n 次 wobble，看三个点与决策 |
| `scripts/zz_af_rate.sh [帧] [on/off]` | 关掉搜索后的稳态帧率（证明 AF 空闲不花钱） |

实测：AF 关闭态 `timing : period=29966us ... fps=33.37`、`avg ... fps=31.28 frames=150`、
`dist clean=132 late=7 slip=12 lost=0`、崩溃 **0**。


## 15. 2026-10-07 晚 VII：**运行期切模式**（`VIDIOC_S_FMT` / `S_PARM` + `/proc/camcap mode`）

§14 把果冻的修法指到"换低读出模式"，这节把这件事做成应用能调的接口：一个 insmod 起来
的模块现在自己带 5 张传感器模式表，`S_FMT` 换分辨率、`S_PARM` 换帧率、`/proc/camcap` 也能切。

### 15.1 结果（真机实测，两条入口，全部 rc=0、崩溃 0）

| 模式 | 入口 | 输出 | 传感器寄存器 | 实测 avg / timing | 描述符 | 受限点 |
|---|---|---|---|---|---|---|
| `preview` bin2 | 默认 | 2000×1500 | `0307=0xb4` VTS `0x0CE4` | **33.43 / 33.33** | 33.26 | 传感器（VTS 3300） |
| `custom2` bin1 | `/proc` `mode custom2 1` | 1920×1080 | `0307=0x99` VTS `0x0834` | **86.72 / 76.11** | 120.09 | 转换（conv 7.2 ms） |
| `custom3` bin1 | `S_PARM 60` | 4000×2256 | `0307=0x93` VTS `0x0A00` | **39.48 / 43.15** | 60.02 | 转换（conv 17.8 ms > 16.6 ms） |
| `hs_video` bin1 | `S_FMT` + `S_PARM 240` | 1920×1080 | `0307=0xb4` VTS `0x04D4` | **93.00 / 85.25** | 240.05 | 转换（需 4.16 ms，现约 10.8 ms） |
| `normal_video` bin1 | `S_FMT` | 4000×2256 | `0307=0xb4` VTS `0x0E4A` | **28.53 / 29.85** | 30.00 | 传感器 |

切回去也正常：`/proc` 写 `mode preview 2` 后仍是 33.30 fps。`--get-fmt-video` 报的
Bytes per Line 与 `out_width×2` 一致（4000 宽报 8000）。

### 15.2 设计：模式表进驱动，两条入口一座状态机

| 件 | 说明 |
|---|---|
| `src/imx582_modes.h` | 由 `scripts/gen_modes_header.py` 从 `src/rubensimx582_Sensor.h` 生成：init 表 112 对 + 5 张模式表各 111 对 + 每模式的描述符（`hsize`/`vsize`/`hts`/`vts`/`vts_table`/`pclk_khz`/`fps_x100`/`mipi_mbps`/`sensor_bin`/`exp_max`） |
| 收录的模式 | `preview` 4000×3000、`normal_video` 4000×2256、`custom3` 4000×2256@60、`custom2` 1920×1080@120、`hs_video` 1920×1080@240 |
| 不收的模式 | `custom4` 8000×6000（60 MB/帧，超 CMA）与 `custom5`（非 binning，4-cell CFA 转换器还不支持） |
| `VIDIOC_S_FMT` | `vb2_is_busy()` 时 `-EBUSY`；否则按当前 bin 再按另一个 bin 匹配目标尺寸，命中就重放表并改 `cam_bin`/`cam_src_*`/`out_*`/曝光上限 |
| `VIDIOC_S_PARM` | `timeperframe` 的倒数 = 想要的 fps，用来在同尺寸的多张表之间选（1080p 的 120 vs 240、4000×2256 的 30 vs 60） |
| `enum_framesizes` / `enum_frameintervals` | 5 张表 × bin{1,2} 去重后列出，帧率按 `fps/100` 约分 |
| `/proc/camcap` | `modes` 列全部表（活动那行标 `<- active`）；`mode <name> [bin]` 直接切（bin 省略=保持当前） |

切换的写序完全照抄用户态 bring-up（`scripts/imx582_bring.py`）的实测节奏：
`0x0100=0x00` → 等 20 ms → init 表 → 等 20 ms → 模式表 → 写 VTS → 等 50 ms → 需要时给接收端重定时
→ `0x0100=0x01` → 等 50 ms。

### 15.3 ★ 真凶：模式表是 **8 位寄存器**，16 位写把每个值挪到了下一个寄存器

第一次实机切换时，驱动日志一切正常（`mode: custom2 ...`、`rx: 1370 Mbps/lane ...`），
传感器却回读出 `0x0306=0x00 0x0307=0x00 0x0340=0x00 0x0341=0x00` 且一个包都不发。

原因：`cam_sensor_write16()` 发的是一条 **4 字节**消息 `[reg_hi, reg_lo, val_hi, val_lo]`，
而 vendor 模式表全是**字节寄存器**（`0x0306` 和 `0x0307` 是表里两条独立 pair）。多出来的那个
前导 `val_hi = 0x00` 会被传感器当成"下一个寄存器的值"：

```
写 w16(0x0306, 0x00)  然后  w16(0x0307, 0xB4)
  实际落盘： 0x0306=0x00, 0x0307=0x00        ← 0xB4 被挤到 0x0308 去了
写 w16(0x0340, VTS>>8) 然后 w16(0x0341, VTS&0xff)
  实际落盘： 0x0340=0x00, 0x0341=0x00
```

这正好解释了那两次回读，也解释了为什么 **AE 一直好使**：曝光 `0x0202`、模拟增益 `0x0204`、
数字增益 `0x020e` 是货真价实的 16 位寄存器，`write16` 对它们是对的。

修法：新增 `cam_sensor_write8()`（3 字节 `[reg_hi, reg_lo, val]`）与 `cam_sensor_read8()`
（2 字节地址写 + `I2C_M_RD` 1 字节读），模式表重放与 `0x0100`/VTS 全走 8 位口；
`cam_sensor_write16()` 只留给 AE 三件套。加 `mode_trace=1` 可以逐条打印写入并回读校验
（`0x0100/0x0101/0x0112/0x0114/0x0306/0x0307/0x0340/0x0341`）。

### 15.4 接收端重定时：只有两个字段跟速率走

`scripts/port2_rx71.py`（用户态，移植自 `isp71_ref` 的 `mtk_cam_seninf_set_csi_mipi()`）把速率
写死成 1370 Mbps，而 IMX582 有两档：preview/normal_video/custom2 = **1370 Mbps**，
custom3/hs_video = **1964 Mbps**。逐字段看完那份序列后，**只有两个值跟速率有关**：

| 模式 | MIPI Mbps/lane | CSI2 `DMY_CYCLE` | D-PHY `HS_TRAIL` |
|---|---|---|---|
| preview / normal_video / custom2 | 1370 | 13 | 26 |
| custom3 / hs_video | 1964 | 9 | 13 |

驱动现在按 `m->mipi_mbps` 重算这两个值（`cam_rx_set_rate()`，`CAMCAP_SENINF_CK=273 MHz`、
`cycles = 64×273 MHz / data_rate + 1`、`hs_trail = ⌈(224000/mbps − 68)×273 MHz / 1 GHz⌉`），
`rx_rate=1` 时只在速率变化时动手；1370 档算出来与 `port2_rx71.py` 写的完全一致，所以同速率
切换不动接收端。

### 15.5 还差什么（诚实清单）

1. **高帧率档都是转换受限**：1080p 现在 86–114 fps（描述符 120/240 里只跑到这个数的一半到
   九成），4000×2256 只有 39.5 fps（描述符 60）。要在不降画质的前提下把 240 fps 吃满，得让
   转换更快（每像素工作量再降，或换更宽的读写路径），光靠线程数已经没用了。
2. `custom4` 8000×6000（60 MB/帧）和 `custom5`（非 binning）没接：前者超 CMA 池，后者要
   4-cell CFA 的转换器。
3. 切模式会短暂中断推流（表重放约 200 ms），应用要自己重开一次 stream。

### 15.6 本节新增/更新

| 文件 | 作用 |
|---|---|
| `src/imx582_modes.h`（新，15 996 B） | 生成的模式表 + 描述符（驱动自带，不再依赖用户态 `imx582_bring.py` 才能换模式） |
| `scripts/gen_modes_header.py`（新） | 从 vendor 头文件生成上表；带 `mipi_mbps` 字段 |
| `scripts/check_mode_tables.py`（新） | 逐条比对 `src/imx582_modes.h` 与 `modes/mode_*.txt`（证明两条路写的是同一张表） |
| `src/cam_cap.c` | `cam_sensor_write8/read8`、`cam_mode_match/program/geometry/select`、`cam_mode_write_table`、`cam_mode_verify`、`cam_rx_set_rate`、`S_FMT`/`S_PARM`/`enum_*` 接线；新参数 `dphy_base=0x11c86000` `rx_rate=1` `mode_trace=0` `mode_init_replay=1`；`.ko` **918 640 B** |
| `scripts/zz_sw_test.sh`（新） | 全部模式两条入口的验收矩阵（streamer 一律 `timeout 25`） |
| `scripts/zz_restore.sh`（新） | 把设备放回默认配置（preview bin2 2000×1500） |
| `scripts/zz_modechk.sh`（新） | `/proc` `mode` 命令的三个探针，定位过一个解析 bug（`sscanf` 返回 2 被 `== 1` 误判成参数错误） |

## 16. 2026-10-08 凌晨 VIII：**转换器优化 + 三槽流水线 + 帧率账本 + 可复现构建**

§15 的模式切换已经能用，但每个高帧率档都是"转换受限"。这一节把转换做快一轮，并且回答"别人 clone
了仓库能不能编出同版本"。

### 16.1 结果（真机，只用模块默认参数：`conv_threads=8`、`pipe_slots=3`、`v4l2_bin=2`）

| 模式（传感器表） | 输出 | 描述符 | 实测 avg fps | timing fps | 判定 |
|---|---|---|---|---|---|
| preview 4000×3000 | 2000×1500（bin2） | 33.26 | **33.84** | 33.38 | 传感器/VTS 天花板，打满 |
| custom2 1920×1080 | 1920×1080 原生 | 120.09 | **112.74** | 103.36 | 94% |
| custom2 1920×1080 | 960×540（bin2） | 120.09 | **120.34** | 120.59 | 打满 |
| custom3 4000×2256 | 2000×1128（bin2） | 60.02 | **60.34** | 59.61 | 打满 |
| custom3 4000×2256 | 4000×2256 原生 | 60.02 | **48.52** | 58.86 | 81%，转换受限 |
| normal_video 4000×2256 | 4000×2256 原生 | 30.00 | **29.76** | 29.92 | 传感器上限，打满 |
| hs_video 1920×1080 | 1920×1080 原生 | 240.05 | 96.83 | 247.37 | 转换受限（用户已决定不做 240） |

`--list-formats-ext` 现在给出六个离散尺寸与区间：4000×3000 / 2000×1500 = 33.260；4000×2256 /
2000×1128 = 30.000 与 60.020；1920×1080 / 960×540 = 120.090 与 240.050。全部 rc=0、崩溃 0。

### 16.2 优化了什么（三处，都不改画面语义）

1. **色度矩阵每对像素只做一次**：YUYV 的 U/V 本来就是两个像素共用的。旧代码对两个像素各算一遍再
   平均；新代码先把同一色调映射后的 tap 相加（`ar = a0 + a1` …），再做一次矩阵 `>>9`。颜色矩阵是
   线性的 ⇒ 两者只差 ≤1 LSB，`scripts/check_yuyv_chroma.py` 用真实色调表在 78 408 对上验证：
   亮度逐位相同，色度最坏差 1 LSB。
2. **行首尾 padding，去掉内层循环的三个条件分支**：每行解包到 `out[1..n]`（新增
   `cam_unpack_row_pad()`，两端复制邻居），`xm` / `xp` / `xpp` 的条件选择全部消失。
3. **该对象单独 `-O3`**（`CFLAGS_cam_cap.o := -O3`），默认 `conv_threads` 4 → **8**（worker 都
   nice 10，不会饿死桌面）。

合计：1080p 转换 11.9 → 6.5–7.9 ms（帧率 83 → 112 fps），4000×2256 19.5 → 15.2 ms（37 → 48.5 fps）。

### 16.3 三槽流水线：`period ≈ conv + P/N`

`pipe_slots` 默认从 2 改为 3，每帧消掉一份 `P/N` 的等槽时间：

| 配置 | 1080p120 | 4000×2256@60 |
|---|---|---|
| 2 槽（旧） | 83.3 | 37.3 |
| **3 槽（默认）** | **112.7** | **48.5** |
| 4 槽 | 110.7（更差） | 46.1（更差） |
| 3 槽 + 6 线程 | 88.0 | 40.4 |

⇒ 一帧的转换是**串行**的一道工序（一个 `cam_cap_conv` 线程取槽，再分给 8 个 worker），所以
`period ≈ conv + P/N`；加槽只消等待、不加吞吐，第 4 个槽因为 CMA/缓存压力反而更差。打满的条件是
`conv ≤ P − P/N`：1080p（P = 8.33 ms）要 conv ≤ 5.6 ms，4000×2256（P = 16.7 ms）要 ≤ 11.1 ms。

### 16.4 为什么原生 4K60 还差一点，而半尺寸轻松打满

4000×2256 = 9.02 Mpx，8 线程下转换 15.2 ms（≈1.7 ns/px）；`custom3` 的 bin=2 半尺寸只有 2.26 Mpx
⇒ 约 3.8 ms，远低于 16.7 ms 的帧周期。所以：

- **要 60 fps 的实用路数是 bin=2 半尺寸（2000×1128）**，实测 60.34 fps；
- 原生 4000×2256@60 目前 48.5 fps（81%），要补满还得让转换再快约 20%；
- 用户态拷贝不是瓶颈：4/8/12 个 mmap 缓冲、带不带 `--stream-to` 都是 48–51.5 fps；设备日志里是
  `convert: 8 workers, 282 rows each`，且**没有**任何 `worker stalled` 告警，worker 确实并行。

### 16.5 可复现构建（别人 clone 仓库能编出同版本吗）

**能，而且可以取证。** 三件事：

1. 模块必须匹配的那个内核提交原本**不在任何公开 ref 上**（对象在 GitHub 服务器上，但 clean clone
   按名字取不到），现在已经打成**附注 tag `k50-camera-base`**（tag 对象 `5087eada53f0` → commit
   `0b8dd2e87b3d`）推到公开内核仓 `rubens-mt6895-mainline/linux`。
2. 出厂模块的指纹：`srcversion: 493F61FF760E440C2CC5AA7`、`vermagic: 7.2.0-g0b8dd2e87b3d-dirty
   SMP preempt mod_unload aarch64`。
3. 一键脚本 `scripts/reproduce_build.sh` + 文档 `docs/REPRODUCIBLE_BUILD.md`：clone 那个 tag →
   给 `CREDITS` 追加一行脏标记（复现 `-dirty`）→ 用 `docs/k50_mainline_config.gz` 当 `.config` →
   `olddefconfig` → **只需 `modules_prepare`，不必完整编内核**（配置里
   `# CONFIG_MODVERSIONS is not set`、`# CONFIG_MODULE_SIG is not set`）→ `z_build_camcap.sh`。

端到端实测：复现构建 915 600 B，**srcversion 与出厂完全相同**（md5 不同，差在构建路径相关字节），
vermagic 相同 ⇒ 代码同一、可直接加载。剩下的差异只有构建机路径，不影响功能。

### 16.6 本节新增/更新

| 文件 | 作用 |
|---|---|
| `src/cam_cap.c` | 色度/矩阵每对一次、`cam_unpack_row_pad()`、内层去分支、`pipe_slots=3`、`conv_threads=8`；`.ko` **909 216 B** |
| `scripts/check_yuyv_chroma.py`（新） | 证明"色度每对一次"与"逐像素平均"只差 ≤1 LSB |
| `scripts/zz_b60.sh` / `zz_ct4.sh` / `zz_accept.sh`（新） | 半尺寸矩阵 / 线程与槽数扫描 / 默认参数最终验收 |
| `scripts/reproduce_build.sh`（新） | 一键复现构建（面向仓库，不依赖本机环境） |
| `docs/REPRODUCIBLE_BUILD.md`（新） | 复现配方与 `srcversion` 取证 |
| `scripts/z_build_camcap.sh` | 生成的 Makefile 加 `CFLAGS_cam_cap.o := -O3` |

## 17. 2026-10-08 凌晨 IX：**四颗相机全部出帧**（CSI 端口参数化 + 微距 I2C 控制器 overlay）

PR #18 的贡献者（Akisaira）用 Plasma Camera / Snapshot 实测四颗相机都能出图。这一节在我们的
CAMSV 栈上把同一台机器的四颗相机全部复现，并把驱动里写死的"端口 2"参数化。

### 17.1 四颗相机与它们的 CSI 通路

| 相机 | 传感器 | 物理 CSI 口 | SENINF intf | PHY 节点 | D-PHY_TOP | CTRL / CSI2 | 输出 | 实测 |
|---|---|---|---|---|---|---|---|---|
| 主摄 | IMX582 (0x10) | 2 | 4 | `0x11c84000` | `0x11c86000` | `0x1a014200` / `0x1a014a00` | 4000×3000 → 2000×1500 | 33.4 fps（bin2）、原生 4K30 30.2 |
| 前摄 | IMX596 (0x10) | 0 | 0 | `0x11c80000` | `0x11c82000` | `0x1a010200` / `0x1a010a00` | 2592×1952 | 29.8 fps |
| 超广角 | S5K4H7 (0x2d) | 1 | 2 | `0x11c90000` | `0x11c92000` | `0x1a012200` / `0x1a012a00` | 3264×2448 | 30.2 fps |
| 微距 | GC02M1 (0x37) | 3 | 6 | `0x11c94000` | `0x11c96000` | `0x1a016200` / `0x1a016a00` | 1600×1200 | 30.2 fps |

规则（来自他们的 `drivers/media/platform/mediatek/isp/isp71/mtk_seninf71*.c` 与 `mt6895.dtsi`）：

- PHY 节点内布局 = `ANA A +0x0000`、`ANA B +0x1000`、`DPHY_TOP +0x2000`、`CPHY_TOP +0x3000`；
- **DT 端口号就是 SENINF pad 号**，`inputs[i].intf = i`，只有偶数端口受支持（"Interface 2N receives
  CSI port N as a whole (4D1C)"），所以**物理口 N ⇒ SENINF intf 2N**；
- `SENINF_TOP_PHY_CTRL_CSI(p) = 0x0040 + 4*p`（p = 物理口号），`SENINF_CTRL_BASE(i) = 0x0200 +
  0x1000*i`，`SENINF_CSI2_BASE(i) = 0x0a00 + 0x1000*i`；
- 四颗相机在 `rubens.dts` 里分别是 `seninf_csi0_in`（前摄）/ `csi1_in`（超广角）/ `csi2_in`（主摄）
  / `csi3_in`（微距），**全部经 CAM_MUX 3 汇到同一个 CAMSV**（`camsv0@1a110000` = 我们树里的
  `camsv1@1a110000`）⇒ 同一时刻只能一颗出流。

驱动侧的改动只有三处（其余本来就通用）：新增 `SENINF_TOP_PHY_CTRL_CSI(p)` 宏、route 改用
`SENINF_TOP_PHY_CTRL_CSI(route_intf / 2)`、`cam_rx_set_rate()` 改用 `SENINF_CSI2_BASE(route_intf)`。
于是 `route_intf` + `dphy_base` 两个模块参数就能覆盖任意端口。

### 17.2 新增工具（都在 `scripts/`）

| 脚本 | 作用 |
|---|---|
| `gen_sensor_tables.py <driver.c> <outdir> [表名…]` | 从他们的驱动里抽出 `cci_reg_sequence` 表，转成设备侧可重放的 `0xREG 0xVAL` 文本 |
| `sensor_bring.py <bus> <addr> <table.txt>…` | 通用传感器重放：8 位（A8=1）或 16 位寄存器地址、ID 回读、`0x0100` 上电时序 |
| `csirx_bring.py [port] [link_mhz] [秒] [lane 数] [trail_ns]` | 按端口算 ANA/DPHY/TOP/CTRL/CSI2 基址与重定时值，重放厂商 CSI-RX 上电序列 |
| `zz_front_cap.sh` / `zz_uw2.sh` / `zz_macro_cap.sh` | 前摄 / 超广角 / 微距的端到端上电 + 抓帧 |
| `zz_macro_grab.sh` | 把当前微距配置抓成 `/root/macro.yuyv` |
| `dt/ovl_i2c4.dts` + `src/ovl_i2c4.c` + `z_build_ovl6.sh` | 微距专用的运行时 device-tree overlay 模块 |

### 17.3 微距的特殊之处：我们 DT 里没有 `i2c@11d03000`

微距挂在 `i2c4`（`0x11d03000`）上，而我们树里只有 `i2c_cam_a/b/c/d`（`11d01000/11d02000/11d05000/
11d06000`）与 `i2c7`（`11d04000`）⇒ 这条控制器**必须由运行时 overlay 新建**。用的就是既有的
`cam_ovl` 机制（`of_overlay_fdt_apply` + `.incbin` 的 dtb），踩了两颗雷：

1. **`OF: overlay: Invalid overlay_fdt header`（-22）**：内核的 `fdt_check_header()` 第一件事就是
   要求 FDT 块**8 字节对齐**（`if ((uintptr_t)fdt & 7) return -FDT_ERR_ALIGNMENT;`）。`.incbin`
   紧跟 `pr_info` 字符串 ⇒ 落在 `.rodata` 的 4 mod 8 上。修法 = 在 `ovl_blob.S` 里
   `ovl_i2c4_blob_start:` 前加 `.balign 8`（复核偏移 `0x68` ✓）。
2. **`OF: overlay: symbols in overlay, but not in live tree`（-22）**：dtc 带 `-@` 会生成
   `__symbols__` 节点，而我们的 live DT **没有** `/__symbols__` ⇒ 去掉 `-@`、并给 dts 里的节点去掉
   标签（无标签就不会生成 `__symbols__`）。另外给模块加了 `module_exit` + `of_overlay_remove`
   （否则 overlay 模块不可卸载，开发期只能换名字）。

成功后：`/proc/device-tree/soc@0/i2c@11d03000` 出现、`/dev/i2c-*` 多出一条（动态次设备号），
`0x37` 上的 GC02M1 回读 `0xf0=0x02 0xf1=0xe0` = 芯片 ID `0x02e0` ✓。

### 17.4 证据（不是"看起来对"）

- 每颗相机都抓到真帧并核对计数：`cam_mux_chk : 0x04b00640 (CHK_RES)` = 1200|1600（微距）、
  `0x09900cc0` = 2448|3264（超广角）、`frame_ready 1 / last_result 0`；
- 帧率与传感器的 HTS×VTS 自洽（微距 2192×1268 @ 84 MHz = 30.0 fps ✓）；
- 抓到本地的帧用 `scripts/render_yuyv.py` 渲染：微距首帧 `Y mean 12.35`、`U 128.84`、`V 127.97`
  （凌晨、AE 关闭 ⇒ 真正偏黑、色度中性，不是均匀灰假像）；
- 全部 rc=0、crashes 0。

## 18. 2026-10-08 凌晨 X：**转换器第二轮优化 + 帧率账本修正** ⇒ 原生 1080p120 打满

§16 之后剩下的差距是"转换受限"。这一轮把每帧的**串行成分**再切一刀。

### 18.1 三处改动

1. **并行 band cache 失效**（新参数 `sync_parallel`，默认 1）：传感器经 DMA/IOMMU 写入，CPU 读之前
   必须失效可缓存别名。原来在转换线程上一次性 `dma_sync_single_for_cpu()` 整块 18 MB（这是帧周期
   要付的串行时间）；现在每个 worker 只失效**自己那一带**（`cam_band_sync()`，带之间重叠一行，
   保证每行都被覆盖），并把最大值记进 `t_sync`/`s_sync`，`/proc/camcap_info` 的 `timing`/`avg`
   两行新增 `sync=` 字段。`sync_parallel=0` 保留旧的整块路径以便对照。
2. **worker 行 scratch 预分配**：`cam_v4l2_convert_full_fast()` 需要三行解包数据
   （`3*(cam_src_w+2)` 个 `u16`），原来是**每带每帧** `kmalloc_array` 一次（分配器抖动 + 每帧
   8 次分配）。现在池启动时每个 worker 分配一次，停止时释放，`scratch == NULL` 时才回退到
   临时分配（并保留 `_ref` 兜底）。
3. **满尺寸转换器内层循环去乘法**：输出指针改为递减（`q = o + (n-1)*4` 起，循环头 `q -= 4`），
   替掉每组一次的 `(n - 1 - (x >> 1)) * 4`（180° 翻转语义不变）。

另修一个**账本 bug**：`t_prev` 原来在 `cam_v4l2_thread()` 入口初始化为 `ktime_get()`，于是第一帧的
"间隔"把整段启动时间算了进去（实测那一帧 ≈132 ms）⇒ 150 帧平均被拖低（18.7 ms vs 稳态 16.8 ms），
`dist` 里还会出现一次假 `lost(>=58ms)`。改成 `t_prev = 0` 起步，第一帧只对时不计入。

### 18.2 实测（真机，`conv_threads=8`）

`sync_parallel` A/B（custom3 4000×2256@60，60 帧）：

| `sync_parallel` | avg fps | `sync=`（avg） | `sync=`（串行整块的代价） |
|---|---|---|---|
| **1（默认）** | **51.09** | 382 µs | 每带最大 0.15–0.38 ms |
| 0 | 45.88 | 1927 µs | ≈1.9 ms/帧 |

⇒ 并行 band 失效值 **+11%**。

槽数与 vb2 缓冲数（custom3）：

| 配置 | avg fps | 稳态 timing fps |
|---|---|---|
| 3 槽 + 4 个 mmap 缓冲 | 51.07 | 60.06 |
| 3 槽 + **8 个 mmap 缓冲** | 53.37 | 59.61 |
| **4 槽 + 8 个缓冲** | **54.69** | 59.35 |

⇒ 用户态给足缓冲值 +2.3 fps，第 4 个 raw 槽再 +1.3 fps（三个额外槽都能分配成功）。

### 18.3 最终帧率表（`zz_rates.sh 150`，`conv_threads=8 pipe_slots=4 sync_parallel=1`，8 个 mmap 缓冲）

| 模式 | 输出 | 描述符 | avg fps | timing fps | 判定 |
|---|---|---|---|---|---|
| custom2 1920×1080 | **原生 1920×1080** | 120.09 | **117.91** | 121.86 | **打满（±2%）** |
| custom3 4000×2256 | **原生 4000×2256** | 60.02 | 50.79 | **60.28** | 稳态打满，平均被偶发突发拖低 |
| normal_video 4000×2256 | 原生 4000×2256 | 30.00 | 30.23 | 30.16 | 传感器上限，打满 |
| preview 4000×3000 | 2000×1500（bin2） | 33.26 | 32.76 | 33.18 | 传感器上限，打满 |

对比优化前（§16 的表）：1080p 原生 112.7 → **120**、4000×2256@60 原生 48.5 → 稳态 **60**、
4000×2256@30 与 binned 2000×1500 打满不变；`.ko` **914 528 B**，crash 0。

**仍然要如实说的**：custom3 原生 4K60 的 **150 帧平均** 是 50.8–53.5 fps（稳态 60.3），差距来自
偶发的 ≥58 ms 突发（每 150 帧 3 次，`dist` 里是 `lost`），不是转换吞吐不够： 半尺寸
2000×1128@60 与 960×540@120 都是稳稳打满。

## 19. 2026-10-08 深夜 XI：**对焦在平坦场景里乱跑**的修复（对比度下限 + 平坦回退）

§14 的自动对焦是"开环 VCM + 对比度爬山"。它在**场景没有对比度**时会坏，用户报的就是这个：
镜头一直在动、最后停在一个没有依据的位置。

### 19.1 两个现象，一个根因

真机日志（暗场，`metric` 只有 0–2）：

```
cam_af: fine pos=0 metric=2 (best 2 @ 0)
cam_af: scan 1 done, pos=0 metric=2 (was 0), stubborn=0
cam_af: coarse pos=0 metric=0        # 第二轮：10 个粗位置全是 0
cam_af: scan 2 done, pos=0 metric=0 (was 0), stubborn=1
... 约 3 s 后又是一轮 coarse ...
```

- **停在 DAC 0**：`cam_af_start()` 把 `best_metric` 清 0、`best_pos` 设成第一个粗点（`af_min` = 0），
  而样本采纳是严格 `m > best_metric`。整轮都是 0 时**没有赢家**，镜头就停在"机械静止点"：
  这颗模组的静止点是 **macro 焦距（≈0.4 m）**，不是无穷远。
- **反复重扫**：HOLD 里的重扫条件是 `m * 100 < best_metric * 70`，`best_metric ≈ 2` 时噪声就能满足，
  周期是 `12 << stubborn` 帧 ⇒ `stubborn=3` 时**约每 3 s 扫一次**，每次把镜头扫过 10 个粗位置。

两个现象合起来就是用户看到的"镜头一直抽、画面一直糊"。

⚠️ **诊断陷阱**：`/proc/camcap_info` 的 `af` 行读的是**最后一帧**的统计。流没在跑时它是陈旧值：
我第一次手工扫 11 个位置拿到一模一样的 `metric=227`，不是镜头不动，而是 **Cheese 打开着设备但流已经停了**
（`vf_on: 0`、`int_status: 0`）。**先确认流在跑，再读 `af` 行。**

### 19.2 修复

| 旋钮 | 默认 | 作用 |
|---|---|---|
| `af_floor` | 200 | 低于它的样本仍然记录，但**不能赢得比较**；0 = 旧行为 |
| `af_fallback` | 0 | 首次扫描且没有任何历史位置时的落点（0 = 机械静止点，即 macro） |
| `CAMCAP_AF_FLAT_FRAMES` | 300（≈10 s） | 平坦场景里的重扫最小间隔 |

行为改动：① 样本采纳变成 `m >= af_floor && m > best_metric`；② HOLD 里 `m < af_floor` 时
**不 wobble**、重扫限速到 300 帧；③ 扫描结束时若 `best_metric < af_floor`，置 `flat`、把镜头放回
**扫描开始时的位置** `hold_pos`（而不是噪声赢家）；④ 成功扫描后记住 `hold_pos = best_pos` 供下次回退；
⑤ wobble 也不接受低于下限的"赢家"；⑥ `af_fallback` 只在完全没有历史时用。

`/proc/camcap_info` 的 `af` 行新增 `floor=`/`flat=`。

### 19.3 真机验证

修复后在**有光**的房间（y≈100，房间里有对比度但指标仍在 900 上下）：

| 时刻 | `af` 行 |
|---|---|
| 起流、手动 512 | `manual … pos=512 metric=922 floor=200 flat=0` |
| `af auto` 后 20 s | `auto state=hold pos=512 metric=925 best=922 best_pos=512 hold=925 stubborn=0 scans=3` |
| 再静默 25 s | `auto state=hold pos=512 metric=922 best=920 hold=922`；33.3 fps 不掉 |

期间 5 次 wobble（约 7.5 s 一轮）全部 `wobble held pos=512`：±64 的两个邻居测到 916–921，
**从未比 held 值好 1%** ⇒ 镜头留在 512，不再被噪声拖走。

**独立验证**（不信任驱动自己的指标）：流跑着时在 DAC 0/256/512/768/1023 各抓一帧
（`scripts/zz_afsharp.sh`），离机用 `scripts/sharpness.py` 量最后一帧：

| DAC | Y mean | mean \|dY\|(列) | Laplacian 方差 | mean \|Laplacian\| |
|---|---|---|---|---|
| 0 | 101.9 | 3.51 | 194.2 | 10.87 |
| 256 | 102.1 | 3.50 | 192.7 | 10.83 |
| **512** | 99.7 | **3.63** | **206.1** | **11.16** |
| 768 | 100.2 | 3.54 | 196.5 | 10.97 |
| 1023 | 100.2 | 3.55 | 197.6 | 11.01 |

三个独立指标全部在 512 取最大 ⇒ 驱动选的位置是对的。但**变化幅度只有 2–7%**：
这一场（昏暗房间、高增益噪声主导）本身没有多少对焦信息。

### 19.4 诚实清单

- 对比度对焦**需要场景有对比度**。平坦/极暗场景下修好的是"不乱跑"，
  不是"凭空找到焦点"：此时镜头保持在原位（`hold_pos`），并打印
  `scan N found no contrast (metric … < floor), lens back to …`。
- 指标是**平均 |dY|（Q8）**，不含任何高通/归一化 ⇒ 它的绝对值由场景纹理与噪声决定，
  暗场噪声可以把它抬到几百，此时"有值"不等于"有信息"。真要更稳需要换成高通/Laplacian 类指标，
  或只在采集时给用户一个手动焦点（`v4l2-ctl -c focus_absolute=N`）。
- `scans` 计数同时把 wobble 计进去（一次 wobble 也 `scans++`），所以它比"粗扫描次数"大。
- 验证时把用户的 Cheese 结束了（`fuser -k /dev/video0` 是测试脚本第 0 步）。

### 19.5 新增/相关工具

| 脚本 | 用途 |
|---|---|
| `scripts/zz_afnow.sh` | 只读：AF/AE 参数 + `af`/`avg`/`timing`/`stats`/`route` 行 + dmesg AF 尾 + 设备持有者 |
| `scripts/zz_afdiag.sh` | 手工扫：`af off` → 逐点 `af pos N` 量指标 → `af auto` 观察 |
| `scripts/zz_af_fix.sh` | 回归验收：起流 → `af auto` → 20 s/25 s 观察"不得乱跑" → 手工扫对比度 |
| `scripts/zz_afsharp.sh` | 在多个 DAC 位置各抓帧，供离机测量 |
| `scripts/sharpness.py` | 离机算 `mean |dY|`、Laplacian 方差/均值（独立于驱动指标） |



