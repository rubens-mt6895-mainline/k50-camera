# ISP 可行性评估（K50 / MT6895 / 主线 7.2.0）： 结论：**接不上**

> 文档目的：回答 m03706 的后半句「弄完后看看能不能接上 ISP」。
> 结论先行：**在主线内核上无法把 MT6895 的 ISP（imgsys / ISP7.1）接起来**，原因是三条互相独立的硬证据（§2 §3 §4），
> 它们各自都足以否决；不是"还没调通"，而是"路不存在"。
> 我们现在跑的是**另一条硬件通路**：SENINF → CAMSV1（简单通路）→ DMA，色彩处理由 `cam_cap.ko` 在 CPU 上做（§6）。
> 最后 §7 给出在**不碰 ISP** 的前提下还能把画质做到什么程度。

---

## 1. 先把"ISP"这个词在这颗 SoC 上说清楚

MT6895 的相机数据有**两条**下行通路（[dt/hyperos_fdt.dts](../dt/hyperos_fdt.dts) 里的节点名即架构图）：

```
IMX582 ──MIPI CSI2(4 lane)──► SENINF(csi port2 → intf4 → mux1)
                                   │
                     ┌─────────────┴──────────────┐
                     ▼                            ▼
              CAM_MUX 3                      CAM_MUX 0/1/2
              → camsv1@1a110000              → camsys_rawa/b/c
              （"SV" = simple video）          → cam2mm0/1 GALS 桥
                     │                            ▼
                     ▼                     imgsys / ISP7.1 @15000000
              IMGO DMA → DRAM               （真正的 ISP：OB/ LSC/ AWB/ AE/
              【我们走的是这条】               demosaic/ CCM/ gamma/ YUV …）
                                             │
                                             ▼
                                     imgsys_fw / CCU 协处理器
                                     isp_main / isp_dip1 / isp_ipe 电源域
                                     ispdvfs + GCE(CQ) + larb13/14/25/26
```

* **CAMSV** 是"简单通路"：只有一个 TG 时序发生器 + 打包(PAK)+ 直接 DMA，**没有任何画质处理单元**。
  厂商只用它做低功耗/快速抓帧、MRAW 旁路和视频小流。
* **ISP（imgsys）** 才是"全通路"：RAW→YUV 的全部算法（黑电平、LSC、去马赛克、AWB/AE、CCM、gamma、NR、锐化…）都在这里，
  而它的寄存器序列**不是 CPU 直接写的**：由 **CCU 协处理器的固件**通过 CQ 触发（证据见 §4）。

"接上 ISP" = 让数据走下面那条支路，并且把 imgsys 那套电源/时钟/桥/固件全部拉起来。

---

## 2. 证据 A：主线内核里**根本没有 MTK ISP 驱动**（也没有 IMX582 驱动）

在编译树 `${KDIR}`（git HEAD `0b8dd2e87b3d5b9288089ba79922e2391f7e648b`，我们的内核就是它编的）里逐项查过
（[scripts/wsl_isp_recon.sh](wsl_isp_recon.sh)、[scripts/wsl_tree_check.sh](wsl_tree_check.sh)）：

| 查什么 | 结果 |
|---|---|
| `drivers/media/platform/mediatek/` | 只有 `jpeg`、`mdp`、`mdp3`、`vcodec`、`vpu`： **没有 `isp/`** |
| `find drivers/media -iname '*isp*'` | 只命中无关驱动（`v4l2-isp.c`、`ti/omap3isp`、`raspberrypi/pisp`、`sti/bdisp`） |
| `.config` 里 `CONFIG_.*ISP` | **只有 `CONFIG_VIDEO_RCAR_ISP=m`**（瑞萨），没有任何 MediaTek ISP 选项 |
| 全树 grep `mediatek,mt*-isp` compatible | **零命中** |
| `seninf` / `camsv` 驱动源码 | **树里完全没有**（我们的 `cam_cap.ko` 是自己按寄存器写的） |
| `drivers/media/i2c/` 里的 IMX582/586 | **没有**（194 个 sensor 驱动里有 imx111/208/214/219/258/274/283/290/296/319…，就是没有 582/586） |

也就是说：**ISP 驱动、SENINF 驱动、sensor 驱动三样在主线里都不存在**。我们现在的成功是"绕开 ISP 自己写 CAMSV 通路"，
所以"再接上 ISP"不是配置问题，而是要凭空写出 ISP7 驱动。

---

## 3. 证据 B：厂商的 ISP 驱动**我们手里有完整代码，但装载不进去**（这不是"反编译难度"的问题）

`isp71_ref/` 里有两个**厂商 ISP 模块**，而且**代码是完整的**（不是被抽空的壳）：

```
mtk-cam-isp.ko          2 597 024 B   ELF64 aarch64 REL, not stripped
                                     BuildID sha1 48f77a6a0945524867ddf0b94b87eb6aa7dbfc13
                                     .text ≈ 807 KiB（文件偏移 0x1000–0xcae28）
                                     .rodata ≈ 124 KiB（0xcae28–0xe9f62，寄存器表/常量）
                                     导出/定义函数 718 个，未定义符号 315 个，12 个 .rela 段
mtk-cam-plat-mt6895.ko     13 880 B   平台数据（10 个函数）
```

模块自己声明的身份（`strings` 出来的 `alias=`）说明它就是要接我们这条硬件：

```
alias=of:N*T*Cmediatek,camisp        （= camisp@1a000000，见 FDT 11610 行）
alias=of:N*T*Cmediatek,cam-raw
alias=of:N*T*Cmediatek,cam-yuv
alias=of:N*T*Cmediatek,seninf-core   （= seninf_top@1a010000）
alias=of:N*T*Cmediatek,seninf
depends=mtk_ccu,mtk_sec_heap,gz_tz_system,mtk-cam-plat-util,mtk-icc-core,mmqos-common,
        v4l2-fwnode,imgsensor,mtk_ccd_remoteproc,system_heap,mtk-smi,mtk-smi-dbg,
        aee_aed,iommu_debug,ccd_rpmsg
```

**它装载不进去，有四层独立的阻断**（[scripts/wsl_isp_blob_check.sh](wsl_isp_blob_check.sh)、[scripts/wsl_isp_syms.sh](wsl_isp_syms.sh)）：

1. **vermagic 不匹配**：对方是 `vermagic=5.10.198-android12-9-gb80b558ee02f SMP preempt mod_unload modversions aarch64`，
   我们是 `7.2.0-g0b8dd2e87b3d-dirty SMP preempt mod_unload aarch64`。内核 `insmod` 直接拒绝；
   想强塞需要 `CONFIG_MODULE_FORCE_LOAD`，而**设备上这个选项是关的**（`rmmod -f` 也无效，见 CAMERA_NOTES §9）。
2. **modversions 不匹配**：对方是带 `modversions` 编的（每个导入符号带 CRC），我们的内核 **`CONFIG_MODVERSIONS` 未开**
   ⇒ 连"符号 CRC 校验"这一关都过不去（我们的内核里根本没有 `__crc_*`）。
3. **315 个导入符号里有 152 个在主线内核里不存在**（只有 163 个能对上）。缺的那 152 个分四类，每一类都不是"改个名字"能解决的：
   * **Android/GKI 专有**：`__cfi_slowpath`（CFI 间接调用检查）、`__tracepoint_android_rvh_*`、`android_rvh_probe_register`、
     `aee_kernel_warning_api_func` / `aee_is_printk_too_much`（MTK 异常引擎）、`__log_{read,write,post_read}_mmio`（GKI MMIO 日志）；
   * **TEE / 安全**：`KREE_CreateSession` / `KREE_TeeServiceCall` / `KREE_CloseSession`（MTK 的 TEE client API）、
     `gz_tz_system`（GenieZone TEE）、`dmabuf_to_secure_handle`、`mtk_sec_heap`；
   * **CCU 协处理器 / 固件**：`mtk_ccu_rproc_ipc_send`、`mtk_ccd_get_buffer*`、`ccd_rpmsg`、`mtk_ccd_remoteproc`；
   * **MTK 基础设施**：`mtk_smi_larb_ultra_dis`、`mtk_smi_dbg_hang_detect`、`mtk_iommu_register_fault_callback`、
     `mtk_icc_set_bw`、`mtk_mmqos_wait_throttle_done`、`dma_heap_*`（Android dma-buf heap）。
4. **即便把 1–3 全部暴力绕过**（我们做不到），5.10→7.2 之间 `struct device`/`v4l2_device`/`media_*` 等大量结构体与 API
   已经变了；这个模块嵌入的是 5.10 时代的结构体布局，装进去只会立刻 oops。
   （我们在本项目里**已经吃过一次这种亏**：早期因为编译树 `.config` 与设备不一致，`struct device` 差 8 字节，
   模块一装就在 `dma_alloc_attrs` 里崩了：见 `docs/CAMERA_CAPTURE_WORKING.md`。）

> ★ **顺带更正一条旧笔记**：CAMERA_NOTES 早期写过"`isp_ko.asm` 里所有 `bl` 目标都是 0 ⇒ 模块被抽空/不可用"。
> 那是**误读**。`.ko` 是**可重定位目标文件**，`bl` 到外部符号的位移本来就写 0，真实目标在 `.rela.*` 段里；
> `mtk-cam-isp.ko` 有 12 个 `.rela` 段、718 个函数、`.text` 807 KiB，代码是**完整**的。
> 它唯一的死因是上面 1–4（编译目标内核不同），不是"代码被抹掉"。

---

## 4. 证据 C：ISP 的寄存器序列**不由 CPU 写**，而是 CCU 固件 + TEE 安全通道

这是最根本的一条。`mtk-cam-isp.ko` 自己的日志字符串把它的工作方式说得很清楚：

```
get ccu proc pdev successfully / error: failed to find ccu rproc pdev
boot ccu rproc fail / error: ccu rproc_boot failed!
error: find mediatek,camera_camsys_ccu failed!!!
CCU trigger CQ. tg:%d cq_src:0x%lx cq_dst:0x%lx cq_addr = 0x%lx init_value = %d
after CCU trigger CQ. tg:%d cq_src:0x%x cq_dst:0x%x initial_value = %d
Sensor Secure CA
KREE_TeeServiceCall
```

即：

* 每一帧的 ISP 参数由内核塞进 **CQ（command queue）**，再由 **CCU 协处理器**去触发/搬运（`ccu_apply_cq` / `ccu_stream_on` / `ccu_hsf_config`）；
* 传感器初始化还要走 **"Sensor Secure CA"**（TEE 里的安全 TA）：静态链接 `KREE_*` + `gz_tz_system`；
* `camera_camsys_ccu` / `mw` 都在 FDT 里（`camera_camsys_ccu`、`camera_imgsys_ccu`、[dt/hyperos_fdt.dts:13074](../dt/hyperos_fdt.dts#L13074)、
  `imgsys_fw@15000000`、`ispdvfs { compatible = "mediatek,ispdvfs"; }`）。

**这些东西我们一件都没有**：

| 需要的东西 | 我们手上的状态 |
|---|---|
| `mtk_ccu` / `mtk_ccd_remoteproc` / `ccd_rpmsg` 驱动 | 提取包里**没有**（只有 `clk-mt6895-ccu.ko`、`mmqos-*.ko`、`mtk-icc-core.ko`） |
| `imgsensor`（厂商 sensor 框架） | **没有** |
| `gz_tz_system`（GenieZone TEE） | **没有** |
| CCU / ISP 固件镜像 | 设备 `/lib/firmware` 只有 **19 个文件**（Wi-Fi/BT/触摸/屏幕/音频），**没有任何 ccu/isp/imgsys 固件**；`/vendor`、`/odm`、`/system` 分区**不存在**（这台机器跑的是纯 Debian） |
| remoteproc 实例 | `/sys/class/remoteproc` 里**只有 GPU 那个**（`13c40000.gpueb..8.0`），没有 ccu |
| 运行中的设备树 | 我们当前的 DT 里**连 `ccu` / `camisp` / `imgsys` / `camsys` 节点都没有**（我们是用 `cam_cap.ko` 直接对寄存器操作，绕开 DT） |

再加上 FDT 里那四条"厂商自己把 ISP 域按未用关掉"的节点：**`disable-unused-pd-isp_main` / `isp_dip1` / `isp_ipe` / `isp_vcore`**
（[dt/hyperos_fdt.dts:396-411](../dt/hyperos_fdt.dts#L396)）：说明连 HyperOS 自己在这台机器上也只启用其中一部分
（对应 `isp_main-supply = <0x54>`、时钟名 `isp-0/isp-1/ipe-0/dip1-0..3`、larb `camisp_l13/l14/l25/l26`）。

**要"接上 ISP"，实际工作量 = 从零写一个 ISP7.1 驱动（imgsys_fe + imgsys_fw + GCE/CQ 编程 + cam2mm GALS 桥 + 4 个 MTCMOS 域
+ 约 50 个时钟 + DVFS/regulator + larb13/14/25/26 的 IOMMU 域 + imgsys 中断）+ 逆向 CCU 固件协议 + 拿到 TEE 里的签名 TA。**
这不是本次移植的余量工作，而是另一个量级、且最后一步可能被**安全启动/签名固件**彻底堵死的项目。

---

## 5. 一句话对照表

| 问题 | 答案 |
|---|---|
| 主线有 MT6895 ISP 驱动吗？ | 没有。也没有 SENINF/CAMSV 驱动，也没有 IMX582 驱动。 |
| 厂商 ISP 驱动能装吗？ | 不能。vermagic 不同 + modversions 不匹配 + 152 个符号缺失 + 5.10↔7.2 ABI 已变。 |
| 就算装上了，能跑吗？ | 不能。它依赖 CCU 固件、TEE（`KREE_*`/GenieZone）和签名 TA，这三样我们都没有。 |
| 有固件/分区能捞吗？ | 设备上是纯 Debian：`/vendor`、`/odm`、`/system` 不存在，`/lib/firmware` 里没有任何相机固件。 |
| 那现在拍到的画质是怎么来的？ | CAMSV 简单通路 + **`cam_cap.ko` 里我们自己写的软件色彩管线**（§6）。 |
| 结论 | **ISP 接不上；但相机可用，且是"软件 ISP"在替它干活。** |

---


> **⚠️ 更正（2026-10-07 实测）**本文 §6 记录的曝光/增益上限是**错的**：
> 曝光 `0x0202` 线性有效到 0x6000 以上、模拟增益 `0x0204` 只有低 10 bit 有效（`0x0100`..`0x03f0` ≈ 0.5×..4.9×）、数字增益 `0x020e` 是干净的线性倍率。
> 真机测得的曲线与用法见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §9.2。

## 6. 我们现在实际在用的"软件 ISP"

`src/cam_cap.c` 的内核侧管线（每帧 ~18 MB RAW12 读进来，出 2000×1500 YUYV）：

| 阶段 | 实现 | 位置 |
|---|---|---|
| 12-bit 解包 | 3 字节 → 2 像素（`px0=b0|((b1&0xf)<<8)`，`px1=(b1>>4)|(b2<<4)`） | `cam_px_even/odd` |
| 2×2 binning | 4 个同色/邻色样本合 1（等价于 4× 光通量），4000×3000 → 2000×1500 | `cam_v4l2_convert` |
| 黑电平 | `v4l2_black`（默认 248，实测暗场 240–248） | `cam_lut_build` |
| 白平衡 | `wb_r_q8` / `wb_b_q8` 两个 Q8 增益（默认 1.03× / 2.40×，灰世界标定） | `cam_lut_build` |
| 线性预增益 | `v4l2_gain_q8`（默认 768 = 3.0×） | `cam_lut_build` |
| 色调曲线 | `int_sqrt(x<<16)` ⇒ **x^0.5**（不用 libm），clamp 255 | `cam_lut_build` |
| RGGB 反马赛克 | R=偶行偶列；G=偶奇/奇偶均值；B=奇行奇列（相位有双重证据，见 CAMERA_CAPTURE_WORKING §7.1） | `cam_v4l2_convert` |
| 色彩空间 | BT.601 **全范围** YUYV 4:2:2（与驱动声明的 `V4L2_QUANTIZATION_FULL_RANGE` 自洽） | `cam_v4l2_convert` |
| 方向 | FLIP180 **在反马赛克之后**对成品 YUYV 做（先转 Bayer 会把 RGGB 静默变 BGGR） | `cam_yuyv_flip` |

它**没有**（ISP 才有）：镜头阴影校正 LSC、自动曝光/自动白平衡闭环、CCM（色彩矩阵）、去噪、锐化、3D/2D NR、
局部色调映射、以及 14-bit HDR 合成。所以画质是"能看清"级别，不是"手机拍照"级别。

另外两个硬限制（硬件给的，不是算法能救的）：
* **曝光积分上限 ≈ 16 ms**（`0x0202 = 0x0380`，再大截断）：室内暗光下这是主要的噪声来源；
* **模拟增益上限 `0x0204 = 0x0300`**（写 `0x0f00` 会被硬件截回 `0x0300`，`0x3f00` 反而回退）。

---

## 7. 不碰 ISP，还有哪些"把画质拉近一点"的现实选项（按性价比排序）

1. **给驱动加 AE/AWB 闭环**（最值得做）：`cam_cap_v4l2` 线程已经在每帧后拿到 YUV，可以算平均亮度 → 反查
   `0x0202/0x0204/0x020e` 写回传感器；算 R/G/B 均值 → 调 `wb_r_q8/wb_b_q8`。
   这样"暗房间 vs 亮窗户"都能自动适应，Cheese 的观感会有质的变化。传感器 I²C 就在驱动的同一条总线（bus 10，0x10）上，容易。
2. **暴露 V4L2 用户控件**：把 `v4l2_gain_q8` / `wb_*_q8` / black / 曝光时间挂成 `V4L2_CID_*`（`v4l2_ctrl_new_std`），
   让 `v4l2-ctl -c brightness=…` 和 GUI 应用能调：`cam_cap.c` 已经引了 `<media/v4l2-ctrls.h>`。
3. **全分辨率模式**（`out_width/height = 4000×3000` 或 4000×1500 裁切）：细节明显更多，代价是 CPU 转换时间上升（≈4×），
   帧率掉到 ~2 fps；可以做成一个模块参数。
4. **更好的色调曲线**：现在只有 x^0.5。可以换成"黑电平 → 分段 gamma + 轻微 S 曲线"，并加一个简单的 3×3 CCM
   （用色卡标定一次即可），肤色会比现在准。
5. **降噪**：在 2×2 binning 时顺便做一次"相邻帧平均"（把上一帧 YUV 按 1/4 权重混进来）：最便宜的有效降噪，
   代价是轻微拖影。对暗光静态场景收益很大。

> 这些都**不依赖 ISP**，也不需要重编内核（只需重编 `cam_cap.ko`）。

---

## 8. 参考脚本与证据来源

| 脚本 | 作用 |
|---|---|
| [scripts/wsl_isp_recon.sh](wsl_isp_recon.sh) | 主线树里找 MTK ISP / seninf / camsv / imx582（证据 A） |
| [scripts/wsl_tree_check.sh](wsl_tree_check.sh) | 从设备 config 反向验证树是完整的（排除"树被裁剪"的误判） |
| [scripts/wsl_isp_blob_check.sh](wsl_isp_blob_check.sh) | `mtk-cam-isp.ko` 的 ELF 头 / vermagic / 函数与符号计数（证据 B） |
| [scripts/wsl_isp_syms.sh](wsl_isp_syms.sh) | 315 个导入符号 vs 我们 `Module.symvers` 的 16 982 个导出：163 满足 / 152 缺失，并按类列出（证据 B3） |
| [scripts/wsl_isp_blob_size.sh](wsl_isp_blob_size.sh) | 段布局 + `depends=` + CCU/TEE 字符串（证据 C） |
| [scripts/zz_isp_fw.sh](zz_isp_fw.sh) | 设备侧：固件目录、remoteproc、DT 节点、分区（证据 C） |

相关文档：[docs/CAMERA_CAPTURE_WORKING.md](CAMERA_CAPTURE_WORKING.md)（CAMSV 抓帧全流程）、
[docs/V4L2_CAMERA.md](V4L2_CAMERA.md)（`/dev/video0` 与相机软件）、[docs/CAMERA_NOTES.md](CAMERA_NOTES.md)。
