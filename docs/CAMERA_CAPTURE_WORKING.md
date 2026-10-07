# IMX582 → CAMSV1 采集链路：可用配置（实测打通 · 完整全帧）

日期：2026-10-06 19:20（§5.1/ §7 于 19:35 补写） · 设备 Redmi K50 / MT6895 (paris) · 内核 `7.2.0-g0b8dd2e87b3d-dirty SMP preempt aarch64`

## 结论一句话

**从 IMX582 经 CSI port 2 采到完整真实图像：4000×3000，12-bit 像素，6000 字节/行，18,000,000 字节/帧；
本地按 RGGB 反马赛克 + gray-world 白平衡 + 转 180°，得到可看的彩色图。**
`frame_ready 1`、`last_result 0`（TG 正常收帧），数据恰好停在 18,000,000 字节处。
一条命令出图：`powershell -File ${K50_REPO}\scripts\k50_shot.ps1 <tag> [dgain]`（见 §7.4）。

| 抓取 | 内容 | nz 字节 | md5 |
|---|---|---|---|
| `frames/h_tpg.bin` | 传感器测试图案 | 10,492,380 | `45b95c332154c0ec835784b67f436e8b` |
| `frames/h_scene.bin` | 实景（未增益，很暗：中位 256/4095） | 14,868,088 | `a403ac4538002aa13e03dd5bdf210c02` |
| `frames/h_bright.bin` | 实景 + 曝光 0x0800 / 模拟增益 0xf0 / dgain 2× | 17,299,755 | `4a7ea89606799c58aa36d32d585acc0e` |

## ★ 三个关键事实（此前全部搞错了）

1. **像素是 12-bit，不是 RAW10。** `PAK_MODE` 必须取 **0x82**。判据：行首出现
   `fc cf ff` **3 字节周期**，按 MTK 12-bit 打包（2 像素/3 字节）解出 `0xFFC = 4092 = 1023×4`（满量程）。
   ⇒ **一行 4000 像素 = 6000 字节**，不是 5000。之前一直按 `xsize=5000` 传，
   每行被砍掉 1/3，再被当成 RAW10 解码 ⇒ 图像必然错。
2. **`PAK_DBL_MODE` 与 `DBL_DATA_BUS` 成对耦合**，正确组合是
   `dbl_data_bus=2` + `pak_mode=0x82` + `pak_dbl=2` + `route_pix_mode=2`。
   其它组合要么丢一半行（extent 只有 7.5 MB，`last_result=-110`），要么整行变成
   `ff ff 00 00 00 00 00 00` 这种匀速微观周期（打包被破坏）。见 `docs/camsv_frame_params.md:77-88`。
3. **`frame_bytes` 就是 CMA 缓冲区尺寸**（`src/cam_cap.c:365`，`module_param(ulong)`，默认 16 MiB），
   满帧 18 MB > 16 MiB ⇒ **insmod 必须传 `frame_bytes=18874368`**，无需重编译（CMA 池 32 MiB）。

## 之前的误判（重要教训）

- 旧文档说「标准 MIPI RAW10、5000 字节/行、有效几何 4000×1500、每帧 7.5 MB」：**全部作废**。
  7.5 MB = 1500 行 只是**写了一半帧**：TG 从不完成（`last_result=-110`），
  DMA 窗口不按帧对齐，于是抓到的 1500 行**跨在两帧边界上**（下半第 N 帧尾 + 上半第 N+1 帧头）。
  **这正是「看起来像两帧拼接在一起」的根因**，不是打包问题、也不是传感器的竖直抽取。
- 「`pak_dbl=0` 的直方图是纯 0xff/0x00 ⇒ 打包正确」是**假证据**：测试图案只有 0/满值，
  12-bit 流被按 10-bit 读也能得到纯 ff/00。判据必须同时看**空间结构**和**行数**。
- 曝光/增益「怎么调都不变」的原因：**16-bit 传感器寄存器必须写两个数据字节**，
  之前 `w3@0x10 0x02 0x02 0x08`（只给 1 字节数据）是非法写入。正确写法
  `w4@0x10 0x02 0x02 0x08 0x00`（曝光 0x0800）、`w4@0x10 0x02 0x04 0x00 0xf0`（模拟增益）、
  `w4@0x10 0x02 0x0e 0x02 0x00`（数字增益 2×）。改对后 nz 从 14.87 M 升到 17.30 M，亮度明显变化。

## 完整可用配置

### 1. 传感器 / 电源（冷启动顺序，见 `scripts/zz_v80.sh`）

```
load: cam_ovl cam_genpd cam_clk2 cam_clk cam_clk3 cam_rails
fan53870 (i2c-11 @0x35): 0x09=0xbf (AFVDD 2.900V) · 0x0a=0x36 (DOVDD 1.804V) · 0x03=0x60
GPIO149 / GPIO20 / GPIO159 / GPIO158 / GPIO164 = high
MCLK pinmux
GPIO155 = reset pulse
i2cdetect -y -r 10  →  0c / 10 / 51
port2_rx71.py       (SENINF / D-PHY 上电与路由)
imx582_bring.py     (I²C-10 @0x10: INIT 112 对 → PREVIEW 111 对 → 0x0100=0x01)
```

**DOVDD（FAN53870 LDO7）不开，主摄就完全不工作**： 这是最初「相机死」的根因。
传感器活着：`0x0100=0x01`（streaming），`0x0112=0x0A`（4 lane），
`0x0340/41=0x0E4A`（VMAX 3658），`0x0342/43=0x1EC0`（HMAX 7872），
`0x034C/4D=0x0FA0`（X_OUT 4000），`0x034E/4F=0x0BB8`（Y_OUT 3000），
`0x0348/49=0x1F3F`（X_END 7999）、`0x034A/4B=0x176F`（Y_END 5999）⇒ 8000×6000 阵列 2×2 binning。
帧周期 = 7872×3658 / 440.78 MHz = 65.3 ms ≈ 15.3 fps，行时 17.86 µs。

### 2. SENINF / CAMSV 路由（`cam_cap.ko` 的 `route` 命令）

```
CSI port 2 (4 lane) → SENINF intf 4 → SENINF mux 1 (0x1a011d00, SRC_SEL=8)
                    → CAM_MUX 3 (0x1a010460, SRC_SEL=1, EN=1) → camsv1@1a110000
```

实测回读：
```
S0_DI_CTRL (csi2+0x20) = 0x002b0011     (VC0 / DT 0x2b / S0_GRP_EN)
cam_mux 3 CTRL = 0x001f8181  OPT = 0x0000ab80  CHK_CTL = 0x0bb80fa0
mux 1 CTRL_0 = 0x00000001   CTRL_1 = 0x001f0108
TOP_MUX_CTRL_0 = 0x03020400
```
`CSI2_IRQ_STATUS = 0x00000325`（FRAME_SYNC + ECC_NO_ERR + CRC_CORRECT + FS/FE_RECEIVE）⇒ D-PHY 模拟侧正确。

### 3. DMA 缓冲 + IOMMU（关键，见 `src/cam_cap.c`）

- 用 `of_changeset_*` 在 `/soc@0` 下**动态加一个 DT 节点** `camcap@1a110000`
  （`compatible="camcap,camsv"`、`reg=<0x1a110000 0x1000>`、`iommus=<disp_iommu phandle 2>`），
  `of_changeset_apply()` → `of_find_device_by_node()` / `of_platform_device_create()` →
  `of_dma_configure(&pdev->dev, np, true)` → `iommu_get_domain_for_dev()`。
  这样 `mtk_iommu_mt6895` 的 `attach_device` 会跑，页表基址被写进
  `REG_MMU_PT_BASE_ADDR (0x1e802000) = 0x7CF00000`（此前恒为 0）。
- **缓冲不能用 IOMMU 设备来分配**：非相干设备会走 `iommu_dma_alloc_noncontiguous`
  → buddy `alloc_pages`，被 `CONFIG_ARCH_FORCE_MAX_ORDER=10`（4 MiB）和开机碎片卡住。
- 正确做法：用**无 IOMMU 的一次性 platform device** 调 `dma_alloc_coherent(frame_bytes)`
  → CMA 给物理 `0xfa500000`（非缓存），再
  `iommu_map(cam_iommu_dom, map_iova=0x10000000, cam_buf_phys, size, IOMMU_READ|IOMMU_WRITE, GFP_KERNEL)`
  → 把**固定 IOVA `0x10000000`** 写进 `IMGO_BASE_ADDR`。卸载时 `iommu_unmap` 再 `dma_free_coherent`。

dmesg 期望：
```
platform soc@0:camcap@1a110000: Adding to iommu group 0
MTK-DOWN IOMMU attach dev=soc@0:camcap@1a110000 ... domid=0 ids[0]=0x2 larb=0 port=2
MTK-DOWN-IOMMU map iova=0x10000000 pa=0xfa500000 size=0x100000 count=0x10
cam_cap: iommu_map: iova 0x10000000 -> pa 0xfa500000, 18874368 bytes
```
**零 IOMMU fault。**

### 4. 采集（`/proc/camcap` 协议）： ★ 已知可用的满帧配置

```
rmmod cam_cap; insmod /root/cam_cap.ko \
    dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 route_pix_mode=2 frame_bytes=18874368
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
   # 顺序 = fmt pxl_start pxl_end lin_start lin_end xsize ysize stride
   # xsize / stride 的单位都是【字节】；12-bit ⇒ 4000 px × 1.5 = 6000
echo arm > /proc/camcap
dd if=/proc/camcap of=/root/h_frame.bin bs=1M count=19
```
（`echo ... > /proc/camcap` 可能打印 `sh: echo: I/O error`，**非致命**，字段确实生效。）

**判据（每次都要看这三样）**
```
frame_ready 1 / last_result 0                     # TG 正常收帧，不是 -110
数据到 17,999,000 而 18,000,000 处为 0            # extent 恰 = 3000 × 6000
/proc/camcap_info: buffer_dma 0x10000000, buffer_phys 0xfa500000,
                   buffer_size 18874368, mapping dma_alloc_coherent (IOMMU IOVA)
```
`nz` 字节数的廉价求法：`dd if=/proc/camcap bs=1M count=19 | tr -d '\000' | wc -c`。
清零缓冲（只用于实验，物理地址稳定在 `0xfa500000` = 4005 MiB）：
```
dd if=/dev/zero of=/dev/mem bs=1M count=18 seek=4005 conv=notrunc
```

### 5. ★ 曝光（决定画面亮度的真正原因）

传感器曝光寄存器 `0x0202` 默认只有 **0x0004 = 4 行 ≈ 0.071 ms**（行时 17.86 µs），
相对整帧 65 ms 等于几乎全黑 ⇒ **之前所有「很暗的图」都是欠曝约 230 倍，不是通路问题。**

| 0x0202 | 行数 | 积分时间 | 12-bit 像素中位 | std |
|---|---|---|---|---|
| 0x0004（默认） | 4 | 0.07 ms | 256 | 4.9 |
| 0x0380 | 896 | 16.0 ms | 272 | 26.2 |
| 0x0E00 | 3584 | 64.0 ms | 272 | 26.2（与 0x0380 完全一致 ⇒ 再长无效） |

> **★ 2026-10-06 晚更正：上表最后一行是"中位字节均值"这个廉价判据饱和造成的假象。**
> 用驱动内 `stats`（每帧 93 750 个 2×2 块的 raw 绿均值）重标，`0x0202` 是**完整 16 位**且到
> `0x6000` 仍线性：`0x0020→260`、`0x0380→386`、`0x0d00→736`、`0x2000→1315`、`0x6000→2638`(clip 31%)。
> 即**不存在"0x0380 / 16 ms 积分上限"**；上限由驱动参数 `exp_max` 决定： 但它**必须 ≤ bring-up 写的 VTS − 128**，
> 因为曝光到达 VTS 时传感器会把帧周期拉长。当前 `exp_max = 0x0c64`（3172 行）+ VTS 3300 ⇒ 32.5–33.3 fps
> （2026-10-06 深夜更新）。
> 详见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §9.2。

写入必须 **16-bit 双字节**：`i2ctransfer -f -y 10 w4@0x10 0x02 0x02 0x03 0x80`。
配合模拟增益 `0x0204=0x00f0`、数字增益 `0x020e=0x0200` 使用。
**黑电平 ≈ 248**（未曝光时的底），出图前要先减掉再拉伸。
长曝光下画面里能清楚分辨窗/灯、家具轮廓与暗部区域；`frames/lit_gam_view.png`、`lit_zoom.png` 是代表图。

#### 5.1 ★ 增益（2026-10-06 晚补测）

**模拟增益 `0x0204`**（曝光固定 0x0380、dgain 0x0400；廉价判据 = 画面中间 64 KiB 采样的字节均值）：

| 写入 `0x0204` | 0x00f0 | 0x01e0 | 0x03c0 | 0x0f00 | 0x3f00 |
|---|---|---|---|---|---|
| 字节均值 | 50.6 | 50.5 | **75.7** | **76.4** | 64.3（反而下降） |

⇒ **0x03c0 已经到顶，0x0f00 与之等价；再往上写被硬件截断**（回读：写 0x0f00 只剩 0x0300）。

> **★ 2026-10-06 晚更正（同一条判据饱和）**：`0x0204` 的真实规则是**只保留低 10 位（掩码 `0x3ff`）**，
> 所以 `0x0f00 & 0x3ff = 0x0300`、`0x3f00 & 0x3ff = 0x0300`： 那两条"截断/退化"现象只是掩码。
> 细扫（exp=0x0380，回读无截断）：`0x0300→385`、`0x0320→404`、`0x0340→429`、`0x0360→463`、
> `0x0380→516`、`0x03a0→599`、`0x03c0→764`、**`0x03f0→1903`**（≈4.9×）、`0x07ff` 回读 `0x03ff` → 满屏。
> 即**可用区间是 `0x0100..0x03f0`**，但 `0x03a0` 以上曲线很陡（一个码换来的光量 > 一个 AE 死区宽度），
> 所以 AE 的上限默认压在 `0x03a0`。详见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §9.2。

**数字增益 `0x020e`** 有效且单调：0x0400 / 0x0800 / 0x1000 → RAW 中位数 400 / 516 / 776。
但 0x1000 时 p99 已顶到 4095，**约 1% 像素过曝**（用户判定"失真"）⇒ **实用上限 0x0800，推荐 0x0400。**

**★ I²C 读回顺序**：必须 `i2ctransfer -f -y 10 w2@0x10 0x02 0x02 r2@0x10`（**先写寄存器号，再读**）。
写成 `r2@… w2@…` 时读回值无意义： 我早期因此误判"增益写不进去"。

#### 5.2 推荐工作点（用户选定）

```
0x0202 = 0x0380   曝光 896 行 ≈ 16 ms（**不是上限**，是当时手调的推荐点；见上面更正）
0x0204 = 0x0300   模拟增益（当时的手调点；真实可用到 0x03f0）
0x020e = 0x0400   数字增益（动态范围保留最多的一档）
```

> 2026-10-06 晚起，**这条手调工作点已经被驱动内 AE 取代**：驱动默认 `auto_exposure=0`(Auto)，
> 它会自己走 `曝光 → 模拟增益 → 数字增益` 并在 `again=0x03a0`、`dgain=0x0100` 上稳定（均值 1304）。
> 手调仍可用（`auto_exposure=1` + 上面三个控件/参数），见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §9。

对应抓取：`frames/pos2_0400.bin`（用户认可的"第一张"）、`frames/room1.bin`（一键流水线产物）。
两档备选也留着：`frames/pos2_0800.bin`（更亮）、`frames/pos2_1000.bin`（过曝失真，仅作反例）。

### 6. 本地解码（12-bit，`scripts/analyze32.py` / `render_full.py` / `render_view.py`）

```python
d = np.fromfile("h_frame.bin", np.uint8)[:3000*6000]
g = d.reshape(3000, -1, 3).astype(np.uint16)          # 2000 组 = 4000 px
b0, b1, b2 = g[:, :, 0], g[:, :, 1], g[:, :, 2]
P = np.empty((3000, 4000), np.uint16)
P[:, 0::2] = b0 | ((b1 & 0x0F) << 8)
P[:, 1::2] = (b1 >> 4) | (b2 << 4)                    # 12-bit, 0..4095
```
产物：`frames/h_bright_view.png`（实景，对比度增强）、`h_tpg_view.png`（测试图案自检）、
`h_bright_full_gray.png` / `h_bright_color.png`（RGGB 假设，4000×3000 / 2000×1500）。

**测试图案自检（用于验证几何）**：`i2ctransfer -f -y 10 w3@0x10 0x06 0x01 0x02`（见 `imx586_Sensor.c:4273-4286`）。
本机实测图案是 **3 电平条**：列 0-24 ≈ 4086（白）、列 25-74 ≈ 2046（中灰）、列 75-99 = 0（黑），
且 3000 行中任意行的低/高位游程结构完全一致 ⇒ 每行确实是 4000 像素、无截断、无接缝。

## 7. ★ 彩色：Bayer 相位 = RGGB（已定案）+ 读出方向转 180°

### 7.1 相位（两条独立证据）

1. **厂商代码**：`src/imx586_Sensor.c:256`
   `.sensor_output_dataformat = SENSOR_OUTPUT_FORMAT_RAW_4CELL_HW_BAYER_R`
   MTK 命名里 `_RAW_*_**R**` = 首像素为 R，即 **RGGB**。
   同表其他字段：`.i2c_addr_table = {0x34, 0x20, 0xff}`、`.mclk = 24`、`.mipi_settle_delay_mode = 0`。
2. **数据自证（不依赖任何文档）**：把 4000×3000 按 2×2 拆成四个相位，比较两个棋盘格各自的内相关：

   | 棋盘格 | 内相关（三次抓取） | 含义 |
   |---|---|---|
   | `(偶,偶)` vs `(奇,奇)` | 0.841 / 0.839 / 0.841 / 0.941 | R vs B，差异大 |
   | `(偶,奇)` vs `(奇,偶)` | **0.978 / 0.979 / 0.978 / 0.983** | ★ 两个绿，最相似 |

   四相位均值 `[ee] 465 [oo] 352 [eo] 493 [oe] 496`： 两个绿几乎相等，R > B（暖光室内合理）
   ⇒ **绿色落在 row+col 为奇的棋盘格** ⇒ RGGB。（若为 GRBG/BGGR 则另一个棋盘格才是绿。）

### 7.2 读出方向：整体 180°

用户实测（m03648）：「图片反了180°」。**翻转必须在反马赛克之后做**：
180° 旋转把 `(偶,偶)` 映射到 `(奇,奇)`，等于把 RGGB 静默变成 BGGR；先转再解颜色必错。

```python
m = np.stack([R, G, B], -1)
if FLIP180: m = m[::-1, ::-1]      # 传感器读出方向与手机姿态相反
```

### 7.3 反马赛克与白平衡（`scripts/render_color.py` / `render_set.py`）

```python
P  = np.clip(P - np.percentile(P, 0.2), 0, None)   # 每帧实测黑电平（随增益变：240/228/200）
R = up(P[0::2, 0::2]);  B = up(P[1::2, 1::2])
G = 0.5 * (up(P[0::2, 1::2]) + up(P[1::2, 0::2]))  # up = PIL 'F' + BILINEAR 上采样
luma = (R + G + B) / 3;  sel = (luma > p20) & (luma < p85)
gw = (G[sel].mean() / R[sel].mean(), 1.0, G[sel].mean() / B[sel].mean())   # gray-world
```

实测（`frames/color_frame.bin`）：反马赛克均值 **R 152.5 / G 189.7 / B 87.5**（G 最高 ✓ Bayer 特性）
⇒ gray-world 增益 **R×1.22、B×2.16**（暖光室内，蓝要拉 2.2 倍才中性）。
产物：`frames/color_wb_gray[_view].png`（gray-world）、`color_wb_patch[_view].png`（white-patch）、
`color_raw[_view].png`（不做白平衡，即传感器实际输出的暖绿偏色）。

### 7.4 ★ 一条命令出图

```
powershell -File ${K50_REPO}\scripts\k50_shot.ps1 <tag> [dgain_hex]
#   tag       例 "room1"  ->  frames/room1.bin / room1_color.png / room1_view.png
#   dgain_hex 0400(默认，推荐) | 0800(更亮) | 1000(约 1% 过曝)
```

链路：`k50_shot.ps1`（Windows）→ `zz_shot_remote.sh`（WSL，scp + ssh）→ `zz_shot.sh`（设备侧
insmod/route/曝光增益/cfg/arm/dd）→ scp 回 `frames/<tag>.bin` → `render_set.py` 出彩图。
设备侧每步都是 `nice -n 19`、单任务串行（见 `CAMERA_NOTES.md` §9.3 的死机纪律）。

## 待办

1. ~~判定有效几何~~ **已定：4000×3000，12-bit，6000 B/行。**
2. ~~亮度~~ **已解决**：曝光 0x0202 = 0x0380（当时手调的推荐点，**不是上限**）+ 模拟增益 0x0300 + 数字增益 0x0400；
   出图前按每帧实测的黑电平（p0.2 ≈ 200~248）相减再拉伸。
3. ~~确认 Bayer 相位~~ **已定案：RGGB**（厂商 `SENSOR_OUTPUT_FORMAT_RAW_4CELL_HW_BAYER_R` + 四相位相关性双证；
   2026-10-06 深夜又用"关 AWB + 已知色偏"的物理实验独立确认 **(0,0) tap = 物理 R**）。
   同一轮还定位并修好了真正的 R↔B 互换： 它**不是**相位问题，而是 YUYV 色度槽顺序（`byte1` 必须是 Cb、
   `byte3` 必须是 Cr）：见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §11.4。
   方向 **180° 已修正**（用户在 §7.2）。
4. ~~同步进冷启动流程~~ 已由 `scripts/zz_shot.sh` + `k50_shot.ps1` 承担；`scripts/zz_v80.sh` 尾部补采集步骤。
5. 剩下的是画质而非通路问题：镜头是否对焦、白平衡算法选型（gray-world 偏冷 / white-patch 偏蓝）、
   单帧噪声（未做多帧累加）、以及 ISP 侧（AF/AE/坏点/去马赛克质量）：目前全部在 CPU 上做。
