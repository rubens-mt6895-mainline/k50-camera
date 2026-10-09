# K50 (rubens / MT6895) 相机移植：mainline / Debian 侧

红米 K50（代号 rubens，联发科 MT6895）在 mainline Linux 上把**四颗摄像头**跑起来的 out-of-tree
采集驱动、传感器寄存器表、bring-up 工具与实测记录。

内核侧对应仓库：<https://github.com/rubens-mt6895-mainline/linux>（分支 `7.2-mt6895-xiaomi-rubens`）。
本项目的驱动没有进内核树： 它通过自己的 `/dev/videoN` 节点提供 YUYV 视频流，标准 V4L2 应用
（Cheese、GStreamer、`v4l2-ctl`）都能直接用。

## 仓库内容

| 路径 | 内容 |
| --- | --- |
| `src/` | 驱动 `cam_cap.c`（CAMSV 采集 + V4L2/videobuf2 + AE/AWB/AF 控制律 + 四节点）；`imx582_modes.h`（模式表）；`ovl_i2c4.c`（运行时 DT overlay）；一批 bring-up 探针模块；厂商开源内核里的参考驱动 |
| `dt/` | 设备树片段：相机 bring-up 覆盖层、厂商相机 dtsi |
| `modes/` | IMX582 七个模式的寄存器表（文本，`0xREG 0xVAL`，可直接重放到传感器） |
| `sensors/` | IMX596 / S5K4H7 / GC02M1 的初始化与尺寸表（同样格式） |
| `docs/` | 文档，见下 |
| `scripts/` | 只收录被文档引用的工具（构建、bring-up、验证、分析） |

## 文档

| 文件 | 内容 |
| --- | --- |
| [docs/CAMERA_CAPTURE_WORKING.md](docs/CAMERA_CAPTURE_WORKING.md) | **最小可用配置 + 三条关键事实**（12-bit / 1.5 B 每像素、`DBL_DATA_BUS/PAK_DBL/PAK_MODE` 成对约束、缓冲必须 4096 对齐），以及当初三个误判 |
| [docs/V4L2_CAMERA.md](docs/V4L2_CAMERA.md) | **完整工程日志**：从抓帧到 V4L2 节点、AE/AWB/AF 的三次修复、模式矩阵、四摄参数化、多节点、外部 review 的逐条处置（§1–§25） |
| [docs/CAMERA_NOTES.md](docs/CAMERA_NOTES.md) | **调查时间线**：逐日记录 + 被推翻结论的就地标注 + CAMSV 寄存器逆向（§8 及其附录 A）+ 反汇编取证 |
| [docs/seninf_routing.md](docs/seninf_routing.md) | **路由正本**：port → SENINF intf → mux → CAM_MUX → CAMSV 的推导、每条寄存器写的来源与实测证据；附录 A = D-PHY 接收机初始化序列 |
| [docs/ISP_FEASIBILITY.md](docs/ISP_FEASIBILITY.md) | 为什么**不能用** MTK ISP：主线无驱动、厂商 `mtk-cam-isp.ko` 的 152 个缺失符号、寄存器序列由 CCU 固件 + TEE 写 |
| [docs/STOCK_AF_ANALYSIS.md](docs/STOCK_AF_ANALYSIS.md) | 原厂 HyperOS 对焦栈逆向：`VCMDrv::SetFocusPosition`、`dw9800v.ko` 寄存器协议、只给主摄装了马达的证据 |
| [docs/REPRODUCIBLE_BUILD.md](docs/REPRODUCIBLE_BUILD.md) | 别人 clone 下来能编出同一个模块的配方（tag、工具链、`.config`、`srcversion` 取证） |
| [docs/k50_mainline_config.gz](docs/k50_mainline_config.gz) | 构建所用的内核 `.config` |

## 数据通路

```
IMX582 ─ MIPI CSI-2 port 2 ─▶ SENINF intf 4 ─▶ SENINF mux 1 ─▶ CAM_MUX 3 ─▶ camsv1@1a110000 ─▶ IMGO DMA ─▶ /dev/video0
IMX596 ─ port 0 ─▶ intf 0 ─┐
S5K4H7 ─ port 1 ─▶ intf 2 ─┼─▶ 同一组 SENINF mux / CAM_MUX 3 ─▶ 同一路 CAMSV
GC02M1 ─ port 3 ─▶ intf 6 ─┘
```

- 四颗相机**汇到同一路 CAMSV**，所以同一时刻只能有一路出流。
- 主摄的 I²C（bus 10，`0x10`）由驱动管理；另外三颗的**上电、寄存器表、D-PHY 时序全部由用户态脚本完成**
  （驱动没有它们的 eeprom/regulator 节点），驱动只负责给它们开视频节点。
- 线上格式：12-bit 打包，1.5 字节/像素（4000×3000 ⇒ 6000 字节/行、18 000 000 字节/帧）。

## 当前状态（2026-10-09）

- **四颗相机都能出帧**：IMX582 4000×3000（~33 fps）、IMX596 2592×1952（29.9）、S5K4H7 3264×2448（30.1）、
  GC02M1 1600×1200（30.1）。
- **多节点**：`cam_nodes=4` 时暴露 `/dev/video0..3`，GStreamer/Cheese 里能看到四个相机条目；
  默认 `cam_nodes=1`，行为与单节点版本逐字节一致。
- **帧率**：preview（2000×1500，2×2 binning）32–33 fps；`v4l2_bin=1` 输出原生分辨率时
  1080p120 实测 117.9–120.1 fps（打满）、4000×2256@60 稳态 60.3 fps、4000×2256@30 打满、
  4000×3000 打满传感器天花板（~33 fps）。`hs_video` 240 fps 模式只能跑到 182 fps（转换耗时）。
- **颜色**：CFA = RGGB（厂商 `SENSOR_OUTPUT_FORMAT_RAW_4CELL_HW_BAYER_R` + 2×2 相位相关实测双重确认）；
  红蓝错位的真因是 YUYV 色度字节序（byte1 = Cb、byte3 = Cr），不是 Bayer 标签。
- **曝光/白平衡/对焦**：AE 用对数半步 + IIR（不呼吸）；灰世界 AWB；对比度 AF（度量为"绝对亮度差之和 ÷
  亮度和 ×1000"，不再随曝光饱和），只有主摄有马达（DW9800V @ `0x0c`）。
- **没有 ISP**：去马赛克、AE/AWB/AF、色彩全部在 CPU 侧完成（见 `docs/ISP_FEASIBILITY.md`）。
- **已知边界**：`custom4` 8000×6000 需要 60 MB/帧、超出 CMA 池；`custom5` 是非 binning 的 4-cell CFA，
  转换器未支持。滚动快门是传感器读出时间的物理事实（4000×3000 约 27 ms、1080p 约 4 ms）。

## IMX582 模式表（vendor 表，本机实测）

| 模式 | 输出 | HTS×VTS | pclk | 表内 fps | 驱动里的输出 |
| --- | --- | --- | --- | --- | --- |
| `preview` | 4000×3000 | 7872×3658 | 864 MHz | 30.00 | 2000×1500（bin 2）或 4000×3000（bin 1） |
| `normal_video` | 4000×2256 | 7872×3658 | 864 MHz | 30.00 | 4000×2256 / 2000×1128 |
| `custom3` | 4000×2256 | 4592×2560 | 705.6 MHz | 60.02 | 同上，60 fps |
| `custom2` | 1920×1080 | 2912×2100 | 734.4 MHz | 120.09 | 1920×1080 / 960×540 |
| `hs_video` | 1920×1080 | 2912×1236 | 864 MHz | 240.05 | 1920×1080 / 960×540 |
| `custom4` | 8000×6000 | 9184×6271 | 864 MHz | 15.00 | 未收录（超出 CMA） |
| `custom5` | 4000×3000（1:1） | 9184×3135 | 864 MHz | 30.01 | 未收录（4-cell CFA） |

像素时钟规则（IMX586 标定表与 IMX582 实测双重验证）：`pclk = 4.8 MHz × ((0x0306<<8)|0x0307)`、
`fps = pclk / (HTS × VTS)`。`capture` / `slim_video` / `custom1` / `custom6` 四张表在这份 rubens
vendor 驱动里是空的。每个模式的寄存器表在 `modes/mode_<name>.txt`。

## 快速开始

```sh
# 1) 编模块（需要与设备内核完全一致的构建树；配方见 docs/REPRODUCIBLE_BUILD.md）
bash scripts/reproduce_build.sh                      # 从 tag 起整条链，给出 cam_cap.ko

# 2) 上机：开机脚本已经把基础模块（cam_rails/cam_clk/...）和 cam_cap.ko 拉起来
sh scripts/cam_boot.sh                               # 设备侧；日志 /var/log/cam_boot.log

# 3) 看流
v4l2-ctl -d /dev/video0 --list-formats-ext
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=100 --stream-to=/dev/null
cat /proc/camcap_info                                # 帧率、AE/AWB/AF、时序分布

# 4) 换模式（不用重新加载模块）
echo "mode custom2 1" > /proc/camcap                 # 1920×1080 原生输出
v4l2-ctl -d /dev/video0 -v width=4000,height=2256    # 等价的标准 V4L2 路径

# 5) 四个相机都出现在 Cheese 里（另外三颗要先做用户态上电）
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh
sh scripts/zz_front_cap.sh                           # 前摄 IMX596 上电（另有 zz_uw2.sh / zz_macro_cap.sh）
```

设备侧的实验结果常用 `scripts/zz_ctrl_run.sh <脚本> [参数]`（从开发机推模块 + 脚本上去再执行）。

## 已知边界 / 诚实清单

- **同一时刻只有一路能出流**：四颗相机共用 CAM_MUX 3 / 同一路 CAMSV。
- **驱动不做隐式重路由**：如果引擎还在别的相机上，向 `/dev/video0` 推流会直接返回 `-EBUSY`
  并打印原因（2026-10-09 一次整机死锁的教训，见 `docs/V4L2_CAMERA.md` §25）；要切回主摄先跑
  `echo mode <name> > /proc/camcap`。
- 辅助相机的上电/寄存器表是**用户态**完成的，驱动不会去碰它们的 I²C。
- `hs_video` 240 fps 模式打不满（182 fps）；`custom4`/`custom5` 未收录。
- 暗光下高帧率只能靠增益（曝光被 VTS 限制），会有噪声。

## 来源与许可

- `src/cam_cap.c`、`src/cam_*.c`、`src/ovl_i2c4.c`、`dt/`、`modes/`、`sensors/`、`scripts/`、`docs/`
  为本项目产物，按 GPL-2.0 提供（与内核模块一致）。
- `src/imx586_Sensor.c`、`src/imx586_Sensor.h`、`src/rubensimx582_Sensor.h`、`src/sensor_list.c`、
  `src/imx586_mainline.c`、`src/imx586_rockchip.c` 取自小米开源内核
  <https://github.com/MiCode/Xiaomi_Kernel_OpenSource>（`rubens-s-oss` 分支），版权与许可归原项目。
