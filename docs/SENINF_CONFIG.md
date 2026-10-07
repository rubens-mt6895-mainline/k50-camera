# MT6895 SENINF/CSI2 配置移植指南（ISP7.1 参考 → ISP6S rubens）

参考源码：`${K50_REPO}\isp71_ref\`（MotorolaMobilityLLC/kernel-mtk，分支
android-13-release-ttt，drivers/media/platform/mtk-isp/camsys/isp7_1/cam/）。
关键文件：
- `mtk_csi_phy_2_0/mtk_cam-seninf-hw_phy_2_0.c`：完整上电/配置序列（3227 行）
- `mtk_csi_phy_2_0/mtk_cam-seninf-seninf1.h|seninf1-csi2.h|seninf1-mux.h|tg1.h`：数字寄存器位域
- `mtk_csi_phy_2_0/mtk_cam-seninf-top-ctrl.h`：TOP 控制块
- `mtk_csi_phy_2_0/mtk_cam-seninf-mipi-rx-ana-cdphy-csi0a.h`：模拟 RX 位域
- `mtk_cam-seninf-route.c`：mux 路由决策逻辑
- `mtk_cam-sv-regs.h`：CAMSV 模块寄存器（抓帧 DMA 用）

## 来源与时效

**整理基础（两类来源，性质不同）**

1. **ISP7.1 参考源码**：本机 `${K50_REPO}\isp71_ref\`（MotorolaMobilityLLC/kernel-mtk，分支
   android-13-release-ttt）。本文配置序列的主要依据是 `mtk_csi_phy_2_0/`；实际设备（HyperOS）
   用的是同目录下的 `mtk_csi_phy_3_0/`（见 ▲6）。
2. **vendor（ISP6S / `imgsensor/src/common/v1_1`）源码抓取** = 下文表格"依据"列写的 **`v1_1 dump`**。
   ⚠️ 澄清：它**不是设备寄存器 dump**，而是 vendor `imgsensor/src/common/v1_1/seninf.c`、
   `seninf_drv.h`（以及 `isp6s/seninf/seninf_impl.c`）的 grep/sed 抓取产物，行内偏移是
   **源码常量**，因此需要被下文 ▲ 实测条目覆盖。

**`v1_1 dump` 的可复核痕迹（本次已定位）**

- 抓取脚本：`z_seninf_impl.sh`（`sed -n '40,140p'` 于 `common/v1_1/seninf.c`）、`z_seninf_mux.sh`、
  `z_seninf6s.sh`；检索路径为 WSL `${HOME}/fp_work/cam/ksrc/...`。
- 落盘产物：`out/seninf_impl.c.txt`、`out/seninf_impl.txt`、`out/seninf_mux.txt`、`out/seninf6s.txt`、
  `out/6s_drv.txt`、`out/6s_muxdef.txt`（mtime **2026-09-30 22:07–22:31**）。
- 原始源码树（WSL `${HOME}/fp_work/cam/ksrc/`）本次**未能逐字复核**（本机 UNC 访问被拒），
  行号级引用一律以落盘产物为准。

**来源未记录（待补）的条目**

- 表中若干 `v1_1 dump` 行（如"每口 CSI2_EN / CSI2_IRQ_STATUS / MUX_CTRL_0"）在已落盘产物里
  **找不到对应的寄存器读数**（产物只有源码常量与打印格式串）⇒ 这类行的来源标
  **`来源未记录（待补）`**。
- `out/seninf_regs.log`（2026-10-01 02:16，设备 `/dev/mem` 读 0x1A004000 起）**全 0，不可用**，
  不作为依据。
- 另一组独立实测把口页基准写死为 `CTRL=0x1A014200 / CSI2=0x1A014A00`
  （`port2_v14.py:24`、`port2_v21.py:24`、`lane_probe.py:22-23`），与
  `seninf_all_ports.py:46` 的 `SENINF + 0x200 + i*0x2000` 自洽： 这是本文"每口"行的旁证。

**时效政策**

- 凡标 **▲** 的行/条目 = **已被后续实测会话修正**，修正值优先；**原文数值一律保留**以便对照。
- 「探针策略」「取景器」「前置条件（已验证）」三节内容仍然有效、保持原样；其中出现的
  `口基+0x8D8` 请按 ▲3 读作 `口基+0x8DC`。

**已定案（2026-10-05 复核，四条独立证据： 本文原值正确，无需改动）**

1. **每口 MUX_CTRL_0 = `口基+0xB00`**（即 `if_base + 0x0d00 + 0x1000*seninfIdx`，口2 = `0x1A014D00`）**正确**。
   `CAMERA_NOTES.md §2「2026-10-02 深夜」「init_iomem 循环解码」条` 记的口2 `mux=0x1A014F00` 属 **TG 空间**，不是 mux： `0x0f00` 是 **3_0 的
   `reg_if_tg[i]`**（2_0 里 TG = `0x0600`），该侧已在 `CAMERA_NOTES.md §2「2026-10-02 深夜」「2026-10-05 复核修正」条` 就地修正（原值保留）。
   证据：
   - `isp71_ref/mtk_csi_phy_2_0/mtk_cam-seninf-hw_phy_2_0.c:120-121`：`reg_if_mux[j] = if_base + 0x0d00 + 0x1000*j`；同文件 `:116` TG = `0x0600`。
   - `isp71_ref/mtk_csi_phy_3_0/mtk_cam-seninf-hw_phy_3_0.c:161-162`：mux 同样 `0x0d00 + 0x1000*j`；`:156` TG = **`0x0f00`**（这正是 `0xf00` 被误当 mux 的来源）。
   - 设备 `mtk-cam-isp.ko` 反汇编 `isp_ko.asm`：两处 mux 循环初值 `add x_, x_, #0xd00`（`0x5c5ac`、`0x7aaf4`）。
   - 实测已配通：`MUX12 = 0x1a01cd00 = 0x0d00 + 0x1000*12` ✓（若按 `0xf00` 应为 `0x1a01cf00`，与实测不符）。
2. **每口页步长 `0x2000` 与 driver 的 `0x1000` 不矛盾**（两个不同地址空间，恒等而非冲突）：
   driver 的 `reg_if_ctrl[i]` 按 **seninfIdx** 步长 `0x1000`，而端口→seninfIdx 映射为 `port*2`
   （据口2 实测 `ctrl=0x1A014200` 反推 idx=4）⇒ `0x200 + 0x1000*4 ≡ 0x200 + 0x2000*2`，
   对 port 0–5 两种写法完全等价。`0x1000` 只属于 TOP 内 flat mux 阵列（见 ▲1 表行）。
   ⚠️ 更正（2026-10-05 晚复查）：`CAMERA_NOTES.md §2「2026-10-02 深夜」「init_iomem 循环解码」条` 的
   `ctrl[i]=if+0x200+0x1000i` / `csi2[i]=if+0xa00+0x1000i` **不是笔误**： 与本节 `port*2 = seninfIdx`
   的口径完全一致（i 是 seninfIdx）。该条**唯一的错**是把 `mux[i]=if+0xf00+0x1000i` 的块名写成 mux（`0xf00` 是 3_0 的 TG 块；mux 实为 `if+0x0d00+0x1000*j`，见 ▲1 表行）。本文此前"笔误在彼侧"的标注作废。

## 地址映射（MT6895 实测/推断）

| 块 | 地址 | 依据 |
| --- | --- | --- |
| SENINF TOP + CAM MUX | 0x1a010000 + 0x000..0x1FF | rubens v1_1 dump: TOP_MUX_CTRL_0=base+0x10 |
| CAM MUX CTRL/TG源选择 | 0x1a010400..0x40C + MUX_OPT 0x420 | v1_1 dump + seninf_impl.c |
| SENINF 口 i (0-9)，i = 口页号 | 0x1a010000 + 0x200 + i*0x2000 | v1_1: SENINF1_CTRL=base+0x200；10口×0x2000<0x20000。**步长 0x2000 经实测旁证保留不改**（口页 = `if+0x200+0x2000*i`：i=2 → `0x1A014200` ✓，旁证 `port2_v14.py:24`、`port2_v21.py:24`、`seninf_all_ports.py:46`）。⚠️ 索引口径注意：driver 内部按 **seninfIdx 步长 0x1000**（`phy_2_0.c:115`），口2→seninfIdx=4（`0x200+0x1000*4`）；本表 `i` 是**口页号**（`0x200+0x2000*2`），两者对 port 0–5 恒等。`CAMERA_NOTES.md §2「2026-10-02 深夜」「init_iomem 循环解码」条` 把每口步长写成 `0x1000i`：**该步长口径正确**（driver 按 seninfIdx 索引，同本表口径注意项），**仅块名 `0xf00` 标错**（应是 TG；mux 实为 `0x0d00 + 0x1000*j`）；彼侧已就地加「2026-10-05 复核修正」条 |
| 每口 CTRL | 口基+0x000（即 +0x200） | v1_1 dump |
| 每口 CSI2_CTRL | 口基+0x010（+0x210） | 与 ISP7 相对布局一致 |
| 每口 CSI2_EN | 口基+0x800（+0xA00） | v1_1 dump |
| 每口 CSI2_IRQ_STATUS | 口基+0x8C8（+0xAC8，写1清） | **来源未记录（待补）**（原标 `v1_1`，落盘产物内无对应读数） |
| ▲ 每口 CSI2_PACKET_CNT | 口基+0x8D8（+0xADC，被动计数）；**实测正确地址 = per-csi2 块 +0xDC（口2 = `0x1a014adc`）** | 原 `v1_1`；实测修正 `CAMERA_NOTES.md §2「2026-10-04 深夜」`（"PKT `0x1a014adc` = 0" 条）、`§2「2026-09-30 晚补充」`（"CSI2_EN=+0xA00" 条，含 `CSI2_PACKET_CNT=+0xADC`）与 csi2 块 `+0xA00` 换算一致 |
| 每口 MUX_CTRL_0 | 口基+0xB00（+0xD00） | **来源未记录（待补）**（原标 `v1_1`）。✅ 已定案：该值**正确**；`CAMERA_NOTES.md §2「2026-10-02 深夜」「init_iomem 循环解码」条` 的 `mux=0x1A014F00` 属 TG 空间。详见「来源与时效」已定案 1 |
| ▲ TOP 内 flat SENINF mux 阵列 `reg_if_mux[j]` | `if_base + 0x0d00 + 0x1000*j`（j=**mux 号 0–12，非口号**；j=12 → MUX12 = `0x1a01cd00`，已配 EN=1 SRC_SEL=4） | 实测修正 `CAMERA_NOTES.md §0 决定性突破链`（"两个寄存器地址修正" 条）：原记 `+0xf00` **是错的**（`0xf00` 是 TG 区）；另证 `mtk_cam-seninf-hw_phy_2_0.c:120-121`、`..._3_0.c:161-162`、`isp_ko.asm`（`0x5c5ac`/`0x7aaf4` 初值 `#0xd00`） |
| ▲ SENINF_TOP_PHY_CTRL_CSI2 | `TOP + 0x48`（**不是 `0x68`**；`0x68` 属 TG 区、写不进） | 实测修正 `CAMERA_NOTES.md §0 决定性突破链`（"两个寄存器地址修正" 条） |
| DPHY/CDPHY 模拟 RX | 0x11c80000 + 0x20000 | vendor DT "ana-rx" reg |

**注意**：口内子块（CTRL/CSI2/MUX/TG）在 ISP7 里是独立基地址，6S 是平铺偏移。
ISP7 的子块内偏移照用：CSI2_EN=csi2块+0x0，CSI2_OPT=+0x4，HDR_MODE_0=+0x8，
MUX_CTRL_0=mux块+0x0，MUX_CTRL_1=+0x4，MUX_OPT=+0x8。6S 的对应关系按上面
表里 v1_1 dump 的实际值优先。

**▲ PHY 版本（重要）**：HyperOS 实际用的是 **`mtk_csi_phy_3_0`**，**不是本文复刻的 `mtk_csi_phy_2_0`**
（依据：HyperOS dmesg 打印逐句匹配 `phy_3_0.c`；来源 `CAMERA_NOTES.md §2「2026-10-05 凌晨」`（"D1 ★★★" 条）、`DIFF_REPORT.md:29-30`）。
**但基址仍是 2_0 风格**（port2 = `0x11c88000` / `0x9000` / `0xa000`）：即"2_0 风格基址 + 3_0 语义"
（3_0 语义：时钟 lane settle、`SPARE0=0xf1`、trail 计算、RESYNC full-write、`CDR_CK_DELAY=4`、
无 RESERVE/RST_MODE）。⚠️ **3_0 头文件里的基址表属于别的芯片，不要用**（其中 port2 写成
`0x4000/5000/6000`）；试过，真 port2 块全静默。来源 `CAMERA_NOTES.md §0 决定性突破链`（"MT6895 ANA 布局实证" 条）。

## 配置序列（从 hw_phy_2_0.c 提取）

1. **模拟 BG 上电**（csirx_phyA_power_on，目标口的 ana base）：
   - ANA_8 的 6 个 EQ_OS_CAL_EN=0；ANA_0 的 BG_LPF_EN=0、BG_CORE_EN=0
   - udelay(200)；BG_CORE_EN=1 → udelay(30) → BG_LPF_EN=1 → udelay(1)
   - 6 个 EQ_OS_CAL_EN=1 → udelay(1)
2. **EQ tune**（mtk_phy_csi_cdphy_ana_eq_tune）：ANA18/1C/20 的 EQ_IS=1、EQ_BW=1（每 lane）
3. **DPHY init**（csirx_dphy_init，ana_dphy_top base）：每 lane HS_PARAMETER：
   settle_delay_dt（默认 0x23?）、HS_PREPARE=2、**▲ HS_TRAIL：实测 = `0x1a`（26）**
   （本文原仅写"HS_TRAIL（ctx 值）"、未给数值；`CAMERA_NOTES.md §2「2026-09-30 深夜：SENINF 配置序列情报」`（"CSI_CLK_273MHZ 参数组" 条）记 `0x34`、
   `CAMERA_NOTES.md §2「2026-10-01 接手会话」`（"口2 原厂参数" 条）记"口2 原厂 0x20"：**两者均与实测 26 冲突**；
   计算链 dphy_trail=68 / ui_224=163 / SENINF_CK=273MHz → `ceil((163-68)*273e6/1e9)=26`。
   来源：`hyperos_workstate\DIFF_REPORT.md:30` 与 `CAMERA_NOTES.md §2「2026-10-05 凌晨」`（"D2: HS_TRAIL=0x1a" 条）： `DIFF_REPORT.md:30`
   明确标注"CAMERA_NOTES.md 称口2 原厂 hs_trail=0x20 与实测 26 冲突，该笔记待更正"）、
   data_rate<800M 时 HS_TRAIL_EN=1
4. **CSI2 数字**（csirx_seninf_csi2_setting，csi2 块）：
   - DBG_CTRL: RG_CSI2_DBG_PACKET_CNT_EN=1（启动包计数 → 我们的探针！）
   - RESYNC_MERGE_CTRL: CYCLE_CNT_OPT=1
   - 4 lane: CSI2_EN = (1<<4)-1 = 0xF
   - CSI2_OPT: CPHY_SEL=0；HDR_MODE_0: HEADER_MODE=0、HEADER_LEN=0
5. **SENINF CTRL**（csirx_seninf_setting，ctrl 块）：SENINF_CSI2_CTRL 的
   RG_SENINF_CSI2_EN=1；后接 SENINF_EN=1
6. **SENINF mux**（set_mux_ctrl，mux 块）：
   - CTRL_1: MUX_SRC_SEL=seninf 口号、PIX_MODE_SEL=pixel_mode（RAW10→2px/周期=1?）
   - MUX_OPT: HSYNC_POL/ VSYNC_POL
   - CTRL_0: 写 |0x6（SW_RST+IRQ_RST）再写 &~0x6
   - MUX_EN（CTRL_0 bit0）=1
7. **TOP mux**（set_top_mux_ctrl，TOP 块）：TOP_MUX_CTRL_0/1/2/3 每 8bit 一个
   SENINF_MUX 的源选择（MUX1..13）；把目标 mux 的源=seninf 口
8. **CAM MUX**（set_cammux_src，TOP 块 0x400 区）：CAM_MUXx_SRC_SEL（4bit/个）=
   seninf mux 号；CAMSV 的 TG 从 CAM MUX 取数据
9. **CAMSV TG+DMA**：mtk_cam-sv-regs.h + cam_regs.h（本地 fp_work/cam/cam_regs.h），
   SV 模块 0x1a110000 起（camsv0-7）+ 0x1a180000（camsv8-11）。配置 TG帧时序、
   DMA IMGO 目标地址、使能后等 IRQ/查 INT_STATUS。

## 探针策略（不用知道物理接线）

- 逐口执行 1-5 步，读 CSI2_PACKET_CNT（口基+0x8D8）两次间隔 100ms；
  **计数增长的口 = 主摄 MIPI 实际接入的口**。
- IMX582 preview 输出尺寸：运行时读传感器 0x034C/D（x_out_size）、0x034E/F。
- MIPI 数据率 = pixel_rate×10bit/4lane；preview 模式由 PLL 寄存器决定（~1.4G 量级）。

## 取景器

- `${K50_REPO}\cam_view.c`：读 /tmp/frame.rgb（头 "K50F"+u32 w+u32 h+RGB888），
  最近邻缩放写 /dev/fb0，每 0.5s 重刷。抓帧侧负责 RAW10→RGB888（简单 nearest
  邻去马赛克，RGGB）后写此文件。
- 编译：`aarch64-linux-gnu-gcc -O2 -static -o cam_view cam_view.c`

## 前置条件（已验证 ✓）

cam_load.sh → cam_go.sh：电源域 ON、电轨 ON、PMIC VOUT、MCLK 三层全开、
传感器 streaming（0x0100=0x01）。抓帧模块按 cam_clk 的模式加载
（insmod 前确认 provider 可用，见 cam_probe_dbg.ko）。
