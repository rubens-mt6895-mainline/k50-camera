# K50 (rubens) IMX582 相机移植：mainline / Debian 侧

红米 K50（代号 rubens，联发科 MT6895）在 mainline Linux 上把 IMX582 后摄跑起来的 out-of-tree 采集驱动、传感器模式表、bring-up 记录与脚本。

内核侧对应仓库：<https://github.com/rubens-mt6895-mainline/linux>（分支 `7.2-mt6895-xiaomi-rubens`）。

## 硬件与数据通路

- 传感器：IMX582（CSI port 2），I²C bus 10（`i2c-mt65xx`）地址 0x10，EEPROM 0x51，对焦 DW9800V 地址 0x0c
- 线上格式：RAW10，4 lane（寄存器 `0x0112=0x0a`、`0x0114=0x03`）
- 通路：IMX582 → CSI-2 port 2 → SENINF intf 4（SENINF_5）→ SENINF mux 1（`0x1a011d00` SRC_SEL=8）→ CAM_MUX 3（`0x1a010460`）→ `camsv1@1a110000` IMGO DMA → V4L2 `/dev/video0`（YUYV 422）
- 关键约束：`DBL_DATA_BUS=2 + PAK_DBL=2 + PAK_MODE=0x82` 三件套同时成立才配对；抓帧缓冲必须是 4096 对齐（否则 IOMMU `min_pagesz 0x1000` 映射失败、出黑帧）；CAMSV 在 larb0 后面，只能走 IOVA，用 `dma_alloc_coherent` 拿 CMA + IOMMU 映射

## 当前状态（2026-10-07）

- 采集通路打通，V4L2 出 YUYV 流，Cheese 可用
- 帧率：preview 表 + VTS `0x0CE4`(3300) ⇒ 上限 ~33.5 fps，实测 32–33 fps（转换线程 4）
- 全尺寸输出：`v4l2_bin=1` 时输出原生分辨率（1080p 不再缩到 960×540），1080p 90+ fps、4000×2256 22 fps、4000×3000 19 fps（受转换耗时限制）
- 颜色：CFA = RGGB（物理实验 + 厂商 `.sensor_output_dataformat = SENSOR_OUTPUT_FORMAT_RAW_4CELL_HW_BAYER_R` 双重确认）；红蓝错位的真因是 YUYV 色度字节序（byte1=Cb、byte3=Cr），Bayer 标签交换在灰世界 AWB 下不可见
- 曝光/白平衡：对数半步 + IIR 的 AE 环（不闪烁）、灰世界 AWB
- 对焦：DW9800V 开环 + 对比度爬山搜索（V4L2 `focus_absolute` / `focus_automatic_continuous`）
- 已知边界：mainline 上没有可用的 MTK ISP（厂商 `mtk-cam-isp.ko` 无法加载，ISP 由 CCU 固件 / TEE 驱动），所以去马赛克、AE/AWB/AF 全部在 CPU 侧完成；滚动快门是传感器读出时间的物理事实，只能用低读出模式缓解（1080p 约 4 ms，4000×3000 约 27 ms）

## 传感器模式表（IMX582，本机实测寄存器）

只有 7 个模式有非空寄存器表；`capture` / `slim_video` / `custom1` / `custom6` 在这份 rubens 表里是空的。

| 模式 | 输出 | HTS×VTS | pclk | fps |
| --- | --- | --- | --- | --- |
| preview | 4000×3000 | 7872×3658 | 864 MHz | 30.00 |
| normal_video | 4000×2256 | 7872×3658 | 864 MHz | 30.00 |
| custom3 | 4000×2256 | 4592×2560 | 705.6 MHz | 60.02 |
| custom2 | 1920×1080 | 2912×2100 | 734.4 MHz | 120.09 |
| hs_video | 1920×1080 | 2912×1236 | 864 MHz | 240.05 |
| custom4 | 8000×6000 | 9184×6271 | 864 MHz | 15.00 |
| custom5 | 4000×3000（1:1 裁切） | 9184×3135 | 864 MHz | 30.01 |

像素时钟规则（经 IMX586 标定表与 IMX582 实测双重验证）：`pclk = 4.8 MHz × ((0x0306<<8) | 0x0307)`，`fps = pclk / (HTS × VTS)`。
每个模式的寄存器表在 `modes/mode_<name>.txt`（由 `scripts/gen_mode_table.py` 从 `src/rubensimx582_Sensor.h` 导出，可直接重放到传感器）。

## 实测帧率（V4L2，2026-10-06/07）

`v4l2_bin=1`（全尺寸转换器，每行只解包一次）：

| 模式 | 输出 | 实测 | 备注 |
| --- | --- | --- | --- |
| custom2 | 1920×1080 | 91.2 fps（8 线程；4 线程 61–66） | burst 上限 115–126 fps |
| hs_video | 1920×1080 | 65.4 fps | burst 上限 216 fps（arm 4.6 ms） |
| custom3 | 4000×2256 | 39.0 fps | 转换耗时未单独测 |
| normal_video | 4000×2256 | 22.3 fps | 转换 40.8 ms > 33 ms 周期 ⇒ 有 late/slip |
| preview | 4000×3000 | 19.4 fps | burst 上限 33.2 fps |

`v4l2_bin=2`（2×2 binning，输出半尺寸，预览用）：preview 输出 2000×1500，32.7 fps。
8 线程下转换成本约 4.3–4.5 µs / 千输出像素。曝光上限 `exp_max=0x0c64`(3172) 必须低于 VTS，否则帧周期被拉长（曾出现 9 fps）。

## 目录

| 路径 | 内容 |
| --- | --- |
| `src/cam_cap.c` | 唯一驱动：CAMSV 采集 + V4L2/videobuf2 + `/proc/camcap` + AE/AWB/AF + 双缓冲流水线 + 2×2/全尺寸转换器 |
| `src/imx586*.c`、`src/rubensimx582_Sensor.h`、`src/sensor_list.c` | 厂商 IMX586/IMX582 传感器表与参考实现（来源见下） |
| `src/cam_*.c`、`src/mod_*.c`、`src/Makefile` | 相机供电/时钟/GPIO/overlay 等配套 out-of-tree 模块 |
| `docs/CAMERA_NOTES.md` | 相机移植全过程记录（最长的一份） |
| `docs/V4L2_CAMERA.md` | V4L2 驱动接口、模块参数表、30 fps 与红蓝问题的闭环 |
| `docs/SENINF_CONFIG.md`、`docs/seninf_routing.md` | SENINF/CAM_MUX 路由与寄存器 |
| `docs/camsv_*.md` | CAMSV 寄存器序列/帧参数逆向 |
| `docs/CAMERA_CAPTURE_WORKING.md`、`docs/ISP_FEASIBILITY.md` | 采集可用状态、ISP 可行性结论 |
| `scripts/` | bring-up / 测速 / 模式切换 / 对焦标定 / 转换器等价性验证脚本 |
| `modes/` | 7 个模式的寄存器表（`0xREG 0xVAL` 文本） |
| `docs/k50_mainline_config.gz` | 构建该模块用的内核配置 |

## 构建

`src/` 是 out-of-tree 模块目录，在内核工作树里编译：

```sh
K=${KDIR}      # 内核工作树（构建过 7.2.0-g0b8dd2e87b3d 的那棵）
OUT=${K50_REPO}/out/camcap_0b8dd2e
SRC=${K50_REPO}/src
ARCH=arm64 LLVM=1 make -C $K M=$SRC modules
```

仓库里的脚本用占位符代替了本机路径，运行前按自己的环境设置：

| 变量 | 含义 |
| --- | --- |
| `${K50_HOST}` | 设备地址（手机 SSH 可达的 IP） |
| `${K50_KEY}` | SSH 私钥文件名（`~/.ssh/` 或 `/tmp/` 下） |
| `${WINHOME}` | Windows 用户目录（WSL 里即 `/mnt/c/Users/<user>`） |
| `${HOME}` | WSL 用户目录 |
| `${KDIR}` | 内核工作树路径 |
| `${K50_REPO}` | 本仓库路径 |
| `${WINPATH}` | 其他 Windows 本机路径 |

## 加载

```sh
insmod cam_cap.ko v4l2_enable=1 conv_threads=4 pipeline=1
```

常用参数：`v4l2_enable`（开 V4L2 节点）、`v4l2_bin`（1 = 全尺寸转换器 + 原生输出，2 = 2×2 出半尺寸）、`v4l2_full_cache`（1 = 每行只解包一次）、`exp_hsize/exp_vsize/v4l2_src_stride`（运行期几何）、`exp_max`（曝光上限，必须 < VTS）、`out_width/out_height`、`wb_r_q8/wb_b_q8`（AWB 初值）、`rb_swap`、`pipeline`、`conv_threads`、`ae_enable/awb_enable/af_enable`。

## 来源与许可

- `src/cam_cap.c`、`src/cam_*.c`、`scripts/`、`docs/`、`modes/` 为本项目产物，按 GPL-2.0 提供（与内核模块一致）
- `src/imx586_Sensor.c`、`src/imx586_Sensor.h`、`src/rubensimx582_Sensor.h`、`src/sensor_list.c`、`src/imx586_mainline.c`、`src/imx586_rockchip.c` 取自小米开源内核 <https://github.com/MiCode/Xiaomi_Kernel_OpenSource>（`rubens-s-oss` 分支），版权与许可归原项目
