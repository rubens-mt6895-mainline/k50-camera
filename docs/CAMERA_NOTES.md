# K50 (rubens/MT6895) 摄像头移植笔记

> 本文 = 摄像头子系统的**时间线 + 结论**。寄存器/序列速查见 [`SENINF_CONFIG.md`](SENINF_CONFIG.md)；项目总状态见 [`project_memory.md`](project_memory.md)。
> 阅读顺序：§0 现状 → §1 硬件与资产 → §2 时间线（正序） → §3 路线选择 → §4 禁令与教训。
> 历史结论一律保留原始记述；已被推翻的结论**就地标注**而不删除。

---
## 0. 当前状态与卡点（2026-10-05 晚最新）

### 决定性突破链
1. **相机 MMIO 死区根因**：cam_ovl 的 overlay 未应用（routeA 里 insmod 静默失败）→ cam_genpd attach 无效 → cam_main 域 OFF → cam_m 模块门控块 0x1a000000 全关 → **整个 0x1a00-0x1a17 相机寄存器区读0写丢**。修法：rmmod/insmod cam_ovl（确认 dmesg `of_overlay_fdt_apply=0`）+ rmmod/insmod cam_genpd（8/8 attach）→ genpd 正规上电（含 cam_lp-* subsys 时钟）→ 门控 sta=0xffffff87，区域复活。
2. **内核侧写入确认**：cam_mmtest.ko（构建法见上节）ioremap 写 CSI2 EN=0xF/RESYNC=0x300df106/DBG/CTRL 全部粘住。区域复活后 devmem 也能读了。
3. **两个寄存器地址修正**：`SENINF_TOP_PHY_CTRL_CSI2 = TOP+0x48`（不是 0x68！0x68 是 TG 区，写不进）；`reg_if_mux[j] = if_base + 0x0d00 + 0x1000*j`（0xf00 是 TG！）。MUX12=0x1a01cd00，已配 EN=1 SRC_SEL=4（HyperOS 工作态 mux[12] en1 src4 的复刻）。
4. **MT6895 ANA 布局实证 = 2_0 风格基址**（port2=0x11c88000/9000/a000）+ 3_0 语义（时钟 lane settle、SPARE0=0xf1、trail 计算、RESYNC full-write、CDR_CK_DELAY=4、无 RESERVE/RST_MODE）。3_0 头文件的基址表（port2=0x4000/5000/6000）属于别的芯片，**不要用**：v22 试过，真 port2 块全静默。
5. **lane FSM 首次观测到活动**（配置 settle/trail 后）：dataFSM=0x20801080（DL0=0x80/DL1=0x10/DL2=0x80/DL3=0x20）、clkFSM=0x120（CL0=0x20）：传感器信号到达 DPHY 数字层（此前所有实验全是 0x1 静默）。但注意 vendor 映射（LC0=2）与 schem 映射（LC0=4）下 CL 都见过 0x20，**0x20 不能证明时钟锁定**。
6. ko 反汇编再确认：4d1c lane 表（LD0=1/LD1=3/LD2=0/LD3=4/LC0=2）、SPARE0、LANE_EN 语义与 Moto 完全一致。

### 当前卡点（PKT=0 的剩余嫌疑，按优先级）
- **⚠️ 最新（2026-10-05 晚）：唯一未闭环项 = GPIO158/159（vcam_ldo/dvdd）物理低 → HS 驱动器无电 → DPHY 只见 LP-11**。内核 GPIO 请求路径（gpio linehandle）全 EINVAL、devmem `DO_SET` 不反映物理电平；详见 §2「2026-10-05 晚」的「健康窗口突破」节。**下方四条为 2026-10-05 下午的快照，保留备查。**
- **FSM 语义未知**：0x80/0x20/0x10 各 lane 状态不一致，无法判断"时钟锁定"vs"仅偏置"。HyperOS 侧无 devmem 拿不到工作态 FSM 对照。
- 传感器 TX 是否真在发 MIPI HS：fc 寄存器只证明时序发生器在跑。鉴别法=前端相机或 IMX596 对照（无 init 表，未做）。
- CSI2 FIFO 是否需要下游 mux/cam_mux 全链 drain 才计数（mux12 已配 en+src4，cam_mux0 未配）。
- SENINF_DBG 调试端口只回显 sel 值，拿不到原始数据（可能需要特定 DBG_CTRL 配置）。

### 下一步（按序）
1. 配 cam_mux0（src=mux12，pcsr=if+0x400，gcsr=if+0x300，set_cammux_src/cammux 函数）补全 drain 链 → 看 PKT。
2. 若仍 0：给 CSI2 IRQ_EN=0xffffffff 后读 IRQ_STATUS（resync/data-not-enough 错误计数由 IRQ 驱动递增）。
3. 若仍 0：CAMSV DMA 直抓（绕过 PKT 计数语义问题，Route A 原计划）。
4. 手机时钟又漂了（慢约 8h），05:00 关机是手机时钟：注意换算。

---
## 1. 硬件与资产

### 1.1 模组与参考驱动
- 主摄 Sony **IMX582**（48MP OIS），前摄 Sony **IMX596**（20MP），8MP 超广角 + 2MP 微距。
- 参考驱动：小米开源 `MiCode/Xiaomi_Kernel_OpenSource` 分支 **rubens-s-oss**（kernel 4.19），已稀疏克隆到
  WSL `${HOME}/fp_work/cam/ksrc`。
- IMX582 驱动：`drivers/misc/mediatek/imgsensor/src-v4l2/common/rubensimx582_mipi_raw/`（V4L2 subdev 风格，比老式 ioctl 更接近主线）。

### 1.2 原厂 vendor DTB 的 MMIO 地图
- `seninf_top@0x1a010000` base 0x1a010000 size 0x20000，ana-rx 0x11c80000，中断 0x1bc。
- `camsv0..10`（CSI-2 接收）@ 0x1a110000 / 0x1a111000 / ... 0x1a181000。
- `imgsys_fw@0x15000000`（ISP 固件）。
- `camisp_l13/l14/l25/l26`（larb / 内存路径）。
- 电源域 cam_main/cam_suba/b/c/mraw，时钟 clk_cam_seninf + 各路 top_seninf。
- **CCI（摄像头专用 I2C）节点不在主 DTB**，在厂商相机驱动里。

### 1.3 主摄上电时序 pw_seq 与 chip ID 读法
- I2C 写地址 `0x34`（7-bit 0x1a），另一地址 `0x20`。
- chip ID：`read 0x0016<<8 | read 0x0017`，应为 **0x0582**。
- 上电时序（pw_seq）：
  1. RST 拉低
  2. AFVDD 2.9V → 2.9ms
  3. AVDD1(VCAM_LDO) → 1.2ms
  4. AVDD 2.9V / AVDD2 1.8V / DVDD 使能
  5. DOVDD → 1.8ms
  6. MCLK 24MHz + driving current
  7. RST 拉高 → 3ms 后可 I2C

### 1.4 现状与路线（2026-09-27 快照，结论见 §3）
- 主线无任何 MTK 现代相机驱动（CCI/seninf/camsv/imgsys 全缺）。
- 要从 vendor 4.19 驱动逆向：先 CCI I2C 驱动 → 通电读 0x0582 → 再 seninf/camsv MIPI 收流 → larb/dma → imgsys ISP。
- 这是多阶段工程，不是一次能完成。当前已具备硬件地图 + 参考源码。

### 1.5 历史阻塞（2026-09-25，⚠️ 已解除，留存备查）
- 传感器 I2C 走 `i2c-mtk`（CCI 引擎），imgsensor_i2c.h 里 `#include "i2c-mtk.h"`、`mtk_i2c_transfer()`。
- **该 CCI 引擎驱动 `i2c-mtk.c` 不在小米开源 rubens-s-oss 里**（全树搜索无此文件）。即寄存器地图没开源。
- 下一步只能：从原厂 vendor 镜像里抠出编译好的 `i2c-mtk.ko` 反汇编，或从同款 MTK CCI 的其它设备开源树找寄存器定义。
- 未拿到 CCI 寄存器前，无法写 mainline CCI I2C 驱动，也就读不出 chip ID。

<!-- K50-RUBENS-DOC-CANARY:RMT6895-C8BDA554A1EC -->

---
> **本节阻塞已于 2026-09-27 解除**：`i2c-mtk`（CCI 引擎）是可选封装层，imgsensor v4l2 框架全走标准 I2C 子系统，主线 i2c-mt65xx 驱动够用。详见 §2 的「2026-09-27 重大转折」一节。

---
### 1.6 CAMSV（CSI-2 接收）寄存器表

来源：vendor `mtk_cam-sv-regs.h`（2026-09-30 深夜收录）。

- CAMSV0 基址 **`0x1a110000`**（`camsv0..10` 依次 +0x1000 至 `0x1a181000`，见 §1.2）。
- 偏移：`CLK_EN=0x60`、`TG_SEN_MODE=0x100`、`TG_VF_CON=0x104`、`GRAB_PXL=0x108`、`GRAB_LIN=0x10C`、`FRMSIZE_ST=0x138`、`IMGO_BASE=0x700`、`XSIZE=0x710`、`YSIZE=0x714`、`STRIDE=0x718`、`FBC_CTL1=0x240`。
- 实测：CAMSV0 `frmsize_st=0`、`inter=0x102`（TG idle）： 测试图案数据已到达 CAM MUX checker（见 §2「2026-09-30 深夜 II」）但 CAMSV0 收不到。
- **未解项**：① 6S 的 `CAM_MUX_EN` 写入位置/机制（ISP7.1 是 `0x410`，6S 拒写，或有 shadow/next-ctrl）；② CAMSV0 对应哪个 cam_mux（`cam_mux_num=23` vs 8 个 camsv + 11 个 cam 口，映射未定）；③ CAMSV `TG_SEN_MODE(0x100)` / `PATH_CFG(0x110)` 是否需额外配置。
- CAMSV DMA 之前必须过 **IOMMU**（dmesg 有 `MTK-DOWN-IOMMU` map 记录，需 iova）。

### 1.7 主线无 seninf 驱动时的 vendor 快照线索

- 设备无 seninf 驱动、无 `/dev/video*`、DT 无 seninf 节点；vendor 快照 `isp6s/seninf` 只有 mux switch 部分：`seninf_cfg.h` 里 **`base=0x1A004000`**、**`ANA=0x11C80000`**；impl 里有 **`MUX0_OPT=0x420`**、**`MUX_CTRL=0x400`**、**`CHK_CTL=0x500`**（`SENINF_CAM_MUX0_OPT` 即 `0x420`）。
- **`0x1A004000` 读全 0（未使能）**。出路 = 移植 seninf 驱动（mtk-seninf），或 cam_ovl overlay 补节点 + CAMSV DMA 抓帧。
- ⚠️ 上表部分数字与 `SENINF_CONFIG.md`（2026-10-05 修订版）口径不同，**以该文的「▲ 修正」与「来源与时效」为准**。

### 1.8 设备侧脚本资产索引（一键复现链）

- **一键加载**：`cam_load.sh`（5 个 `cam_*` 模块依序 insmod）→ `cam_go.sh`（pinmux → PMIC → sensor ID 检查 → init 寄存器表 → `0x3020`/`0x0100` → framecnt 验证）。版本演进：**v3**（fan53870 先 VOUT 后 PWRON）、**v4**（电源段错误，弃用）、**v6**（修正 L6=`0x2c`/L7=`0x18` + GPIO devmem 拉高，见 §2「2026-10-05：」的「原厂配方执行清单实测」节）。
- **sensor 侧**：`cam_init.sh`（v3 全表 w3 化 226 条；**v7 完整原厂序列 236 条**）、`fp_fast3.c`（C 快写：健康窗口内 33ms 写完整表）、`cam_view.py` / `cam_view.c`（取景器，协议 `"K50F"+w+h+RGB888` → 缩放写 `/dev/fb0`）。
- **内核模块**：`cam_ovl` / `cam_genpd` / `cam_rails` / `cam_clk2` / `cam_clk` / `cam_clk3` / `cam_probe_dbg` / `cam_pwr` / `mclk` / `mclk2` / `cam_mmtest`（设备 `/root/cam_*.ko`）。
- **探测脚本**：`seninf_probe.py`（v2 完整 CSI2 init）、`sv_test2.py` / `sv_test3.py`（TM 路由）、`scan_dphy_fsm.py`（DPHY FSM 采样）、`sweep_b.py`、`port1b_csi2.py`、`hs_probe.py`、`phy115.py`、`all_ports_full.py`、`full_dphy.py`、`full_rx_config.py`、`final_verdict.py`、`ldo_sweep.py`、`cam_stream.sh`、`gpiotoolG`。
- Windows 侧：`isp71_ref/`、`SENINF_CONFIG.md`、`isp71_fields.json`（全部位域表）、`cam_view.c`、`outcomputer/cam_view_a64`。
- 各脚本/日志的**逐日期清单**见 §2 时间线各节的「资产」行（本节只是索引，不替代原始记录）。

### 1.9 PM §9 迁移补遗（旧口径、扫描范围与目录级资产）

> 本文件由 `project_memory.md` §9 / §9.4c–§9.4h 迁入重组而成。下列细粒度事实只在 PM 原文里出现过，迁入时补记于此，避免随 PM 瘦身丢失。

- **已废止的 SENINF 旧口径**：早期 `SENINF_CONFIG.md`（v1_1）写 `CSI2_EN = 口 + 0x800`、`PKT_CNT = 口 + 0x8D8`；**2026-10-05 修订后正确值为 `CSI2_EN = 口 + 0xA00`、`CSI2_PACKET_CNT = 口 + 0xADC`**（见 §2「2026-09-30 晚补充」与 `SENINF_CONFIG.md` 的 ▲ 修正）。**旧脚本按 0x800/0x8D8 读包计数会恒读错误地址**： 排查遗留脚本时注意。
- **CAM MUX_EN 未解项的扫描范围**：6S 的 `CAM_MUX_EN` 若不在 ISP7.1 的 `0x410`，候选扫描区为 **`0x400`-`0x4FF` 全部可写位**，或存在 shadow / next-ctrl 机制（见 §1.6 未解项 ①）。
- **MCLK 的时钟选择器名**：sensor0 的 MCLK = **GPIO152 = CMMCLK2**，对应时钟树选择器 **`CLK_TOP_CAMTG3_SEL`**（HyperOS 运行态 `hyperos_clk_summary.txt` 抓取；主线侧 `camtg3/seninf/seninf1-4` 均 273MHz）。
- **目录级资产**：`hyperos_clk_summary.txt` + `hyperos_gpio.txt`（HyperOS 相机运行中抓取，WSL fp_work/cam/）、`hyperos_fdt.dtb` / `hyperos_fdt.dts`（原厂 live DT，见 §2「2026-10-02 凌晨补充」）、`isp71_ref/`、`isp71_fields.json`（全部位域表）、`outcomputer/cam_view_a64`。
- **IMX582 必须完整初始化才能开流（ENXIO 教训）**：只写 `0x0100=0x01`（未做 232 寄存器 init）→ 传感器随即**失联（`ENXIO`）**。232 寄存器表曾因 `/root` 被清而丢失，后由 Android 原厂 `rubensimx582_mipi_raw` imgsensor 驱动补回（见 §2「2026-10-01 晚」cam_init.sh v3/v7）。
- **抓帧目标格式**：**RAW10**（IMX582 输出）→ 去马赛克 / 直接 PGM 灰度 → 写 `frame.rgb`（协议 `"K50F"+w+h+RGB888`）→ `cam_view` 上屏。
- **`cam_view.py` 两个副本**：设备 `/root/cam_view.py`（ANSI 实时显示 streaming 状态 / framecnt / 帧率 / CSI2 5 路统计，`python3 /root/cam_view.py`）+ Windows `${K50_REPO}\cam_view.c`（aarch64 静态版）。
- **framecnt 跳动样本**（健康窗口 `0x0005` 计数）：`0xeb→0x0b→0x2a→0x48→0x66…`，约 29.4-31.5fps（≈30fps 实锤）。

### 1.10 PM §0/§9 迁移补遗（原文级细节）

> 本节由 `project_memory.md` §0 状态表相机行、§9 尾部与 §9.4h 迁入。这些细节原本只存在于 PM，PM 瘦身后由本节承载。

- **原厂 `csirx_seninf_*` 三段函数名与语义**（v84 由 `isp_ko.asm` 反汇编翻译）：① `csirx_seninf_setting` = **口基址 + 0x00 / 0x10 置 bit0**；② `csirx_seninf_top_setting` = **TOP 基址 + 0x60/0x64/0x68/0x6c**，译成寄存器名即 **`SENINF_TOP_PHY_CTRL_CSI0/1/2/3`**；③ `csirx_seninf_csi2_setting` = 常量写入 5 条。
- **⚠️ 该组寄存器里 bit8-9 的名字是 `RG_PHY_SENINF_MUX<n>_CPHY_MODE`，不是 `SRC_SEL`**： 旧记「bit8-9 = SRC_SEL = 2」**是错的**。`SRC_SEL` 在 **`SENINF_TOP_MUX_CTRL_n`** 里，mask `0xf<<n`。行为差异：**port0-3 置 `0x200` → `CPHY_MODE=2`；port4-7 只 `&=~0x100` → `CPHY_MODE=0`**。
- **运行态数据通路终点 = `cam_raw_a`（`0x1a030000`）**：原厂配方为 sensor → seninf → **cam_raw_a**（主线侧该地址未见使用，仅供 diff 对照）。
- **★ 已排除的红鲱鱼：原厂工作态 `camtg3_ck` 子级门也是 0**： 只需 enable `_sel`，不必等子门。同理 `mtk_cam_dbg/*/data` 在录视频时仍全 0（**按需 dump 机制**，不是故障）→ **禁止盲写 ctrl**。
- **IMX582 I2C 协议（w4 被静默拒绝的坑）**：IMX582 = **16-bit 寄存器地址 + 8-bit 数据** → 写必须用 `i2ctransfer w3@0x10 <addr_hi> <addr_lo> <data>`；**`w4`（16-bit 数据）写 `0x0100` 会被传感器静默拒绝**（读回恒 `0x00`，其余寄存器也大多不提交）。早期全部 w4 尝试（含 cam_init.sh 初版）都栽在这里。
- **`cam_go.sh` 输出判据**：ID 校验打印 **`IMX582 ALIVE` / `IMX582 DEAD`**。
- **模块重载顺序（复现传感器苏醒的关键）**：`rmmod` 全部后按 **`cam_ovl → cam_genpd → cam_clk2 → cam_clk → cam_clk3 → cam_rails`** 逆序 insmod，**`cam_rails` 必须最后**： 其 RST 低脉冲（GPIO155）必须在 MCLK 稳定之后打，传感器内部 PLL 才 lock、寄存器才提交。
- **并行 AI 冲突坑（环境级教训）**：曾有另一 AI 同时改指纹 + `mddriver`（mddriver 会导致设备重启，属已知问题），造成频繁重启；跨版本加载模块用 `vermagic` sed 修补；**fake `Module.symvers` 并发写坏要用 python 去重**（`awk $2` 转义会静默丢失符号）。
- **环境备注**：设备 `/tmp` 重启即清（模块每次要重推）；`/root` 持久。

## 2. 时间线（严格正序）

> §1 已收走的硬件/资产情报，在时间线原位置不再重复，只保留当时的判断与修正过程。

### 2026-09-27（下午）GPIO ABI 逆向 + 当前阻塞
1. **gpiotool EINVAL 根因链条（已解到最后一层）**：
   - 设备内核 `CONFIG_GPIO_CDEV_V1 is not set` → v1 ioctl 全 EINVAL（合理）。
   - 该内核树的 v2 ABI 与标准 5.10 不同（混合 ABI）：`gpio_v2_line_request` = **offsets 为 u32[64]**、num_lines/event_buffer_size/padding 在 config 之后；`gpio_v2_line_config.flags` 是 **u64**；行 fd 的取值 ioctl 用 **v1 风格 GPIOHANDLE_GET/SET_LINE_VALUES（0x08/0x09，u8 values[64]）**；GET_LINE 的 ioctl 返回值恒 0，**fd 在 req.fd 字段里**（这个坑浪费了几轮）。
   - 最终版 gpiotool（${K50_REPO}\gpiotool.c）在 line 5 上返回 EBUSY（被内核驱动占用）→ **请求路径本身能工作**；但所有空闲脚（0/15/100/158/164/246）在请求阶段 EINVAL，且**无任何内核日志**（"Invalid base" 为 0）：错误发生在 pinctrl/pinmux 早期静默路径。pinctrl-paris 未设 init_valid_mask，DYNAMIC_DEBUG 未启用，无法在线追。
   - **⚠️ 事故记录**：全引脚扫描（0-246 逐个 request+close）导致整机冻结（用户手动重启恢复）。**禁止再做全引脚扫描**；单引脚测试安全。
2. **当前总阻塞**：MTK pinctrl 对空闲引脚的 chardev 请求 EINVAL（内核移植层问题）。需要带插桩的内核重编定位（在 pinmux_request_gpio / mtk_pinmux_gpio_request_enable / gpio_v2_line_config_validate 加 dev_err 打印）。
3. **fan53870@35（主线 i2c-11）不 ACK**：DTBO 节点无 enable-gpio/supply（VCC 应常供），全总线扫描无 0x35。疑似其供电依赖相机域电源（受 GPIO 控制）：同样被 GPIO 阻塞。
4. **下一步**：
   a. 内核插桩重编：pinctrl 路径加打印，定位 EINVAL 具体函数。
   b. **更快的路**：写一个最小内核模块（gpiod_get + sysfs 切换）绕过 chardev：goodix_fp 驱动的内核态 GPIO（216/136）工作正常，说明内核态请求可能不受影响。
   c. GPIO 通了之后：拉 GPIO158（vcam_ldo）+GPIO164（rt5133 EN）→ 扫 i2c-11 看 fan53870 → 使能 LDO6/7 → 扫 i2c-10 读 IMX582 ID（0x0016/0x0017=0x0582）。
5. **工具资产**：gpiotool.c（最终混合 ABI 版）、gpio_probe.c（fd/ABI 探测器）。相机电源假设链：avdd1=vcam_ldo(GPIO158) → dovdd=fan53870-l7(2.8V) → afvdd=fan53870-l6(2.8V)，主摄 IMX582 在 i2c-10@0x10。

### 2026-09-27（晚）重大突破：GPIO/电源链全通
1. **GPIO 已完全打通**（无需改内核）：
   - gpiotool 的 EINVAL 与树内 mtk pinctrl 无关：**这个内核是混合 ABI**（见下），且我犯了两个低级错误（values ioctl 命令号用错版本 + **ioctl 返回值当 fd**，实际 fd 在 `req.fd` 字段）。
   - 最终可用 ABI（gpiotool.c 已是终版）：v2 GET_LINE `_IOWR(0xB4,0x07,req)`，req = {u32 offsets[64]; char consumer[32]; config{u64 flags; u32 num_attrs; u32 padding[5]; attr[10]×{id,pad,u64}}; u32 num_lines; u32 event_buffer_size; u32 padding[5]; s32 fd}；flags INPUT=BIT(2)/OUTPUT=BIT(3)；行 fd 的取值用 **0x08/0x09 + u8 values[64]**（v1 风格）。
   - **内核态 GPIO 用全局编号**：gpiochip0 base=512，pinctrl 引脚 N 的全局号 = 512+N。cam_pwr.ko（${K50_REPO}\cam_pwr.c）已验证：gpio_request(670)=512+158 成功拉高、676=512+164 成功。
   - 模块构建方法（树被 clean 过）：`printf 5列symvers > K/Module.symvers`（crc\tsym\tvmlinux\tEXPORT_SYMBOL_GPL\t空namespace）+ `make ARCH=arm64 LLVM=1 modules_prepare`（生成 scripts/module.lds）+ `make ARCH=arm64 LLVM=1 M=... modules`。脚本 cam_src_find.sh 有全程命令。
   - **⚠️ 事故**：全引脚扫描（247 脚逐个 request）导致整机冻结，用户手动重启。**禁止全引脚扫描**。
2. **电源链验证**：
   - cam_pwr.ko 拉高 GPIO670（vcam_ldo/AVDD1）+ GPIO676（rt5133 EN）后：**fan53870@0x35 在 i2c-11 上出现并可读写**（之前无应答是因为没电）。
   - fan53870 寄存器（部分解码）：**0x00-0x06 = LDO1-7 CTRL，EN mask=0x09**（bit0+bit3，来自 vendor .ko 反汇编 enable_mask=9）；0x10-0x16 可写（写 0x01 后变为 01×5，疑 VSET 或第二 CTRL bank）。已全部写 0x09 使能。
   - 传感器仍未 ACK：**缺 MCLK**（cam0 mclk pinctrl + clock 门控，chardev 做不了）和复位时序：Sony 传感器 I2C 应答的硬前提。
3. **下一步（下会话）**：扩展 cam_pwr.ko 为完整上电模块：pinctrl_select_state（cam0 mclk/rst 组）或 clk 框架使能 MCLK 24MHz → RST 时序 → 扫 i2c-10 读 IMX582 ID 0x0582。参考 pw_seq（本文件上方）和 vendor imgsensor 的 kd_camera_hw。
4. 总线速查：i2c-1=aw8697(0x5a)+0x42(新发现，未知)；i2c-5=mt6375(0x34)+0x55(未注册应答)+0x64；i2c-6=tfa9874(0x34/0x35)；i2c-7=bq28z610(0x55)+sc8551(0x66)；i2c-11=fan53870(0x35)+sc8551(0x66)。rt5133@0x18(i2c-5) 仍未出现。

### 2026-09-27（晚）外场协助方案（设备被带走期间）
**外场操作包已备齐：${K50_REPO}\outcomputer\（一次性拷走）**
- putty.exe / pscp.exe / puttygen.exe（0.85 w32，已下载）
- ${K50_KEY}.ppk（由 ${K50_KEY} 预转换的 PPK v3，MAC 已校验）+ ${K50_KEY}（OpenSSH 格式备用）
- ta_host_v40（SAVE 门补丁版）+ cam_pwr.ko + bt-hid-autoconnect.sh
- README.txt：完整分步操作（网络→连接→传文件→指纹测试→相机测试→回滚）
- 网络方案：HONOR 热点伪装成 tenda-5（SSID/密码同 K50 家里配置）→ K50 自动回连（零触摸）→ Win7 加入同热点 → pscp 传 ta_host_v40/cam_pwr.ko → putty 全程操作。
- 指纹测试判定信号：fingerstate head 非空 / [ts] finger 写入 / SAVE final status=0。
- 相机判定：cam_pwr insmod 后 i2c-10 出现 0x10 → 读 0x0016/0x0017 = 05 82。

### 外场执行路径（设备在外场期间）
设备在外场时的执行路径（${K50_REPO}
emote\ 三个脚本）：
1. **step1-phone-setup.sh**（手机触摸屏手打 3 行）：root 临时密码 k50out + 开 SSH 密码登录 + 打印 IP。
2. 外场电脑 `ssh root@<手机IP>`（同网络/热点）→ 整段粘贴 **step2-fingerprint-relay.sh**：dd 补丁 goodixfp.ta 的两个门（文件偏移 235916/235932 写 NOP 1f2003d5，先校验原始字节 e0220035/c20e0054）→ 跑 enroll 20 → 抓关键结果。**v40 补丁等价实现，无需传输二进制！**
3. **step3-camera-relay.sh**：只读检查（电源轨保持？MCLK/RST 引脚状态？总线扫描）。相机完整上电仍缺 cam_pwr.ko 传输：若手机有外网，可走 GitHub 中转（ta_host/cam_pwr.ko 均为自有代码，无固件内容）。
修复回滚：`cp /opt/goodixta/ta/goodixfp.ta.orig /opt/goodixta/ta/goodixfp.ta`。
注意：dd 补丁作用于 TA 文件本身，回家后 push v40（内含同样补丁）之前要用 .orig 恢复或确认 v40 加载器补丁幂等（写相同 NOP，幂等 ✓ 不冲突）。

### 2026-09-27（晚）MCLK 解码完成：下次开机即可执行的读 ID 计划
1. **MCLK/RST 引脚解码（关键突破）**：
   - vendor mclk.c（imgsensor/src/common/v1_1/camera_hw/mclk/mclk.c）证实：**MCLK 只需 pinctrl 状态切换，无任何 clock 框架调用**：MTK 的 MCLK 时钟是引脚模式自带的硬件时钟线（mode 1 直连固定时钟）。
   - pinmux 编码：MTK_PIN_NO(x)=(x)<<8。**cam0 MCLK = pinmux 0x9801 = 引脚 152（0x98）mode 1**；mclk_off = 0x9800（mode 0 GPIO）。
   - **cam0 RST = pinmux 0x9b00 = 引脚 155**（GPIO 模式，output-low/high）。
   - 上电顺序（vendor pw_seq）：RST 低 → AVDD1(vcam_ldo ✓) → fan53870 LDO 全开(✓) → **MCLK pin152 mode1** → RST 拉高 → 3ms 后可 I2C。
2. **执行路线（两选一）**：
   a. debugfs pinmux-select（零代码）：`echo "<group> <func>" > /sys/kernel/debug/pinctrl/pinctrl-paris/pinmux-select`：需先从 pingroups/pinmux-functions 查 pin 152 的组名和 mode1 功能名（设备在线后第一步）。
   b. cam_pwr.ko 扩展：ioremap 0x10005000，写 pin 152 的 MODE nibble=1（MODE 寄存器布局从 pinctrl-mt6895.c 字段表确认）。
3. **gpiotool 待修**：行 fd 的取值 ioctl 应为 **0x0E/0x0F + struct{bits,mask}**（本树 v2 linereq ABI，bits 在前）；现版用 0x08/0x09+u8[64] 会 EINVAL。修好后 RST/其它 GPIO 可控。
4. **MCLK 时钟频率问题**：模式 1 输出的具体频率待实测（vendor 框架支持 6/12/13/19.2/24/26/52MHz 多档，对应 DT clocks 列表；IMX582 需 24MHz=CLK_TOP_UNIVPLL_192M_D8(139)）。若 mode1 默认频率不对，需查 camtg 分频寄存器。先试 mode1 直读。
5. **完整测试序列（设备上线后照抄）**：
   ```
   insmod cam_pwr.ko                     # rails: GPIO670/676 high + fan53870 LDOs 0x09
   # MCLK: pin 152 → mode 1（pinmux-select 或内核模块写 MODE）
   # RST: pin 155 low→high（gpiotool 全局 512+155=667）
   i2cdetect -y -r 10                    # 期待 0x10 出现
   i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1   # ID 高字节 = 0x05
   i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1   # ID 低字节 = 0x82
   ```
6. 指纹侧并行状态：v40（SAVE 门补丁）已构建未推送（设备离线），设备回来先推 v40 再跑指纹。

**Streaming 尝试结果**：
- 232 寄存器 init **0 错误**（I2C 层全通过）
- 0x0100（streaming on）写后读回 **0x00** → 传感器没有真正进入流模式
- 根因：**MCLK (CMMCLK2) 时钟没有真正输出**。pinmux-select 只做了引脚功能切换，但 CMMCLK2 的时钟源（camtg_sel→camtg_ck 链）仍被门控。mclk2.ko 使能了 camtg_sel（enable=1）但 camtg_ck 仍 enable=0。
- **SENINF (0x1a010000) /dev/mem 读 → segfault**：CAM_MAIN 电源域未开，总线到 seninf/cam 寄存器的路是断的。
- **下一步（按序）**：
  1. 使能 CAM_MAIN 电源域（通过 /dev/mem 写 SCPSYS 寄存器，或用内核模块绑定 power domain）
  2. 使能 camsys 时钟（cam_m_camtg_con/cam_m_seninf_con 等，clk framework 或 /dev/mem）
  3. 使能 camtg_ck/camtg2_ck（MCLK 输出门）
  4. 重新写传感器 init + streaming
  5. /dev/mem 读 SENINF 验证 MIPI 数据流

### 2026-09-27（深夜）🏁 里程碑：IMX582 chip ID 读取成功（0x0582）
完整上电序列（cam_power.sh 终版，全部已验证）：
1. 电源轨（gpiotoolG chardev）：GPIO158(vcam_ldo/1.2V)、GPIO149(avdd)、GPIO20(avdd2)、GPIO159(dvdd)、GPIO164(rt5133 EN)
2. fan53870(i2c-11@0x35)：**寄存器表来自 datasheet**（fan53870-d.pdf 已下载，文本在 fan53870-text.txt）：0x02 IOUT=0x7f、**0x09 LDO6_VOUT=0xB3(2.804V AFVDD)、0x0A LDO7_VOUT=0xB3(2.804V DOVDD)、0x03 ENABLE=0x60（bit5=LDO6、bit6=LDO7）**；VOUT 公式 LDO3-7 = 1.5V+(d-16)×8mV。污染已恢复（0x02/0x04/0x05/0x06）。
3. MCLK：`echo "GPIO152 func1" > /sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select`（debugfs 通用函数名 func0-7 = 模式 0-7）
4. RST：GPIO155（gpiotoolG）低 50ms → 高
5. **读 ID**：`i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1` → **0x05**；`...0x17 r1` → **0x82** ✓✓
注意：传感器 I2C 应答**无需 MCLK 时钟确认**（func1 是否真输出 24MHz 待示波器/后续验证：但 I2C 已通）。
下一步（摄像头 M2）：用 rubensimx582_mipi_raw 驱动的寄存器初始化表做完整 sensor init → MIPI/CSIS 配置 → 抓帧。

### 2026-09-27（深夜）FAN53870 寄存器表解出 + 传感器仍不应答
datasheet 已下载（fan53870-d.pdf，60 页，文本已提取 fan53870-text.txt）。**寄存器映射（Table 5）与我猜的完全不同**：
- 0x00 PRODUCT_ID(=01) / 0x01 REV(=01) / 0x02 IOUT(ILIM 设置, 出厂 0x7f)
- **0x03 ENABLE：bit0=LDO1_EN … bit5=LDO6_EN、bit6=LDO7_EN**（使能位集中在这一个寄存器！）
- 0x04-0x0A = LDO1-7 各自的 VOUT（8bit）
- 0x10 DISCHARGE / 0x11 RESET / 0x12 I2C_ADDR / 0x15/0x16 中断 / 0x18-0x1B 状态
- **我的盲写污染**：曾往 0x00-0x06 写 0x09×7 → IOUT(0x02) 被改成 0x09、LDO1/4 被意外使能（0x03=0x09）、LDO1/2/3 VOUT(0x04-0x06) 被写成 0x09。**LDO6/7（相机 DOVDD/AFVDD）从未使能过**（bit5/bit6 从未置位）！
- **修复方案**：0x02=0x7f（恢复 ILIM）、0x04=0x00、0x05=0x00、0x06=0x00（恢复 VOUT）、0x03=0x60（只使能 LDO6+LDO7）；LDO6 VOUT(0x09)/LDO7 VOUT(0x0A) 需按 datasheet 表设 2.8V 的代码。
- FAN53870UC00X：I2C 7'h35 ✓、LDO6/7 默认 2.8V、范围 1.5-3.4V。

### 2026-09-27 重大转折：不需要逆向 i2c-mtk CCI 驱动！
1. **"i2c-mtk" 是可选封装层**：`imgsensor_i2c.h` 中 `#ifndef NO_I2C_MTK #include "i2c-mtk.h" #else mtk_i2c_transfer(...) → i2c_transfer(adap,msgs,num)`。src-v4l2 的 `adaptor-i2c.c` 全部用标准 `i2c_transfer()`。imgsensor（v4l2 框架）完全走标准 Linux I2C 子系统。之前"必须从 vendor 镜像抠 i2c-mtk.ko"的结论作废。
2. **主线 i2c-mt65xx 驱动已在设备上运行**：8 条适配器 up（i2c-1/5/6/7/8/9/10/11）。vendor 的 i2c 控制器 compatible 是 `mediatek,mt6983-i2c`，主线驱动兼容（bq28z610/tfa9874/mt6375 都已正常绑定）。
3. **vendor DTBO（${HOME}/fp_work/cam/dtbo_0.dtb，来自 vendor_boot）包含全部相机节点**：主线一直没应用 DTBO：
   - **sensor0@10（主摄 IMX582，rubensimx582_mipi_raw）→ i2c8 = 0x11d05000 = 主线 i2c-10**；reg=0x10（7-bit，8-bit 写 0x20；驱动 i2c_addr_table={0x20,0xff} 运行时探测）
   - sensor1@10（前摄 IMX596）+ sensor3@2d（微距 s5k4h7）→ i2c2 = 0x11d01000 = 主线 i2c-8
   - sensor2@37（gc02m1）→ i2c4 = 0x11d03000（主线未启用该控制器）
   - camera_eeprom0..3@51/52/50、MCLK/RST/AVDD/DVDD pinctrl 全套（cam0@0..cam0@9：mclk 2/4/6/8mA、rst、avdd、avdd2、dvdd 各 on/off）
   - sensor 节点 compatible = "mediatek,imgsensor0/1/2/3"，sensor-names 匹配驱动名
4. **主摄供电链（来自 dtbo sensor0 节点 + fragment@31/34）**：
   - avdd1-supply = **vcam_ldo**（fragment@31：regulator-fixed 1.2V，**GPIO158 使能**，active-high）
   - dovdd-supply = **fan53870-l7**（onsemi PMIC，init 2.8V）
   - afvdd-supply = **fan53870-l6**（init 2.8V）
   - fan53870 = "onsemi,ldo@35" 挂 vendor i2c9 = **0x11d06000 = 主线 i2c-11**，LDO 寄存器 offset 0x00..0x06（l1..l7），地址 0x35
   - rt5133（Richtek 8-LDO 相机 PMIC）在 vendor i2c5 = 0x11280000 = 主线 i2c-5 @0x18，enable-gpio=164（主线未实例化；主摄不用它，其他镜头/OIS 可能用）
5. **实测（2026-09-27 02:30）**：
   - i2c-11 总线映射验证正确：sc8551@66 ACK（与 DTBO sc8551_i2c9@66 一致）；**fan53870@35 不应答**（疑其供电轨在主线未开）
   - i2c-10 全空（传感器未上电，符合预期）
   - /sys/class/gpio 不存在（内核未开 GPIO_SYSFS）；libgpiod 未装；自写 raw chardev 工具对 gpiochip0（=mtk pinctrl，247 线）ioctl 返回 EINVAL
7. **gpiotool EINVAL 已定位根因（2026-09-27）**：设备内核 `CONFIG_GPIO_CDEV_V1 is not set`（v1 ioctl 全部返回 EINVAL），且 **主线 DTB 的 pinctrl@10005000 节点缺 `gpio-ranges` 属性**（vendor DTB 有 `gpio-ranges = <&pio 0 0 227>`）→ gpiochip valid mask 全空 → 所有 GPIO line 请求被拒。**修法：给主线 DTB 的 pinctrl 节点补 `gpio-ranges = <&pio 0 0 0xe3>`（或按 MT6895 实际 pin 数），用 tmp_swap_dtb.py 换 DTB 即可，无需重编内核**。gpiotool v2 自带 uapi 结构版本在 ${K50_REPO}\gpiotool.c（v1/v2 都因 valid mask 失败，修 DTB 后 v2 版应可用）
6. **明天的路径（按优先级）**：
   a. 修 gpiotool EINVAL（或装 gpiod），拉高 GPIO158（vcam_ldo）+GPIO164（rt5133 EN），重扫 i2c-11 看 fan53870@35 是否出现
   b. 若 fan53870 仍死 → 查其供电（可能来自某 LDO 需先开），或从 vendor.img 抠 fan53870 内核驱动确认寄存器
   c. 把 DTBO 相机 fragments 手工移植进主线 DTB（sensor0 挂 i2c@11d05000 + fixed-regulator + pinctrl；fan53870 需要写最小 regulator 驱动或手动 I2C 使能）
   d. 上电后 i2cdetect i2c-10 应见 0x10；读 0x0016/0x0017 → **0x0582 = 第一个里程碑**
   e. 之后：写最小 V4L2 subdev 驱动（IMX582 寄存器表在 rubensimx582_mipi_raw 全开源）→ seninf/camsv MIPI 收流（真正的大头）

### 2026-09-28（凌晨）MCLK 使能成功 + 传感器仍未 ACK
1. **gpiotool 取值 ioctl 已修**：GET=0x0E/SET=0x0F，struct{u64 bits; u64 mask}（bits 在前）。GPIO 读写全通（155 set/get ✓）。
2. **mclk.ko v2 编译推送成功**：of_clk_get_from_provider(topckgen, CLK_TOP_CAMTG_SEL=20 / CAMTG2_SEL=21) + clk_prepare_enable → **camtg_sel/camtg2_sel enable=1 ✓**（clk_summary 确认）。但 camtg_ck/camtg2_ck enable 仍=0（子级门未开）。
3. **上电时序修正**：RST 先低 → 上电 → MCLK → RST 高（vendor pw_seq 顺序），仍无 ACK。
4. **fan53870 寄存器状态**：ENABLE(0x03)=0x60（LDO6+LDO7 EN）、VOUT(0x09/0x0A)=0xB3(2.8V)、SEQ 全 000。寄存器写入成功但 **LDO5/6/7 状态回读(0x13-0x15 区) = 0x00**（未上电）；LDO3/4 状态有值 → **LDO5/6/7 可能有父电源未开**（vendor 驱动有 "enable parent" 代码）。
5. **当前卡点分析**：
   - IMX582 需要 AVDD(2.8V)+DOVDD(1.8V)+DVDD(1.1V) 三轨全上才 ACK I2C
   - fan53870 LDO6/7 是否真在输出 2.8V → 未知（可能需要额外使能或父电源）
   - sensor0 的 dt 只列了 avdd1/dovdd/afvdd 三路，**缺 dvdd**：dvdd 可能由 GPIO159 控制的轨提供 ✓ 已拉高
   - avdd2(GPIO20) 对应哪路电源待确认
6. **下一步**：
   a. 反汇编 fan53870.ko 找 VSET 寄存器和完整的 LDO 使能序列
   b. 或在 I2C-11 上扫描看是否有其他 PMIC/开关器件
   c. 检查是否有 GPIO 控制的中间电源开关（avdd2/dvdd 轨的上游）

### 2026-09-28 MCLK 使能成功 + streaming 测试
1. **MCLK camtg_sel/camtg2_sel 已使能**（mclk2.ko，of_clk_get_from_provider topckgen idx20/21，enable=1 ✓，24MHz ✓）。camtg_ck 子级门 enable=0 但可能不影响（MTK MUX_GATE 可能是同一 clock 的两面）。
2. **传感器 init 全量下发 0 错误**（cam_init.sh，235 寄存器写）。
3. **streaming 0x0100 读回 0x00**：传感器没有真正进入流模式。原因分析：
   - CMMCLK2 输出可能仍无时钟（camtg_ck 子级门未开？）
   - 或者需要 MCLK 稳定运行一段时间后再下 streaming 命令
   - 或者需要先写 0x0100=0x00 (standby) → 等待 → 再写 0x01 (streaming)
4. **SENINF /dev/mem 读 segfault**：CAM_MAIN 电源域可能未开，总线到 0x1a010000 不可达。
5. **下一步**：写 cam_cap.ko 内核模块绑定 camsys DT 节点（自动使能电源域+所有时钟）→ 配置 SENINF MIPI → CAMSV DMA → 首帧。vendor 参考代码：cameraisp/src/isp_6s/inc/cam_regs.h（TG 寄存器 0x1F00/0x1F04）+ imgsensor/src-v4l2/seninf/（MIPI 配置，需从 MiCode GitHub 拉）。

#### 附：传感器寄存器初始化（原无标题、无日期，据内容同为 09-28 时段）

1. **传感器寄存器写入成功**：从 vendor rubensimx582mipiraw_Sensor.h 提取三张表（init 112 / Image_quality 9 / preview 111 寄存器），gen_i2c_script.py 生成 cam_init.sh（每 reg 4 字节大端 addr16+data16，59 条 i2ctransfer，末尾 streaming on：0x0350=1,0x3020=0,0x0100=1）。设备端执行 **0 错误**，回读 0x0136=0x18 验证一致。
2. **streaming 未生效**（0x0100=0x00）：根因 = MCLK 时钟未使能。pin152 的 func1 只是 mux 到 CMMCLK2 功能，还需要时钟树输出。
3. **主线时钟树（全部注册但 enable=0）**：`univpll_192m_d8(24MHz) → camtg_sel → camtg_ck`（cam0=CMMCLK2）；camtg2-7 同构。索引：CLK_TOP_CAMTG_SEL=20、CAMTG2_SEL=21、CAMTM_SEL=74（mt6895-clk.h）。注册者 = clk-mt6895.c topckgen 驱动（compatible "mediatek,mt6895-topckgen"，of_match 表含 apmixedsys/topckgen/vlp_cksys）。
4. **mclk.ko 两版**：v1 clk_get(NULL,name) 全 -2（DT provider 时钟不支持按名取）；**v2（cam_pwr_mclk.c，of_clk_get_from_provider 方案）已写好待编译**。
5. vendor 机制参考（seninf_clk.c seninf_clk_set）：使能 top_mux_camtg + TG 门 + 24M 源，再 clk_set_parent：v2 只需 enable sel 门（父已默认 24M）。
6. 模块构建配方（已固化）：伪 Module.symvers 23 符号（每行 5 列、行尾 tab）→ make modules_prepare（补 module.lds）→ make ARCH=arm64 LLVM=1 M=$mod modules。

### 2026-09-28 阶段性总结（设备带出+回来后的完整测试）

**已实现（全部实测验证）**：
- GPIO chardev：v2 ABI 完全逆向（fd 在 req 结构体里、values=0x0E/0x0F bits,mask）
- 电源轨 5 路：GPIO 158/149/20/159/164 全拉高
- fan53870 LDO6/7 2.8V：寄存器写入+读回确认
- MCLK 引脚 func1：debugfs pinmux-select
- RST：GPIO155 脉冲
- 传感器 I2C：**235 寄存器 init 0 错误**、Chip ID **0x0582 确认**（i2cdetect 可见 0x10/0x51/0x0C）

**卡住**：streaming(0x0100)=0x00
- 根因 1：CMMCLK2 引脚无实际时钟输出（camtg_ck 子级门 enable=0）
- 根因 2：CAM_MAIN 电源域未开 → SENINF /dev/mem segfault
- 根因 3：无 CAMSV/抓帧驱动

**下一步 = cam_cap.ko 内核模块**（估计 1-2 天工作量）：
1. of_platform_device_create 绑定 camsys DT 节点 → 自动使能电源域 + 全量 clk
2. of_clk_get 使能 camtg_ck/camtg2_ck 子级门
3. ioremap SENINF (0x1a010000) + CAMSV (0x1a110000) 
4. 配置 SENINF MIPI CSI-2（4-lane，IMX582 输出）
5. 配置 CAMSV DMA（目标地址、帧格式、分辨率）
6. 使能 TG（timing generator）→ 等帧中断 → DMA 完成后 dump RAW
7. 用户态：RAW → 图像（10-bit RAW 简单 debayer 或直接 PGM 灰度）

**关键参考文件（已就位）**：
- vendor cam_regs.h：${HOME}/fp_work/cam/cam_regs.h（TG/DMA/中断寄存器布局）
- vendor seninf_impl.c：${HOME}/fp_work/cam/ksrc/.../isp6s/seninf/seninf_impl.c（CAM mux 切换）
- vendor IMX582 驱动：${HOME}/fp_work/cam/ksrc/.../rubensimx582mipiraw_Sensor.{c,h}（init/preview 表）
- fan53870-d.pdf：datasheet 60 页（寄存器表 Table 5-19）
- gen_i2c_script.py：从 vendor 表生成 i2ctransfer 脚本
- gpiotool.c：终版 GPIO chardev 工具

---
### 2026-09-30 凌晨会话（电源域全通，卡 streaming）

#### 定型方案
1. **live FDT 来源**：LK base DTB + dtbo 分区 overlay。boot.img 里内嵌 DTB 只被 patched setup.c 用来读 /chosen/bootargs。改 DT 属性 → 用运行时 overlay（cam_ovl.ko: of_overlay_fdt_apply，CONFIG_OF_OVERLAY=y）。
2. **电源域**：cam_ovl.ko 挂 power-domains（spm phandle 0x4d；SUBA=rawa+yuva，SUBB=rawb+yuvb，SUBC=rawc+yuvc，vendor 验证）→ cam_genpd.ko attach + pm_runtime_get 持有（不持有会被 SPM 拉闸）→ cam_main/suba/b/c/mraw 全 ON。
3. **电轨**：cam_rails.ko 内核持有（gpiotool 一次性进程退出丢 latch）。
4. **CG**：域重新上电会复位 CG。cam_main CG@0x1a000000 可写全开；rawa@0x1a04f000、mraw@0x1a170000 总线死（未解）。

#### 实测状态
- IMX582 ID=0x0582 ✓（i2c-10@0x10），init 232 寄存器 0 错误 ✓
- MODE[152]=1 ✓（0x10005430 nibble0；MODE range 表 pinctrl-mt6895.c:38 起）
- camtg_sel/camtg2_sel enable=1 parent=24MHz ✓（CLK_CFG_5=0x10000060，pdn 0=开）
- streaming 0x0100=0x01 写入成功但回读 0x00，SENINF 无 MIPI 信号

#### 下一步假设（按优先级）
1. CMMCLK2 的 TG 归属：mclk2.ko 只 enable 了 camtg_sel(20)/camtg2_sel(21)，可能实际是 camtg3+（CLK_CFG_6=0x10000070）。全部 camtgX 都 enable 试一遍。
2. vendor seninf_clk.c 的 seninf_clk_set：需 idx_tg + idx_freq 两路 clk + clk_set_parent(idx_tg, idx_freq)；还有 seninf_clk_open 的 SYS 时钟组 + camtm_sel。对照把缺失时钟补上。
3. rawa/mraw CG 总线死：可能是这俩 syscon 地址在 6895 上不是 CG 窗口（查 vendor clk driver 实际 ioremap 偏移）。
4. SENINF mux：主摄默认接 SENINF？读 vendor.dts camera sensor 绑定确认 mux 配置是否也是上电前提。

### 2026-09-30 晚补充：抓帧阶段准备（寄存器情报）
- **per-SENINF 寄存器**（stride 0x2000，base 0x1a010000，10 口）：
  - SENINF_CTRL=+0x200，CSI2_CTRL=+0x210
  - CSI2_EN=+0xA00，CSI2_IRQ_STATUS=+0xAC8（写1清），CSI2_PACKET_CNT=+0xADC（被动包计数，MIPI 到达即增）
  - SENINF_MUX_CTRL=+0xD00，MUX_IRQ=+0xD18，MUX_SIZE=+0xD30
- **TOP 寄存器**：SENINF_TOP_MUX_CTRL_0/1 = 0x1a010010/0x14；CAM MUX（TG 源选择）= 0x1a010400-0x40C（每 TG 4bit 源选择）+ MUX_OPT 0x420 起（每 TG 4 字节）。
- **DPHY 模拟 RX**：0x11c80000（4D5G mipi_rx_ana，MT6895 同族寄存器名 MIPI_RX_ANAxx_CSIxA，参考主线 phy-mtk-mipi-csi-0-5.c 的 mt8365 版 + 需 4D5G 表）。
- **vendor 现实**：rubens 的 SENINF/CSI2 配置完全在**相机 HAL 用户态**做（seninf chardev mmap 直写），内核零参考。获取寄存器表途径：LKML mt8188 seninf 补丁系列（lore.kernel.org）/ android14-6.1 镜像 / Genio ISP7 seninf 驱动。
- **isp 电源域**：isp_main/dip1/ipe=OFF（DIP/IPE/WPE 后处理，raw 抓帧不需要）；isp_vcore=ON。主摄 ISP 前端=camsys rawa（cam_suba 域，已 ON，69 CG gate 已开）。
- **当前状态**：传感器 streaming 保持 ✓；rawa/camsv 模块寄存器读 0（待区分复位值 vs 总线死，可写读回测试）。

### 2026-09-30 晚 II：路径 1 执行完毕（参考源码到手，待设备恢复）
- **参考源码已落地**：`${K50_REPO}\isp71_ref\`（800K，WSL ${HOME}/fp_work/cam/isp71/）：Motorola kernel-mtk（android-13-release-ttt）的 ISP7.1 CAM V4L2 驱动全套：seninf-drv/route/regs + csi_phy_2_0（模拟+数字 CSI2 序列）+ sv-regs.h（CAMSV）+ top-ctrl/mux/tg 位域头。
- **移植指南**：`${K50_REPO}\SENINF_CONFIG.md`（地址映射、9 步配置序列、逐口探针策略、取景器协议）。
- **取景器已写好并编译**：`${K50_REPO}\cam_view.c` → aarch64 静态版 `/tmp/cam_view`（WSL）+ `${K50_REPO}\outcomputer\cam_view_a64`。协议：抓帧侧写 /tmp/frame.rgb（"K50F"+w+h+RGB888），cam_view 每 0.5s 重刷到 /dev/fb0。
- **下一步**（设备 WiFi 恢复后）：按 SENINF_CONFIG.md 写抓帧模块（用户态 python/devmem 或内核模块）→ 逐口探针找主摄口 → CAMSV DMA 抓帧 → cam_view 显示。
- WiFi 挂了由另一 AI 排查中；本会话期间 mddriver 又引发多次重启，均不影响持久化成果（/root 脚本 + WSL/Windows 双份源码）。

### 2026-09-30 深夜：SENINF 配置序列情报（来自 ISP7.1 set_test_model）
- **三层 mux 拓扑**：seninf 口输入 → [TOP_MUX_CTRL(0x10-0x1C): 每 mux 4bit 源=seninf 口] → SENINF MUX{1-13}(0xD00+j*0x1000) → [CAM MUX(0x400-0x40C): 每 cam_mux 4bit 源=mux 号] → CAM/CAMSV TG。
- **关键常量**：TEST_MODEL=1（mux SRC_SEL 选 1 = 内部测试图案，0=csi2 输入）；PIX_MODE=2（默认）；CSI_CLK_273MHZ 参数组：SETTLE_DT=0x10、HS_TRAIL=0x34。
- **mux ctrl 细节**：MUX_CTRL_1(+4)=SRC_SEL(4bit)|PIX_MODE(2bit@8)；CTRL_0(+0)：bit0=EN、bit1=IRQ_RST、bit2=SW_RST（先 |0x6 复位再清）；MUX_OPT(+8)：hsync bit8/vsync bit9。
- **cam mux**：EN=0x410（bit per cam_mux）、IRQ_STATUS=0x4A8（clr 写 3<<cam_mux*2）、IRQ_EN=0x4A0；CTRL_0-3 每 8bit 两个 4bit 源选；CHK_CTL_1（期望尺寸）0x504+j*0x10。
- **测试图案 TM 寄存器**（tg 块 = 0x600+0x1000*intf）：TM_CTL=0x8（PAT=0xC@4-7、EN=bit0）、TM_SIZE=0xC（PXL 5632|LINE 4224@16）、TM_CLK=0x10（CLK_CNT=7）、TM_DUM=0x18（DUMMYPXL 100|VSYNC 100@16）。
- **模拟 RX 完整序列**已提取（phyA_power_on + phyA_init 全部字段位表在 ${K50_REPO}\isp71_fields.json），seninf_probe.py v2 已实现完整初始化：三口 CSI2 全部正确配置但无包（pkt_cnt 不动、clkFSM=0x101 dataFSM=0x80808080 三口相同，port3 不存在读0）。
- **当前谜团**：传感器 streaming ✓ 但所有 CSI 口收不到 MIPI。已排除：RX 未配置（v2 已全配）。待试：TESTMDL→CAMSV 路由（sv_test2.py，修正 SRC_SEL=1）；若测试图案能到 CAMSV，则问题在传感器→CSI 链路；路由通了之后 CAMSV DMA/IOMMU 是下一关。

### 2026-09-30 深夜 II：路由实验结果（sv_test2/sv_test3 + 6S 寄存器布局修正）
- **6S CAM MUX 布局（vendor dump 亲证）**：CTRL_1=0x404、CTRL_2=0x408、IRQ_EN=0x4A0（默认 0x1F8280）、IRQ_STATUS=0x4A8、CHK_RES j=0x508+j*0x10；0x400 默认 0x1F8280（与 IRQ_EN 同值，语义未明）。**0x40C/0x410/0x418 拒绝写入**（EN 位置未定！ISP7.1 的 EN=0x10→0x410 在 6S 不生效）。
- **重大发现**：写 0x404/0x504 后读到 **0x1618 ≈ 5632+24**（= TM_PXL+消隐）→ **测试图案数据已流到 CAM MUX checker**！TM→MUX1→CAMMUX 链路通。
- **CAMSV0 收不到**（frmsize_st=0、inter=0x102=TG idle）：cam mux0/1 × src 0/1/2 全扫无效。未解点：
  1. 6S 的 CAM_MUX_EN 写入位置/机制（ISP7.1 是 0x410，6S 拒写；或有 shadow/next-ctrl 机制）
  2. CAMSV0 对应哪个 cam mux（cam_mux_num=23 vs 8 个 camsv+11 个 cam 口，映射未定）
  3. CAMSV TG_SEN_MODE(0x100)/PATH_CFG(0x110) 可能需要额外配置
- **传感器 MIPI 谜团**：seninf_probe.py v2 完整模拟初始化后三口均无包（clkFSM=0x101/dataFSM=0x80808080 全口一致）。若 TESTMDL 链路最终打通 CAMSV，则传感器侧疑点集中在：数据率匹配（缺 rate 相关模拟参数）、sensor MIPI 输出使能、PCB 走线对应的 CSI 口。
- **下一步优先级**：1) 查 6S cam mux EN 机制（对比 0x4A0 IRQ_EN 可写性）2) 试全部 23 个 cam_mux EN 位（EN 可能不是 0x410）3) CAMSV DMA 前先解 IOMMU（MTK-DOWN-IOMMU）。

---
### 2026-10-01 接手会话：MIPI 链路物理层终判（软件侧 100% 穷尽）

> ⚠️ **本节结论已作废**：下方「结论：MIPI 物理链路死亡」已被 2026-10-01 深夜 II 推翻： HyperOS 相机实测全部正常（硬件链路完好，差异在主线侧软件）。作废原因是终判所用鉴别实验的前提不成立：DPHY 接收链路本身从未被证明工作，「分布不变」不能证明 TX 未发。原文保留以供追溯。

#### 原厂 dtsi 关键发现（rubens_mt6895_camera_v4l2.dtsi / cust_mt6895_alpha_camera_v4l2.dtsi）
- **主摄 sensor0 (imx582) 供电**：dovdd=fan53870_l7、afvdd=fan53870_l6、avdd1=vcam_ldo(GPIO158 1.2V)、dvdd=GPIO159 轨（dtsi 无 dvdd-supply）。**"L2=dvdd/L4=avdd"是 dtsi 里另一颗摄像头（L558 行）的映射，别搞混！**
- **sensor0 → seninf_csi_port_2**（factory 接线 = 口2！）
- **口2 原厂参数**：hs_trail=0x20(32)、settle_delay_dt/ck=0x1C(28)（≠273MHz 默认 0x34/0x10）
- fan53870 L1: 0.528-1.504V、L6/L7: 1.504-3.4V（dtsi 电压范围）
- streaming_control 仅 0x0100=1；MIPI 配置全在 init 表（0x0112=0x0a/0x0113=0x0a/0x0114=0x03，与我们的 cam_init 一致）

#### 本会话技术修正
1. **口2 地址算术错误**：0x11C80000+0xA000=0x11C8A000（不是 0x11D20000/0x11CA0000）！此前所有会话从未正确测过口2。ANA2A/2B=0x11C88000/0x11C89000。
2. **鉴别方法论（kills 一切噪声误判）**：传感器 0x0114=0x00（TX 关）vs 0x03（TX 开）对比 FSM 分布：真信号必然变化，浮空线噪声必然不变。P1 的"活动"（0x1010↔0x101 翻转）在 TX 关时一模一样 = 噪声伪影！**9.4d 的"LP 信号"结论由此作废。**
3. fan53870 ENABLE 位号 = LDO号-1（bit0=LDO1...bit6=LDO7）；LDO1/2 公式 0.8+(d-99)*8mV（1.048V=0x82）；fan53870 只有 7 路 LDO（另一 AI 的"LDO5-8=0x0c-0x17 区域"是误读，那是时序/中断寄存器）。
4. mmap python 陷阱：offset 必须关键字传参（第 4 位置参数是 prot）。

#### 终判矩阵（final_verdict.py，全部 TX 开关不变 = 无信号）
8 组合（L7 2.8V/1.8V × 测试图案 ON/OFF × TX ON/OFF）× 3 口：
- P0: clk 恒 0x120、data 恒 0x80808080（自己的空闲态，无信号）
- P1: 0x1010/0x101 双态噪声（TX 不变量 = 浮空线拾取）
- P2: clk 恒 0x101、data 恒 0x80808080（无信号）

#### 结论：~~MIPI 物理链路死亡~~ ⚠️ 已于 2026-10-01 深夜作废
传感器核/PLL/framecnt/I2C 全健康、电源全供（7 LDO + GPIO 轨 + 两种 L7 电压）、寄存器=原厂精确值、三口 RX 全配（本会话修正地址后口2 首次被正确测试）：TX 开关不变 = 输出未到达 SoC。
可能原因：① MIPI TX 驱动器损坏（此前多会话 DOVDD=2.8V 过压 55% 跑过，I2C pad 耐受但 MIPI 驱动器可能先死）② 排线/连接器接触不良 ③ 模块内部断线。
**下一步 = 硬件动作**：重插摄像头排线、换排线、换模组、或示波器直接量传感器侧 clock lane 焊点。

#### 资产更新
- /root 新增：port1b_v12/v13.py、port2_v1.py、fs_mon.py、onoff_fsm.py、tx_toggle.py、port_disc.py、all_csi2.py、csi2_irq_probe.py、final_verdict.py、ldo_sweep.py、cam_stream.sh
- Windows 侧同名镜像；cam_go.sh v4 电源段错误（L2/L4）→ 待改 v5：L7=0x36(1.8V dovdd)+L6=0xb3(2.8V afvdd)+EN=0x60，dvdd/avdd 走 GPIO 轨（cam_rails）

---
### 2026-10-01 深夜（v44 系列）：收流软件侧彻底穷尽 → "MIPI 信号从未到达 SoC"（⚠️ 结论随后被推翻一半）

**本轮把所有软件侧配置做完，得到结论：IMX582 MIPI 数据从未到达 SoC 的 DPHY 输入。**

- **cam_init.sh v7（完整原厂序列）**：init(112) + Image_quality(9) + `0x0138=0x01` + preview(111) + streaming（`0x0350=1` → `0x3020=0` → `0x0100=1`）= **236 条 w3，执行 0 错误**；验证 ID=`0x05` / stream=`0x01` / `0x0136=0x18`(校准保留) / `0x0307=0xB4`(PL1) / **framecnt 1→9 精确 30fps**；**test pattern `0x0601=1` 写入成功且 framecnt 继续跳**： sensor 侧（含 MIPI PHY 校准）100% 健康。
- **电源域全链确认（cam_all_power.py）**：`MM_INFRA(0x1c001E6C)` / `ISP_VCORE(0xE30)` / `ISP_MAIN(0xE24)` / `CAM_VCORE(0xE58)` / `CAM_MAIN(0xE44)` **全部已 on（`0xc000000d`）**（cam_genpd 早已拉起）；scpsys 无 MIPI/CSI 专用域，seninf 的 ISP_MAIN+CAM_MAIN 覆盖。**电源不是问题**。
- **DPHY 完整配置（full_dphy.py）**：`seninf_probe.py` 缺 **`DPHY_RX_LANE_EN(0x0)=0xF01`、`LANE_SELECT(0x4)`、`HS_RX_EN_SW(0x8)`、`CLOCK_LANE 参数(0x10)`、`SYNC_DETECT(0x40-0x4C)`、`DPHYV21_CTRL(0x180)=7`**： 补全后回读全部生效（LaneEN=`0xF01` / LD0=`0x30103402` / DPY21=`0x200f0f07`），但 **clkFSM=`0x101`、dataFSM=`0x80808080` 恒默认**。
- **MUX 配置（full_rx_config.py）**：`MUX_IMG_SIZE(+0x20)` 写 `0x0BB80FA0`(4000x3000) 生效（默认 `0x10801600`=5632x4224 是 ROM 默认）；**VSIZE_ERR IRQ(bit3) 在配 IMG_SIZE 后消失**： 但 RCV_SIZE/PIX_CNT 仍 0。MUX_OPT/TOP_MUX 区写不进（只读/校准区，同 `0x1A004000`）。
- **`0x1A010D40` 身份确认 = 口0 MUX 的 FIFO_STATUS（mux 块 +0x40）**：bit0-8=FIFO_WA、bit16-24=FIFO_RA；`0x00020002` = WA=2/RA=2（微活动，非像素数据）；写 1 清的是 `MUX_IRQ_STATUS(0xB18)` / `CSI2_IRQ(0xAC8)`： 非 D40。**之前当"事件寄存器"的 D40 其实是 FIFO 指针**。
- **8 口全测（all_ports_full.py，完整 DPHY+CSI2+MUX，`0x2000` stride）**：P0-P7 全部 PKT=0/FIFO=0/RCV=0/PIX=0；**FSM 恒默认**（P1 的 dataFSM=`0x10101010` 与 P0 的 `0x80808080` 差异只是 lane_en 初始态，无计数器活动佐证）。
- **本轮结论**：**MIPI 物理信号不存在**： sensor 侧完全健康（含 PHY 校准、test pattern、30fps 帧计数），但 **DPHY 收不到任何 clock/data 信号**；远程软件配置已穷尽。
- **本轮候选（后大半被推翻）**：硬件/物理层问题（MIPI lane 走线/焊接/连接器，或非 GPIO 供电的 MIPI PHY 电源缺失）；或用示波器量 clock lane 548MHz / 检查排线。
- **资产**：`cam_all_power.py` / `full_dphy.py` / `full_rx_config.py` / `all_ports_full.py` / `mux_mon.py` / `irq_probe.py` / `combo_test.py`（设备 /root 同名）；日志 out/v7_final、full_dphy、full_rx、all_ports_full、mux_mon、irq_probe、combo_test、fan53870.log。

### 2026-10-01 晚：🟢 传感器复活根因（fan53870 重启归零）+ 收流口定位（推翻上一节一半）

**上一节的"信号不存在"结论被推翻一半： 信号实际到达 SoC 口1，但 sensor 的 MIPI TX 只发 LP 不发 HS。**

- **🟢 fan53870 重启归零 = sensor 失活根因（最重要修复）**：bus11（=dtsi `&i2c9`）`0x35` fan53870 PMIC 重启后 **PWRON(`0x03`)=`0x00`、VOUT(`0x04`/`0x09`/`0x0A`)=`0x00`** → DOVDD(L7)/AFVDD(L6)/LDO1 无电 → sensor I2C 死（NACK）。**修复序列（先 VOUT 后 PWRON）**：`i2ctransfer -f -y 11 w2@0x35 0x04 0xb3`（LDO1）、`w2@0x35 0x09 0xb3`（L6 afvdd）、`w2@0x35 0x0a 0xb3`（L7 dovdd）、`w2@0x35 0x03 0x7f`（PWRON）→ 读回 `0x03=0x7e` / `0x04=0xb3` = ALIVE。**已固化进 cam_go.sh v3**（sensor 在 bus10=dtsi `&i2c8`，bus 编号 = dtsi − 1）。
- **🟢 全电源 GPIO 确认高**（GPIO149 avdd / GPIO20 avdd2 / GPIO159 dvdd / GPIO164 rt5133en / GPIO158 avdd1=vcam_ldo / GPIO155 rst），MCLK GPIO152=CMMCLK2 24MHz 物理翻转正常（500 采样 283 次），clk_summary camtg3/seninf/seninf1-4 全 273MHz Y。
- **🟢 收流口定位（sweep_b.py ANA B 通道扫描）**：ANA **B 通道**（0B=+`0x1000` / 1B=+`0x5000` / 2B=+`0x9000` / 3B=+`0xD000`）配置后，**P1（`DPHY_TOP_1=0x11C86000`）CL0/CL1/DL0-3 检测到持续 LP 信号翻转**（cl0=`0x1`↔`0x10`、dl=`0x1`↔`0x10`，几十万采样多状态）：**IMX582 MIPI 实际接物理口 1（ANA1B + DPHY1，seninf index 2/3）**！此前全测 A 通道全 0 是**因为接的是 B 通道**（DPHY 为 A/B 共享，ANA RX 前端独立）。
- **🔴 但 sensor 的 MIPI TX 只发 LP 不发 HS**：DPHY1 CL0 恒 LP-01(`0x1`)、无任何 cl≥`0x20`（HS 状态码）；CSI2 PACKET_CNT 全 10 idx 全 0（含 FULL OPT：B2P+IMG_PACKET+FIFO_PUSH `0x3F`）。**已穷尽**：`0x0114`（`0x01`/`0x03`/`0x07`）、`0x0117`（`0x00`/`0x01`/`0x03`）、`0x0115`（`0x00`/`0x01`/`0x04`/`0x08`/`0x10`/`0x20`/`0x11`/`0x30`）、完整冷启动（power_cycle → cam_go v3 → cam_init v7 → `0x0114=0x03` → stream）：HS 均不出现。sensor 侧完全健康（ID=`0x0582`、236 条 w3 全 0 错误、framecnt 30fps、`0x0114=0x03` 回读、`0x0115=0x30`、PLL `0x0307=0xB4`）。
- **HS 不出的根因候选（软件已穷尽，下一步物理）**：① **MIPI TX PHY 模拟电源实际电压未验证**： avdd1=vcam_ldo(GPIO158 使能 1.2V) / avdd2(GPIO20) / dvdd(GPIO159) 只是 GPIO 使能脚，rail 电压来自外部 PMIC（bus 扫描：bus7 `0x55`/`0x66`、bus8 `0x50`/`0x51`/`0x58` 有候选，rt5133 不在 bus10/11）；② cam_init 缺失原厂 MIPI TX 配置块（`0x0114`-`0x0130` 区域零初始化，`0x0115=0x30` 是 sensor 默认值）：需原厂 rubensimx582 驱动寄存器表（本地 Motorola 树无此驱动、GitHub 未找到公开源码）。
- **口绑定（实测）**：物理口 1 = seninf csi-port 1 = ANA1A(+`0x4000`) / ANA1B(+`0x5000`) + `DPHY_TOP_1`(+`0x6000`)；IMX582 信号在 **1B**。**dtsi `csi-port="2"` ≠ 物理口 2： dtsi 软件声明与实际布线不符，以实测为准。**
- **新资产**：`cam_go.sh v3`（fan53870 段）、`sweep_b.py` / `port1b_csi2.py` / `sweep_idx2.py` / `hs_check.py` / `hs_probe.py` / `phy115.py` / `full_seq.py` / `clk_hf.py` / `sweep_lane.py` / `sweep_all.py` / `mipitx_status.py` / `sensor_state.py`；日志 out/sweep_b.log（口1 信号证据）、out/port1b_csi2.log、out/hs_probe.log、out/full_seq.log、out/clk_hf.log、out/sensor_state.log、out/hs_check.log。

### 2026-10-01 重启后复验 + 两条硬教训（HS 仍不出）

- **🔍 RX 配置是读取 lane FSM 的前提（重要修正）**：重启后不配 DPHY LANE_EN/HS_RX_EN 时全口 FSM 恒 `0x01`/`0x80`（哑状态）；配置 RX（`LANE_EN=0xF01`、`HS_RX_EN=0xF01`、ANA1B=`0x11C85000`、`DPHY_TOP_1=0x11C86000`）后 **口1 CL0=`0x02` / DL=`0x02020202`（LP-10）可复现**： 与重启前一致。此前"重启后 lane 全静默"是未配 RX 的误判。
- **已补验死路（HS 均不出现，口1 恒 LP-10）**：① 完整 PLL 块（`0x0301=0x05` / `0x0303=0x04` / `0x0305=0x04` / `0x0306=0x01` / `0x0307=0x68` / `0x030B=0x01` / `0x030D=0x04` / `0x030E=0x01` / `0x030F=0xA0` / `0x0310=0x01`，IMX586 preview 值，写入读回正确）；② `0x0112`/`0x0113` MIPI 速度全值 `0x00`-`0x1F`；③ `0x0115`/`0x0117` 全值扫描（`0x00`-`0xFF`）；④ 完整电源循环（fan53870 全关→VOUT→`0x7f`→RST→cam_init→stream）；⑤ 冷启动 RST 重脉冲。**imx586 preview 完整时钟块已在 sensor 上验证写入，HS 依旧不出**。
- **⚠️ 教训 1（GPIO 危险）**：`cam_gpio.ko`（参数化单 GPIO）sweep pin 164/188/160-190 时**命中 wifi/蓝牙 combo 使能脚 → wlan0 被禁用、SSH 失联**（No route to host）→ 需重启。**今后禁止 GPIO sweep**；GPIO 候选（164=rt5133en 按 cam_rails、188=rt5133 enable 按 dtsi"临时选的未用脚"）均不可靠且触碰有风险。
- **⚠️ 教训 2（fan53870 过流）**：写 fan53870 `0x01`/`0x02`/`0x03`=`0xff`（全 LDO 使能+全 PWRON）**触发 OCP 锁存，芯片 I2C 彻底无 ACK**（写 `0x7f` 一直安全，回读 `0x7e` 掉 bit0）→ 需重启。**fan53870 只允许写 VOUT(`0x04`/`0x09`/`0x0a`=`0xb3`) + PWRON=`0x7f`，禁止 `0xff`。**
- **rt5133 终判**：全 bus（1/5/6/7/8/9/10/11）`0x18`/`0x19`/`0x1a`/`0x4a`/`0x64` 均无 ACK；bus5 `0x1a`（`0x01=0x5f` / `0x03=0x12` / `0x07=0x0b` / `0x3e=0xff` / `0x3f=0x01`）、`0x34`（`0x00=0x72` PMIC ID? / `0x01=0x18` / `0x06=0xc3`）、`0x4a`、`0x64` 全 dump 确认**非 rt5133**。dtsi rt5133 `enable-gpio=188` 注释 "Temporarily choose unused gpios" = 移植临时脚。**rt5133 从未在 I2C 出现 = 硬件未使能（或不在任何可及 bus）。**
- **结论强化**：sensor 核心/时钟/PLL/PHY 校准全健康、LP 驱动器工作（`0x0114=0x01`→口1 LP-10），**HS 驱动器无电**（dtsi 里 avdd1=rt5133_ldo5 / dovdd=rt5133_ldo1 全走未使能的 rt5133；fan53870 LDO5-8 即 `0x0c`-`0x17` 区域 VOUT 当前全 0 未配）。**下一步候选（不碰 GPIO、不写 `0xff`）**：a) fan53870 `0x0c`-`0x17` 逐 LDO 设 VOUT=`0xb3` 试 MIPI TX 电源（每次一个，验 lane HS）；b) 从 Android 原厂 rubensimx582 驱动找 MIPI TX 配置块/电源归属；c) 若仍无 → 硬件级（排线/焊接）确认。

### 2026-10-01 深夜 II：HyperOS 相机全好 → "物理层死亡"终判作废 + 原理图情报

#### 核心事实
- **HyperOS 3.0.7.0 相机全部正常**（用户实测）→ 硬件链路完好，主线侧软件问题。
- 终判方法漏洞：TX on/off 鉴别实验里，DPHY 接收器从未被正确使能到能感知线路的状态，"分布不变"不能证明 TX 没发。教训：鉴别实验的前提是接收链路本身被证明工作。
- 用户提供了主板位号图 + 原理图 PDF（${K50_REPO}\红米K50_主板*.pdf）。

#### 原理图关键情报（摄像头相关）
- **主摄 = WIDE 48M IMX582（页48）**：MIPI_WIDE_CLK/LN0-3<35> → SoC **CSI0**（页21）；I2C = CAM_SCL8/SDA8 = **I2C8**（页19: I2C8: WIDE_CAM = 我们的 bus10 ✓）；MCLK = CAMW_MCLK（SoC 有 CAM_CLK0-7 八个专用球，页21）。
- **主摄专属 LDO 树（页52，与 dtsi 不同！）**：
  - CAMW_AVDD_2P9 ← U7002 NCP163（EN=CAMW_AVDD_EN）
  - CAMW_DVDD_1P1 ← U7001 WL2834CA-6 buck（EN=CAMW_DVDD_EN）
  - CAMW_AVDD_1P8 ← U7004 WL2836D18（EN=CAMW_AVDD1P8_EN）
  - CAMW_AF_2P8/CAMW_DRI_2P8 ← FAN53870（I2C9=bus11 ✓）
  - VCAM_LDO ← U7003 SGM61022 buck（Vout=0.45×(1+R7006/R7007)，R7006=66.5K R7007=36K→约1.27V?）
  - 专用使能 GPIO：CAMW_DVDD_EN/CAMW_AVDD_EN/CAMW_AVDD1P8_EN/VCAM_LDO_EN/CAMM_VDDIO_EN + FAN53870_RESET_N/IRQ
- HyperOS 包（${WINPATH}\...\[正式版]HyperOS3.0.7.0_For_K50）含 boot/boot_magisk/boot_kernelsu/boot_sukisu 变体 + images/{super,vbmeta*,dtbo,vendor_boot,userdata}.img + Flash.bat（参考其 vbmeta --disable-verity --disable-verification 用法）。
- 前置 S5K3T2→CSI1、ULTRA IMX355→CSI2/4、MACRO→CSI3（页49-51）。

#### 下一步计划
1. 刷入 boot_magisk（✓已刷）→ HyperOS rooted。
2. 用户开 USB 调试 + 相机取景中 → adb root dump：seninf/DPHY/CSI2 全部寄存器、fan53870 I2C、LDO 使能 GPIO 状态、MCLK 配置、clk_summary。
3. 与主线配置 diff → 找出遗漏项 → 回主线复现。
4. 恢复主线：fastboot 刷 boot_a/vendor_boot_a/dtbo_a（out_mainline_backup）+ userdata 稀疏镜像重建（rootfs_backup.tar.gz 4GB 已验证 146118 文件）。

### 2026-10-01 深夜 III：HyperOS 工作态情报大丰收（gold mine）

#### 已抓取并持久化的资产（${K50_REPO}\ + isp71_ref\）
- **mtk-cam-isp.ko（2.5MB）**：HyperOS 的完整相机 ISP/seninf 驱动模块！kallsyms 证实函数名与 ISP7.1 参考源码一致（csirx_seninf_csi2_setting / mtk_cam_seninf_cammux / set_top_mux_ctrl 等）。**这就是"能工作的"寄存器编程的最终真相源**：待反汇编提取 MT6895 精确序列。
- mtk-cam-plat-mt6895.ko（14KB）：6895 平台差异。
- hyperos_fdt.dtb/dts：原厂 live 设备树（509KB dts）。
- hyperos_clk_summary.txt（相机运行中抓取）+ hyperos_gpio.txt。

#### 运行态实锤（相机取景中）
- **主摄供电**：vcam_ldo=1.2V ON（gpio-423=本地158 ✓）+ fan53870-l6=**2.9V afvdd ON** + fan53870-l7=**1.8V dovdd ON**；l1-l5 全 disabled。→ 主线电源配方：L6=0xBF? (2.9V)、L7=0x36、EN=0x60 + vcam_ldo(G158)。⚠️ 注意 l6 2.9V ≠ 我们猜的 2.804V（0xb3），regulator 报 2900000uV（0xbf=2.9V）。
- **MCLK**：camtg_sel + camtg3_sel 双使能（都 24MHz）：主摄 MCLK=camtg3（与主线 cam_clk3 一致 ✓）。
- **DT 实锤**：sensor0(imx582) → seninf csi-port_2；pinctrl cam0 全套（mclk=152✓ rst=155✓ avdd=149✓ avdd2=20✓ dvdd=159✓）；mclk 时钟 phandle= topckgen idx 0x16=CAMTG3_SEL ✓。
- **fan53870 原厂 init-voltage（DT）**：l1=1.1V l2=1.2V l3/l4/l5=2.8V l6/l7=2.8V?? 但运行态 l7=1.8V（HAL 动态调）：**以运行态为准：L7=1.8V**。

#### 下一步（回主线后执行）
1. 反汇编 mtk-cam-isp.ko（objdump，kallsyms 符号在）提取：csi-port→seninf idx 映射、csi2/dphy/cammux 精确寄存器序列（对照 ISP7.1 源码）、口2 的完整配置。
2. 修正主线序列：电源（L6=2.9V/L7=1.8V/EN=0x60）+ 口2 seninf 配置（从 .ko 提取）+ MCLK=camtg3。
3. 恢复主线：fastboot 刷 boot_a/vendor_boot_a/dtbo_a（out_mainline_backup）+ userdata sparse 重建（rootfs_backup.tar.gz）。

### 2026-10-02 凌晨：恢复完成 + 相机卡点前移到内核配置

#### 恢复结果（另一 AI 会话执行，本会话验证）
- mainline 三件套 + userdata sparse 均刷回成功，**Debian 系统完整恢复**（SSH/wlan0/${K50_HOST}）。
- WiFi/SSH 修复根因 = **刷机后文件属主错乱**：NM 插件模块、authorized_keys、NM profile 全是 k50 属主，NM/sshd 拒绝加载。`chown -R root:root` 修复。**mke2fs -d 填充的镜像会保留 tar 里的一切属主：恢复后要批量检查属主！**

#### 相机真正的卡点（修正认知）
- 主线内核 7.2.0 **CONFIG 里没有任何 MTK CAM/SENINF/ISP 选项**（/proc/config.gz "Camera ISPs" 段为空），且 **/lib/modules 不存在**（全 built-in，无模块树）。
- **主线源码树没有 seninf/ISP 驱动**：drivers/media/platform/mediatek/ 只有 jpeg/mdp/vcodec/vpu。HyperOS 的 mtk-cam-isp.ko 是 5.10 vendor 驱动，**无法直接加载**（vermagic/API）。
- 可用参考源：isp71_ref/（seninf 子集 V4L2 源码）+ mtk-cam-isp.ko（二进制，符号全）+ vendor ksrc cameraisp（旧式 char 驱动）。

### 2026-10-02 凌晨补充：🟢🟢 HS 不出根因实锤： 原厂 fdt（HyperOS）电源/GPIO 配方

**先导事实（用户刷回安卓实测）**：**HyperOS 相机全好 = MIPI TX 硬件完好，"物理层死亡/过压损坏"终判作废**。所有 HS 不出的根因 = **主线 Debian 没按原厂配方供 IMX582 的电源**。

**权威配方（原厂 `hyperos_fdt.dtb` 反编译 `${K50_REPO}\hyperos_fdt.dts`，sensor0@10 节点 + pinctrl 段）：**

- **电源绑定**：`avdd1-supply=vcam_ldo`、`dovdd-supply=fan53870-l7`、`afvdd-supply=fan53870-l6`。
- **vcam_ldo 节点**：min/max=**1.2V**，`gpio=<0x4e 0x9e 0x00>` = **GPIO158**（`0x9e`=158），`enable-active-high`。
- **fan53870（bus11 `0x35`）LDO 定义（offset 0-6 = 寄存器 `0x04`-`0x0a`）**：L1 init 1.15V、L2 init 1.2V、L3 init 2.9V、L4 init 2.8V、L5 init 2.8V、**L6(`0x09`) init 2.8V=afvdd**、**L7(`0x0a`) init 2.8V=dovdd**（min 1.5 / max 3.4V）。**HyperOS 运行态（相机取景中 dump）：L6=2.9V(afvdd)、L7=1.8V(dovdd)、L1-L5 关、vcam_ldo=1.2V、MCLK=camtg3 24MHz、sensor0→csi-port_2**。
- **pinctrl 13 态（sensor0）**：`mclk_off/2ma/4ma/6ma/8ma` + `rst_low/high` + `avdd_off/on` + `avdd2_off/on` + `dvdd_off/on`。**GPIO 编号（pinmux 高 8 位=GPIO）**：
  - **GPIO152 = CMMCLK2（MCLK）**，pinmux `0x9800`/`0x9801`
  - **GPIO155 = CAMW_RSTN（rst）**，`0x9b00`
  - **GPIO149 = CAMW_AVDD_EN（avdd，U7002→CAMW_AVDD_2P9 2.9V）**，`0x9500`
  - **GPIO20 = CAMW_AVDD_IP8_EN（avdd2，U7005→CAMW_AVDD_1P8 1.8V）**，`0x1400`
  - **GPIO159 = CAMW_DVDD_EN（dvdd，U7001→CAMW_DVDD_1P1 1.1V）**，`0x9f00`
  - GPIO158 = VCAM_LDO_EN（U7003 buck → VCAM_LDO 1.2V = avdd1）
- **原理图（见 §2「2026-10-01 深夜 II：HyperOS 相机全好」）拓扑交叉确认**：U7002(NCP163) / U7005(SGM2045-1.80) / U7001(WL2834CA) / U7003(SGM61022) / U7004(WL2836D18)；fan53870 输出映射 LDO1=CAMF_DVDD_1P1、LDO2=CAMM_DVDD_1P2、LDO3=CAMM_AVDD_2P8、LDO4=CAM_AVDD_2P8、LDO5=CAMW_AF_2P8、LDO6=CAM_DVDD_1P8、LDO7=?： **注意：fdt 运行态权威值 L6=afvdd / L7=dovdd，与原理图 LDO 序存在标注差异，一切以 fdt / 运行态为准**。

**🔴 根因结论（修正上一节）**：主线 Debian 只配了 fan53870 部分 LDO 且电压错（L1/L6/L7=`0xb3`≈3.15V），**从未使能 U7001/U7002/U7005（GPIO159/149/20 从未拉高）→ IMX582 MIPI TX 模拟电源（AVDD_2P9/AVDD_1P8）与核心 DVDD 无电 → I2C（DOVDD 供电）活着但 HS 驱动器无电 → 只发 LP**。用户"过压损坏"怀疑不成立（安卓实测硬件完好），但 **`0xb3` 驱动 1.8V/1.1V 轨确实是错配，必须修正**。

**✅ 回 Debian 后执行清单（优先级高）**：
1. **修正 cam_go.sh fan53870 段**：L6(`0x09`)=**`0x2C`**(2.8V afvdd)、L7(`0x0a`)=**`0x18`**(1.8V dovdd)，PWRON=`0x7f`；**禁止 L1/L6/L7=`0xb3`**。
2. **新增 GPIO 上电**（gpiod/sysfs；HyperOS 全局号 = chip_base + offset，gpiochip0 base=265）：GPIO149=高(avdd 2.9V)、GPIO20=高(avdd1.8V)、GPIO159=高(dvdd 1.1V)、GPIO158=高(vcam_ldo 1.2V)、GPIO155=高(rst)，GPIO152=mclk(camtg3)。**遵守教训：不 sweep，只动这 6 个已知脚，逐个确认方向/电平**。
3. 重新跑 cam_init.sh v7(236 条) + streaming + 口1(ANA1B) FSM 探测： 预期 **HS 状态码出现（cl≥`0x20`）**。
4. 若 HS 出现 → 继续 SENINF/CAMSV 抓帧（cam_view 出图）。

**⚠️ 电源顺序参考（HyperOS imgsensor 典型）**：avdd(149) → avdd2(20) → dvdd(159) → vcam_ldo(158) → dovdd/afvdd(fan53870) → rst 高(155) → mclk(152) 稳定 → I2C init → stream。

### 2026-10-02 深夜：mtk-cam-isp.ko 反汇编突破（口2 真相）
- **init_port 跳转表**：port→seninfIdx 0基：0→0,1→2,**2→4**,3→6,4→8,5→10,6→1,7→3,8→5,9→7,10→9,11→11（口2=seninfIdx4 ✓ 与 ISP7.1 SENINF_5 一致）。
- **init_iomem 循环解码（权威地址）**：ctrl[i]=if+0x200+0x1000i，csi2[i]=if+0xa00+0x1000i，mux[i]=if+0xf00+0x1000i（12个），cam_mux[j]=if+0x400+0x20j（23个）。**口2：ctrl=0x1A014200 / csi2=0x1A014A00 / mux=0x1A014F00**： port2_v1 的地址其实是对的！
  - ⚠️ **2026-10-05 复核修正（原文保留）**：上面 `mux[i]=if+0xf00+0x1000i` **块名标错**： `0xf00` 是 **TG 块**（`phy_3_0` 的 `reg_if_tg[i]`），不是 mux。mux 是 TOP 内 **flat 阵列**：基址 `0x0d00`、步长 `0x1000`、索引是 **mux 号（0–12）而非口号**，即 `reg_if_mux[j]=if+0x0d00+0x1000*j`。证据：`isp71_ref/mtk_csi_phy_2_0/…hw_phy_2_0.c:116,120-121`（tg=`0x600`、mux=`0x0d00`）、`…phy_3_0.c:156,161-162`（tg=`0xf00`、mux=`0x0d00`）、设备 `mtk-cam-isp.ko` 反汇编 `isp_ko.asm` @`0x5c474`/`0x7a954`（mux 循环初值均 `+0xd00`）；旁证 `mux[12]=0x1a01cd00` 实测已配通 ✓。⇒ **口2 的 `0x1A014F00` 是它的 TG 块地址**，口2 的 mux 走 `mux[12]=0x1a01cd00`（见本文件 §0 第 3 条）。ctrl/csi2 两值不变（`0x200+0x1000*4`、`0xa00+0x1000*4`，seninfIdx=4 ✓）。详见 `SENINF_CONFIG.md` ▲1。
- **top_setting 每口源选**：if+0x60/0x64/0x68/0x6c，口2 案例=**if+0x68 bits[9:8]=2**（0x1A010068）。set_top_mux_ctrl：mux_idx→if+0x10 起 4bit 域。
- **csi2_setting**：DBG_CTRL=+0xe0(bit17)、RESYNC=+0x10(bit8)、OPT=+0x4(CPHY=0)、EN=+0x0(0xF)、HDR=+0x8/0xc： 与 ISP7.1 一致。
- **此前口2 无包的根因（修正后）**：① settle/trail 用错（用了 0x10/0x34，DT 口2 要 0x1C/0x20）② L6 afvdd 2.9V 当时未供电 ③ mux 链（mux=0x1A014F00 SRC_SEL、top mux 0x1A010068、cam_mux 0x1A010400）未按 .ko 流程走。
- **恢复主线进行中**：rootfs tar 解包 WSL ${HOME}/rootfs_stage → mke2fs -U ef657ae4-... 59152376×4K → img2simg → fastboot flash userdata + 三件套。

---
### 2026-10-04 深夜：Route A 深挖：配置已 100% vendor 复刻，仍 0 包；唯一出路=HyperOS 工作态寄存器 diff

#### 重大修正 1：scpsys 基址错误（此前所有"SPM ctl"读写全是错误地址！）
- **scpsys 基址 = 0x1c001000**（mt6895.dtsi `power-controller@1c001000`，reg=0x1c001000+0x1000），**不是 0x1c004000**！
- 此前会话读的 0x1c004e24"isp_main ctl=0xC0F41F1F"、"CAM_MAIN ctl=0x31BC1120"全是 SPM 其他寄存器的乱值，据此推断的位语义全作废。
- 误写过 0x1c004e24（0xC0F41F1F→0xC0F41E0D），已恢复原值。
- 真实 ctl：isp_main=0x1c001e24（off=0x00001112 / **on=0xC000000D** 与 cam_main 0x1c001e44 完全同构）。

#### 重大修正 2：isp_main 已手动上电成功
- 上电序列（复刻 scpsys_power_on）：ctl@0x1c001e24 写 PWR_ON|0x6 → 等 ctl 内 sta bits30-31 → 清 CLK_DIS(bit4) → 清 ISO(bit1) → 置 RST_B(bit0) → 写 PWR_ON_2ND|0x8 → 等 sta=3 → 清 SRAM_PDN(bit8) 等 ack(bit12) 清 → 总线保护释放：infracfg_ao clr=0x10001C38 写 0x405 再 0x80A（mask=BIT0|2|10 / BIT1|3|11，BUS_PROT_IGN 无需等 ack）。
- 脚本：/tmp/pwr_isp.sh + pwr_isp2.sh（PWR_ON_2ND 单独写，漏写它 bit31 ack 不来）。
- genpd 里 isp_main 仍显示 off（绕过内核直改寄存器，无设备 attach 无副作用）。
- 域 ID 确认：seninf DT power-domains=<spm 8><spm 12> = ISP_MAIN+CAM_MAIN（mt6895-power.h）。

#### 重大修正 3：is_4d1c=TRUE（之前记反了！）
- vendor 源码：`if (port >= CSI_PORT_0A) portNum=(port-0)>>1; else portNum=port;` csi-port"2"→portNum=2→**is_4d1c=(2==2)=TRUE**。
- 4d1c = 4data+1clk 跨 A/B 前端（与原理图吻合）：模拟侧 CKSEL 全部=1、**时钟=portA 的 L2**（baseA CDPHY_RX_ANA_0 bit14=1）；数字 LANE_SELECT：LC0=2/LD0=1/LD1=3/LD2=0/LD3=4、CK_DATA_MUX_EN(bit31)=1 → 0x80413002；LANE_EN=0x0F01（LC0=bit0，LD0-3=bit8-11）。

#### v17：从头文件自动生成脚本（gen_v17.py → port2_v17.py）
- 解析 isp71_ref/mtk_csi_phy_2_0/ 五个头文件（ana-csi0a/csi0-dphy/top-ctrl/seninf1/seninf1-csi2），精确复刻 mtk_cam_seninf_set_csi_mipi() 全序列：phyA_init(A+B)→dphy_init(settle=0x1C/prepare=2/trail=0x20/trail_en=1)→seninf csi2(PKT_CNT_EN/RESYNC/OPT/EN=0xF/HDR)→ctrl(CSI2_EN/SENINF_EN)→top(0x68 DPHY_EN)→phyA_setting(CKSEL/CKMODE/EQ)→dphy_setting(lane select)→phyA_power_on(BG_CORE→LPF→OSCAL bits16-21 @ANA_8)。
- **结果：PKT 0x1a014adc = 0，clkFSM=0x101，dataFSM=0x01010101（全部 lane 恒为 1 = 只见 LP-11）**。

#### v18-v19：排除法
- v18 扫 5 种 lane 映射（vendor 4d1c / 原理图 CLK=2B_L1 / 2B_L0 / 混合）：**全部恒 LP-11**：任何物理 lane 都收不到 HS，排除 lane 映射问题。
- v19 ANA 写粘性扫描 0x11c80000-0x11c9f000：port2 三块（0x11c88000 csi_rx A / 0x9000 B / 0xa000 dphy_top）基址正确、可写、粘滞；ko 反汇编 csirx_phyA_power_on 确认位布局与 Moto 头文件一致（BG_CORE=bit0/LPF=bit1/OSCAL=0x20 bits16-21/RESERVE 0x3003→ANA_9=0x24）。
- 读回异常：ANA_0=0x00670012（bit13 多出、bit0 BG_CORE 消失、OSCAL 自清）：硬件自管理，不影响结论。

#### v20：传感器侧彻底洗清
- **cam_init.sh 全部 236 个寄存器逐一回读校验：100% 一致**（仅 0x0100 流控位随开关变化）。模式表无静默 NACK。
- 出流确认：0x0100=1 后 fc 寄存器 0x0005 每秒 +30（30fps ✓）；MCLK camtg3=24MHz（与 HyperOS hyperos_clk_video.txt 完全一致）；I2C bus10 @0x10 在位。
- 注意坑：i2ctransfer 寄存器参数必须带 0x 前缀，裸 '09' 被当十进制！

#### 结论与下一步
- 软件配置已与 vendor 驱动逐位一致（连 ko 反汇编都核对过）、电源/时钟/域全对、传感器模式表全对出流正常：**但 6 条物理 lane 全部只见 LP-11**。FSM=1 无法区分"传感器没发"vs"信号没到 SoC pad"（浮空输入也偏置成 LP-11）。
- HyperOS 用同一传感器+同一 MCLK+同一电源表+同一模式表=硬件链路必然完好 ⇒ **差异只能在 SoC 侧某个未被复刻的状态**，纸面推理已穷尽。
- **下一步（需刷 HyperOS，约 1-2h，已有全套备份：rootfs_backup.tar.gz + userdata_sparse.img + phone_root_scripts_20261004.tar.gz + phone_cam_modules_20261004.tar.gz）**：
  1. 刷 HyperOS 四件套（vbmeta --disable-verity/--disable-verification + boot_magisk + vendor_boot + dtbo）+ fastboot -w 清 userdata（HyperOS 与 Debian userdata 加密不兼容会 crash-loop）。
  2. 用户开 USB 调试 → adb `am start -a android.media.action.STILL_IMAGE_CAMERA` 开取景。
  3. dump：`/sys/kernel/debug/mtk_cam_dbg/0..22`（引擎 dump）、seninf v4l2 节点 VIDIOC_LOG_STATUS（logstatus.c 已备）、若 /dev/mem 可用则 busybox devmem 全量 dump 0x1a010000+0x20000 与 0x11c80000+0x20000。
  4. 与主线状态 diff → 找出缺失的寄存器/时钟/电源位。
  5. 恢复主线：out_mainline_backup 三件套 + userdata_sparse.img + 重推 phone_*.tar.gz 内容到 /root。
- SSH 现在要用 `-i ~/.ssh/${K50_KEY}`，IP 随热点变化（本次 ${K50_HOST}）。

---
### 2026-10-05 凌晨：连环根因逐一击破：HyperOS diff 落地 + 门控真相

#### HyperOS 工作态 diff 结论（另一 AI 完成，${K50_REPO}\hyperos_workstate\DIFF_REPORT.md）
- **D1 ★★★：HyperOS 用的是 CSI PHY 3.0 驱动（mtk_csi_phy_3_0），不是我们复刻的 2.0！** dmesg 打印逐句匹配 phy_3_0.c。isp71_ref 里两套源码都有。
- D2: HS_TRAIL=0x1a(26) 非 0x20（计算链 dphy_trail=68, ui_224=163, SENINF_CK=273MHz）
- D3: RESYNC_MERGE_CTRL=0x300df106（先写 0x2020f106 再 OR：DMY_CYCLE=13, DMY_CNT=3, DMY_EN=0xf；cycles=64*273e6/data_rate+1）
- D4 ★★★: **时钟 lane settle 从未写过**！DPHY_TOP 0x10/0x14（CLK_LANEx_HS_PARAMETER）bits16-23=0x1c
- D5: DPHY_RX_SPARE0(+0xf0)=0xf1（non-legacy）
- D6: ANA_SETTING_1(+0xf4)=0x00140254（默认值，无写入）
- phy_3_0 phyA_init 与 2_0 差异：**不写 ANA_9 RESERVE/SETTING_0 CSR_RST_MODE**（注释掉）、CDR_CK_DELAY=0x4 非 0
- HyperOS 实测零错误：packet_cnt_status=0x73c 在走、err 全 0。mux 路由 vc0: dt0x2b mux12 cam0 4000x3000 + vc1: mux0 cam15 992x1488。

#### port2_v21.py（phy_3_0 复刻）结果 = 新根因连环揭露
1. **CSI2 块(0x1a014a00)/CTRL(0x1a014200)/TOP(0x1a010068) 全部拒写且读 0**： 历届所有 seninf 数字配置从未生效过！！（ANA 0x11c8xxxx 和 DPHY_TOP 0x11c8a000 一直正常，掩盖了这点）
2. 根因链：**重启后 cam_ovl 的 DT overlay 没有应用成功**（routeA insmod cam_ovl "OK" 但 overlay 未生效）→ syscon@1a000000 节点无 power-domains → cam_genpd attach 后 rpm_hold 无效 → cam_main 域 OFF → **cam_m 模块门控块 (0x1a000000 sta=0x0，camsys 全部模块时钟关)** → 整个 0x1a00xxxx-0x1a17xxxx 相机 MMIO 死区（读 0、写丢弃）。
3. **修法**：rmmod cam_ovl; insmod cam_ovl（确认 dmesg "of_overlay_fdt_apply(866 bytes)=0"）→ rmmod/insmod cam_genpd（8/8 attach）→ genpd 走内核正规上电（含 subsys clocks cam_lp-*）→ 门控 sta=0xffffff87 → **CL_FSM 从 0x1 变 0x20、数据 lane FSM 0x80（MIPI 信号首次到达 SoC！）**：时钟 lane settle(D4) 是信号层修复的关键。
4. 仍剩：seninf 数字块(0x1a01xxxx)在 /dev/mem 下仍读 0 写无效（门控块 0x1a000000 本身也出现 0x12345678 诡异值：/dev/mem 对该区域读不可靠）。正在编内核态验证模块 cam_mmtest.c（iokernel 侧 ioremap 测试写入+PKT）。
5. 构建环境：**真构建树 = ${KDIR}/**（vermagic 7.2.0-g0b8dd2e87b3d-dirty 逐字匹配，CONFIG_ARM64=y）；${HOME}/work/mt6895-mainline/linux 的 .config 是 x86 的（不能用于模块）；D:\ 树 .config 也成了 x86（今晚被污染）；**WSL 对 ${K50_REPO}/mt6895-mainline/ 有持续性 I/O 错误**（D 盘局部问题，Git Bash 可读，wsl --shutdown 后依旧），建议 chkdsk。
6. 手机 05:00 定时关机已设（用户要求）。WiFi 又掉了，SSH 断，全程串口（k50.ps1）。

#### 待办（cam_mmtest 编完之后）
- insmod cam_mmtest → dmesg 看内核侧写入是否粘 + PKT 是否计数
- 若内核侧粘：把 v21 全套配置搬进模块跑（devmem 弃用于 0x1a01 区）
- PKT 计数后：mux 链（mux[12] src4 → cam0）→ CAMSV DMA raw 抓帧 → cam_view

### cam_mmtest 构建与加载（2026-10-05 中午）
- 构建成功：`make -j8 LLVM=1 ARCH=arm64 -C ${KDIR} M=<模块目录> modules`（必须 LLVM=1 + ARCH=arm64；WSL 的 /tmp 每次会话被清，放 ${HOME}/cam_mmtest/）。vermagic 差 -dirty，用 python 等长重写 .modinfo 节（readelf -SW 定位 .modinfo off=0x7a8 size=0x61，重写为 license/name/vermagic + NUL padding）。
- **加载即崩**：insmod 段错误，oops 在 load_module→module_finalize→apply_alternatives_module→__apply_alternatives。clang 18.1.3 与内核完全一致，原因未明（.modinfo 等长补丁存疑或 alternatives 对新模块文本处理问题）。
- 随后尝试加载已知良好的 mclk.ko 后**整机挂死**（串口无输出、SSH 超时），用户需强制重启。
- 重启后直接继续：modinfo 补丁法换一个思路（改用源码里 MODULE_LICENSE 前 module_vermagic 伪造？或干脆查 -dirty 来源：worktree 当前 clean，touch 一个文件重编即可自然 -dirty：下次先试这个，别再二进制补丁！）。

---
### 2026-10-05：🟡 原厂配方执行清单实测（设备 WiFi 掉线，全程 COM9 串口驱动，无人值守）

**⚠️ 串口通道（重要工作方式变更）**：设备 wlan0 掉线（No route to host，SSH 不可用），全程用 **USB gadget serial（COM9，115200 8N1）** 驱动。工具：`${K50_REPO}\scripts\k50.ps1 -Cmd "<cmd>" / -Push <local>`（自动找口，可指定 `-Port COM9`；**命令结尾必须裸 `\r`**，CRLF 会被行规程吞掉；长命令链输出常丢 → 习惯落盘 `> /root/x.log` 再 cat；嵌套 powershell 调用若卡住会留 OpenConsole 僵尸占 COM9 → 杀 zombie 进程释放）。**SSH 恢复前所有设备操作走串口。**

**✅ 执行清单第 1-2 条完成（新资产 cam_go_v6.sh）**：
1. **fan53870 修正生效**：L6(`0x09`)=**`0x2c`**(2.804V afvdd)、L7(`0x0a`)=**`0x18`**(1.804V dovdd)、PWRON(`0x03`)=**`0x7f`**（**i2cset 在此内核 Write failed，必须 i2ctransfer `w2@0x35`**）。回读确认 `0x03=0x7f` / `0x09=0x2c` / `0x0a=0x18`。
2. **GPIO 上电实测**：**GPIO149/155/158/159 重启后 DIR=0（输入）、DATA=0（低）→ cam_rails 未拉高！** 用 devmem RMW（GPIO_BASE `0x10005000`）：DIR(`0x10005110`)=`0xC8020200`（置输出：bit21=149 / bit27=155 / bit30=158 / bit31=159）+ DATA(`0x10005010`)=`0xC8020200`（拉高）→ 回读 `0xC8020200` ✓。GPIO20 已高（bank0 `0x00100008` bit20=1）。**gpiotoolG 对这些脚报 Device busy（被 cam_rails claimed）→ 裸拉高必须 devmem 物理寄存器。**
3. **sensor 完全复活**：cam_go_v6.sh（fan53870 → 模块重载（rails 最后）→ MCLK → RST）后 IMX582 ID=`0x0582`、`0x0114=0x03`、`0x0115=0x30`、`0x0307=0x68`、framecnt=`0xc0`(192) 在走（**30fps 出帧**）。
4. **RX 配置 + FSM 探测**：`DPHY_TOP_1(0x11C86000)` `LANE_EN=0xF01` / `HS_RX_EN_SW=0xF01` / `CLOCK_LANE=0x30103402`（回读 `0x10100002`）/ `DPHYV21_CTRL=0x7` + ANA1B(`0x11C85000`) RX=`0x1` 全部生效；**scan_dphy_fsm.py（本地 `${K50_REPO}\scan_dphy_fsm.py`；FSM=base+`0x30`/`0x34`；DPHYS 基址：D0=+`0x2000`、D1=+`0x12000`、D2=+`0x6000`(=`0x11C86000`!)、D3=+`0x16000`、D4=+`0xa000`、D5=+`0xe000`，ANA=`0x11C80000`）** 8 采样：**D0-D4 恒 `0x101`/`0x80808080`、D5=0**： **HS 仍不出**（`0x101`=LP-11 idle，无 cl≥`0x20`）。
5. **候选 a（fan53870 LDO5-8，`0x0c`-`0x0f` VOUT=`0x2c`）实测 = 失败且危险**：写入后 RST+init **sensor I2C 全 Error（No such device）被打死**；写回 `0x00` + 重跑 cam_go_v6.sh 复活。**`0x0c`-`0x0f` 是敏感区（非 MIPI TX 电源），禁止乱写。**

**🔴 HS 不出的现状归纳（电源理论已齐仍无 HS）**：sensor 电源全就绪（fan53870 L6/L7 + GPIO rails 高 + MCLK 24MHz）、sensor 出帧 192、DPHY RX 配置生效，但 **所有 DPHY 收不到 HS**。上一节的"电源根因"已执行完毕仍无效 → **回到候选②：cam_init 缺原厂 MIPI TX 配置块（`0x0114`-`0x0130` 区域）**，或 **物理层（MIPI 走线/焊点）**。下一步：a) 找原厂 rubensimx582 驱动寄存器表（本地 Motorola 树/公开源码）；b) 完整电源循环（fan53870 全关→GPIO 全关→按 HyperOS 顺序重开）再试；c) 用户可验证 HyperOS 相机正常（硬件好）： 问题锁定主线软件配置缺失。

**⚠️ 教训**：① 设备 WiFi 偶发掉线常态（重启即愈），SSH 挂时别慌，COM9 是可靠通道；② 串口长命令链输出常丢，落盘分段 cat；③ fan53870 只动 L6/L7 + PWRON=`0x7f`，`0x0c`-`0x17` 区域别碰。

### 2026-10-05 晚：🟢🟢 健康窗口突破 + MIPI TX 仍无输出（v23-v60 系列，C 快写）

**先导：sensor 每次模块重载后只在极短窗口（RST 后 0.1-0.3s）内健康**： go 脚本内 ID=`0x0582` / `0x0114=0x03` / `0x0307=0x68`，go 结束后 0.16s 即退化 ID=`0x00` 且 `0x01xx`/`0x03xx` 写入"不粘"。此前 v23-v47 全部"写入不粘"结论 = **i2ctransfer 子进程 150-300ms 开销错过窗口的假象**，不是 sensor 写保护。

**✅ 决定性突破（fp_fast3.c，C 语言 ioctl 直连 `/dev/i2c-10`）**：
- 健康窗口内等 ID=`0x0582` → **全 236 寄存器表 33ms 写完**（ioctl 每写 <10µs）→ 读回 **`0x0112=0x0a`、`0x0113=0x0a`、`0x0114=0x03`、`0x0100=0x01`、`0x0350=0x01`、`0x0307=0xb4` 全部粘住**（v56 修正前缀后确认；v55 曾用错前缀读到 `0x0312`/`0x0314`）。
- **sensor 内部 streaming 确认**：`0x0100=1` 后 **fc（`0x0005`）`0xFF`→`0x01` 在走**（v56/v60）： 数字核心出帧。
- **🔴 但 MIPI TX 物理仍无输出**：FSM 恒 `0x101`/`0x01010101`（LP-11）、PKT=0： **`0x0114=0x03` 配上但物理 HS 不出**。fc 走 + LP-11 = sensor 用 DOVDD(1.8V fan53870 L7) 跑数字核心，但 **HS 驱动器电源轨物理缺失**。
- vendor 交叉确认（`imx586_Sensor.c` streaming_control）：`0x0350=1` → `0x3020=0` → `0x0100=1` → poll fc≠`0xFF`，与我们表尾一致；`0x0104`=组保持（Grouped Parameter Hold），非软复位。

**🔴 GPIO158/159 物理低 = 与 HyperOS 的最终差异（HS 不出的最可能根因）**：
- **DIN bank4（`0x10005210`）bit30/31 = 0**（GPIO158=vcam_ldo 1.2V、GPIO159=dvdd 1.1V 物理未拉高）；GPIO149(bit21)/155(bit27)/20(bank0 bit20) 物理 Hi ✓。
- **HyperOS 对照（`hyperos_workstate\gpio_preview.txt`）**：HyperOS gpiochip0 **base=265**（mainline base=0/ngpio=247），**`gpio-423 = soc:odm:vcam_ldo = out hi`**： 即 HyperOS 下 GPIO158 out hi，**mainline 物理低与 HyperOS 不符**。
- **GPIO 输出路径全受阻（本窗口实测）**：① gpiotoolG 写失效（v45 已证）；② `/sys/class/gpio` 不存在（`CONFIG_GPIO_SYSFS=n`）；③ **gpio linehandle ioctl 全部 EINVAL**（`/dev/gpiochip0`，label=`pinctrl_paris`，ngpio=247，flags 全组合试过，errno=22： pinctrl 内核层拒绝）；④ devmem 写 `0x10005110`（候选 DO）无效；⑤ `DO_SET`=**`0x10005710`**（写 `0x40000000` 生效读回 `0x40000001`）但 **DIN 不变**；⑥ `DIR`=**`0x10005310`**（bit30 可写 → `0x40000011`，GPIO158 方向已设输出）但物理仍低。
- **MT6895 GPIO 寄存器布局（实测确定）**：pinmux mode 区 **`0x10005400`-`0x100054c0`**（每 2 引脚 4 字节，**`MODE152=0x10005430`**=`0x00000001` ✓，GPIO158/159 → **`0x1000543c`**=0=GPIO 功能）；**DIN `0x10005200`-`0x10005270`**（bank0-7，每 bank 4 字节）；**`DO_SET 0x10005700+`**（`0x10005710` 生效）；`0x10005300`-`0x100053f0`=PAD 配置（`0x11`/`0x33`/`0x77` 模式）；`0x10005100` 与 `0x10005000` 值相同（别名/只读）。

**🔴 现状归纳**：sensor 电源（fan53870 L6/L7 + GPIO149/20/155 高）、MCLK（24MHz 物理翻转，bank4 DIN 证实）、genpd（cam_main on）、RX 配置（DPHY/CSI2 与 HyperOS 一致）、sensor 内部 streaming（fc 走）全部 OK；**唯一未闭环 = GPIO158/159（vcam_ldo/dvdd）物理低 → HS 驱动器无电 → LP-11**。内核 GPIO 请求路径（linehandle）全 EINVAL，devmem `DO_SET` 不反映物理（疑 pinctrl 持有/方向未真正生效）。

**下一步候选（按优先级）**：① **重启系统**（真正断电 sensor 冷启动，避开伪断电累积态）→ go22 → fp_fast3 全表 → FSM/PKT；② 读 sensor PLL 锁定状态寄存器（`0x0115`/`0x0124` 等）确认 MIPI PLL lock；③ 修内核 pinctrl（让 gpio 请求可用，`CONFIG_GPIO_SYSFS`/linehandle 路径）；④ 物理验证 HyperOS 下 GPIO158/159 电平（若 HyperOS 也低 → 供电假设推翻，回看 MIPI TX 配置块）。

**⚠️ 本窗口新教训**：① **传感器实验必须用 C 快写**（Python subprocess i2ctransfer 太慢必错过窗口），`fp_fast3.c` 已固化；② 读回寄存器**注意 8-bit 前缀**（`0x0112` 用 `0x01` 前缀、`0x0312` 用 `0x03` 前缀，v55 因前缀错白跑一轮）；③ 所有 GPIO 物理电平以 **DIN（`0x10005210`）为准**，debugfs/gpio 软件状态不可信；④ 不要再用 GPIO sweep（前述教训仍有效）。

## 3. 路线选择：Route A vs Route B
- **A（快，出原始帧）**：主线内核上用 devmem/自编模块跑 CAMSV raw 抓帧：不依赖内核配置，纯 MMIO。口2 正确序列已从 .ko 提取（csi2=0x1A014A00/ctrl=0x1A014200/mux=0x1A014F00/top mux=0x1A010068 bits[9:8]=2、DT 参数 settle=0x1C/trail=0x20、电源 L6=2.9V/L7=1.8V）。查帧用 csi2 PKT 计数器。
- **B（完整，长线）**：把 vendor mtk-cam-isp V4L2 栈（+CCU 固件+IOMMU+media controller）移植到 7.2.0 内核：大工程，需内核重编。

---
## 4. 禁令与教训

### 4.1 禁令
- 🚫 重打包 dtbo/boot 再刷 = 不开机（2026-09-29 血泪）。DT 改动一律 cam_ovl.ko 运行时 overlay。

### 4.2 经验教训（2026-10-01）
- 鉴别实验必须先证明测量链路本身工作。
- 原理图是最终真相源：dtsi 的 supply 映射过时/错误（avdd1=vcam_ldo 1.2V vs 实际 CAMW_AVDD_2P9）。
- A/B 槽镜像不能混搭换槽（vbmeta/slot_suffix/镜像族必须配套）。

---
### 4.3 散落在时间线里的禁令/事故索引

- 🚫 **禁止全引脚扫描**（247 脚逐个 request 致整机冻结）： 见 §2「2026-09-27（下午）」与「2026-09-27（晚）」。
- 🚫 **禁止重打包 dtbo/boot 再刷**（2026-09-29 不开机）： 见 §2「2026-09-30 凌晨会话」禁令节。
- 🚫 刷机后必须 `chown -R root:root`（mke2fs -d 保留 tar 属主，NM/sshd 拒绝加载）： 见 §2「2026-10-02 凌晨：」的「恢复完成」节。
- ⚠️ mmap offset 必须关键字传参（第 4 位置参数是 prot）： 见 §2「2026-10-01 接手会话」。
- ⚠️ `/dev/mem` 对该区域读不可靠（0x1a01xxxx 区需内核态 ioremap 验证）： 见 §2「2026-10-05 凌晨」。
- 🚫 **禁止 GPIO sweep**（扫 pin 160-190 命中 wifi/BT combo 使能脚 → wlan0 被禁用、SSH 失联）： 见 §2「2026-10-01 重启后复验」。
- 🚫 **fan53870 禁止写 `0xff`**（全 LDO 使能触发 OCP 锁存 → I2C 彻底无 ACK）；**`0x0c`-`0x17` 区域禁止乱写**（会打死 sensor I2C）： 见 §2「2026-10-01 重启后复验」与「2026-10-05」。
- ⚠️ **sensor 实验必须用 C 快写**（i2ctransfer 子进程 150-300ms 会错过 RST 后 0.1-0.3s 的健康窗口）： 见 §2「2026-10-05 晚」的「健康窗口突破」节。
- ⚠️ **读 sensor 寄存器注意 8-bit 前缀**（`0x0112` 用 `0x01`、`0x0312` 用 `0x03`）： 见 §2「2026-10-05 晚」的「健康窗口突破」节。
- ⚠️ **GPIO 物理电平以 DIN（`0x10005210`）为准**，debugfs/gpio 软件状态不可信： 见 §2「2026-10-05 晚」的「健康窗口突破」节。
- 🚫 **任何抓帧都必须有界**：`v4l2-ctl --stream-count=0` 的意思是**无限流**（不是"零帧"）。一次把 `nc=0`
  原样传下去的失误，在 11 分钟里写了 **122 GB**（≈20 500 帧 × 6 MB YUYV）。`scripts/zz_mode.sh` 现在
  有 nc 守卫（0 = 不抓帧）： 见 §16。

---

## 5. 2026-10-06 会话：传感器侧已证完，卡点收敛到 D-PHY 时钟 lane

### 5.1 传感器侧（结论：完全正确，不要再查）
- **实测把 `fp_fast3.c` 的 236 条表与 vendor 头文件 `rubensimx582_Sensor.h` 的 `rubensimx582_preview_setting[]`（4000×3000）逐条对齐：完全一致**，含完整 MIPI/PLL 块 `0x0301=05 / 0x0303=02 / 0x0305=02 / 0x0306=00 / 0x0307=B4 / 0x030B=01 / 0x030D=18 / 0x030E=05 / 0x030F=5A / 0x0310=01`、MIPI 输出控制 `0x0401/0x0404-0x040F`、`0x034C-0x034F=0x0FA0/0x0BB8`（4000×3000）、`0x3F0C=01`、`0x4034/0x4035=0x01F0`。`fp_fast3` 另多写 `0x88D6/0x9852/0xAE09..AE16/0xB071/0x0138`。
- **`fp_fast3` 每次稳定成功**：`t0.00 ID OK 0582` → `t0.032 table done (236 writes)` → 回读 `0016=05 0017=82 0112=0a 0113=0a 0114=03 0100=01 0350=01 0307=b4`，`fc(0x0005)` 在走 ⇒ **传感器内部 30fps 出帧，MIPI TX 已按 vendor 表配置**。
- ⇒ **传感器寄存器表、健康窗口、供电、RST 全部无问题。剩余问题 100% 在 SoC 侧 D-PHY/SENINF。**

### 5.2 ★ D-PHY 实例映射（本轮实测修正）
- 6 个 D 实例：`0x11C82000 / 0x11C92000 / 0x11C86000 / 0x11C96000 / 0x11C8A000 / 0x11C8E000`。**`0x11C8E000` 全 0（无 FSM 寄存器，未实现）**，其余 5 个有 FSM（`+0x30` 时钟 lane、`+0x34` 数据 lane）。
- ANA 块：**活**的是 `0x11C80000 / 0x11C84000 / 0x11C85000 / 0x11C88000 / 0x11C89000`（复位态 `+00=00670011 +04=00420844 +08=44031010 +14=00000045 +18=10101010 +1c=10101010 +20=20000000 +f0=000000e2 +f4=00140254`）；**`0x11C8C000` 全 0（未实现）**。
- **`port2_v17.py` 用的口2 三元组 = ANA `0x11C88000`/`0x11C89000` + DPHY_TOP `0x11C8A000`**（与 SENINF_CONFIG.md 一致）；而 `fp_fast3.c` 读的是 `0x11C86000+0x30/0x34`。**两者不是同一实例，尚未统一。**

### 5.3 ★★ 关键发现：v17 的「顺序」首次让数据 lane 出现 `0x20`
- 顺序：`phyA_init(A+B 默认值) → dphy_init(settle 0x1c/prepare 2/trail 0x1a/trail_en @+0x10,0x14,0x20,0x24,0x28,0x2c) → seninf csi2/ctrl/top → phyA_setting(CKSEL bits8-10=7, CKMODE=0, L2_CKMODE_EN) → dphy_setting(LANE_SELECT=0x80413002, LANE_EN=0xF01, HS_RX_EN_SW=0xF01) → phyA_power_on(BG_CORE→BG_LPF→6×EQ_OS_CAL_EN @ANA+0x20 bits16-21) → 重新补写 LANE_EN`。
- **在该顺序下，`0x11C8A000+0x34` 从恒 `0x80808080` 变成稳定 `20011001`（byte0=0x20）**；`0x11C86000+0x34` 变成 `10101010`/`01010101` 交替。**`0x20` 正是历史 v21 记录的「MIPI 信号到达 SoC」值（CL_FSM 0x1→0x20）。**
- **反例：rx63（先把模拟上电做完再配数字）只得到 `10101010` 这类跳变，且 `DPHY+0x00` bit0 被清 0。⇒ 顺序有实质影响，应以 v17 顺序为准。**

### 5.4 ★★ 仍未解决：时钟 lane 恒 LP-11，PKT 恒 0
- `0x11C8A000+0x30`（时钟 lane FSM）**始终 `0x00000101`**，`CSI2_PACKET_CNT(0x1a014adc)=0`、`IRQ(0x1a014ac8)=0`，24×0.25s 与 40×0.25s 长采样均无变化。
- **sweep 结果**：① `+0x10/+0x14` settle 写 0x00–0x40 全部无效（回读恒 `+0x10=10100000`、`+0x14=10000000`，**bits18/19 拒写 ⇒ 该寄存器可写字段极窄，settle 的 bit16-23 字段假设可疑**）；② `LANE_SELECT` LC0_SEL=0..7：ck 恒 `0x00000101`（LC0_SEL=3 时唯一变成 `0x00000102`，dat 恒 `01010201`/`01010101`）；③ `+0x10/+0x14` 整字写 `0x30103402` 等 6 种 ⇒ 回读 `10100002`/`00100002`，**ck 仍 `0x101`**；④ `LANE_EN`(`+0x00`) 写 `0xF01/0x1F01/0x1001` ⇒ 回读仍 `0x00000f00`–`0x00000f01`，**bit0 粘不稳**。
- **⚠️ 异常观察（已定性为假信号，勿再追）**：
  - `port2_rx65.py` sweep 4 里 `ck=00002010`、`port2_rx67.py` 段 A 里 **bit1 及以上任意一位**都让 `ck=00002001`、`dat=01100120`： 一度被当成「时钟 lane 解锁」。
  - **但 `port2_rx67.py` 段 A 的对照证明它是伪信号**：只有**保持原值 `0xF01`（bit0）时 ck 不动**（`0x101`）；**只要把 `+0x00` 写成任何「与当前值不同」的数就翻成 `0x2001`，即使该位根本不粘**（bit2–bit15 回读全是 `0x00000f00`，一位没写进去，ck 照样变 `0x2001`）。⇒ **`0x2001/0x2010` 是「寄存器被改动」这个动作触发的锁存位，不是 MIPI 时钟检测结果。**
  - **`port2_rx68.py` 用同样思路（`LANE_EN=0xF02`）复现失败**：30×0.5s 内 ck 恒 `0x101`、dat 恒 `0x01010101`、`PKT=0`、`IRQ=0`。`+0x10` 在不同轮次回读 `0x10100000` 或 `0x00000000`（非确定，取决于 PHY 内部残留状态）。**同一脚本、同一顺序、同一环境，跨轮结果不稳定 ⇒ `0x11C8A000` 的 FSM 读值不能作为「时钟到达」的判据。**
  - **判决依据仍然是 `CSI2_PACKET_CNT(0x1a014adc)`：所有实验（rx61–rx68，累计 >100 秒采样）恒为 0，`CSI2_IRQ_STATUS(0x1a014ac8)` 恒 0。⇒ MIPI 数据包从未被 SoC 接收。**
- **`DPHY_RX_LANE_EN` 语义可疑**：按注释 LD0-3_EN=bits8-11、LC0_EN=bit0，但 `0xF01` 回读成 `0x00000f00`（bit0 丢），而 `0x0000F00F` 回读 `0x00000003`、`0xFFFF` 回读 `0x00000f03`。**⇒ 真实字段划分与注释不符，应以「能让 ck 变 0x20」的写入组合为准。**

### 5.5 本轮新增脚本（设备端，均已跑）
- `${K50_REPO}\port2_rx61.py`（2 实例 + SENINF 数字）、`port2_rx62.py`（全 6 实例 + 6 ANA）、`port2_rx63.py`（模拟满载上电 + 全 6 实例）、**`port2_rx64.py`（v17 原序 + v17 口2 三元组 → 首次得 `20011001`）**、`port2_rx65.py`（时钟 lane 逃逸 sweep 1-4）、`port2_rx66.py`（LANE_EN 解锁 + 40 次 PKT 观察）。
- 驱动壳：`zz_v61.sh`～`zz_v66.sh`（均为 `cam_go_v6.sh` → `fp_fast3` → python 的三段式）。
- 结论脚本：**`port2_rx64.py` 是当前最佳基线**（v17 顺序 + v17 三元组）。

### 5.6 下一步（按优先级，给下一个会话）
1. **换判据：只用 `CSI2_PACKET_CNT(0x1a014adc)` 与 `CSI2_IRQ_STATUS(0x1a014ac8)` 判断成功**，不要再用 DPHY FSM 读值（已被 5.4 证伪为不可靠）。
2. **统一 DPHY 实例映射**：确认口2 到底是 `0x11C8A000`（v17/SENINF_CONFIG）还是 `0x11C86000`（fp_fast3 读的那个）；目前两者都能写出非零 FSM，但都无法产生 PKT。
3. **❌ 已排除：MIPI 引脚/焊盘 pinmux（不要再查）**。vendor `seninf_top@1a010000` 节点**没有任何 `pinctrl-0`/`pinctrl-names`**（`hyperos_fdt.dts:13084-13098`）⇒ MT6895 的 CSI lane 是**专用模拟焊盘**，不经过 pinmux。`pinctrl-mtk-mt6895.h` 里的 `MIPI0_D_SCLK/SDATA`、`MIPI1..4`、`MIPI_M`、`CONN_MIPI*` 是**另一组**（连接/天线侧），与本相机口无关。
4. **vendor 节点确认的地址与拓扑（可信，直接用）**：`reg = <0x1a010000 0x20000>, <0x11c80000 0x20000>`，`reg-names = "base","ana-rx"` ⇒ **D-PHY 模拟区 = `0x11C80000`，size `0x20000`（0x11C80000–0x11C9FFFF），与实测一致**；`seninf_num=0x0a(10)`、`mux_num=0x11(17)`、`cam_mux_num=0x17(23)`、`pref_mux_num=0x0d(13)`；`clocks/clock-names` 共 7 条 = `clk_cam_seninf`(=cam_main syscon `0x10` bit8) + `clk_top_seninf/seninf1/seninf2/seninf3/seninf4` + `clk_top_camtm`；**`power-domains = <isp_main(0x08), cam_main(0x0c)>`（双域！）**；`dvfsrc-vmm-supply = <0xe2>`；`interrupts = <0 0x1bc 4 0>`。
5. **顺带确认（非根因）**：`0x1a010010` 的 `TOP_MUX_CTRL_0..5`（24 字节 / 6 个 32 位寄存器，覆盖 mux 0–23）**复位态是恒等映射**（byte n = n），与 vendor dmesg 的 `TOP_MUX_CTRL_0(0x03020400)…5(0x00001514)` 除已路由位外逐字节一致 ⇒ 该阵列正常，且 **PKT 在 CSI2 接收端统计（早于 mux），路由不可能是 PKT=0 的原因**。
6. **零风险对照**：HyperOS 的 `/dev/mem` 不可用，但可用 vendor `.ko` 反汇编（`isp_ko.asm` / `Redmi_K50_驱动提取包\03_内核模块\all_modules\`）直接读 `mtk_csi_phy_3_0` 的 `dphy_setting()`、LC0/LC1 位定义，以及 `mtk_cam_seninf_set_idle`/`set_camtg` 的真实寄存器序列。
7. **不要再碰的**：`0x11C8C000`/`0x11C8E000`（未实现）；不要盲写 PDA/CG（`zz_wtest.sh` 式）；`0x88D6` 等未知寄存器；不要重打包 dtbo/boot。

### 5.7 设备状态
- 本轮全部实验 03:49–04:00（设备时钟）；一次性 cron 任务 `cron_i79nhgw` 于 **2026-10-06 04:30 CST** 关机（用户 m00641「我只要今天关机」）。
- 设备侧堆栈：`cam_rails cam_clk cam_clk2 cam_clk3 cam_genpd cam_ovl m6315 ccci_md2 mod_ovl5`；`/root/` 下有 `fp_fast3`、`port2_rx6*.py`、`cam_go_v6.sh`、`gpiotoolG`。

---

## 6. 2026-10-06 04:0x 会话：找到 vendor seninf 驱动**完整源码**，并更正地址表

### 6.1 ★ vendor 源码位置（重大发现，比任何逆向/推断都权威）
`${K50_REPO}\isp71_ref\` 下：
- `mtk_cam-seninf-drv.c`（53279 B，主驱动：probe / stream-on / power / clk 顺序）
- `mtk_cam-seninf-hw.h`（4792 B）、`mtk_cam-seninf-def.h`（5188 B）、`mtk_cam-seninf-regs.h`（774 B，`SENINF_BITS/READ_BITS/WRITE_REG` 宏）
- `mtk_cam-seninf-route.c`（27611 B）、`mtk_cam-seninf-ca.c`、`mtk_cam-seninf-if.h`、`mtk_cam-seninf-hw.h`
- **`mtk_csi_phy_3_0\mtk_cam-seninf-hw_phy_3_0.c`（119737 B / 3933 行）= 全部 PHY + SENINF 寄存器序列**
- `mtk_csi_phy_3_0\mtk_cam-seninf-csi0-dphy.h`（41531 B）、`mtk_cam-seninf-mipi-rx-ana-cdphy-csi0a.h`（31906 B）、`mtk_cam-seninf-seninf1-csi2.h`（33202 B）、`mtk_cam-seninf-top-ctrl.h`（24376 B）、`mtk_cam-seninf-seninf1-mux.h`、`mtk_cam-seninf-cammux-pcsr.h`/`-gcsr.h`、`mtk_cam-seninf-tg1.h`
- `mtk_csi_phy_2_0\` 是同名文件的 2_0 版本（可对比）
- 另有 `mtk-cam-isp.ko`(2597024 B)、`mtk-cam-plat-mt6895.ko`(13880 B)、`hyperos_fdt.dtb`(408613 B)

### 6.2 ★★ 地址表权威更正： `port2_v17.py` 及其派生脚本用错了 D-PHY 实例
权威来源：`mtk_csi_phy_3_0\mtk_cam-seninf-hw_phy_3_0.c:73-171  mtk_cam_seninf_init_iomem()`，`ana_base = 0x11C80000`：

| port | ANA csi_rx A | ANA csi_rx B | **DPHY_TOP** | CPHY_TOP |
|---|---|---|---|---|
| 0 | +0x0000 | +0x1000 | **+0x2000** | +0x3000 |
| **2** | **+0x4000** | **+0x5000** | **+0x6000** | +0x7000 |
| 4 | +0x8000 | +0x9000 | **+0xa000** | +0xb000 |
| 5 | +0xc000 | +0xd000 | +0xe000 | +0xf000 |
| 1 | +0x10000 | +0x11000 | +0x12000 | +0x13000 |
| 3 | +0x14000 | +0x15000 | +0x16000 | +0x17000 |

⇒ **口2 正确三元组 = ANA A `0x11C84000` / ANA B `0x11C85000` / DPHY_TOP `0x11C86000`（CPHY_TOP `0x11C87000`）。**
⇒ **`port2_v17.py` 用的 `ANA_A=0x11C88000, ANA_B=0x11C89000, DPHY_TOP=0x11C8A000` 其实是 port 4**；`port2_rx61..68.py` 全部继承此错误（rx64「首次得到 0x20011001」也是打在 port4 的 PHY 上）。
⇒ 之前记的「`0x11C8E000` 未实现」= **错**，它是 port5 的 DPHY_TOP；「`0x11C8C000` 未实现」= **错**，它是 port5 的 ANA A。六个 DPHY_TOP 实例 `0x11C82000/0x11C92000/0x11C86000/0x11C96000/0x11C8A000/0x11C8E000` = port 0/1/2/3/4/5，全部真实存在。
⇒ **`SENINF_CONFIG.md` 的结论（“3_0 基址表属另一颗芯片、本机 port2 用 2_0 风格 0x11C88000/9000/a000”）已被源码推翻。** 反而 `cam_v6b.sh` 里被标为「口1」的 `DPHY_TOP_1=0x11C86000, ANA1B=0x11C85000` 才是指向 **port2** 的正确值。
⇒ **但地址更正**不解决卡点**：本轮新增 `port2_rx70.py`（= rx64 全部序列，只把三元组换成正确的 `0x11C84000/0x11C85000/0x11C86000`，对照仍采 port4 的 `0x11C8A000`），由 `zz_push70.sh` 推到设备跑完 → **仍然 ck=`0x00000101`、dat=`0x01010101`、PKT=`0`、IRQ=`0`（24×0.25 s 全程）**。⇒ 用错实例是真实缺陷，但不是根因。

### 6.3 `init_iomem()` 里的其余权威映射
```c
reg_if_top                              = if_base;
reg_if_ctrl[i]      = if_base + 0x0200 + 0x1000*i;   // i = seninfIdx
reg_if_tg[i]        = if_base + 0x0f00 + 0x1000*i;
reg_if_csi2[i]      = if_base + 0x0a00 + 0x1000*i;
reg_if_mux[j]       = if_base + 0x0d00 + 0x1000*j;   // j = mux 号
reg_if_cam_mux_pcsr[k] = if_base + 0x0400 + 0x0020*k;
reg_if_cam_mux_gcsr    = if_base + 0x0300;
```
- `seninfIdx`（`init_port()`，line 173-238）：`CSI_PORT_2`/`CSI_PORT_2A` → **`SENINF_5`**（数值 = 4）⇒ 口2 的 ctrl=`0x1A014200`、csi2=`0x1A014A00`、tg=`0x1A014F00` ✔ 与既有结论一致。`CSI_PORT_2B`→`SENINF_6`(5)。
- `ctx->is_4d1c = (port == portNum)`，`portNum = (port>=CSI_PORT_0A) ? (port-CSI_PORT_0)>>1 : port` ⇒ `CSI_PORT_2` 走 `else` 分支 ⇒ **is_4d1c = TRUE** ✔。
- `portA = CSI_PORT_0A + (portNum<<1)`，`portB = portA+1`。

### 6.4 D-PHY / ANA 寄存器字偏移（vendor 头文件，可直接照抄）
`mtk_cam-seninf-csi0-dphy.h`（`DPHY_RX_*`，字偏移）：
`LANE_EN=0x0000`、`LANE_SELECT=0x0004`、`HS_RX_EN_SW=0x0008`、`CLOCK_LANE0_HS_PARAMETER=0x0010`、`CLOCK_LANE1_HS_PARAMETER=0x0014`、`DATA_LANE0_HS_PARAMETER=0x0020`、`DATA_LANE1=0x0024`、`DATA_LANE2=0x0028`、`DATA_LANE3=0x002c`、`CLOCK_LANE_FSM=0x0030`、`DATA_LANE_FSM=0x0034`、`DATA_LANE_SYNC_DETECT_NORMAL=0x0040`、`_DESKEW=0x0044`、`_ALTCAL=0x0048`、`_PRESEQ=0x004c`、`DESKEW_CTRL=0x0050`、`DESKEW_TIMING_CTRL=0x0054`、`DESKEW_LANE_SWAP=0x0058`、`DESKEW_LANE0..3_CTRL=0x0060/0x0064/0x0068/0x006c`、`DESKEW_IRQ_EN=0x0080`、`DESKEW_IRQ_STATUS=0x0084`、`IRQ_EN=0x0088`、`IRQ_STATUS=0x008c`、`STATUS_0=0x00a0`、`STATUS_1=0x00a4`、`DESKEW_DBG_MUX=0x00e0`、`DESKEW_OUT=0x00e4`、**`SPARE0=0x00f0`**、**`SPARE1=0x00f4`**、`BIST_ENABLE=0x0100`、`BIST_STATUS=0x0104`、`BIST_CONFIG_0/1/2_LANE0=0x0110/0x0114/0x0118`、`LANE1=0x0120/0x0124/0x0128`。
`mtk_cam-seninf-mipi-rx-ana-cdphy-csi0a.h`（`CDPHY_RX_ANA_*`）：`ANA_0..ANA_12 = 0x0000,0x0004,...,0x0030`（步进 4）、`FORCE_MODE_0..8` 与 `FORCE_MODE_EN_*`、`AD_0=0x0048`、`AD_1=0x0058`、`AD_HS_0/1/2=0x00a0/0x00a4/0x00a8`、**`ANA_SETTING_0=0x00f0`**、**`ANA_SETTING_1=0x00f4`**、`ANA_DBG_OUT=0x00f8`。
⇒ 与既有结论对照：D5 `SPARE0(+0xf0)=0xf1` ✔、D6 `ANA_SETTING_1(+0xf4)=0x00140254` ✔、D4 时钟 lane settle 落在 `+0x10/+0x14` ✔、settle 则落在 `+0x20..+0x2c` ✔。

### 6.5 `csirx_dphy_init()` 逐条（hw_phy_3_0.c:1336-1527）
1. `settle_delay_dt = settle_delay_ck = DPHY_SETTLE`，源码注释 **`// 0x1c = 100ns/(1/csi_ck)`**（与 v17 的 `0x1c` 一致）；若 DTS 给了 `dphy_data_settle/dphy_clk_settle` 则按 `SENINF_CK * val / 1e9` 向上取整换算。
2. `SENINF_BITS(base, DPHY_RX_DATA_LANE0..3_HS_PARAMETER(0x20/0x24/0x28/0x2c), RG_CDPHY_RX_LD0..3_TRIOx_HS_SETTLE_PARAMETER, settle_delay_dt)`。
3. `SENINF_BITS(base, DPHY_RX_CLOCK_LANE0/1_HS_PARAMETER(0x10/0x14), RG_DPHY_RX_LC0/LC1_HS_SETTLE_PARAMETER, settle_delay_ck)` ← **这就是 notes 的 D4，之前「从未写过」。**
4. **PREPARE：`#if __SMT` 时 = 2，`#else` 时 = 0**（写 `RG_CDPHY_RX_LD0..3_TRIOx_HS_PREPARE_PARAMETER`）。cam_v6b/rx6x 一律写 2： **需确认本平台 `__SMT` 的取值**。
5. HS_TRAIL：`ui_224 = (DPHY_TRAIL_SPEC*1000)/(data_rate/1e6)`；若 `csi_param.dphy_trail==0 || dphy_trail > ui_224` → **`hs_trail = 0`**；否则 `hs_trail = ceil((ui_224 - dphy_trail) * SENINF_CK / 1e9)`。写 `RG_DPHY_RX_LD0..3_HS_TRAIL_PARAMETER`。
6. `hs_trail_en = (data_rate < SENINF_HS_TRAIL_EN_CONDITION) || (dphy_trail!=0 && hs_trail!=0)`；**仅非 CPHY 时写 `RG_DPHY_RX_LD0..3_HS_TRAIL_EN`，CPHY 时强制 0**。`data_rate = mipi_pixel_rate * bit_per_pixel / num_data_lanes`。

### 6.6 `csirx_phyA_power_on()` 逐条（hw_phy_3_0.c:1036-1080）
`base = ctx->reg_ana_csi_rx[portIdx]`（**按 portIdx 取，A/B 两块要分别调用**）：
1. `CDPHY_RX_ANA_8(0x20)` 清 6 个 `EQ_OS_CAL_EN`：`L0_T0AB`/`L1_T1AB`/`L2_T1BC`/`XX_T0BC`/`XX_T0CA`/`XX_T1CA`；
2. `CDPHY_RX_ANA_0(0x00)`：`BG_LPF_EN=0`、`BG_CORE_EN=0`；`udelay(200)`；
3. 若 `en`：`BG_CORE_EN=1` → `udelay(30)` → `BG_LPF_EN=1` → `udelay(1)` → 6×`EQ_OS_CAL_EN=1` → `udelay(1)`。
（与 `SENINF_CONFIG.md` 的 9 步第 1 步一致，现已由源码逐字确认。）

### 6.7 已核对：SENINF **数字侧**我们做得与源码一致（不是卡点）
`csirx_seninf_csi2_setting()`（1551-1685）逐条 = `SENINF_CSI2_DBG_CTRL` 的 `RG_CSI2_DBG_PACKET_CNT_EN=1`；`SENINF_CSI2_RESYNC_MERGE_CTRL` 先 `RG_CSI2_RESYNC_CYCLE_CNT_OPT=1`；`csi_en = (1<<num_data_lanes)-1`；DPHY 分支：`RG_CSI2_CPHY_SEL=0`、**`SENINF_WRITE_REG(SENINF_CSI2_EN, csi_en)`（整字写）**、`RG_CSI2_HEADER_MODE=0`、`RG_CSI2_HEADER_LEN=0`、**整字写 `0x2020f106`**，然后 `#if __SMT == 0` 才补 `RG_CSI2_RESYNC_DMY_CYCLE=cycles`（`cycles = ceil(64*SENINF_CK/data_rate)+CYCLE_MARGIN`，源码注释日志 `cycles 13`）、`RG_CSI2_RESYNC_DMY_CNT=3`（`legacy_phy` 时 =4）、`RG_CSI2_RESYNC_DMY_EN=0xf`（4 lane；2 lane = 0x3）。**⇒ v17/rx6x 写的 `0x2020f106` + bit8 + CSI2_EN=0xF 与源码一致。**
`csirx_seninf_setting()`（1687-1698）：`SENINF_BITS(pSeninf, SENINF_CSI2_CTRL, RG_SENINF_CSI2_EN, 1)` 然后 `SENINF_BITS(pSeninf, SENINF_CTRL, SENINF_EN, 1)`： `pSeninf = reg_if_ctrl[seninfIdx]`，口2 = `0x1A014200`，`SENINF_CSI2_CTRL` = 该页 `+0x10` = `0x1A014210` ✔（= 我们写的 CTRL+0x10 bit0 与 CTRL+0 bit0）。
⇒ **数字侧无遗漏；缺口在 PHY 模拟/lane 侧（`csirx_phyA_setting` / `csirx_dphy_setting` / `csirx_seninf_top_setting` 尚未逐条比对）。**

### 6.8 下一步（给下一个会话，按优先级）
1. **按源码逐函数复刻**（先用**正确的 port2 三元组**）：`csirx_phyA_power_on` → `csirx_dphy_init` → `csirx_seninf_csi2_setting`(1551) → `csirx_seninf_top_setting`(1700) → `csirx_phyA_setting`(1870 与 2126 两份，看清 `#if` 用哪份) → `csirx_dphy_setting`(2636)；然后 `mtk_cam_seninf_set_idle`(2810)/`set_camtg`。
2. **查清这几个宏的实际取值**：`__SMT`（决定 PREPARE=0 还是 2）、`DPHY_TRAIL_SPEC`、`SENINF_HS_TRAIL_EN_CONDITION`、`DPHY_SETTLE`、`SENINF_CK`、`DPHY_SETTLE` 的 `FIX_DPHY_SETTLE` 开关。
3. 判据**只用** `CSI2_PACKET_CNT(0x1a014adc)` 与 `CSI2_IRQ_STATUS(0x1a014ac8)`。
4. `mtk_cam-seninf-drv.c` 里看 probe/stream-on 的完整顺序（power domain ×2、7 条 clock、`set_idle`、`set_camtg`、`mtk_cam_seninf_set_csi_mipi`）。
5. 若仍不动：考虑 **`isp_main(0x08)` 域**（vendor `seninf_top.power-domains = <isp_main, cam_main>` 双域，而我们的 `ovl_pwr.dts` 只挂了 cam_main）。

---

## 7. ★★★ 2026-10-06 重大突破：主摄**供电根因** + IMX582 真正出流（MIPI 收包成功）

### 7.0 一句话结论
**主摄长期"死"的唯一根因是 FAN53870 的 LDO7（DOVDD）与 LDO6（AFVDD）从未使能**： 主摄模块
（IMX582 + DW9800V AF + EEPROM）整体没有 I/O 电，所以 bus 10 上三个器件全部 ENXIO。
补上供电后 **IMX582 立刻可读写、可 stream on，CSI2 每帧收到 0x118C = 4492 个包，ECC/CRC 全对**。
之前所有"地址错 / 时钟没开 / MTCMOS 没上电"的猜测都不是根因（地址修正仍是必要的，但不是卡点）。

### 7.1 根因证据链
| 证据 | 事实 |
|---|---|
| `hyperos_workstate/regulator_summary.txt` | `fan53870-l7 use=1 1804mV → 8-0010-dovdd`；`fan53870-l6 use=1 2900mV → 8-0010-afvdd`；`vcam_ldo use=1 1200mV → 8-0010-avdd1` |
| `hyperos_fdt.dts:6367-6435` `i2c@11d05000` | 主摄总线只挂 3 个器件：`sensor0@10`(rubensimx582) / `camera_af_main@0c`(dw9800v) / `camera_eeprom0@51`；`clock-frequency = 0xf4240` = **1 MHz** |
| `hyperos_fdt.dts:6437-6544` `i2c@11d06000` | `onsemi,ldo@35` = **FAN53870**（`fan53870-l1..l7`，phandle l6=0x31a=afvdd、l7=0x2f3=dovdd）+ `sc8551_i2c9@66`/0x61a80=400kHz |
| `hyperos_fdt.dts:10859-10868` | `vcam_ldo` = regulator-fixed 1.2V，`gpio = <0x4e 0x9e 0> `= **GPIO158**，phandle 0x2f2 = `avdd1-supply` |
| 实机 `i2cdetect -y -r 10`（修前） | **全空**，0x10/0x0c/0x51 三个都 ENXIO |
| 实机 FAN53870 dump（修前） | **`0x03 ENABLE = 0x00`**（7 路 LDO 全关）、`0x04..0x0A` 全 0、`0x12=0x01`(=0x35 地址确认)、`0x10=0x7f`、`0x11=0x06`、`0x13=0x05` |

### 7.2 FAN53870 数据手册要点（`fan53870-text.txt`，**非 UTF-8，必须 `grep -a`**）
- 从地址：FAN53870 = `7'h35`；`0x12 I2C_ADDR` bits1:0: 00=0x20 / 01=0x35 / 10=0x61 / 11=0x72。
- **电压公式**：**LDO1/LDO2 = `0.800V + (d−99)×8mV`，有效 d = 0x63..0x7F**；
  **LDO3..LDO7 = `1.500V + (d−16)×8mV`，d = 0x10..0xFF**。（校验：0x7F→2.388V、0x36→1.804V、0xBF→2.900V）
- 寄存器：`0x00`PID / `0x01`REV / `0x02`IOUT / **`0x03 ENABLE`**（bit6=LDO7_EN，bit5=LDO6_EN，…bit0=LDO1_EN）/
  `0x04..0x0A`=LDO1..LDO7_VOUT / `0x0B..0x0E`=LDOx_SEQ / `0x0F`SEQUENCING /
  `0x10`DISCHARGE（默认 0x3F）/ **`0x11 RESET`**（bits7:4 写 0b1011 软复位；bit0 FLT_SD_B）/
  `0x12`I2C_ADDR / `0x13/0x14`COMP / `0x15..0x17`INTERRUPT1..3 / `0x18..0x1B`STATUS1..4（bit6 = CHIP_SUSD）/ `0x1C..0x1E`MINT。
- 保护：OCP>1ms 永久关断；UVP 4 次永久关断；**整芯片 4 次故障→全部锁存，需拉低 RESET_B 清除；
  RESET_B 拉低时 I²C 通信被禁用。**

### 7.3 修复（写值，来自 HyperOS 运行时真值）
```sh
BUS=11; ADDR=0x35          # FAN53870 在 i2c-11 (11d06000)
i2ctransfer -f -y 11 w2@0x35 0x09 0xbf   # LDO6_VOUT = 0xBF → 2.900V  (afvdd)
i2ctransfer -f -y 11 w2@0x35 0x0a 0x36   # LDO7_VOUT = 0x36 → 1.804V  (dovdd)
i2ctransfer -f -y 11 w2@0x35 0x03 0x60   # ENABLE = bit6(LDO7)|bit5(LDO6)
```
**修前 `cam_go_v6.sh` 的三处错误**：`0x0a 0x18` 实际 = 1.564V（注释写 1.804V 是算错）、
`0x09 0x2c` = 2.724V、`0x03 0x7f` 会打开全部 7 路（其它 LDO 属副摄）。**均已纠正。**
修复后：`0x03=0x60 0x09=0xbf 0x0a=0x36`，`0x16/0x18/0x19/0x1a/0x1b` 全 0（无故障），
**`i2cdetect -y -r 10` 出现 `0c / 10 / 51`，`ID16=0x05 ID17=0x82` = IMX582 ALIVE。**

### 7.4 IMX582 初始化 + stream on（`imx582_bring.py`）
- 表取自 `rubensimx582_Sensor.h`：`rubensimx582_init_setting[]`（**112 对**，24-137 行）、
  `rubensimx582_preview_setting[]`（**111 对**，144-256 行）。
- 顺序：`0x0100=0x00`（stream off）→ 112 对 init → 111 对 preview → **`0x0100=0x01`（stream on）**。
- 用 ctypes + `I2C_RDWR(0x0707)` ioctl 直接读写 `/dev/i2c-10`（16 位寄存器地址 + 8 位数据）；
  112 写耗时 15.7 ms、111 写 19.9 ms。
- 回读验证：`0x0100=0x01 0x0112=0x0a 0x0113=0x0a 0x0114=0x03 0x0115=0x30 0x0307=0xb4
  0x030d=0x18 0x030e=0x05 0x030f=0x5a 0x0310=0x01 0x0340=0x0e 0x0341=0x4a 0x0342=0x1e 0x0343=0xc0`。
- **修前 `cam_go_v6.sh` 的最大缺陷：从不写 `0x0100=0x01`** ⇒ 即使有电也永远不出流。

### 7.5 ★ 出流结果（设备 16:17:32）
```
PKT(0x1a014adc) 采样 20 次：0A92 06C5 0515 0237 00E0 118C 118C 1154 0E03 0B33
                           07A7 0497 01EB 118C 0FC2 0C65 09EC 0830 0438 02FF
IRQ(0x1a014ac8) = 0x00000325（粘滞未清）
ckFSM(0x11c86030) = 0x00000110 / 0x00000101（随数据变化）
datFSM(0x11c86034) = 0x10101010 / 0x01010101 / 0x40404040（随数据变化）
```
- `PACKET_CNT` 是 `SENINF_CSI2_PACKET_CNT_STATUS(0x00dc)` 的 **bits15:0**，每帧重载到 **0x118C = 4492** 后递减；
  4492 包/帧 ≈ 4000×3000×10bit 全帧（≈3345 字节/包）⇒ **完整帧数据已进入接收器**。
- **IRQ 解码（`mtk_cam-seninf-seninf1-csi2.h:385-443`）**：`0x325` = bit0 `ERR_FRAME_SYNC`（粘滞，从未清）、
  **bit2 `ECC_NO_ERR`（头 ECC 正确）**、**bit5 `CRC_CORRECT`（载荷 CRC 正确）**、
  **bit8 `FS_RECEIVE`（帧起始收到）**、**bit9 `FE_RECEIVE`（帧结束收到）**。
  ⇒ **ECC/CRC 全对说明 D-PHY 模拟侧也是正确的**；bit0 只是首次配置瞬间的粘滞残位。
- 判活判据（以后只用这两个）：`0x1a014adc`（PKT）与 `0x1a014ac8`（IRQ）。

### 7.6 CAMSV（下一步的落点）
- **`SENINF` 之后的数据通路是 `SENINF mux → CAM_MUX → CAMSV`**，CAMSV 自己有 TG + IMGO DMA。
- **完整寄存器表 = `isp71_ref/mtk_cam-sv-regs.h`**（631 行），关键偏移（相对 CAMSV 实例基址）：
  `MODULE_EN=0x0040`（TG_EN bit0 / PAK_EN bit2 / IMGO_EN bit4）、`FMT_SEL=0x0044`（TG1_FMT bits2:0 / TG1_SW bits6:5 / LP_MODE bit8）、
  `INT_EN=0x0048`、`INT_STATUS=0x004C`、`SW_CTL=0x0050`、`CLK_EN=0x0060`（TG_DP_CK_EN bit0 / IMGO_DP_CK_EN bit15）、
  `TG_SEN_MODE=0x0100`（CMOS_EN bit0）、`TG_VF_CON=0x0104`（VFDATA_EN bit0）、
  `TG_SEN_GRAB_PXL=0x0108`、`TG_SEN_GRAB_LIN=0x010C`、`TG_PATH_CFG=0x0110`（SEN_IN_LSB bits2:0 / TG_FULL_SEL bit15）、
  `TG_FRMSIZE_ST=0x0138`、`TG_INTER_ST=0x013C`、`PAK_CON=0x01C0`、
  **DMA：`IMGO_BASE_ADDR=0x0700`、`IMGO_BASE_ADDR_MSB=0x0704`、`IMGO_OFST_ADDR=0x0708`、`IMGO_XSIZE=0x0710`、`IMGO_YSIZE=0x0714`、`IMGO_STRIDE=0x0718`、`IMGO_BASIC=0x071C`（BUS_SIZE bits3:0 / FORMAT bits9:4 / BUS_SIZE_EN bit28 / FORMAT_EN bit29）、`IMGO_CON0..4=0x0720..0x0730`、`IMGO_CROP=0x074C`、`DMA_SPECIAL_EN=0x0738`。**
- 实例基址（vendor DTS）：**`camsv1@1a110000` … `camsv16@1a187000`，步进 0x1000**。
- **★ 反汇编路线可行**：`${K50_REPO}\isp_ko.asm`（`mtk-cam-isp.ko` 的反汇编，**符号完整**）含全套 CAMSV 硬件函数：
  `mtk_cam_sv_top_config`(0x4699c)、`mtk_cam_sv_format_sel`(0x45254)、`mtk_cam_sv_pak_sel`(0x453e0)、
  `mtk_cam_sv_xsize_cal`(0x45570)、`mtk_cam_sv_tg_config`(0x4578c)、`mtk_cam_sv_dmao_config`(0x47ab4)、
  `mtk_cam_sv_fbc_config`(0x47f60)、`mtk_cam_sv_tg_enable`(0x47fbc)/`_disable`(0x48e44)、
  `mtk_cam_sv_top_enable`(0x485ec)/`_disable`(0x48f0c)、`mtk_cam_sv_dmao_enable`(0x48ac4)/`_disable`(0x493bc)、
  `mtk_cam_sv_vf_on`(0x494e0)、`mtk_cam_sv_enquehwbuf`(0x49790)、`mtk_cam_sv_dev_config`(0x4acc4)、
  **`mtk_cam_sv_dev_stream_on`(0x4b3e0)**、`mtk_cam_sv_pipeline_config`(0x450fc)、
  `camsv_irq_handle_err`(0x4c800)、`mtk_irq_camsv`(0x4d748)。
  ⇒ **从这些函数里可逐字恢复 (寄存器偏移, 写入值) 序列**（见 §8）。
- SENINF 侧 CAM_MUX 映射（`mtk_cam-seninf-hw_phy_3_0.c`）：`reg_if_cam_mux_pcsr[k] = if+0x0400+0x0020*k`、
  `reg_if_cam_mux_gcsr = if+0x0300`；传统 imgsensor 路径（`isp71_ref/isp6s_seninf/seninf_impl.c`）里
  `SENINF_CAM_MUX_CTRL_0..3 = 0x0400/0x0404/0x0408/0x040c`，**每字节一个 cam_mux，值 = seninf mux 号**。

### 7.7 本轮新增/更新的文件
- **PC 侧**：`imx582_bring.py`（IMX582 init+preview+stream）、`zz_v75.sh`/`zz_push75.sh`（FAN53870 修复）、
  `zz_v76.sh`（sensor/SENINF 状态 dump）、`zz_v77.sh`/`zz_push77.sh`（完整出流流程）、`zz_push.sh`（通用推送执行器）。
- **设备侧**：`/root/imx582_bring.py`、`/root/zz_v75.sh`、`/root/zz_v77.sh`。
- 复制进工作区：`isp71_ref/isp6s_seninf/`（vendor 传统 seninf 源码）。
- **`cam_go_v6.sh` 仍是过期版本**（fan53870 三个值错、缺 `0x0100=0x01`）；新流程见 `zz_v77.sh`。

---

## 8. CAMSV 完整寄存器序列（从 `isp_ko.asm` 反汇编逐字恢复）

### 8.0 方法学与可信度
- `isp_ko.asm` 里 **`dev->base = [x0, #0x18]`**（ioremap 后的 CAMSV 寄存器基址）。每个寄存器访问都是 32 位 RMW：
  `ldr x8,[x0,#0x18]` → `add x2,x8,#IMM` → `ldr w8,[x2]` → `orr/and w8,w8,#MASK` → `str w8,[x9]`（x9 = base+IMM）。
  少数是直接 `str wN, [base, #IMM]`（无条件整字写）。
- **`bl` 目标全被清零**（反汇编时没有应用重定位，`bl` 反汇编成"调用自身"）⇒ 从这个 `.asm` **无法**解析被调用者。
  下文的**调用顺序**是按各函数体特征与偏移匹配推得的（顺序高置信；单个 `bl`→符号映射为推断）。
  > ★ **2026-10-06 更正（见 §11.2）**：这里原本写"`.ko` 剥离重定位后的产物"：**这是错的**。
  > `.ko` 是**可重定位目标文件**，`bl` 到外部符号的位移本来就写 0，真实目标放在 `.rela.*` 段里；
  > `isp71_ref/mtk-cam-isp.ko` 有 **12 个 `.rela` 段、718 个函数**，代码是完整的。
  > **如果要做更细的分析，正确做法是先把 `.rela.text*` 重定位应用到 `.text`（或用 `readelf -r` 对照）再反汇编**，
  > 这样所有 `bl`/`adrp+add` 的符号目标都能恢复出来。
- 每个函数最后一条 `ret` 之后的大段 `bti j` / `ldar` 是跳转表/CFA 桩，**不是函数体**。
- 完整报告：`${K50_REPO}\camsv_report.md`（≈330 行，8 个配置函数）、
  `${K50_REPO}\camsv_register_sequence_report.md`（13 个使能/关闭函数）。

### 8.1 偏移全表（`isp71_ref/mtk_cam-sv-regs.h` 复核）
`0x014 TOP_FBC_CNT_SET`(RCNT_INC1 b0)、`0x040 MODULE_EN`(TG_EN b0 / PAK_EN b2 / PAK_SEL b3 / IMGO_EN b4 /
UFE_EN b6 / QBN_EN b7 / DOWN_SAMPLE_PERIOD b23:16 / DOWN_SAMPLE_EN b24 / DB_LOAD_HOLD b25 / DB_LOAD_FORCE b26 /
DB_LOAD_SRC b29:28 / DB_EN b30 / DB_LOCK b31)、`0x044 FMT_SEL`(TG1_FMT b2:0 / TG1_SW b6:5 / LP_MODE b8 / HLR_MODE b9)、
`0x048 INT_EN`、`0x04C INT_STATUS`、`0x050 SW_CTL`、`0x060 CLK_EN`(TG_DP_CK_EN b0 / QBN_DP_CK_EN b1 /
PAK_DP_CK_EN b2 / UFEO_DP_CK_EN b4 / IMGO_DP_CK_EN b15)、`0x074 DCIF_SET`(MASK_DB_LOAD b7 /
ENABLE_OUTPUT_CQ_START_SIGNAL b8 / FOR_DCIF_SUBSAMPLE_EN b15)、`0x078 SUB_CTRL`(CENTRAL_SUB_EN b0)、
`0x07C PAK`(PAK_MODE b7:0 / PAK_DBL_MODE b9:8)、`0x088 MISC`(VF_SRC b0)、
**`0x100 TG_SEN_MODE`**(CMOS_EN b0 / SOT_MODE b2 / SOT_CLR_MODE b3 / DBL_DATA_BUS b5:4 / TIME_STP_EN b16 /
SOF_SUB_EN b17 / VS_SUB_EN b18 / STAGGER_EN b23 / HDR_EN b24)、
**`0x104 TG_VF_CON`**(**VFDATA_EN b0** / SINGLE_MODE b1 / FR_CON b6:4 / SP_DELAY b10:8 / SPDELAY_MODE b12)、
`0x108 TG_SEN_GRAB_PXL`(PXL_END b31:16 / PXL_START b15:0)、`0x10C TG_SEN_GRAB_LIN`(LIN_END b31:16 / LIN_START b15:0)、
**`0x110 TG_PATH_CFG`**(SEN_IN_LSB b2:0 / DB_LOAD_DIS b8 / DB_LOAD_SRC b9 / DB_LOAD_VSPOL b10 / DB_LOAD_HOLD b11 /
SUB_SOF_SRC_SEL b21:20)、`0x164 TG_SUB_PERIOD`(VS_PERIOD b7:0 / SOF_PERIOD b15:8)、`0x1C0 PAK_CON`(PAK_IN_BIT b20:16)、
**`0x240 FBC_IMGO_CTL1`**(FBC_RESET b8 / FBC_DB_EN b9 / LOCK_EN b12 / DROP_TIMING b13 / FBC_SUB_EN b14 /
FBC_EN b15 / VALID_NUM b23:16 / SUB_RATIO b31:24)、`0x244 FBC_IMGO_CTL2`(IMGO_RCNT b7:0)、
`0x600 SPECIAL_FUN_EN`(DCM_MODE b26)、
**DMA：`0x700 IMGO_BASE_ADDR` / `0x704 IMGO_BASE_ADDR_MSB` / `0x708 IMGO_OFST_ADDR` / `0x710 IMGO_XSIZE` b15:0 /
`0x714 IMGO_YSIZE` b15:0 / `0x718 IMGO_STRIDE` b15:0 / `0x71C IMGO_BASIC` / `0x720..0x730 IMGO_CON0..4` /
`0x74C IMGO_CROP` / `0x75C FRAME_SEQ_NO`**。

### 8.2 纯 C 函数（**无任何 MMIO**，不用移植）
`mtk_cam_sv_pipeline_config`(0x450fc)、`mtk_cam_sv_format_sel`(0x45254)、`mtk_cam_sv_pak_sel`(0x453e0)、
`mtk_cam_sv_xsize_cal`(0x45570)、`mtk_cam_sv_cal_cfg_info`(0x499ac)。
- `format_sel`：FOURCC → TG1_FMT 码：GR/BG=1、BA/RG=2、`8AB1`=4、其它=0。
- `pak_sel`：返回 `0x80` GR/BG、`0x81` BA、`0x82` RG、`0x8F` 8AB1；再用 `bfi` 把 2 位 TG1_SW 折进 bits[9:8]。
- `xsize_cal`：宽度；422→`3w/2`、420→`5w/4`；按像素对齐表取整。

### 8.3 `mtk_cam_sv_tg_config`(0x4578c)：时序/窗口
| 偏移 | 寄存器 | 操作 | 值 |
|---|---|---|---|
| 0x100 | TG_SEN_MODE | AND-clear | `&= 0xfffffffe`（CMOS_EN=0）|
| 0x100 | TG_SEN_MODE | OR-set | `\|= 0x40000`(VS_SUB_EN) 且 `\|= 0x20000`(SOF_SUB_EN) 若 `[x1+8]!=0`，否则清 b18/b17 |
| 0x164 | TG_SUB_PERIOD | RMW | b7:0 = `[x1+8]&0xff`；b15:8 = 同一值（VS/SOF period）|
| 0x100 | TG_SEN_MODE | OR/AND | `\|= 0x400000`(STAGGER_EN) 若 `[+0xf34]!=0`，否则清 |
| 0x110 | TG_PATH_CFG | AND-clear | `&= 0xffcfffff`（清 SUB_SOF_SRC_SEL）|
| 0x100 | TG_SEN_MODE | OR-set | `\|= 0x10000`（TIME_STP_EN，**无条件**）|
| 0x104 | TG_VF_CON | AND-clear | `&= 0xfffffffd`（清 SINGLE_MODE b1）|
| 0x100 | TG_SEN_MODE | RMW | 格式：0→`&=0xffffffcf`；1→`&=0xffffffcf,\|=0x20`；2→`\|=0x30`；3→`&=0xffffffcf,\|=0x10`（DBL_DATA_BUS b5:4）|
| 0x108 | TG_SEN_GRAB_PXL | **整字写** | `((w1+h2)<<16) \| w1`（w1=start, h2=width）|
| 0x10C | TG_SEN_GRAB_LIN | **整字写** | `((w2+h3)<<16) \| w2`（w2=start, h3=height）|

### 8.4 `mtk_cam_sv_top_config`(0x4699c)：模块/格式/中断/打包
| 偏移 | 寄存器 | 操作 | 值 |
|---|---|---|---|
| 0x040 | MODULE_EN | OR-set | `\|= 0x1`（**TG_EN**）|
| 0x040 | MODULE_EN | AND-clear | `&= 0xbfffffff`（DB_EN=0）|
| 0x040 | MODULE_EN | AND+OR | `&= 0xcfffffff; \|= 0x20000000`（DB_LOAD_SRC=2）|
| 0x078 | SUB_CTRL | RMW | `\|= 0x1`(CENTRAL_SUB_EN) 若 `[x19+8]!=0`，否则 `&= 0xfffffffe` |
| 0x074 | DCIF_SET | RMW | `&= 0xffffff7f`；条件满足再 `\|= 0x8000`+`\|= 0x100`，否则清 |
| 0x088 | MISC | RMW | `&= 0xfffffffe`（VF_SRC=0）；条件满足 `\|= 0x1` |
| 0x044 | FMT_SEL | **整字写** | fmt 码（1 GR/BG、2 BA/RG、4 8AB1、0 default）|
| 0x048 | INT_EN | **整字写** | **`0x00011070`** |
| 0x040 | MODULE_EN | RMW | 若 `[x19+8]!=0`：`\|= 0x01000000`(DOWN_SAMPLE_EN) 且 b23:16 = `[x19+8]&0xff`；否则 `&= 0xfeffffff` + 同插入 |
| 0x040 | MODULE_EN | OR-set | `\|= 0x4`（**PAK_EN**）|
| 0x040 | MODULE_EN | AND-clear | `&= 0xfffffff7`（PAK_SEL=0）|
| 0x1C0 | PAK_CON | RMW | `(raw&0xffe0ffff) \| 0x000e0000` ⇒ **PAK_IN_BIT b20:16 = 14** |
| 0x07C | PAK | **整字写** | `pak_sel \| (([x19+6]&0x3)<<8)`（0x80 GR/BG、0x81 BA、0x82 RG、0x8F 8AB1）|
| 0x040 | MODULE_EN | AND-clear | `&= 0xffffffbf`（QBN_EN=0）|
| 0x600 | SPECIAL_FUN_EN | **整字写** | **`0x04000000`**（DCM_MODE=1）|

### 8.5 `mtk_cam_sv_dmao_config`(0x47ab4)：IMGO 输出窗口
| 偏移 | 寄存器 | 操作 | 值 |
|---|---|---|---|
| 0x710 | IMGO_XSIZE | 整字写 | `xsize-1` |
| 0x714 | IMGO_YSIZE | 整字写 | `ysize-1` |
| 0x718 | IMGO_STRIDE | 整字写 | stride（某些格式下若计算值小于 xsize 则用 xsize 覆盖）|
| 0x74C | IMGO_CROP | 整字写 | `0` |
| 0x720 | IMGO_CON0 | 整字写 | 若 `[x19+0x10]<=9`：`0x10000300`；否则 `0x10000080` |
| 0x724 | IMGO_CON1 | 整字写 | `0x00c00060` / `0x00200010` |
| 0x728 | IMGO_CON2 | 整字写 | `0x01800120` / `0x00400030` |
| 0x72C | IMGO_CON3 | 整字写 | `0x820001a0` / `0x80550045` |
| 0x730 | IMGO_CON4 | 整字写 | `0x812000c0` / `0x80300020` |
**注意：`dmao_config` 从不写 `0x71C`(IMGO_BASIC)。**

### 8.6 `mtk_cam_sv_setup_cfg_info`(0x49dbc)：必须成对的 HOLD 窗口
守卫 `ldrb w8,[x1+0xcafc]`，为 0 则直接 return（**不写任何寄存器**）。否则：
```
0x110 TG_PATH_CFG |= 0x800            # DB_LOAD_HOLD b11 = 1
0x108 = img[x9+0x4]                   # TG_SEN_GRAB_PXL
0x10C = img[x9+0x8]                   # TG_SEN_GRAB_LIN
0x044 = img[x9+0xc]                   # FMT_SEL
0x07C = img[x9+0x10]                  # PAK
0x710 = img[x9+0x14]                  # IMGO_XSIZE
0x714 = img[x9+0x18]                  # IMGO_YSIZE
0x718 = img[x9+0x1c]                  # IMGO_STRIDE
0x110 TG_PATH_CFG &= 0xfffff7ff       # DB_LOAD_HOLD b11 = 0  (释放)
```
**这 9 步的顺序不可重排。**

### 8.7 使能 / 关闭 / 触发（13 个函数，`camsv_register_sequence_report.md`）
| 函数 | 操作 |
|---|---|
| `tg_enable`(0x47fbc) | `0x100 \|= 0x1`（CMOS_EN）|
| `tg_disable`(0x48e44) | `0x100 &= 0xfffffffe` |
| `top_enable`(0x485ec) | `0x060 \|= 0x1`(TG_DP) → `\|= 0x2`(QBN_DP) → `\|= 0x4`(PAK_DP) → `\|= 0x8000`(IMGO_DP)；**bl tg_enable**；**bl dmao_enable**；`0x240 \|= 0x200`(FBC_DB_EN)；**守卫**：仅当 `0x100 b0==1` **且** `[dev+0x98]!=0` 才 `0x104 \|= 0x1` |
| `top_disable`(0x48f0c) | `0x104 &= ~0x1`（若先前在跑）→ bl → `0x040 &= 0xbfffffff`(DB_EN=0) → `0x040=0`、`0x044=0`、`0x048=0`、`0x240=0`（整字清零）→ `0x040 \|= 0x40000000`(重新武装 DB_EN) → `0x060 &= ~0x1`、`&= ~0x4`、`&= ~0x8000` |
| `dmao_enable`(0x48ac4) | `0x040 \|= 0x10`（**IMGO_EN**）|
| `dmao_disable`(0x493bc) | `0x040 &= 0xffffffef` |
| `fbc_config`(0x47f60) / `fbc_disable`(0x49484) | `0x240 = 0` |
| `fbc_enable`(0x48b8c) | **守卫**：若 `0x104 b0==1` → 返回 **-1（不写）**；否则 `0x240 = (raw&0x00ffffff) \| (cfg[8]<<24)`(SUB_RATIO) → `0x240 \|= 0x8000`(FBC_EN) → `0x240 &= 0xfffffdff`(FBC_DB_EN=0) |
| **`vf_on`(0x494e0)** | **`0x104 \|= 0x1`(VFDATA_EN) 开机 / `&= 0xfffffffe` 关机；幂等（状态已一致则完全不写）： 这是"开始/停止采集"的最终开关** |
| `is_vf_on`(0x49714) | 读 `0x104`，返回 `val & 0x1` |
| `toggle_tg_db`(0x48084) | `0x110 \|= 0x100` 再 `&= 0xfffffeff`（DB_LOAD_DIS 脉冲）|
| `toggle_db`(0x48338) | `0x040 &= 0xbfffffff` 再 `\|= 0x40000000`（DB_EN 脉冲）|
| **`enquehwbuf`(0x49790)** | `0x75C = seq`；`0x700 = addr[31:0]`；`0x704 = addr[35:32]&0xF`；**`0x014 = 0x1`（TOP_FBC_CNT_SET.RCNT_INC1，投递踢一脚）** |
| `dev_stream_on`(0x4b3e0) | w19==0 分支：bl vf_on → `0x240=0` → `0x040 &= 0xffffffef` → `0x100 &= 0xfffffffe` → **bl vf_on(dev,1)** ⇒ `0x104 \|= 0x1` |

### 8.8 ★ 单帧捕获的完整调用顺序（来自 `mtk_cam_sv_dev_config`@0x4b18c–0x4b274）
```
1. cal_cfg_info                      (纯 C，算格式/窗口)
2. setup_cfg_info                    (0x110 HOLD → 0x108/0x10C/0x044/0x07C/0x710/0x714/0x718 → 0x110 释放)
3. pipeline_config → format_sel → pak_sel → xsize_cal   (纯 C)
4. tg_config                         (0x100/0x104/0x108/0x10C/0x110/0x164)
5. top_config                        (0x040/0x044/0x048/0x074/0x078/0x07C/0x088/0x1C0/0x600)
6. dmao_config ; fbc_config(0x240=0) (0x710/0x714/0x718/0x74C=0/0x720..0x730)
7. tg_enable (0x100|=1) ; top_enable (0x060|=0x8007 → dmao_enable 0x040|=0x10
                                      → fbc_enable 0x240=(ratio<<24)|0x8000 → 0x104|=1 若 VF)
--- 每帧 ---
8. enquehwbuf: 0x75C=frame_no ; 0x700=addr[31:0] ; 0x704=addr[35:32]&0xF ; 0x014=1
--- 启动 ---
9. dev_stream_on: vf_on(0) → 0x240=0 → 0x040&=~0x10 → 0x100&=~0x1 → vf_on(1)  ⇒ 0x104|=1
--- 停止（反向）---
10. 0x104&=~1 → dmao_disable(0x040&=~0x10)+fbc_disable(0x240=0) → 0x040&=~0x40000000
    → 0x040=0x044=0x048=0x240=0 → 0x040|=0x40000000 → 0x060&=~0x8001
```
**关键顺序约束**：`fbc_enable` 在 `0x104 b0` 已置位时会直接返回 -1 ⇒ **必须在 `vf_on(1)` 之前调用**；
`setup_cfg_info` 的 HOLD/释放必须成对且不可重排；`VFDATA_EN(0x104 b0)` 是所有函数公认的"正在出流"标志。

### 8.9 还需要自己决定的量（vendor 由上层 V4L2/ISP 驱动提供）
- `0x044 FMT_SEL` 的 `TG1_FMT` 码：**IMX582 RAW10 ⇒ 查 `format_sel` 的 FOURCC 表**（RAW10 通常是 MIPI RAW10 → 需确定是 0/1/2/4 中哪一个）。
- `0x100` 的 `DBL_DATA_BUS(b5:4)`：由 `tg_config` 的 fmt 分支决定（0..3）。
- `0x108/0x10C` 的 `PXL/LIN start+end`：按 sensor 的 crop（4000×3000 全幅 ⇒ start=0, end=width/height）。
- `0x710/0x714/0x718`：xszie = width-1、ysize = height-1、stride = 一行的字节数（RAW10 packed ×2）。
- `0x240 SUB_RATIO`：不启用 FBC 压缩时用 `fbc_config`(**0x240=0**) 即可，不必走 `fbc_enable`。

---

## 9. CAMSV 抓帧的 DMA 缓冲区问题（进行中）

### 9.1 已确认的硬件事实
- `SENINF → CAM_MUX → CAMSV → IMGO DMA` 需要一块**物理连续**的 DRAM 缓冲区，地址写进 `0x700/0x704`。
- `MemTotal = 11649468 kB`（≈11.6 GB）；**`CmaTotal = 32768 kB`、`CmaFree = 28576 kB`**（**存在 32 MB CMA 池，空闲 27.9 MB，够放一帧 4000×3000 RAW10 ≈ 12 MB**）。
- `/sys/kernel/debug/cma` **不存在**（debugfs 未挂或未配 `CONFIG_CMA_DEBUGFS`）。
- 存在两个 IOMMU：`mtk-iommu.0x1e802000`、`mtk-iommu.0x1e810000`；但 CAMSV 走物理地址（vendor 用 `dma_alloc_coherent`）。
- `/proc/iomem` 的 reserved 大块：`70000000-75ffffff`(96MB)、`8a000000-8c35ffff`(38MB)、`d4000000-db7cffff`(120MB)、`bd000000-be3fffff`(20MB)、`f8000000-f865ffff`(6MB)、`bf900000-bfffffff`(7MB)。
- `/dev/mem` mmap/读写 MMIO 正常工作（一直在用），但**能否访问 RAM 段待定**。

### 9.2 结论：**必须写一个内核模块拿物理连续缓冲**
`alloc_pages_exact(N, GFP_KERNEL)` 返回物理连续页，`virt_to_phys()` 得物理地址；**不需要 struct device**。
缓存一致性：模块内用 `memremap(phys, size, MEMREMAP_WC)`（非缓存）读取 CAMSV 写进 DRAM 的数据，避免 CPU 读到脏的 cached 行。
备选：`/dev/fb0` 的 `FBIOGET_FSCREENINFO.smem_start` 给出 framebuffer 的物理地址（1920×1080×4 = 8.3 MB，够放 1920×1080 RAW10 = 4.1 MB 的裁剪帧）。

### 9.3 ★★ 设备卡死事故与真正的根因（2026-10-06，**根因已由用户更正**）
**结论：设备不是被某一条 devmem 打死的，而是被我在设备上并行跑了太多任务、把 CPU 吃满拖死的。**
用户观察：**卡死前 CPU 核心 2、4、5、7、8 全部 100% 占用**（8 核里 5 颗满载）。

当时我的负载叠加情况（全部同时压在这台手机上）：
- `/root/imx582_bring.py` 逐条 I²C 写 + 20 次 CSI2 寄存器采样；
- `zz_v77.sh` / `zz_v78.sh` 反复 `/dev/mem` 读写与 `/proc/iomem` 解析；
- 后台还有多个 `zz_watch.sh` / SSH 轮询循环在自己触发重连（pwsh-36、pwsh-38 各有 15–20 次 ssh 重试）；
- 以及 `zz_v79.sh` 的 reserved 段探测。

`busybox devmem 0xd4000000 32`（属于 `d4000000-db7cffff : reserved`）只是最后一根稻草：在 CPU 已被吃满的前提下，
那一次总线访问把已经濒临失控的系统彻底卡住。**归因给单条 devmem 是错的。**

症状：SSH 只能建立 TCP 连接、**卡在 KEXINIT（banner 超时）**，无法登录；USB gadget（COM9，`VID_0525&PID_A4A7`）
仍正常枚举 ⇒ **设备从未自行重启**，是挂死，必须手动长按电源键。

#### 纪律（必须遵守，否则会重犯）
1. **同一时刻只允许一个设备侧任务**，跑完再跑下一个；不要并行开多个 SSH/脚本。
2. **不留后台轮询循环**（`zz_watch.sh` 这类 20 次 ssh 重试本身就是在持续加压）。要看设备是否恢复，用手动单次探测。
3. 设备侧脚本加 `nice -n 19`（必要时 `ionice -c 3`）；长任务分片，每片之间 `sleep`。
4. `/dev/mem` 探测一次只读少量地址，不做批量扫描；不写。
5. **仍不要碰 `d4000000` 及未确认的 reserved 段**（这条依然成立，只是它不再是根因）；要探测 RAM 只能走**已知被内核接管的 System RAM 段**或内核模块。


---

## 10. ★★ 2026-10-06 下半场：V4L2 采集设备 + 系统相机软件（Cheese）打通

**用户目标（m03706 原文）**：「你能把这玩意接到系统的相机软件吗（如果系统没有相机软件可以装gnome的相机），弄完后看看能不能接上ISP」
： 本节回答**前半句**（后半句见 §11）。

### 10.1 结果（全部在真机上验证过）

| 项 | 结果 |
|---|---|
| `/dev/video0` | 建成。`crw-rw---- root video 81,0`，name=`cam_cap`，card=`MT6895 CAMSV1 (IMX582)` |
| 格式 | **2000×1500 YUYV 4:2:2**，Bytes per Line 4000，Size Image 6 000 000，sRGB / ITU-R 601 / **Full Range** |
| 能力 | `VB2_MMAP｜VB2_DMABUF｜VB2_READ`（mmap / dmabuf / read 三种都可用） |
| 系统相机软件 | **Cheese 43.0-1**（apt 装），打开 `/dev/video0` 出图，**2.15 fps**（`arm_count` 124→167 / 20 s），并**录了两段 webm** |
| 取证 | Cheese 录的 webm **第 0 帧**与直读 `/dev/video0` 的渲染图亮度相关 **+0.591（原方向）/ −0.185（转 180°）** ⇒ 同画面、方向正确 |
| 负载 | `cam_cap_v4l2` 内核线程 **88% 单核**，cheese/kwin/plasmashell 各 4–7%，`load average ≈ 1.1`（8 核）⇒ 安全，不会重演 §9.3 的整机卡死 |

完整说明（装机步骤、参数、三种用法、证据、限制）见 **[docs/V4L2_CAMERA.md](V4L2_CAMERA.md)**。

### 10.2 这一程踩到的四个坑（都很贵，别再踩）

1. **`frame_bytes` 必须 4 KiB 页对齐**。设成"正好一帧"的 18 000 000（不是 4096 倍数）会让
   `iommu_map()` 直接 `-22`（`iommu: unaligned: iova 0x10000000 pa 0xfa500000 size 0x112a880 min_pagesz 0x1000`），
   模块**静默退回物理寻址**，CAMSV 往物理地址写触发
   `mtk-iommu-mt6895 1e802000.iommu: fault type=0x5 iova=0xfa52e000 pa=0x0 larb=0 port=2 layer=0 write`，
   于是 `/dev/video0` 能开、`arm` 报 FRAME READY，但**抓到的一帧全 0**（最难查的"假成功"）。
   现在源码写死 `CAMCAP_FRAME_BYTES = 18874368UL`（0x1200000），且 `v4l2_enable` 下 IOMMU 映射失败会让 insmod **硬失败**。
2. **`single_mode=1`**（CAMSV `TG_VF_CON.SINGLE_MODE`）：`arm()` 每 5 ms 轮询而一帧要 ~65 ms，
   从 IMGO_DONE 到 `vf_off()` 之间自由运行的 TG 会开始下一帧并覆盖缓冲头部（约 230 行）。
   开单帧模式后由**硬件**自己停帧：实测 `devmem 0x1a110104` 读回 `0x00000002`（VFDATA_EN 被硬件清掉、SINGLE_MODE 仍在），
   缓冲在 t+1s / t+3s / t+6s 三次 md5 完全相同（`dce307dd2d3ec201645aec1289e82899`）。
3. **FLIP180 必须在反马赛克之后做**。对 Bayer 原始网格做 180° 会把 RGGB 静默变成 BGGR（颜色就错了）。
   现在是在成品 YUYV 上原地翻（行序对调 + 行内 4 字节组序对调 + 组内两个 Y 互换、U/V 留在原组）。
4. **V4L2 地基模块要手工加载，`mc.ko` 是关键**。这份内核配置里 `CONFIG_MEDIA_SUPPORT=m` ⇒
   媒体控制器核心**也是模块**，缺它 `videodev.ko` 会报 26 个 `media_*` 符号 `Unknown symbol`。
   设备没有 `/lib/modules`，所以每次重启后都要手工 insmod（顺序：
   `mc → videodev → videobuf2-common → -memops → -vmalloc → -dma-contig → -v4l2`，
   文件在设备 `/root/v4l2/`；一键脚本 [scripts/zz_cam_up.sh](../scripts/zz_cam_up.sh) + [scripts/zz_cam_app.sh](../scripts/zz_cam_app.sh)）。

### 10.3 新增/更新的文件

* 源码：[src/cam_cap.c](../src/cam_cap.c)（约 2626 行，新增 "V4L2 / videobuf2 capture device" 段与 `v4l2_enable` 参数）
* 产物：[out/camcap_0b8dd2e/cam_cap.ko](../out/camcap_0b8dd2e/cam_cap.ko)（663 296 B）、[out/v4l2/](../out/v4l2/)（7 个 V4L2 模块）
* 脚本：`scripts/zz_cam_up.sh`、`zz_cam_app.sh`、`zz_cam_round.sh`、`zz_stream_cpu.sh`、`zz_cheese_diag.sh`、
  `zz_cheese_vs_gst.sh`、`zz_final_check.sh`、`zz_lock_check.sh`、`zz_v4l2_state.sh`、`zz_isp_fw.sh`、
  `scripts/render_yuyv.py`、`check_v4l2_orient.py`、`analyze_cheese_frame.py`、`cheese_map.py`、
  以及编译侧 `wsl_build_v4l2.sh`、`wsl_build_mc.sh`、`wsl_v4l2_stage.sh`、`wsl_align_cfg.sh`

---

## 11. ISP 结论：**接不上**（附三条硬证据）+ 一条旧笔记更正

**用户目标（m03706 原文）**后半句：「弄完后看看能不能接上ISP」。
**结论：主线内核上接不上**，而且不是"还没调通"，是"路不存在"。完整论证见
**[docs/ISP_FEASIBILITY.md](ISP_FEASIBILITY.md)**，这里只留结论与证据链标题：

### 11.1 三条硬证据（任何一条都足以否决）

1. **主线里根本没有 MTK ISP 驱动**：`drivers/media/platform/mediatek/` 只有 `jpeg/mdp/mdp3/vcodec/vpu`（**无 `isp/`**）；
   `.config` 里唯一的 `*ISP*` 是 `CONFIG_VIDEO_RCAR_ISP=m`（瑞萨）；全树**没有** `mediatek,mt*-isp` compatible；
   连 seninf/camsv 驱动源码和 IMX582 传感器驱动都没有（194 个 sensor 驱动里没有 582/586）。
2. **厂商 ISP 驱动我们手里有完整代码，但装载不进去**：`isp71_ref/mtk-cam-isp.ko` 2 597 024 B、**718 个函数**、
   `.text ≈ 807 KiB`、12 个 `.rela` 段；vermagic `5.10.198-android12-9-gb80b558ee02f … **modversions**`（我们是 7.2.0 主线、未开 MODVERSIONS）；
   **315 个导入符号里只有 163 个能在我们的 `Module.symvers`(16 982) 里找到，152 个缺失**：
   缺的是 `__cfi_slowpath`/`__tracepoint_android_rvh_*`（GKI+CFI）、`KREE_*`/`gz_tz_system`（MTK TEE）、
   `mtk_ccu_rproc_ipc_send`/`mtk_ccd_get_buffer*`/`ccd_rpmsg`（CCU 协处理器）、`dma_heap_*`/`mtk_icc_set_bw`/`mtk_smi_*` 等。
   它的 `depends=` 列了 **15 个厂商模块**（`mtk_ccu,mtk_sec_heap,gz_tz_system,mtk-icc-core,mmqos-common,imgsensor,
   mtk_ccd_remoteproc,ccd_rpmsg,…`），这些我们一个都没有。
3. **ISP 的寄存器序列不由 CPU 写，而是 CCU 固件 + TEE 安全通道**：模块自己的字符串就是证据：
   `CCU trigger CQ. tg:%d cq_src:…`、`boot ccu rproc fail`、`error: find mediatek,camera_camsys_ccu failed!!!`、
   `Sensor Secure CA`、`KREE_TeeServiceCall`。而 CCU/ISP 固件、`/vendor` `/odm` `/system` 分区、
   remoteproc 实例（`/sys/class/remoteproc` 只有 GPU 那个）、TEE（`gz_tz_system`）**我们全都没有**；
   设备 `/lib/firmware` 一共只有 19 个文件（Wi-Fi/BT/触摸/屏幕/音频），没有任何 ccu/isp/imgsys 固件；
   我们当前的 DT 里连 `ccu`/`camisp`/`imgsys`/`camsys` 节点都没有（[dt/hyperos_fdt.dts](../dt/hyperos_fdt.dts) 里才有）。

⇒ **"接上 ISP" = 从零写一个 ISP7.1 驱动 + 逆向 CCU 固件协议 + 拿到签名 TA**，量级与本项目完全不同，
且最后一步可能被安全启动/签名固件堵死。**我们现在用的是 CAMSV 简单通路 + `cam_cap.ko` 里的软件色彩管线，这就是这条硬件上能拿到的最好结果。**

### 11.2 更正 §8.0 的一条旧判断

§8.0 原写"`bl` 目标全被清零（.ko 剥离重定位后的产物）"：**错误**。
`.ko` 是**可重定位目标文件**：`bl` 到外部符号的位移本来就是 0，真实目标存在 `.rela.*` 段里；
`mtk-cam-isp.ko` 的代码是**完整**的（718 函数、`.text` 807 KiB、12 个 `.rela` 段）。
那次是**反汇编时没有应用重定位**，不是文件被抽空。
**后续若要做更细的寄存器/调用图分析：先用 `readelf -r` / 把 `.rela.text*` 应用到 `.text` 再反汇编**，
所有 `bl`/`adrp+add` 的符号目标都能恢复（这比当时"靠函数体特征猜调用顺序"高一个可信度等级）。

---

## 12. ★★ 2026-10-06 深夜：驱动内 AE/AWB 闭环 + V4L2 控件（画质线收尾）

**用户目标（m04495 选定）**：「继续提升画质：驱动内 AE/AWB 闭环 + 暴露 V4L2 控件（推荐）」。
**结论：做成并验收。** 完整文档 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §9（含十个控件表、控制律、实测表、用法）。

### 12.1 结果（真机实测，可复算）

| 项 | 结果 |
|---|---|
| V4L2 控件 | 10 个，`v4l2-ctl --list-ctrls` 全部正确（brightness/contrast/saturation/AWB/red/blue/auto_exposure/exposure_time_absolute/analogue_gain/digital_gain） |
| AE 闭环 | 从最暗手调点自动爬到目标；**收敛后 `ae frames=` 在 120 帧里一次没动** ✅ |
| 跟随目标 | `ae_target` 1800/700/1200 → 均值 1739 / 787 / 1304（各自死区内） ✅ |
| 旋钮链 | `曝光(0x0040→0x3000) → 模拟增益(0x0100→0x03a0) → 数字增益` 逐级使用 ✅ |
| AWB 闭环 | 关→开能重新收敛（1.00/1.00 → 1.15/2.00 → 1.19/2.22） ✅ |
| 出图 | `frames/v4l2_ae_view.png`：Y 均值 186.6，RGB 均值 **180/189.5/184**（旧手调版 63/61/53） |

### 12.2 传感器上限两条重要更正（推翻本文件 §5 的旧写法）

* `0x0202` **不是**"0x0380 / 16 ms 封顶"：它是**完整 16 位**，到 `0x6000` 仍线性。
  旧结论来自"中间 64 KiB 字节均值"这个饱和判据（§5 已就地加更正块）。
* `0x0204` **只保留低 10 位（掩码 `0x3ff`）**：`0x0f00`/`0x3f00` 静默变 `0x0300` 就是这个掩码；
  可用 `0x0100..0x03f0`（0.5×..4.9×），但 `0x03a0` 以上曲线陡增（一个码换来的光量 > 一个 AE 死区宽度）。

### 12.3 三个真 bug（下次直接看这里，别重踩）

1. **I²C adapter 名 ≠ 设备树节点名**：总线 10 的 adapter 叫 **`i2c-mt65xx`**，不是 `11d05000`。
   症状 = **AE 旋钮拧到顶、`frames` 一直涨、但 `hw=(0,0,0)` 且 `stats` 冻结**（一个 I²C 写都没出去）。
2. **AWB 目标式不能乘当前增益**：`tr = cur * G/R` 每帧再乘一次 ⇒ 指数顶到 4.00。
   正确 = 去基座的绝对目标 `tr = 256*(G-black)/(R-black)`；**基座 248 占红信号本身 69%**，
   这就是旧笔记"蓝要吃 2.40× 增益"的真正原因。
3. **AE 极限环**：把"有过曝就强制回退"当成硬覆盖 ⇒ 在死区里也回退，`0x032c↔0x03a0`（均值 783↔1296）无限对跳。
   修法 = **过曝只在均值超出死区时才有资格推动环**（只决定回退幅度，不决定方向）；
   另加"改动后跳 2 帧不纠正"（`CAMCAP_AE_SETTLE`），因为传感器寄存器只对写入之后才开始积分的那一帧生效。

### 12.4 新增/更新的文件

| 路径 | 作用 |
|---|---|
| [src/cam_cap.c](../src/cam_cap.c) | +AE/AWB/控件/I²C（约 3620 行，`.ko` 728 112 B） |
| [scripts/zz_ctrl_run.sh](../scripts/zz_ctrl_run.sh) | 推 `.ko` + 脚本并在设备上执行 |
| [scripts/zz_cal1.sh](../scripts/zz_cal1.sh) · [zz_cal2.sh](../scripts/zz_cal2.sh) | 曝光/模拟/数字增益响应标定 |
| [scripts/zz_plant.sh](../scripts/zz_plant.sh) | 关 AE 做单步被控对象测量 |
| [scripts/zz_ae3.sh](../scripts/zz_ae3.sh)～[zz_ae7.sh](../scripts/zz_ae7.sh) | AE/AWB 验收与排障（`ae_trace` 抓极限环） |
| [scripts/zz_i2cdiag.sh](../scripts/zz_i2cdiag.sh) | I²C 适配器名诊断 |
| [frames/v4l2_ae.yuyv](../frames/v4l2_ae.yuyv) · [v4l2_ae_view.png](../frames/v4l2_ae_view.png) | 收敛后存的 YUYV 帧与渲染图 |
| [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §9 | 完整 AE/AWB 文档 |

---

## 13. ★★ 2026-10-06 深夜 II：过曝修复 + 4 线程并行（2.25→4.36 fps）+ 开机自起（三项验收）

用户 m05019 的三项要求在这里收尾（指纹那项另有 AI 处理）。完整版见
[docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §10。

### 13.1 结果表

| 要求 | 结果 | 判据（可复算） |
|---|---|---|
| ① 过曝 | **修掉** | `Y==255` 占比 **19.43 % → 0.00 %**；`Y≥250` 26.21 % → 1.87 % |
| ③ 多核均衡解码 + 帧率 | **2.25 → 4.57 fps**（Cheese 实测 4.36） | `conv_threads=1/2/4/8` → conv 401/205/107/114 ms |
| ② Cheese「无法连接摄像头」 | **修掉** | `cam-camera.service` 冷启动 20 s 后 `/dev/video0` ready（全卸载演练 4.61 fps） |

### 13.2 过曝两个原因

`v4l2_gain_q8` 768→**256**（它是 **sqrt 曲线之前**的 3.0× 线性前置增益，先把亮部顶到 4095）+
`ae_target` 1200→**1000**。⇒ 判断过曝只看 **`Y==255` 占比**，不要看"亮不亮"。

### 13.3 并行转换：4 是拐点，8 无收益

一帧按行分带，每个 worker 跑完整的 fused 转换（binning+反马赛克+LUT+饱和度+FLIP180+YUYV），
`cam_convert_frame()` 等齐 `nconv` 个 completion。**4 线程 = 4.57 fps；8 线程 conv 反而更慢（114 ms）
⇒ 已变成内存带宽受限**。默认 `conv_threads=4`，`1` 可退回单线程。
分带无接缝（边界跳变 0.113/0.163/0.189 vs 全图行跳变中位 0.140）；
worker `nice 10`，流中 loadavg 0.29–0.93（8 核）。

**代价 = 两次把机器搞到重启**，两个真 bug：

1. **只等一个 completion**（`nconv` 个 worker 各完成一次）⇒ 半成品交帧 + 上一帧未完成就发下一帧
   ⇒ 整池常驻满速、sshd 被饿死。**症状：ping 通但 ssh 超时**（用 ping 区分"被压"和"死机"）。
2. **`c->conv_wq` 从未 `init_waitqueue_head()`** ⇒ 第一个 worker 在 `prepare_to_wait_event()`
   踩 `NULL-24`（`ffffffffffffffe8`）→ `Comm: cam_conv/0` Oops → 硬复位。**两次都是它**
   （第一次 Oops 没落盘，看起来像"说不清的卡死"）。
   ⇒ `kzalloc` 清零的 `wait_queue_head` 是**坏掉的链表头**，不是"空队列"。

### 13.4 开机自起 + 一键复位（"无法连接摄像头"的两个成因）

| 成因 | 现象 | 处理 |
|---|---|---|
| 重启后模块没了 | 没有 `/dev/video0`；手工 `insmod` 报 `Unknown symbol vb2_*` | `cam-camera.service`（oneshot、`After=multi-user.target`、`TimeoutStartSec=240`）开机跑 `/root/cam_boot.sh` |
| 残留进程占着 `video0` | `Device or resource busy` | 服务启动先放占用；`sh /root/cam_reset.sh [--full]` 一键复位 |

`cam_boot.sh` = 等 pinctrl/i2c → 放占用 → `zz_v80.sh`（传感器上电+bring-up）→ `zz_cam_up.sh`（V4L2 栈）。
日志 `/var/log/cam_boot.log`，失败不阻塞启动。冷启动演练（全 `rmmod` 后跑 `sh /root/cam_boot.sh`）：
`IMX582 ALIVE` → `/dev/video0` → **20 s** → 抓帧 4.61 fps ✅

### 13.5 新增文件

| 路径 | 作用 |
|---|---|
| [src/cam_cap.c](../src/cam_cap.c) | 并行转换池 + 超时兜底 + 运行均值（约 3956 行，`.ko` 749 000 B） |
| [scripts/cam_boot.sh](../scripts/cam_boot.sh) · [cam_reset.sh](../scripts/cam_reset.sh) | 开机 bring-up / 一键复位（设备端） |
| [scripts/zz_install_service.sh](../scripts/zz_install_service.sh) · [local_install_cam_service.sh](../scripts/local_install_cam_service.sh) | 安装 cam-camera.service |
| [scripts/zz_coldboot_test.sh](../scripts/zz_coldboot_test.sh) | 冷启动演练（不必真重启） |
| [scripts/zz_cheese_check.sh](../scripts/zz_cheese_check.sh) | Cheese 活性（`arm_count` 增长） |
| [scripts/zz_perf5.sh](../scripts/zz_perf5.sh) · [local_perf_matrix.sh](../scripts/local_perf_matrix.sh) · [zz_load4.sh](../scripts/zz_load4.sh) | 帧率矩阵与负载采样 |
| [scripts/check_bands.py](../scripts/check_bands.py) · [clip_compare.py](../scripts/clip_compare.py) | 分带接缝 / 过曝定量 |
| [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §10 | 本节完整版 |

## 14. ★★ 2026-10-06/07 深夜 III：30 fps 达标（双缓冲流水线 + VTS 3300）+ 红蓝真凶结案

**两项用户验收（m05676）都在这一节结掉。**

### 14.1 ① 帧率：从 4.36 → **32.5–33.3 fps**

- 串行结构（arm 整帧 → 转换）上限 ~20 fps：arm 50.6 ms + conv 33.6 ms 塞不进 33.3 ms 的帧周期。
- **双缓冲流水线 `pipeline=1`**：两个 18 MB 槽；arm 线程只武装下一帧、`cam_cap_conv` 线程转换上一帧，两者重叠。
  第二块槽用 `alloc_contig_pages()` + `iommu_map`（CMA 里第一块仍是 `dma_alloc_coherent`）。
  帧完成时在 `cam_v4l2_finish_slot()` 里 `cam_convert_frame()` 之后**立刻**释放槽（比放在转换线程里早 ~1.5 ms）。
  arm 内部改细粒度 `usleep_range` 轮询 ⇒ arm 从 50.6 降到 30.1 ms。
- 结果（200 帧）：`conv_threads=4` → **32.73 fps**、6 → 32.52、8 → **33.27**；
  `avg : period=30782us arm=30420us conv=20028us gov=30us fps=32.48 frames=200 pipe=200`。
- **暗房（`dark=37%`、AE 三档全顶格）速率不掉**： 旧故障模式（曝光顶到 VTS）会掉到 ~9 fps。

### 14.2 ★ 帧率的真正杠杆是 VTS，不是线程数

| VTS | 寄存器 | 实测 fps |
|---|---|---|
| 3658 | `0x0e4a` | 30.2（+ 双周期停顿 ⇒ 一忙就掉到 30 以下） |
| 3500 | `0x0dac` | 32.2 |
| **3300** | **`0x0ce4`** | **32.5–33.3（当前 · 周期 30.2 ms · 天花板 33.5）** |

- 行时间 ≈ **9.04 µs/行**（HTS 7872 / pclk 864 MHz）。
- **`exp_max` 必须 = VTS − 128**（当前 `0x0c64` = 3172）。曝光 > VTS ⇒ 传感器拉长帧周期 = 旧默认 `0x3000` 下 9 fps 的根因。
  bring-up（`scripts/imx582_bring.py:52`）与驱动默认值**必须一起改**。
- 手动曝光扫描不单调（fps 26.5–33.1）⇒ 抖动来自调度而非 stretch；同状态两次 60 帧长跑 ±2 fps。
- `/proc/camcap_info` 新增 `dist` 行（帧周期直方图 `clean/late/slip/lost`）： 当前 ~93 % clean、~3 % slip。

### 14.3 ② 红蓝互换：不是相位，是 YUYV 色度槽顺序

- **排除 RYYB**（两个"绿" tap 只差 1.6 %）与**排除相位**（灰世界上翻 Bayer 标签几乎不可见，两帧 RGB 平均只差 2.5 %）。
- **真 bug**：为 180° 翻转把一对里的亮度字节写反是对的，但色度槽固定写 `q[1]=v(Cr), q[3]=u(Cb)`；
  YUYV 一对里只有一个 Cb 一个 Cr，**byte1 永远是 Cb、byte3 永远是 Cr**（与哪个 Y 在前无关）。
  `rb_swap=0` 时 u=Cb、v=Cr ⇒ byte1 被写成 Cr = **真正的互换**（用户当初看到的现象）；
  `rb_swap=1` 时系数反过来，歪打正着写对了 ⇒ 看起来"正常"。
- **修复（代数上完全保画面）**：色度槽跟 `rb_swap` 一起翻；`rb_swap` 默认改 **0**（与厂商 RGGB 一致）；
  `wb_r_q8/wb_b_q8` 默认改 **320/434**（RGGB 灰世界解）。
- **物理定案 (0,0) tap = 红**：关 AWB + 已知色偏，物理 R ×2 ⇒ wire `byte3(Cr)=152.6 > 128 > byte1(Cb)=99.4`、画面发红；
  修复前后同一物理操作特征一致 ⇒ 保画面。副产品：旧构建里"加红"要用 `blue_balance`，现在 `red_balance` 名副其实是红。
- 详见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §11.4（含三帧对照表与 md5）。

### 14.4 新增脚本 / 当前状态

| 文件 | 作用 |
|---|---|
| [scripts/zz_vts.sh](../scripts/zz_vts.sh) | VTS 扫描（**必须一次 4 字节 `i2ctransfer`**） |
| [scripts/zz_period.sh](../scripts/zz_period.sh) | 曝光扫描 + 稳态 60 帧 |
| [scripts/zz_coldstart.sh](../scripts/zz_coldstart.sh) | 冷启动（rmmod → `zz_v80.sh` → `zz_cam_up.sh`）后验收 |
| [scripts/zz_reload30.sh](../scripts/zz_reload30.sh) · [zz_final30.sh](../scripts/zz_final30.sh) | 100 / 200 帧验收 + 直方图 |
| [scripts/zz_rbfix.sh](../scripts/zz_rbfix.sh) | 强色偏无眼判别 |
| [scripts/zz_state.sh](../scripts/zz_state.sh) | 只读状态检查（排障第一步） |
| [src/cam_cap.c](../src/cam_cap.c) | 约 4050 行，`.ko` **793 248 B**（VTS 3300 / exp_max 3172 / pipeline=1 / rb_swap=0） |

设备上跑的就是这一版（`/root/cam_cap.ko` 同版，重启自加载），Cheese 随时可开。

---

## 15. ★★★ 2026-10-07 凌晨 IV：**7 个 sensor 模式全部跑通**（4K60 / 1080p120 / 1080p240）+ 一个"假帧率地板"

回答 m06738「所有录制规格能不能都做出来」：**能做，且已逐模式实测**。

| 规格 | sensor 模式 | 标称 | **实测出流** | burst 下限 ⇒ 传感器上限 |
|---|---|---|---|---|
| 4K30 (4000×3000) | `preview` VTS 3300 | 30 | **32.6–33.6** | 30.1 ms ⇒ 33.2 |
| 4K30 (4000×2256) | `normal_video` | 30 | **30.7** | 32.8 ms ⇒ 30.5 |
| 4K30 (1:1 裁切) | `custom5` | 30 | **30.3** | 34.1 ms ⇒ 29.3 |
| **4K60** | `custom3` | 60 | **54.9–55.8** | 16.06 ms ⇒ **62.3** |
| **1080p120** | `custom2` | 120 | **120.3** | 7.96 ms ⇒ **125.6** |
| **1080p240** | `hs_video` | 240 | **167.0** | 4.02 ms ⇒ **248.7** |
| 48MP | `custom4` | 15 | ✗ CMA 只有 32 MiB（一帧 60 MB） | — |

### 15.1 ★ 最重要的一条：之前"高档位只有标称 2/3"是**自己造的**

第一遍测到 custom3 40.6 / custom2 75.0 / hs_video 83.0 fps，而且**VTS 从 1236 改到 2472 帧周期纹丝不动**
（都 12.0 ms），像"传感器 12 ms 读出地板"。真因是 `cam_cap_arm_addr()` 的完成轮询：

```c
else if (elapsed < 20000000LL)
        msleep(CAMCAP_ARM_POLL_MS);   /* =5，HZ=250 ⇒ 一个 jiffy 4 ms 起 */
```

`msleep()` 按 jiffy 向上取整 ⇒ 短帧（1080p240 只有 4.2 ms）的完成时刻被量化到 tick 的整数倍，
**测到的是 tick 周期不是传感器周期**。改成一律 `usleep_range(150, 250)` 后：

| 模式 | 修复前 | 修复后 |
|---|---|---|
| `custom3` 4K60 | 40.64 | **54.9–55.8** |
| `custom2` 1080p120 | 75.01 | **120.30** |
| `hs_video` 1080p240 | 82.98 | **166.95** |
| `preview` / `normal_video` / `custom5` | 32.8 / 30.9 / 29.3 | 32.9 / 30.7 / 30.3（无回归） |

**教训**：地板不随寄存器变化 ⇒ 先怀疑自己的等待/计时（msleep、jiffy、轮询、调度），再怀疑硬件。

### 15.2 还差什么

- **输出半尺寸**：`CAMCAP_BIN = 2`（2×2 binning demosaic），所以 4K 出 2000×1128、1080p 出 960×540。
  全尺寸 debayer 的标量 C 代价：1080p ≈ 20 ms/帧（~50 fps 够 1080p30/60）、4K ≈ 87 ms/帧（~11 fps）
  ⇒ **真 4K30 全尺寸要 NEON/SIMD 或硬件 MDP 路径**。
- **240 fps 是软件瓶颈**：传感器 4.02 ms，出流 167 fps（960×540 转换 3.8 ms + arm 线程抢核）。
- **48MP 受阻于 CMA 32 MiB**（需要 `cma=` bootarg / 改 DT）。
- **模式切换仍是"重放表 + 重载模块"**（~20 s），不是运行期 `S_FMT`。
- **颜色要白天目视复核**：本次证据帧都是全黑房间（Y mean 16–18），只能证明没有错色偏。

### 15.3 新增工具箱

| 文件 | 作用 |
|---|---|
| [scripts/parse_modes.py](../scripts/parse_modes.py) | 解 vendor 表 + **PLL 规则** `pclk = 4.8 MHz × 0x0306/07` + fps 预测 |
| [scripts/gen_mode_table.py](../scripts/gen_mode_table.py) | 导出 `out/modes/mode_<name>.txt`（`0xREG 0xVAL`） |
| [scripts/imx582_bring.py](../scripts/imx582_bring.py) | `IMX582_MODE=<name>` / `--mode <name>` 重放任意表 |
| [scripts/zz_mode.sh](../scripts/zz_mode.sh) | 一条命令跑完一个模式（清模块→重放表→V4L2→fps/burst/存帧） |
| [scripts/zz_scout.sh](../scripts/zz_scout.sh) | 一次 ssh 连跑多个模式 |
| [src/cam_cap.c](../src/cam_cap.c) | 运行期几何 + 亚 jiffy 轮询，`.ko` **796 240 B** |

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §12。

## 16. ★★★ 2026-10-07 凌晨 V：**满尺寸输出**（`v4l2_bin=1`，真 4K / 真 1080p）

§15.2 第一条"输出永远半尺寸"已解决：`v4l2_bin` 成了运行期参数，`1` 走满分辨率 bilinear debayer。

| 模式 | 满尺寸输出 | 实测 | conv | 上限 |
|---|---|---|---|---|
| `normal_video` 4K30 16:9 | **4000×2256** | **29.9 fps** | 21.3 ms | 29.84 ⇒ **arm 受限** |
| `preview` 4K30 4:3 | **4000×3000** | **24.9 fps** | 28.0 ms | 30.24 |
| `custom3` 4K60 | 4000×2256 | **39.0 fps**（到不了 60） | 17.5 ms | 57.96 |
| `custom2` 1080p120 | **1920×1080** | **91.2 fps** | 7.0 ms | 122.2 |
| `hs_video` 1080p240 | **1920×1080** | **93.4 fps** | 6.9 ms | 216.8 |

- **真 4K30（4000×2256）与真 1080p（91–93 fps）都拿到了**；满尺寸 4K60 / 1080p120 还差一点（见 §13.5）。
- 关键优化：`cam_unpack_row()` + 三行滚动窗 ⇒ 每个 raw 采样只解包一次（逐像素版要解包约 8 次），
  逐像素 → 逐行：4000×2256 的转换 **36.3 → 21.3 ms（−41%）**，4000×3000 **51.7 → 28.0 ms（−46%）**。
- 两条等价性证据：`scripts/check_full_demosaic.py` 模型逐字节 PASS（3 种尺寸 × 2 种 `rb_swap`）；
  真机 A/B 平面统计（Y 15.96/16.10、U 127.42/127.38、V 127.30/127.37）与 `stats` 三通道一致。
- **诚实更正**：§15.2 里"4K 全尺寸 ≈ 87 ms/帧 ⇒ 11 fps ⇒ 必须上 NEON"高估了约 4 倍（实测 21.3 ms）。
  **先量再下结论。**
- 新增 `v4l2_bin` / `v4l2_full_cache` 两个参数，`.ko` **826 592 B**；`v4l2_bin=1` 只对 binned 模式
  （`0x0900=1`）正确，4-cell 的 `custom4`/`custom5` 必须保持 `2`。
- ⚠️ **收尾时踩的坑（写下来当禁令）**：想"不抓帧"就传了 `nc=0`，而 `zz_mode.sh` 把它原样给了
  `v4l2-ctl --stream-count=0`： **那是"无限流"**。11 分钟写了 **122 GB**（≈20 500 帧 × 6 MB），
  是 `pgrep`/`df` 巡检发现的。`zz_mode.sh` 已加 nc 守卫（0 = 跳过抓帧），见 §4.3。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §13。


## 17. ★★ 2026-10-07 傍晚 VI：**AE 呼吸修复 + VCM(DW9800V) 对焦 + 果冻读出时间**

用户三项现场反馈（AE 一下亮一下正常 / 0.5 m 没对焦而 0.4 m 可以 / 果冻），`.ko` **872 432 B**，崩溃 0。

**① AE 呼吸**：`cam_ae_step()` 原本**向下最多 −20%、向上可达 2×**（非对称）⇒ 一次过冲要 3.1 步才拉回，
是慢极限环；再加上修正量由**单帧** `mean_g` 直算、被摄物又晚 1 帧。修法四条：对数域半步
`f = int_sqrt(f << 8)`；上下限互为倒数（`CAMCAP_AE_UP_MAX 384` / `CAMCAP_AE_DOWN_MIN 171` / 增益
`CAMCAP_AE_GAIN_MAX 320`）；绿色均值 IIR 平滑（shift 2，`cam_ae_mean_s`）；`CAMCAP_AE_SETTLE` 2→3。
真机收敛后 `mean_s=1035 / 1057 / 1061`（目标 1000、band 120）稳在带内 ⇒ 不再呼吸。

**② 对焦**：VCM **DW9800V** 在 I²C **0x0c**、id **0xeb**（与 vendor 一致）；寄存器映射照主线
`drivers/media/i2c/dw9768.c`（`0x03`/`0x04` = DAC 10 位、`0x02` PD/AAC、`0x06` AAC 模式+分频、`0x07` Tvib），
初始化写序与 vendor 一字不差 ⇒ AAC3、Tvib 12.8 ms。**手动扫描权威曲线**：峰在 DAC **512**（785），
±128 峰宽，两端机械平台。搜索 = coarse(step 128, 9 点) → fine(±64/±32) → hold，整轮 ≈1.3 s；
第二次独立扫描复现并选中 **480**（手动峰 448–512）✓。
**⚠️ 失败记录**：曾把 metric 改成"单位亮度对比度"求曝光无关，真机**全程平坦 7–8**： 700(Q8) ≈ 2.7 级，
除以亮度 100 只剩个位数，整数除法把 1.8× 的差异压成 1 个计数。已回退为原始 `mean |dY|`，曝光不变性
改由**冻结 AE**（`cam_af_scanning()`）保证。**跟踪 wobble**：每 240 帧（≈8 s）重测 `base±64`，
只有赢 >1% 才动 ⇒ 真机 3 次全部 `held`，平坦场景不会被噪声带走。
接口：`/proc/camcap` 的 `af show|on|off|hold|init|scan|wobble|pos <n>`；V4L2 `focus_absolute` /
`focus_automatic_continuous` 实测可见且 value 随搜索更新。
**坑**：`/proc/camcap` 要写整条指令（`af auto`，不是 `auto`，否则 I/O error）；Cheese 会自动重启抢
`/dev/video0`，测量脚本必须先 `pkill -x cheese`。

**③ 果冻**：读出 = 行数 × HTS/pclk，纯传感器事实： `preview` 4000×3000 **27.3 ms**（Cheese 默认）、
`normal_video` 20.6、`custom3` 14.7、**`custom2` 1080p 4.28**、**`hs_video` 1080p 3.64**、`custom5` 31.9、
`custom4` 63.8。⇒ 换 1080p 模式可把 skew 降到 1/6–1/7，代价是曝光上限 28.7 ms → 7.8 ms（少 3.7× 光）
⇒ 暗光噪声 vs 果冻，正是 S_FMT 该暴露的旋钮。

细节（含四条修改的代码位置、扫描表、脚本清单）见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §14。

## 18. ★★★ 2026-10-07 晚 VII：**运行期切模式**（`S_FMT`/`S_PARM` + `/proc/camcap mode`）

§17 把果冻的修法指到"换低读出模式"，这节让它变成应用能调的接口：模块自带 5 张传感器模式表。

**实测（两条入口，全部 rc=0、崩溃 0）**：preview bin2 2000×1500 **33.43 fps**；`/proc` `mode custom2 1`
→ 1920×1080 **86.72 fps**（描述符 120）；`S_PARM 60` → custom3 4000×2256 **39.48 fps**（描述符 60）；
`S_FMT`+`S_PARM 240` → hs_video 1920×1080 **93.00 fps**（描述符 240）；`S_FMT` → normal_video
4000×2256 **28.53 fps**（传感器 30 上限）；切回 preview 33.30 fps。传感器寄存器每一步都验证过
（`0x0307` / VTS 与用户态 bring-up 完全一致）。

**★★ 真凶（很贵）**：模式表全是**字节寄存器**（`0x0306`+`0x0307` 是两条独立 pair），而
`cam_sensor_write16()` 发 4 字节 `[reg_hi,reg_lo,val_hi,val_lo]` ⇒ 多出的前导 `0x00` 被当成"下一个
寄存器的值"，**每个值都挪到了下一个寄存器**（`0x0306=0x00 0x0307=0x00`、`0x0340=0x00 0x0341=0x00`，
与实机回读一致）。AE 一直好使，是因为 `0x0202/0x0204/0x020e` 是真的 16 位寄存器。修法 = 新增
`cam_sensor_write8/read8`（3 字节），模式表与 `0x0100`/VTS 走 8 位口，`write16` 只留给 AE。

**接收端重定时**：`port2_rx71.py` 写死 1370 Mbps，而 custom3/hs_video 是 1964 Mbps；逐字段核对后
**只有两个值跟速率走**（D-PHY `HS_TRAIL`、CSI2 `DMY_CYCLE`）⇒ 驱动按 `mipi_mbps` 重算
（1370 ⇒ 13/26，1964 ⇒ 9/13），同速率切换不动接收端。

**还差**：高帧率档全是转换受限（1080p 86–114 fps、4000×2256 39.5 fps），要吃满 240 fps 得让转换
更快；`custom4` 8000×6000（60 MB/帧）与 `custom5`（非 binning）没收；切模式会中断推流约 200 ms。

细节（代码位置、模式表字段、验收脚本）见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §15。

## 19. ★★★ 2026-10-08 凌晨 VIII：**转换提速一轮 + 三槽流水线 + 可复现构建**

§18 的结论是"高帧率档全是转换受限"。这节把转换做快一轮，并把"别人 clone 仓库能不能编出同版本"
落成可取证的东西。

**优化三处（都不改画面语义）**：① 色度矩阵每对像素只算一次（YUYV 的 U/V 本就共用；矩阵线性 ⇒
与逐像素平均只差 ≤1 LSB，`scripts/check_yuyv_chroma.py` 在 78 408 对上验证）；② 每行解包加首尾
padding（`cam_unpack_row_pad()`），内层循环的 `xm/xp/xpp` 条件分支全消失；③ 该对象单独 `-O3`，
默认 `conv_threads` 4 → 8（worker nice 10）。

**三槽流水线**：`pipe_slots` 默认 2 → 3。一帧的转换是**串行**工序（一个 `cam_cap_conv` 线程取槽再
分给 8 个 worker），所以 `period ≈ conv + P/N`：加槽只消等槽时间、不加吞吐，第 4 个槽反而更差
（CMA/缓存压力），6 线程也更差。8 线程 + 3 槽是定案。

**实测（只用默认参数）**：preview bin2 2000×1500 **33.84 fps**（天花板）；custom2 原生 1920×1080
**112.74 fps**（描述符 120）；custom2 半尺寸 960×540 **120.34**（打满）；custom3 半尺寸 2000×1128
**60.34**（打满 60）；custom3 原生 4000×2256 **48.52**（描述符 60，仍差 19%）；normal_video 原生
4000×2256 **29.76**（传感器 30 上限）；hs_video **96.83**。用户态拷贝不是瓶颈（4/8/12 缓冲、
带不带 `--stream-to` 都 48–51.5 fps），worker 日志证明 8 个都在跑。

**可复现构建**：模块匹配的内核提交原本**不在任何公开 ref 上** ⇒ 已打成附注 tag
`k50-camera-base`（tag 对象 `5087eada53f0` → commit `0b8dd2e87b3d`）推到公开内核仓。出厂模块指纹
`srcversion: 493F61FF760E440C2CC5AA7`、`vermagic: 7.2.0-g0b8dd2e87b3d-dirty …`。配方 = clone 该
tag → 给 `CREDITS` 追加脏标记 → 用 `docs/k50_mainline_config.gz` 当 `.config` → `olddefconfig` →
**只要 `modules_prepare`** → `z_build_camcap.sh`；一键脚本 `scripts/reproduce_build.sh`、文档
[docs/REPRODUCIBLE_BUILD.md](REPRODUCIBLE_BUILD.md)。端到端实测复现产物 srcversion 与出厂**相同**
（md5 差在构建路径字节）⇒ 代码同一、可加载。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §16。

## 20. ★★★ 2026-10-08 凌晨 IX：**四颗相机全部出帧**（CSI 端口参数化 + 微距 I2C overlay）

用户要求"他说四颗摄像头都可以工作，先在我们这复现"。四颗都复现了：

| 相机 | 传感器 | 物理 CSI 口 | SENINF intf | D-PHY_TOP | 输出 | 实测 |
|---|---|---|---|---|---|---|
| 主摄 | IMX582 | 2 | 4 | `0x11c86000` | 4000×3000 / 2000×1500 | 33.4 fps（bin2）、原生 4K30 30.2 |
| 前摄 | IMX596 | 0 | 0 | `0x11c82000` | 2592×1952 | 29.8 fps |
| 超广角 | S5K4H7 | 1 | 2 | `0x11c92000` | 3264×2448 | 30.2 fps |
| 微距 | GC02M1 | 3 | 6 | `0x11c96000` | 1600×1200 | 30.2 fps |

**规则**（他们的 `mtk_seninf71*.c` 与 `mt6895.dtsi`）：DT 端口号 = SENINF pad 号，`inputs[i].intf = i`，
只有偶数端口支持，所以**物理口 N ⇒ intf 2N**；PHY 节点内 = `ANA A +0`、`ANA B +0x1000`、
`DPHY_TOP +0x2000`、`CPHY_TOP +0x3000`；`TOP_PHY_CTRL_CSI(p) = 0x40 + 4p`、
`CTRL_BASE(i) = 0x200 + 0x1000i`、`CSI2_BASE(i) = 0xa00 + 0x1000i`。四颗都在 `rubens.dts` 里经
CAM_MUX 3 汇到同一个 CAMSV（= 我们树的 `camsv1@1a110000`）⇒ 同时只能一颗出流。

**驱动改动只有三处**：新增 `SENINF_TOP_PHY_CTRL_CSI(p)` 宏、route 用 `route_intf / 2`、`cam_rx_set_rate()`
用 `SENINF_CSI2_BASE(route_intf)` ⇒ `route_intf` + `dphy_base` 两个参数即可覆盖任意端口。

**新增工具**：`scripts/gen_sensor_tables.py`（从他们的驱动抽 `cci_reg_sequence` 表 → `0xREG 0xVAL`）、
`scripts/sensor_bring.py`（通用重放：8/16 位寄存器、ID 回读、上电时序）、`scripts/csirx_bring.py
[port] [link_mhz] [秒] [lane 数] [trail_ns]`（按端口算 ANA/DPHY/TOP/CTRL/CSI2 基址 + 重定时值）、
`zz_front_cap.sh` / `zz_uw2.sh` / `zz_macro_cap.sh` / `zz_macro_grab.sh`。

**微距的坑（我们 DT 里没有 `i2c@11d03000`）**：微距挂 `i2c4`，必须用运行时 overlay 新建控制器
（`dt/ovl_i2c4.dts` + `src/ovl_i2c4.c` + `z_build_ovl6.sh`）。两颗雷：① FDT 块必须**8 字节对齐**，
否则 `OF: overlay: Invalid overlay_fdt header`（内核 `fdt_check_header()` 第一件事就查对齐）⇒
`.incbin` 前加 `.balign 8`；② dtc **不能带 `-@`**，我们的 live DT 没有 `/__symbols__`，否则
`OF: overlay: symbols in overlay, but not in live tree` ⇒ 去 `-@` 并去掉节点标签；另外模块要自己带
`module_exit` + `of_overlay_remove`，否则不可卸载。成功后 `/dev/i2c-*` 多一条，`0x37` 回读 `0x02e0`。

**证据**：`cam_mux_chk` 回读的尺寸与几何一致（`0x04b00640` = 1200|1600、`0x09900cc0` = 2448|3264）、
`frame_ready 1 / last_result 0`、帧率与 HTS×VTS 自洽（微距 2192×1268 @84 MHz = 30.0）；抓到本地渲染
（微距首帧 `Y 12.35`、`U 128.84`、`V 127.97` = 真偏黑、色度中性）；全部 rc=0、crashes 0。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §17。

## 21. ★★★ 2026-10-08 凌晨 X：**转换器第二轮优化** ⇒ 原生 1080p120 打满、4K60 稳态打满

**三处改动**：① **并行 band cache 失效**（新参数 `sync_parallel` 默认 1）： 原来在转换线程上一次性
失效整块 18 MB（帧周期要付的串行时间），现在每个 worker 只失效自己那一带（带间重叠一行），
`/proc/camcap_info` 新增 `sync=` 字段；② **worker 行 scratch 预分配**（快转换器要三行解包数据，
原来每带每帧 `kmalloc_array`）；③ **满尺寸转换器内层去乘法**（输出指针递减，替掉每组一次的
`(n-1-(x>>1))*4`）。另修账本 bug：`t_prev` 原来在 arm 线程入口初始化为 `ktime_get()`，第一帧把
启动时间算成"帧间隔"（≈132 ms）⇒ 平均被拖低并造出假 `lost`；改成 `t_prev = 0` 起步。

**实测**：`sync_parallel` 1 vs 0（custom3）**51.09 vs 45.88 fps**（整块失效的代价 ≈1.9 ms/帧）；
vb2 缓冲 4 → 8 值 +2.3 fps（51.07 → 53.37），第 4 个 raw 槽再 +1.3（54.69）。**最终（`zz_rates.sh 150`，
8 线程 / 4 槽 / 8 缓冲）**：custom2 **原生 1920×1080 avg 117.91 / timing 121.86（打满 120）**、
custom3 **原生 4000×2256 timing 60.28（稳态打满；150 帧平均 50.79，被 3 次 ≥58 ms 突发拖低）**、
normal_video 原生 4000×2256 **30.23**（传感器上限）、preview bin2 2000×1500 **32.76**（天花板）。
`.ko` **914 528 B**，crash 0。对比 §19：1080p 112.7 → 120、4K60 48.5 → 稳态 60。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §18。

## 22. ★★★ 2026-10-08 深夜 XI：**对焦在平坦场景里乱跑**的修复（用户报障）

**现象**：镜头一直抽、最后停在没依据的位置（暗场日志：10 个粗点 `metric` 全 0/2，`best_pos` 停在
DAC 0 = 机械静止点 = macro 焦距；HOLD 每 `12 << stubborn` 帧（≈3 s）就重扫一次）。

**两个根因**：① `cam_af_start()` 用严格 `m > best_metric` 且 `best_pos` 初值是第一个粗点 ⇒ 整轮无赢家时
停在 0；② 重扫条件 `m*100 < best*70` 在 `best≈2` 时由噪声满足 ⇒ 反复重扫。

**修复**：新参数 `af_floor`（默认 200，低于它不能赢得比较）、`af_fallback`（默认 **512** = 量程中点，仅
无历史位置可用时用；`0xffff` 哨兵会被拒绝）、新增 `hold_pos`/`flat`：扫描无可用点时把镜头
**放回扫描开始的位置**（成功扫描后记住它）；平坦时**既不 wobble 也不再搜**，停在原地等场景恢复对比度
（恢复后由 `!best_metric` 支路按 `CAMCAP_AF_RESCAN_FRAMES`=12 帧重启一轮）；wobble 也不接受低于下限的赢家。
`af` 行新增 `floor=`/`flat=`。（`CAMCAP_AF_FLAT_FRAMES` 是旧版"每 10 s 重扫一次"的限速旋钮，已不再引用。）

**验证**：修复后 `af auto` → `scan 1 done, pos=512 metric=920`，此后 5 次 wobble 全部 `wobble held
pos=512`（±64 邻居 916–921，从未好 1%），25 s 静默窗内无新扫描，33.3 fps 不掉。**独立验证**：
流跑着时在 DAC 0/256/512/768/1023 各抓一帧（`zz_afsharp.sh`），离机 `sharpness.py` 量
mean |dY| / Laplacian 方差 / mean |Laplacian| ⇒ **三个指标都在 512 取最大**（206.1 vs 192.7–197.6），
与驱动选择一致；但幅度只有 2–7% ⇒ 这一场本身对焦信息很少。

⚠️ **诊断陷阱**：`/proc` 的 `af` 行读"最后一帧"的统计，**流停了就是陈旧值**（Cheese 开着设备但流已停时，
手工扫 11 个位置会拿到一模一样的数字）。先确认流在跑。

**诚实清单**：对比度对焦需要场景有对比度；平坦/极暗场景修好的是"不乱跑"而不是"凭空对上焦"，
此时镜头保持原位并打 `scan N found no contrast …, lens back to …`；指标是未归一化的平均 |dY|(Q8)，
暗场噪声能把它抬到几百，"有值"≠"有信息"。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §19。


## 23. ★★★ 2026-10-08 深夜 XII：**对焦指标在正常照明下饱和** + 原厂 AF 逆向 + 四摄只有主摄有马达

用户报：「偶尔对焦很频繁，手没动都对，有时又死活不对焦，比如在场景中没有文字的情况下不对焦」，
并要求"其他几个头的对焦也做了"和"逆向原厂相机对焦"。

**★ 根因（两条症状同一个）**：bin=2 预览路径的对焦度量是**线性灰度**并在 255 饱和
（`clamp((77r+150g+29b)>>8, 0, 255)`）。raw 电平超过 ~435（正常照明）时两个样本都钳到 255 ⇒ `fv=0`
⇒ 判"平坦"、**永远不聚焦**；同时 `best_metric` 恒 0 ⇒ 每 12 帧重扫一次 ⇒ **"手没动也对个没完"**。
bin=1 满尺寸路径一直用 gamma 后的绿 ⇒ 同一场景两条路径结论不同 = 用户说的"有时行有时不行"。
`scripts/check_af_metric.py` 复算：旧度量在 raw 300/600/1200/2400/3600 上全是 **0.0**（120 时 10229.8），
新度量（对比度千分比）是 217/127/91.5/74.5。

**修复**：`cam_luma8()` → `cam_metric_px(g) = cam_lut_g[min(g,4095)]`（gamma 绿、不饱和、不带 WB 增益），
两个站点统一；`cam_af_metric()` 改成 **`(fv*1000)/fv_y`**（对比度千分比，曝光不变）＋近黑守卫
`CAMCAP_AF_MIN_LEVEL=6`；`af_floor` 默认 **200 → 20**；**抖动退避**（守住翻倍、上限 3000 帧≈100 s、
赢了复位、不跨 AE 台阶测量、`af` 行加 `per=`）；`CAMCAP_AF_RESCAN_FRAMES` 12 → 30；`scans` 与
`wobbles` 分开计数；新增 `cam_vcm_park()`（16 步 × `usleep_range(8400,9400)` 降到 0 = 原厂
`dw9800v_power_off()` 的做法），模块 `__exit` 与 `/proc/camcap park` 都会调用。

**实测**（917064 B，暗房，`out/re/zz_af2.sh`）：90 s 内 **1 次搜索**（旧 ~11 次）、**3 次抖动**且间隔
240→480→960→1920 帧翻倍、33.1 fps、crashes 0、暗房 `metric=546–560‰`。park：推流中 `pos=640→0`（rc=0）；
`af pos 768` 后 `rmmod` ⇒ dmesg `VCM parked at 0 (infinity end)`，`unregistered`→`parked` 459 ms（48 步）。

**原厂 AF 逆向**（`out/re/STOCK_AF_ANALYSIS.md`，360 行）：算法在 `lib3a.af.core.so`、状态机在
`libcam.afmgr.so`、**唯一动镜头的是 `libcam.hal3a.lensdrv.so` 的 `VCMDrv::SetFocusPosition`**
（一条 `VIDIOC_S_CTRL` 写 `V4L2_CID_FOCUS_ABSOLUTE`）⇒ 内核侧把 16-bit DAC 写寄存器 `0x03`；
搜索 = 粗扫→细扫 + 下降反向 + 边界停 + 无峰值跑完全程 + 步数上限；**不乱对焦靠三道闸门**
（AE 变化 + 场景稳定 + 陀螺仪静止）＋暗光抑制搜索；自适应镜头稳定用 `pixel_in_line/pixel_clk`
（我们的等价物是丢弃转换帧）。**拿不到**：所有数值调参（`ParameterDB_af.db`/NVRAM/`*_tuning.so` 里的
`RAWSensorInfo` blob），`AfMgr::getMin/MaxLensPos()` 是返回 0 的桩函数。**不可复刻**：FV 来自 MTK ISP/DIP
统计块、PDAF/Hybrid、33/40 MB AI 模型、FDAF/AISEG、热标定。

**★ 四摄只有主摄有对焦马达**（用户要求"其他几个头也做对焦"的答复）：原厂 DT 里唯一的执行器是
`camera_af_main@0c`（`i2c@11d05000`，唯一带 `afvdd`），原理图里唯一的 AF 电源网络是 `CAMWM_AF_2P8`；
超广角/微距/前摄只有各自的 AVDD/MCLK/RSTN。实机 bus10 上同时有 `0x0c`(VCM, id `0xeb`)/`0x10`/`0x51`。
原厂对这三颗走 `ForceEnableFVInFixedFocus()`（整个目标组当一个 FV 窗口、AF 模式 EDOF、永不动镜头）
⇒ 它们是**固定焦距**，要做的不是补对焦。

**诚实清单**：① 饱和路径**没能在真机复现**（房间太暗：`y=15` ⇒ raw ≈14，离门槛 435 差 30 倍；
手机 `/sys/class/leds/` 为空、无 v4l2 flash 节点 ⇒ 没有任何可控光源），证据是**算术等价**
（`check_af_metric.py` 逐行转写）+ 用户描述吻合（§24 又用"前摄 + 手机屏幕当光源"试了一次：仍不成立，
并顺带发现前摄的曝光写不进去）；② 原厂的数值全拿不到，我们的步长/阈值仍是自己凑的；
③ `af_min/af_max` 仍是 0/1023 全量程，没有 OTP 标定；④ EEPROM 里两段像 DAC 位置表的序列
（≈213–501 / ≈878–994）布局 UNKNOWN，没采用。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §20。

## 24. ★★★ 2026-10-09 凌晨 XIII：**真重启验证通过** + 4K60 600 帧全清 + 度量 A/B 失败复盘

用户说「你先记录吧，然后机器3点关机，你趁着这个时候做一些你想做的事」⇒ 三件事：真重启验证、
4K60 突发复测、想用前摄复现度量饱和。

**★ 真重启 = 开机只注册一次**（`out/re/zz_reboot_check.sh`）：重启后 15 s 回来；服务 8/16/24 s
`activating` → **32 s active**，`ExecStart=/root/cam_boot.sh status=0/SUCCESS`，启动 ~25 s；
**`registered : 1` / `loaded : 1`**（此前同一会话 15 次）、cam_cap 无移除行；`/dev/video0`
`crw-rw----+ root video 81,0`；实拍 20 帧 32.76–33.34 fps、crashes 0、`cam_boot.log` 结尾
`RESULT: ok`。口径：检查脚本的 `removal : 8` 是 grep 太宽的假阳性（命中别的子系统行）。

**4K60 600 帧 ×4 变体全清**：`clean=600 late/slip/lost=0`、墙钟 10.15 s（59.3 fps）、`timing`
59.76–60.76、`avg` 59.40–59.71；`sync_parallel=0` 的同步成本从 1927 µs 掉到 433 µs（转换器第二轮的
红利）。⇒ §21 那条"150 帧平均 51–53"**当前不可复现**；但**同一配置的 150 帧矩阵里又出现 2 lost**，
所以准确结论是"稳态 60 fps 确定，稀疏 ≥58 ms hiccup 仍会偶发，短测平均会被它拉低"：
真机复测 4K60 要看 `timing`/`dist`，别看 150 帧平均。

**重启后全模式矩阵**（`zz_rates.sh 150`，native bin=1）：normal_video@30 **29.94/30.07**、
custom3@60 **60.40 / avg 53.91**（2 lost）、custom2@120 **120.67 / 119.37**（150 clean）、
preview bin2 **33.29/33.06**。注意 `dist` 桶按 33.5 fps 天花板定义 ⇒ 30 fps 模式的名义帧全落
`late(32–40 ms)`，不是掉帧。

**度量 A/B 没做成（有信息量）**：拿前摄 IMX596 + 手机自己屏幕（`videotestsrc checkers-8` 全屏）做
旧/新模块对比，`exp_def=8/16/32` 三档下老模块度量 2092/2096/2095、新模块 480/477‰： **几乎不动**，
画面 stats `r≈256 g≈256 b≈257 dark=41% y=11–12` ⇒ 很暗、`exp_def` 对画面**没有可见影响**
（`ae` 行 `hw=(0x0010,…)` 但 raw 一直 102..400）。没有背光节点（`/sys/class/backlight` 不存在）
= 没有可控光源，因此 §20.6 的"只能算术证明"不变，**新开一条待查：前摄曝光没落地**
（`cam_sensor_apply()` 本身复查无 bug；下一步先 `dmesg | grep 'write .* failed'`：这次我把 dmesg 过滤掉了，
是我自己的流程漏洞）。顺带从 git 取回旧度量真身：`(fv*256)/fv_n`，死在"整幅图都在裁剪点以上"（≈raw 222）。

细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §21。

**★ 更正（同一夜的后续）**：上面"前摄曝光没落地"是**错的**，已由 `out/re/zz_expo4.sh` 推翻：
前摄（IMX596）的 I²C 通路、曝光 `0x0202`、数字增益 `0x020e`（16× ⇒ 画面明显打亮：`g 260→301`、
`max_g 282→452`、`dark 0%→12%`）、以及 `0x0100` 流开关（写 0 时 `dist` 计数当场冻结 + 2 个 `lost`）
**全部有效** ✓。当初误判的两个原因：① `zz_ab_scr.sh` 只比较了"两档都落在同一段近黑区间"的值；
② `zz_expo3.sh` 的辅助函数把 **1 个**寄存器字节喂给 `w4`（应为 2），全部写入被 `Invalid data byte` 拒绝
⇒ 那一轮什么都没写进去。另记一条坑：**写寄存器后"立刻回读"看到的是影子寄存器**（写 `0x0010` 回读
`0x000a`、写 `0x1800` 回读 `0x1200`），不能拿它判对错。度量 A/B 做不成的真正原因收窄为**没有可控光源**
（前摄对着近黑，pedestal ≈250/4095），§20.6 的"只能算术证明"仍成立。细节见 §21.5。

## 25. ★★★ 2026-10-09 凌晨 XIV：**"手没动也重对焦"的修复**（陈旧参考量 → 跟随基线）

用户 m12962 原话：**「大概就是偶尔对焦很频繁，手没动都对」**。

**根因**：HOLD 态的重扫判据拿 `cam_af.best_metric`（**上一次扫描期间、在另一个曝光/另一个镜头位置**测到的
绝对峰值）当参考。度量虽是千分比（`(fv*1000)/fv_y`），但 `cam_degamma[]` 非线性 ⇒ AE 把曝光压 30 倍时，
**静止场景的度量实测从 553 掉到 72**（暗端 `y=11`）⇒ 旧参考下就成了"场景变了" ⇒ 连续 30/60/120/240 帧
低于 70% 就整段重扫，镜头还会停到更差的位置。

**修法**：HOLD 态维护 8 帧 EMA 基线 `cam_af.hold_ref`（`(hold_ref*7 + m)/8`），判据改成 `m*100 < hold_ref*70`
⇒ 曝光/环境光/白平衡的缓慢变化被基线吸收，而真实的场景变化仍会凑满连续 30 帧触发重扫（**敏感度不变，
只换参考量**）。`cam_af_start()`/`cam_af_wobble_start()`/平坦分支清零重新播种；af 行新增 `ref=%u`。
顺手修掉 `cam_af_metric()` 上方那段与代码相反的过时注释。

**★区分度 A/B（`out/re/zz_afae.sh`：曝光摆动、场景不动： 正是用户现场）**：
关键是 `ae_target` 与 AE 内部测量同为 0..1000 尺度，暗房实测 ≈59 ⇒ **低目标必须低于它才会变暗**，
定案 `TLOW=30/THIGH=4000`（第一版用 200/4000，因为都高于 59 ⇒ 只有"要更多光" ⇒ 画面全程不动 ✗）。
同激励 6 循环 ≈72 s：

| 构建 | `scans` | 镜头 | `low` |
|---|---|---|---|
| v2 基线（修复前） | **+4 次重扫** ✗ | `896 → 0 → 128`（停在更差位置） | 167 |
| 新版（修复） | **+0** ✓ | `448` 不动 ✓ | 0 |

**静态场景 90 s 那条腿不具区分度**（两个构建都 +0 次重扫，暗房 AE 已顶格）：只能证明"没退化"。
构建：**919 416 B**、md5 `66c2056d2eaffa260a5a21ff7bd7c6ad`；设备留底 `/root/cam_cap_v2.ko` 可随时回退。
细节见 [docs/V4L2_CAMERA.md](V4L2_CAMERA.md) §22。

**★修复版的收尾三关**：① **真重启** ⇒ `registered : 1` / `loaded : 1`、`source: 4000x3000`、`output:
2000x1500 YUYV, bin 2`、实拍 `timing fps=33.29`、crashes 0；② **默认栈长跑 6 分钟**（`zz_soak.sh 12000`）
⇒ 12 000 帧 / 364.1 s = **32.96 fps**、`dist` clean 11 740 / late 153 / slip 105 / **lost 2**、
**`scans` 全程 = 1（0 次额外重扫）**、`wobbles=6` 每次 `held pos=192`（镜头没动）、温度 49.9 → 50.6 °C、
MemFree 9.41 → 9.24 GB、crashes 0；③ 相机仓 **9fa42e8** / 内核 **fbadb857e208** 已推送 ✓。
（工具坑：`zz_reboot_check.sh` 是**主机侧**脚本，推到设备上跑会误报 `STILL DOWN`，已加守卫。）








## 26. ★★ 2026-10-09 凌晨 XV：**帧间隔直方图的桶改成相对标称周期**

- 症状：用厂商 VTS 的 30 fps 模式（normal_video 4000×2256，周期 33.33 ms）推 80 帧，`dist` 报
  `clean(<32ms)=3 late(32-40ms)=77` ✗： 而同一时刻 `timing fps=30.03 period=33290us`、`avg fps=30.35`，帧率明明是满的。
- 根因：四个桶是**绝对值**，当时按我们缩短过 VTS 的预览模式（VTS 3300 ⇒ 30.2 ms）定的；一换成厂商 VTS 的 30 fps 模式（33.33 ms），
  健康帧就整批落进 `late(32–40 ms)`。
- 修法：`cam_per_hist_add()` 改成按标称周期分档： `nom = 100000000 / cam_mode_fps`（10 M / `fps_x100` = 周期 µs），
  判据 `us*100 < nom*115`（clean）/ `< nom*160`（late）/ `< nom*220`（slip）/ else（lost）；缺失 `cam_mode_fps` 时退回 30500 µs；
  `dist` 行末尾打印 `nom=%uus`；桶自动跟随 `cam_mode_geometry()` 设的当前模式（`VIDIOC_S_FMT` 或开机默认模式）。
- A/B（`out/re/zz_dist.sh`，各 80 帧）：旧构建 `clean=3 late=77` ⇒ 新构建 **`clean=80 late=0 slip=0 lost=0 nom=33333us`** ✓；
  预览模式新构建 `clean=79 late=0 slip=1 lost=0 nom=30066us`（那次 slip 是真实的 1.6–2.2× 抖动）。
- 口径提醒：`lost` 现在要 ≥2.2× 标称周期才计，30 fps 模式下 ≥73 ms 才算： 判 4K60 那种稀疏 hiccup 要看 `timing period`。
- 构建：919696 B，md5 `f7d3a4792a52ea2068302193cf9863c5`；唯一告警是既有的 `camcap_info_read` 栈帧 2272 B（16 KB 内核栈上无害）。

追加（同晚，2026-10-09 01:35，`out/re/zz_matrix.sh`，S_FMT 切换、不重载）：

| 模式 | 标称 | `timing` fps | `avg` fps | clean/late/slip/lost |
|---|---|---|---|---|
| preview bin2 2000×1500 | 30066 µs | 33.06 | 32.71 | 97/1/2/0 |
| normal_video 4000×2256@30 | 33333 µs | 29.96 | 30.30 | **100/0/0/0** |
| custom3 4000×2256@60 | 16661 µs | **60.15** | 53.03 | 130/6/12/3 |
| custom2 1920×1080@120 | 8327 µs | **117.57** | 116.78 | 288/10/0/3 |
| hs_video 1920×1080@240 | 4165 µs | **182.14** | 143.01 | 101/77/84/39 |
| preview bin1 4000×3000 | 30066 µs | 33.27 | 32.57 | 56/2/2/0 |

- `hs_video` 的 240 fps **打不满**：`arm=4225 µs`（≈ 标称 4165 µs）说明传感器在跑 240，但整帧转换 4.0 ms + 取帧开销 ~1.3 ms ⇒ 实测 182 fps。
- `slip`/`lost` 逐次运行都在变（custom3 此前 600 帧全清、这次 3 个 lost）⇒ 只看 `timing`/`avg` 的 period。
