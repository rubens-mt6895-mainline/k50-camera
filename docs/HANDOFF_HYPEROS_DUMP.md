# 移交说明：K50 主摄 HyperOS 工作态寄存器 dump（低费率 AI 可执行）

> 背景：K50(Rubens/MT6895) 主线 Linux 相机移植。主摄 IMX582 在 csi-port2。
> 主线侧软件配置已做到与原厂 vendor 驱动**逐位一致**（传感器 236 个模式寄存器全部
> 回读验证、seninf/ANA/DPHY 全序列复刻、时钟/电源域全对），但 CSI2 包计数恒 0、
> 6 条 MIPI 物理 lane 的 FSM 恒为 1（只见 LP-11，无法区分"传感器没发"和"信号没到 pad"）。
> HyperOS 上相机全部正常 ⇒ 硬件链路完好 ⇒ **差异只能在 SoC 侧某个未复刻的状态**。
> 唯一手段：刷回 HyperOS，开相机取景，dump 工作态寄存器，与主线状态 diff。
>
> 详细技术史见 `${K50_REPO}\CAMERA_NOTES.md`（重点 2026-10-04 节）与 `project_memory.md` §9。

## 环境与路径（全部已验证存在）

| 用途 | 路径 |
|---|---|
| fastboot/adb | `${WINPATH}\刷机工具\UotanToolbox_Windows_x64\Bin\platform-tools\` |
| HyperOS ROM | `${WINPATH}\手机刷机包-备份\K50(Rubens)刷机文件\[正式版]HyperOS3.0.7.0_For_K50\` |
| HyperOS vbmeta | 同上 `images\vbmeta.img`（另有 vbmeta_system/vbmeta_vendor 不用动） |
| HyperOS boot(root) | 同上 `boot\boot_magisk.img`（备用：`boot\boot_sukisu.img`，同样是有 root 的安卓 boot，二选一） |
| HyperOS vendor_boot / dtbo | 同上 `images\vendor_boot.img`、`images\dtbo.img` |
| HyperOS super | 同上 `images\super.img`（**一般不用刷**，当前 super 仍是 HyperOS 的） |
| 主线恢复三件套 | `${K50_REPO}\out_mainline_backup\mainline_{boot,vendor_boot,dtbo}_a.img` |
| Debian userdata | `${K50_REPO}\userdata_sparse.img`（8.2GB sparse，= 当前手机状态） |
| logstatus 工具 | `${K50_REPO}\logstatus_aarch64`（静态 aarch64 ELF） |
| 手机实验脚本备份 | `${K50_REPO}\phone_root_scripts_20261004.tar.gz`、`phone_cam_modules_20261004.tar.gz` |
| 串口脚本（adb 不通时用） | `${K50_REPO}\scripts\k50.ps1`（用法见文件头注释，COM 口自动探测） |

**手机当前状态**：Debian 正常运行，SSH 通（`ssh -i ~/.ssh/${K50_KEY} root@<IP>`，IP 随热点变，
本次是 ${K50_HOST}；如果连不上用 k50.ps1 串口进）。传感器未出流、无危险状态。

**整个流程全程可回滚，但按顺序做，不要跳步。**

---

## 阶段 1：刷 HyperOS（约 15 分钟）

1. 进 fastboot：`adb reboot bootloader`（Debian 里先 `ssh ... "adb reboot bootloader"` 不行的话
   用串口 `k50.ps1 -Cmd "reboot bootloader"`；手机已 root，`reboot bootloader` 直接可用）。
2. `fastboot devices` 确认连上。
3. 刷 HyperOS 四件套（**必须是同一组匹配镜像，slot a**）：
   ```
   fastboot flash vbmeta_a     <ROM>\images\vbmeta.img --disable-verity --disable-verification
   fastboot flash boot_a       <ROM>\boot\boot_magisk.img
   fastboot flash vendor_boot_a <ROM>\images\vendor_boot.img
   fastboot flash dtbo_a       <ROM>\images\dtbo.img
   ```
4. **清 userdata**（Debian 的 ext4 与 HyperOS 加密不兼容，不清会 crash-loop）：
   ```
   fastboot -w
   ```
5. `fastboot reboot`。首次开机会进 MIUI 开机向导。

## 阶段 2：用户配合（唯一需要人的地方）

请用户在手机上：
1. 跳过/完成开机向导（能到桌面即可，不需要联网激活全部）。
2. 开发者选项：设置 → 我的设备 → 全部参数 → 连点"OS 版本"7 次。
3. 开启 USB 调试，插着 USB 线时允许电脑调试授权。
4. 完成后告诉执行者"好了"。

验证：`adb devices` 出现设备 + `adb shell` 能进。

## 阶段 3：抓工作态 dump（核心任务，全部只读！**禁止向 HyperOS 写任何寄存器/文件**）

1. 确认 root：`adb shell su -c id`（boot_magisk 自带 Magisk root；若刷的是 boot_sukisu.img 则是 KernelSU/SukiSU，授权方式类似，弹出授权框让用户点允许）。
2. 开相机取景（后台保持取景）：
   ```
   adb shell am start -a android.media.action.STILL_IMAGE_CAMERA
   ```
3. **取景运行中**依次抓取（每条都存到 `${K50_REPO}\hyperos_workstate\` 下）：
   ```
   adb shell su -c "ls -R /sys/kernel/debug/mtk_cam_dbg/" > mtk_cam_dbg_tree.txt
   adb shell su -c "for d in /sys/kernel/debug/mtk_cam_dbg/*/; do echo == $d; cat $d*; done" > mtk_cam_dbg_all.txt
   adb shell su -c "ls /sys/kernel/debug/ | grep -iE 'seninf|csi|dphy'" > dbgdirs_seninf.txt
   # seninf 自己的 debugfs（若有）全部 cat 下来
   adb shell su -c dmesg > dmesg_preview.txt
   adb shell su -c "cat /sys/kernel/debug/clk/clk_summary" > clk_preview.txt
   adb shell su -c "cat /sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_mtk_v2/pinmux-pins" > pinmux_preview.txt
   ```
4. **logstatus**（seninf 驱动的寄存器全 dump，走内核打印，dmesg 收）：
   ```
   adb push logstatus_aarch64 /data/local/tmp/logstatus
   adb shell su -c "chmod +x /data/local/tmp/logstatus"
   # seninf 是 v4l2 subdev，遍历节点试：
   adb shell su -c "ls /dev/v4l-subdev* /dev/v4l2-subdev* 2>/dev/null"
   adb shell su -c "for n in /dev/v4l*-subdev*; do echo == $n; /data/local/tmp/logstatus $n; done" > logstatus_all.txt
   adb shell su -c dmesg > dmesg_logstatus.txt
   ```
   （logstatus.c 在 ${K50_REPO}\ 可看参数用法；二进制已静态编译好。）
5. **物理寄存器 dump**（如果 `/dev/mem` 存在且可读）：
   ```
   adb shell su -c "ls -la /dev/mem"          # 多半不存在，不存在就跳过本步
   adb shell su -c "busybox devmem 0x1a014adc" # 试探；busybox 可用 magisk 自带
   ```
   若可用，dump 两段（每段 0x20000，4 字节步进，写成 `地址 值` 文本）：
   - seninf base：`0x1a010000 ~ 0x1a030000`
   - ana-rx：`0x11c80000 ~ 0x11ca0000`
   dump 脚本建议用 `while` 循环 + busybox devmem，一次一段，别写 py（Android 上没有）。
   **重点核对地址**（主线侧已知配置，diff 用）：
   - ctrl 口2 = 0x1a014200；csi2 口2 = 0x1a014a00（PKT 计数器 +0xdc，DBG_CTRL +0xe0）
   - ANA A = 0x11c88000、ANA B = 0x11c89000、DPHY_TOP = 0x11c8a000（LANE_EN +0x00、LANE_SELECT +0x04、FSM +0x30/+0x34）
   - seninf top = 0x1a010000（+0x68 = TOP_PHY_CTRL_CSI2）；mux 口2 = 0x1a014f00；cam_mux = 0x1a010400 起 23 个
6. 再抓一份**非取景**（相机关掉后）的 mtk_cam_dbg + dmesg 作对照（可选）。
7. 把 hyperos_workstate\ 目录全部带回（或至少 mtk_cam_dbg_all.txt / logstatus_all.txt / dmesg_* / clk_preview.txt）。

## 阶段 4：diff 与恢复（做完抓取立刻恢复，不要在 HyperOS 里停留）

**diff 要点**（有 dump 后分析）：
- 主线侧参考值（v17 运行后）：LANE_SELECT=0x80413002、LANE_EN=0x0F01、ANA_0 应有 CKSEL bits8-10=1+bit14、
  csi2 EN=0xF、top 0x68 DPHY_EN=1。HyperOS 工作态里凡是**值不同**或**非零而我们为零**的，都是嫌疑。
- 特别注意：FSM 寄存器(+0x30/+0x34)取景中应非 0x0101xxxx（那是 LP-11 静默态）；若 HyperOS 也显示
  某种"静止值"，说明 FSM 语义此前理解有误，重点转向 ANA/时钟差异。
- clk_summary 对比 seninf1-4_ck/camtg3_ck/cam_m_seninf_con 使能与频率。
- pinmux 对比 GPIO152（MCLK）等 camera 组。

**恢复主线**：
1. `adb reboot bootloader`
2. ```
   fastboot flash boot_a        ${K50_REPO}\out_mainline_backup\mainline_boot_a.img
   fastboot flash vendor_boot_a ${K50_REPO}\out_mainline_backup\mainline_vendor_boot_a.img
   fastboot flash dtbo_a        ${K50_REPO}\out_mainline_backup\mainline_dtbo_a.img
   fastboot flash userdata      ${K50_REPO}\userdata_sparse.img
   fastboot reboot
   ```
   （主线 vbmeta 未单独备份：上次恢复时直接刷三件套即可正常启动；若启动失败，先
   `fastboot flash vbmeta_a mainline boot 备份里的 vbmeta` 或报告用户。）
3. 回 Debian 后（等 1-2 分钟，SSH IP 可能又变，连不上用 k50.ps1 查 `ip addr`）：
   ```
   scp -i ~/.ssh/${K50_KEY} phone_root_scripts_20261004.tar.gz root@<IP>:/tmp/
   scp -i ~/.ssh/${K50_KEY} phone_cam_modules_20261004.tar.gz root@<IP>:/tmp/
   ssh -i ~/.ssh/${K50_KEY} root@<IP> "cd /root && tar xzf /tmp/phone_root_scripts_20261004.tar.gz && tar xzf /tmp/phone_cam_modules_20261004.tar.gz"
   ```

---

## 踩过的坑（务必遵守）

1. **刷槽内镜像必须成组**：vbmeta+boot+vendor_boot+dtbo 四件一套，不许混搭。
2. **HyperOS 与 Debian userdata 互斥**：刷对方系统前必须 `fastboot -w`，否则 crash-loop。
3. **HyperOS 里绝对只读**：不 devmem 写、不改文件（上次在 Android 里误写过东西吃过亏）。
4. `adb reboot bootloader` 可用；BCB "bootonce-bootloader" 方案已验证失败，别用。
5. i2ctransfer 参数必须带 `0x` 前缀（裸 `09` 被当十进制）：回主线做实验时注意。
6. 串口是唯一兜底通道：adb/ssh 全挂时用 `scripts\k50.ps1`（COM 自动探测，COM9 曾用过）。
7. 取景必须**保持运行中**抓 dump（挂后台可能被系统杀掉，用 `adb shell "settings put system screen_off_timeout 600000"` 防熄屏，或 dump 期间反复 `input keyevent KEYCODE_WAKEUP`）。
8. 05:00 曾有定时关机，已取消；如发现 `atq`/timer 有新条目先 `shutdown -c`。

## 产出物清单（完成后交付）

- `${K50_REPO}\hyperos_workstate\` 全套 dump
- 一份 diff 报告：HyperOS 工作态 vs 主线 v17 配置的差异寄存器清单（地址/双方值/怀疑理由）
- 手机已恢复回 Debian（SSH 可连、/root 文件已还原）

拿到 diff 报告后，回到主线复现差异寄存器 → 预期 PKT 开始计数 → 继续 mux 链 →
CAMSV DMA raw 抓帧 → cam_view 显示（Route A 后半段计划见 CAMERA_NOTES.md）。

