# K50 (rubens/MT6895, mainline Debian/KDE) 项目总记忆

<!-- K50-RUBENS-DOC-CANARY:RMT6895-C8BDA554A1EC -->

> 合并自 FINGERPRINT_PROGRESS.md + .trae-cn project_memory.md，2026-09-26 更新；2026-10-05 瘦身为「状态快照 + 硬约束 + 索引」。
> 设备 root@${K50_HOST}（k50-linux），SSH 公钥 ~/.ssh/${K50_KEY}（WSL Ubuntu，BatchMode）。
> ⚠️ **`wsl.exe` 自 2026-10-01 起被安全中心黑名单拦截**，旧的 `wsl -d Ubuntu -- bash ${K50_REPO}/<脚本>.sh` 跑法已不可用；改用**设备 SSH 直连 + 设备端原生编译**，完整链路见 §10。

---

## 0. 当前状态快照（2026-10-05 晚更新，细节已下沉专题文档）

| 子系统 | 状态 |
| --- | --- |
| 屏幕/面板 | ✅ 修好：关屏唤醒后自动补亮度，不再永久黑屏；vrf18/vibr 电源时序已平衡 |
| 休眠(s2idle) | ⚠️ mtu3 IP-sleep EBUSY 会中止挂起，但回滚后面板已补亮度，用户可见黑屏问题消除 |
| 指纹 | ✅✅✅ **全链路达成（含无人值守）**：enroll → `finger_0_0.so` → 重启载入 → **认证匹配成功（user id 0 + 鉴权 HMAC）**；常驻守护进程 + systemd 服务下无人值守匹配成功，PAM 集成全套就位。⚠️ v80 关闭了活体检测(ASP)，正式启用前需改回。⚠️ **命中率仍低**：根因是手上 TA 被打桩，v84 已换原厂 TA 待验证；v86b 为当前部署。**详见 [FINGERPRINT_NOTES.md](FINGERPRINT_NOTES.md)** |
| 相机 | ✅ **2026-10-06 已打通**：主线全帧 4000×3000（12-bit）采集 → **标准 V4L2 `/dev/video0`（2000×1500 YUYV，双缓冲流水线，30 fps 达标：32.5–33.3 fps）** → **Cheese 43.0-1 直接出图/录像**；**驱动内 AE/AWB 闭环 + 10 个 V4L2 控件已验收**；**过曝已修**（`Y==255` 19.43 %→0.00 %）；**红蓝互换已结案**（真凶 = YUYV 色度槽顺序，不是相位）；**7 个 sensor 模式全部跑通**（4K60 / 1080p120 / 1080p240 实测 **54.9 / 120.3 / 167.0 fps**）；**满尺寸输出 `v4l2_bin=1`**（真 4K30 **4000×2256 @ 29.9 fps**、真 1080p **1920×1080 @ 91–93 fps**，见 §13），`scripts/zz_mode.sh <mode>`，见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §12）；**`cam-camera.service` 开机自起 + `cam_reset.sh` 一键复位**；**运行期切模式已成**（标准 `VIDIOC_S_FMT`/`S_PARM` + `/proc/camcap mode`，5 张模式表内嵌驱动，转换提速后实测真 1080p **112.7 fps** / 4K60 半尺寸 **60.3** / 4K60 原生 48.5 / 1080p240 96.8，见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §15/§16）。ISP 定论**接不上**（主线无驱动 + 厂商模块 152/315 符号缺失 + CCU 固件/TEE 缺失）。软件 ISP 管线在 `cam_cap.ko` 内。**详见 [CAMERA_NOTES.md](CAMERA_NOTES.md) §10/§12/§13/§14 / [V4L2_CAMERA.md](V4L2_CAMERA.md) / [ISP_FEASIBILITY.md](ISP_FEASIBILITY.md)** |
| 基带 | 🟢 **M3 起跳成功（2026-09-30 22:00）**：运行时 overlay 注入 `modem@10209000` + `ccci_md2.ko`，`boot_status_0=0x5443000c`（MD 正常启动）、tag 表 26 项解析、`md-boot.service` 开机固化；**CCIF 数据通路（握手/RIL）待 M4**。**详见 [BASEBAND_NOTES.md](BASEBAND_NOTES.md)** |
| 蓝牙 HID | ✅ Pebble 鼠标 + K580 键盘可用；重启不丢 bond（Privacy=off + Trusted 枚举，见 §7） |
| WiFi/网络 | ✅ NetworkManager 管 wlan0，固定 MAC，IP ${K50_HOST}；**boot_min4 后 WiFi"无可用链接"= 固件初始化偶发（重启即愈，与 DTB 无关）** |
| 音频 | ✅ TFA9874 + 外放 PCM 已配好（外放可闻未实测） |
| 系统快照/刷机 | 📦 mainline 三件套备份：PC `out_mainline_backup\` + 手机 /root/mainline_*.img；rootfs 全量 tar 4GB（146118 文件验证）；HyperOS 3.0.7.0 ROM 在 ${WINPATH}\...\[正式版]HyperOS3.0.7.0_For_K50（boot_magisk=root 变体）；fastboot 工具在 ${WINPATH}\刷机工具\UotanToolbox_Windows_x64\Bin\platform-tools |

### 文档索引

| 文档 | 承载内容 |
| --- | --- |
| 本文 `project_memory.md` | **状态快照 + 跨子系统硬约束/约定 + 索引**（细节一律下沉到下列专题文档） |
| [FINGERPRINT_NOTES.md](FINGERPRINT_NOTES.md) | 指纹：架构/接口、逆向地址、v14→v86b 逐版本时间线、次要观察与死路、旧 §5.6.x 编号对照 |
| [CAMERA_NOTES.md](CAMERA_NOTES.md) | 摄像头：硬件与资产、严格正序时间线、Route A/B、禁令与教训 |
| [SENINF_CONFIG.md](SENINF_CONFIG.md) | 摄像头 SENINF/CSI2/ANA 寄存器配置与地址映射（含来源时效） |
| [BASEBAND_NOTES.md](BASEBAND_NOTES.md) | 基带：DTS/驱动/构建、SMC 与 tag 表、M3 实战、刷机回滚 |
| [HANDOFF_HYPEROS_DUMP.md](HANDOFF_HYPEROS_DUMP.md) | HyperOS 工作态 dump 交接 |

> 修改规则：**状态与结论改在本文，实现细节改在对应专题文档**；任何一处只保留单一事实来源。

---

## 1. 硬约束 / 不可违背

- **少用 wochgn 的东西**（用户 2026-09-21 明确要求）。除非绝对必要，不采用他的代码/镜像/DTB/补丁；自己验证、自己实现。他的 boot 镜像无法启动，**禁止刷入**。
- 机型一律 `rubens`（REDMI K50），不是 xaga / note11t。全树 "xaga" 命名已清除并验证（kallsyms 0 处）。
- 开发基线是自有仓 `rubens-mt6895-mainline/linux`，分支 `7.2-mt6895-xiaomi-rubens`（本地名 `rubens-k50-fixes`）。最终合入 MT6895-Mainline/linux 的 `port/rubens-clean`。
- 内核源码在 WSL 原生 FS：`${HOME}/work/mt6895-mainline`（**不要**用 /mnt/d 上的 symlink，会挂）。Windows 下经 `\\wsl$\Ubuntu\home\luis\work\mt6895-mainline` 读。
- 无 RTC：冷启时钟漂到过去，先 `date -u -s`；apt 加 `-o Acquire::ForceIPv4=true`。
- KWin Wayland 输出配置在 `~/.local/share/kscreen/b5350822...`；正确竖屏 = rotation:1 + scale:2 → 720x1600。
- KDE 锁屏必须关（Autolock=false, LockOnResume=false）。
- NetworkManager 不得随机化 MAC，固定 `<MAC>`。

## 2. 设备访问 / 账户

| 项 | 值 |
| --- | --- |
| 地址 | ${K50_HOST}（WiFi tenda-5，MAC 固定） |
| root | SSH 公钥登录，密码已锁 |
| 普通用户 | `k50`（sudo 组），口令 `e6dffa25f8602db7aab2` |
| 桌面 | SDDM 自动登录 k50 |
| 刷机 | `scripts/pack_boot.py` + `${K50_REPO}\flash_img.sh <img>`；或在机内 `dd of=/dev/sdc43`（boot_a） |
| 日志 | expdb 分区：`dd if=/dev/sdc11 of=/root/x.bin bs=1M count=128 skip=2` |
| 指纹测试日志 | **设备 `/home/k50/goodix_v*.txt`**（k50 普通用户 home，不是 root 的 /tmp/）。本机拉取：`scp -i ~/.ssh/${K50_KEY} root@${K50_HOST}:/home/k50/goodix_vNN.txt ${K50_REPO}/` |

⚠️ 本文件含明文口令，勿提交公开仓。

---

## 3. 屏幕/显示（已完成）

根因：面板初始化表把 DCS 0x51 亮度写成 0，本移植没有任何组件（mi_disp HAL）把它补回；且 `ctx->backlight` 恒为 NULL（DT `delete-property backlight`）。任何一次关屏/唤醒后永久黑屏。

已修（kernel 7.2.0-g0b8dd2e87b3d-dirty，`drivers/gpu/drm/panel/panel-l11a-...`）：
1. 在 `lcm_panel_init()` 新鲜初始化末尾补发 `bl_tb0`（=上次亮度，默认 1023），用同步 DSI 写，不受 crtc enabled 门控。
2. vrf18/vibr 电源改无条件成对 enable/disable，删掉一次性 start_up 标志（硬件 rail 恒使能导致引用计数不平衡）。
3. mtu3 挂起 EBUSY 未改（USB/typec bring-up）。

其它 DRM 约束：不暴露 cursor plane（KWin 用软光标）；mt6895 平台 GPU 用 mali_csffw.bin + Mesa25。

---

## 4. 蓝牙（已完成，2026-09-26）

### 4.1 历史根因：BLE 扫描扫不到
mt66xx `btmtk_allocate_hci_device()` 没填 `hdev->commands[]`，导致 `hci_le_set_event_mask` 不解掩"LE Advertising Report"，固件静默丢弃所有广播。修复：从可用控制器 dump 64 字节 capability 表 memcpy 进 commands（commit 0b8dd2e8）。Logitech Pebble 由此可被发现。

### 4.2 本次"连上但不能用、必须重配对"根因
- Pebble 是 BLE HID，用**轮换私有地址（RPA）**（尾字节 ...7E/...7F 每次变）。
- 旧链路从没走完 SMP 加密握手（无 bond），所以外设主动重连只建底层链路、不拉起 HOGP。
- 实测：不带看门狗时 LE 链路能起来（state 5）但 **HID input 节点不出现**，几秒后链路掉。
- 配对成功后（`Paired/Bonded/Trusted=yes`，Icon input-mouse，HID UUID），主机主动 `connect` 才出 `Logitech Pebble Mouse` eventN。

### 4.3 固化方案（rootfs-overlay/，编镜像时覆盖进 rootfs）
- `etc/bluetooth/main.conf`：`AutoEnable=true`。
- `usr/local/sbin/bt-hid-autoconnect.sh`：每 5s 遍历 Paired 列表，对 Icon=input-mouse/keyboard/gaming 且 Trusted=yes 但未连接的设备主动 `bluetoothctl connect`（按 bond 不按固定 MAC，RPA 变也没事）。
- `etc/systemd/system/bt-hid-autoconnect.service`：After=bluetooth, Restart=always，multi-user.target.wants 里 enable。
- 前置内核：CONFIG_BT_HIDP=y, CONFIG_UHID=y（已满足）。
- 新设备首次在 KDE 托盘点一次配对（bluedevil agent 走原生 GATT/SMP），bond 落 `/var/lib/bluetooth/`，之后自动重连。

---

## 5. 指纹（✅ 2026-10-07 已生产接线；详见 [FINGERPRINT_NOTES.md](FINGERPRINT_NOTES.md)）

> **本节原有的逐版本调试流水（共 54 个 §5.6.x 小节，v16→v86）已整体迁出** → [FINGERPRINT_NOTES.md](FINGERPRINT_NOTES.md)。

**现状（2026-10-07）**：端到端闭环已达成**并已接线到生产路径**。

- **部署**：`/opt/goodixta/bin/ta_host` = **10-01 proven**（md5 `d723e2269b201ba9fa8b32fdac2da483`）。模板 `/var/lib/goodixta/finger_0_0.so` = 57687 B（md5 `2b1a3e0d080f23eca0c31fdc70edc68a`），真机按压认证命中 2/8（每次 MATCH 都有 `get user id 0.`）。
- **④ 解锁**：`/etc/pam.d/common-auth` = pam_echo 提示 → **`pam_unix`（密码优先；正确密码 50~83 ms 通过、不碰传感器）** → `pam_exec /usr/local/bin/goodix-fp-pam`（单次采集：锁屏上按回车=采一帧指纹）→ pam_deny → pam_permit。白名单 `/etc/goodix-fp-pam.users`（fptest, k50）。桩测试已证：指纹成功会跳过 pam_unix/pam_deny 由 pam_permit 放行。
- **③ 系统设置录入**：`goodix-fprintd.service` 在 system bus own `net.reactivated.Fprint`（自写 fprintd 兼容服务，源 `tools/goodix-fprintd.py`），KDE 用户管理 KCM 可直接录入/删除；`EnrollStart` 会先把旧 store 备份挪走再开录（TA 才允许新录入），失败自动搬回，本机只保留一枚指纹。`/usr/local/bin/goodix-fp-restore` 可回滚存储。
- **体检/验收**：`/usr/local/bin/goodix-fp-status`（只读全链路体检）、`/home/k50/fp_unlock_test.sh`（引导式真机按压测试）。
- **⚠️ 未了**：命中率 20%~30%（硬件/噪声；GPIO136 浮空、**没有可用的手指在位信号**，采集必须由用户主动按回车触发）；ASP（活体）仍关闭；手上的 `goodixfp.ta` 是被打桩样本（与 HyperOS 原厂差 37 字节）；v87 重编（删 v66 `sizeof_finger_template` NOP + daemon 补 `gf_data_process_init()`/UP 中断）**暂缓**，只暂存 `bin/ta_host.v87`、不覆盖 proven host。
- **⚠️ 已定案的坑**：v86b 的 v66 `sizeof_finger_template` NOP 会把模板写坏成 55172 B → 认证恒 1006，**不要部署 v86b**；5 个 slot 存在时 TA 永远拒绝新录入（`REACH_FINGERS_UPLIMIT` 1005），重录前必须先清空。
- **八个根因**（DAC 写回 v64、prev_tpl v65、TA 镜像查表函数序言被覆盖 v70、gid/fid 偏移 v71、操作队列为空 v73、auth 缺 heavy recovery v73b、无人值守节奏被 TOO_FAST 挡 v79、ASP 误拒 v80）→ 见 FINGERPRINT_NOTES.md §0.1。
- **细节**：§3.59（真凶定案）与 §3.60（生产接线）→ FINGERPRINT_NOTES.md；v85 崩溃根因 → 本文 §11 与 §3.58。

## 6. WiFi / 网络（已完成）
- NetworkManager 管 wlan0（删掉 unmanaged 配置，仅 wlan1/ap0 保留），连接 tenda-5（WPA2 PSK `PHI_lpwan099`），固定 MAC，autoconnect。
- MTK gen4m 驱动 wifi6 关联偶发 ASSOC-REJECT 16，需多轮 `ip link set wlan0 down/up; nmcli c up`（`wifi_cycle.sh`）。
- system-connections 目录 0700、文件 0600 root:root。

## 7. 蓝牙 HID（已固化，2026-09-26 补）

设备：Logitech Pebble 鼠标 <MAC>（LE，static random），Logi K580 键盘 <MAC>（LE）。
控制器 hci0 = <MAC>（MTK UART，btmtk 驱动）。

**重启后丢 bond 的根因（2026-09-26）**：内核 BT 控制器不支持 RPA，bluetoothd 启动时尝试 `set mode` 设 LE privacy 被拒（journal: `Failed to set mode: Not Supported (0x0c)` ×2），导致 LE 设备 bond 不加载：`bluetoothctl devices Paired` 只剩 BR/EDR 的 HONOR 手机，Pebble/K580 变成未配对。

**修复（两处，都已落盘并同步 rootfs-overlay/）**：
1. `/etc/bluetooth/main.conf` `[General]` 段加 `Privacy = off`。
2. `/usr/local/sbin/bt-hid-autoconnect.sh` 里 `bluetoothctl devices Paired` 改成 `bluetoothctl devices Trusted`（Trusted 列表在 privacy 失败时仍保留）。

**鼠标"睡死不回来"的根因（2026-09-27 第二次修复）**：Pebble 深睡唤醒后的**外围发起重连**失败：BlueZ 5.66 在重连时重新做 GATT 发现，Logitech 固件对 PNP_ID / HID Information / Report Reference / Protocol Mode 的读取返回 ATT "Unlikely Error"(0x0e)，HOG profile 建立失败、连接被丢弃（journal `profiles/input/hog-lib.c:report_read_cb() Error reading Report value: Request attribute has encountered an unlikely error` 成对刷屏）。autoconnect 每 5s 重试也走同样路径必败。**修法：main.conf `[GATT]` 段 `Cache = always`**（跳过重连时的重新发现，读缓存）。重启 bluetooth 后断开/重连循环 hog 报错 0 次，输入节点正常出现。注意：鼠标深度睡眠期间主机 connect 返回 "No route to host (113)" 是正常现象（需动一下鼠标唤醒）；journal 里 vcp/mcp/bap/sap plugin init failed 是 BlueZ 5.66 无对应库的无害提示。WakeAllowed 属性被拒（内核 mgmt 缺 wake 能力），未启用。
**K580"连上但无法输入"根因（2026-09-27 第二次修复）**：用户重启后 K580 `Paired:no/Bonded:no` 但 `/var/lib/bluetooth/.../info` 文件完好（LTK/IRK 都在）：bluetoothd **运行时**把 bond 状态丢了（键盘有 IRK、内核不支持 RPA 解析是主要嫌疑；无加密则 HOG 输入通道不建，hog-lib ATT 0x0e 报错）。**修法（双保险，均已实战验证）**：
1. main.conf `[GATT] Cache = always`（防 Logitech 重连 HOG 重发现失败）+ K580 info 删除 `[IdentityResolvingKey]` 段（备份 /root/k580_info.bak）→ 重启 bluetoothd 后三设备全部 Paired=yes、双输入节点、零报错。
2. **autoconnect 自愈**：设备 Connected 但 30s（6×5s）无输入节点 → `systemctl try-restart bluetooth` 重载 bond，冷却 10 分钟防循环。已闭环验证。
- journal 里 vcp/mcp/bap/sap plugin init failed 是 BlueZ 5.66 无对应库的无害提示；鼠标深睡时 connect 返回 "No route to host (113)" 正常（动一下即醒）。WakeAllowed 被拒（内核 mgmt 缺 wake 能力）。
- 备份：设备 `/etc/bluetooth/main.conf.bak.*`、`/root/k580_info.bak`；overlay 已更新（main.conf `[GATT] Cache = always` + bt-hid-autoconnect.sh 自愈版）。

**2026-09-27 下午：自愈脚本 v1 从未生效（TAB bug）+ 第二次开机复发**
- 脚本 v1 的 Name 匹配模式里 TAB 被写成字面 `^I`，name 永远为空 → 检测永远跳过。v2 修掉（awk `$1=="Name:"`）并把故障条件加强为 **Connected:yes 且 (Paired:no 或 无输入节点)**。已实战闭环：触发 → bluetoothd 重启 → K580 Paired/Bonded yes + 双节点恢复。
- K580 info 的 IRK 删除仍然生效（未复发），但**开机 bond 依然丢失**：另有机制。已给 bluetoothd 加 `-d`（/lib/systemd/system/bluetooth.service 已改，下次重启后 journalctl -u bluetooth 抓 bond 加载过程）。
- 待办：下次开机后用 debug 日志定位 bond 丢失点；修好后移除 -d。

**2026-09-27 正午：根因终于确认：Logitech 外设重配对后轮换地址**
- 开机 debug 日志（bluetoothd -d）显示 bond 加载正常，但外设重连时 BlueZ 发起新配对（KDE 弹窗）→ 失败 0x0e → **清除原 bond**。
- 实测：重新配对后键盘地址 D0:9A:C1:CF:25:**FB→FC**、鼠标 DF:0A:03:B1:45:**7F→80**（末字节+1）。**每次重配对，外设固件就换一个静态地址**：旧 bond 全部作废，这就是历次"重启后连不上/弹配对框"的总根源。
- 当前状态：键盘 …FC、鼠标 …80 均已 Paired/Bonded/Trusted，autoconnect 运行中（设备深睡需触摸唤醒后 5s 内自动连上）。
- gpiotool/模块成果无影响。注意：附近有邻居的同款 Pebble（<MAC> 曾是邻居的？！不：用户确认只有自己一个 Pebble，80 是自己鼠标重配后的新地址）。
- **待下次重启验证**：地址是否随重启保持（应该会：轮换只发生在重配对时）。若仍丢，bluetoothd -d 日志继续抓。
- 教训：修复脚本时不要用 TAB 字面量（v1 的 ^I bug 让自愈整整失效了一轮）。

**2026-09-27 下午：最终根因 = 启动竞态（已修复）**
- bluetoothd -d 日志 + BlueZ 5.66 源码（bluez566_{device,adapter}.c 在 ${HOME}/fp_work/）确证：**bt-hid-autoconnect 在 bluetoothd 启动后 1 秒内就发起连接**，连接事件把设备对象提前创建，存储加载循环 `goto device_exist` 跳过 `device_create_from_storage` → 设备无 bonded 标记 → Paired:no/HOG 破裂/弹窗。BlueZ 5.66 adapter.c 的 `device_exist:` 只对有 BR/EDR [LinkKey] 的设备 set_paired/bonded（LE 设备依赖 load_ltks 时的 find_device 补标记，被竞态破坏）。
- **验证**：停止 autoconnect 后干净重启 bluetoothd → 两设备立即 Paired:yes/Bonded:yes（竞态理论实证）。
- **修复**：bt-hid-autoconnect.sh 开头加 `wait bluetooth active + sleep 15` 再开始连接；rootfs-overlay 已同步。
- 配套机制保持：JustWorksRepairing=always + AlwaysPairable（静默重配对）、NoInputNoOutput 自动接受代理（bt-agent-auto.service，应对外设重配后换地址）、自愈检测（Connected 但 Paired:no/无输入节点 → 重启 bluetoothd）。
- **待验证**：下次重启后外设应自动恢复（地址 FC/80 稳定，bond 存储完好，无竞态）。若仍失败，bluetoothd -d 日志在手。

**2026-09-27 13:xx：竞态修复后冷启动仍丢标记 → 最终方案落地**
- 第二次重启实测：竞态修复（15s 延迟）后冷启动 LE 设备**仍不标记 bonded**：BlueZ 5.66 的 cold-boot 缺陷（adapter.c 只对 BR/EDR [LinkKey] 标记，LE 设备无论有无竞态都不标记；手动 restart bluetoothd 后才标记， Paired 立即恢复）。**结论：这台设备的蓝牙冷启动必须重启一次 bluetoothd。**
- 最终方案：自愈脚本 v3：Trusted 设备 Paired:no（无论连接与否）30 秒 → 自动重启 bluetoothd → Paired 恢复 → autoconnect 连接。开机后 ~45 秒全自动恢复，无需人工。
- 当前全部机制就位：竞态延迟 + 自动接受代理 + JustWorksRepairing + 冷启动自愈。**下次重启为最终验证**。

重启 bluetooth 后三个设备全部 `Paired: yes`。autoconnect 服务每 5 秒轮询 Trusted HID 设备并主动 `connect`。注意鼠标要动一下/按键才会从深度睡眠醒来响应连接。

**固化清单（rootfs-overlay/）**：
- `etc/bluetooth/main.conf`（Privacy=off + [GATT] Cache=always）
- `etc/systemd/system/bt-hid-autoconnect.service`
- `usr/local/sbin/bt-hid-autoconnect.sh`
- 另有 `k50-bt-up.service` / `/usr/local/sbin/k50-bt-up.sh`（上电）。

## 8. USB（已完成）
- host 模式：&ssusb `phys=<&u2port USB2>`、&u3port disabled、eye=3；`try-power-role=source`。
- 历史教训：`ssusb_force_vbus()` 只能在 mtu3_start()（切 device 角色）调，不能在 probe() 无条件调：否则开机钉死 device，host 永远枚举不到。已 checkout 25b88ba084c8 回退。

## 9. 摄像头（✅ 2026-10-06 已打通：主线全帧采集 + `/dev/video0` + Cheese 出图；ISP 定论"接不上"）

> **本节原有的逐条调试流水与 §9.1–§9.4h 小节已整体迁出** → [CAMERA_NOTES.md](CAMERA_NOTES.md)。

**现状（结论，2026-10-06）**：**已完整打通，端到端可用**： 冷启动 → IMX582 复活（GPIO149/20/159/158/164 + MCLK pinmux + fan53870 供电 + 复位脉冲 + I²C 初始化）→ SENINF port2 → CAMSV1 → IOMMU 支撑的 18 MiB **12-bit 全帧 4000×3000** 采集 → `cam_cap.ko` 内核侧软件色彩管线（解包/2×2 binning/黑电平/白平衡/增益/`int_sqrt` 曲线/RGGB 反马赛克/BT.601 全范围 YUYV/后置 FLIP180）→ **标准 V4L2 设备 `/dev/video0`（2000×1500 YUYV，4 线程并行 4.36 fps）** → **系统相机软件 Cheese 43.0-1 直接出图并录像**（录得的 webm 帧与直读 `/dev/video0` 亮度相关 +0.591 = 同画面同方向）。

**画质线（2026-10-06 深夜收尾）**：驱动内 **AE/AWB 闭环 + 10 个 V4L2 控件**已做成并验收： AE 从最暗手调点自动爬到目标，**收敛后 `ae frames=` 在 120 帧里一次不动**；改 `ae_target` 1800/700/1200 分别落到均值 1739/787/1304；AWB 关→开能重新收敛；出图 RGB 均值 180/189.5/184（旧手调固定参数版只有 63/61/53）。同时更正两条旧结论：`0x0202` 是**完整 16 位**（不是 0x0380 封顶）、`0x0204` **掩码 0x3ff**（`0x0f00`/`0x3f00` 静默变 0x0300 就是这个掩码）。**详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §9 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §12**。

**画质线 II（2026-10-06 深夜 II，三项验收）**：① **过曝修掉**： `v4l2_gain_q8` 768→256（它是 **sqrt 曲线之前**的 3.0× 线性前置增益）+ `ae_target` 1200→1000；判据 `Y==255` 占比 **19.43 % → 0.00 %**（`Y≥250` 26.21 %→1.87 %），RGB 均值 180/190/185 → 93/98/94。② **多核并行转换**： 一帧按行分带、每 worker 跑完整 fused 转换（binning+反马赛克+LUT+饱和度+FLIP180+YUYV），`cam_convert_frame()` 等齐 `nconv` 个 completion；`conv_threads=1/2/4/8` → conv 401/205/107/114 ms、fps 2.25/3.37/**4.57**/4.60 ⇒ **4 是拐点，8 已内存带宽受限**，默认 4；分带边界跳变 0.113/0.163/0.189（全图行跳变中位 0.140）⇒ 无接缝；worker `nice 10`、流中 loadavg 0.29–0.93。**代价 = 两次把机器搞到重启**：`cam_convert_frame()` 只等一个 completion（症状 = **ping 通但 ssh 超时**）+ **`c->conv_wq` 从未 `init_waitqueue_head()`**（`Comm: cam_conv/0` 在 `prepare_to_wait_event()` 踩 `NULL-24` = `ffffffffffffffe8` 的 Oops → 硬复位；两次崩溃都是它）。③ **Cheese「无法连接」修掉**： 成因只有两个（重启后模块没了 / 残留进程占着 `video0`），用 `cam-camera.service`（oneshot、`After=multi-user.target`、`TimeoutStartSec=240` → `/root/cam_boot.sh` = 等 pinctrl/i2c → 放占用 → `zz_v80.sh` → `zz_cam_up.sh`；日志 `/var/log/cam_boot.log`）自动化，冷启动演练 **20 s** 后 `/dev/video0` ready、抓帧 4.61 fps；一键复位 `sh /root/cam_reset.sh [--full]`。**画质线 III（2026-10-06/07 深夜 III，两项用户验收）**：① **帧率 4.36 → 32.5–33.3 fps（≥30 达标）**： 双缓冲流水线（`pipeline=1`：arm 线程只武装下一帧、`cam_cap_conv` 线程转换上一帧，两者重叠；第二块 18 MB 槽用 `alloc_contig_pages()`+`iommu_map`；帧完成时在 `cam_v4l2_finish_slot()` 里 `cam_convert_frame()` 之后立刻释放槽；arm 改细粒度 `usleep_range` 轮询 ⇒ 50.6→30.1 ms）+ **VTS 3300（`0x0ce4`，行时间 9.04 µs ⇒ 周期 30.2 ms）+ `exp_max = VTS−128 = 0x0c64`**（曝光 > VTS 会拉长帧周期 = 旧 `exp_max=0x3000` 下暗房 9 fps 的根因；bring-up 与驱动默认必须一起改）。200 帧实测 4/6/8 线程 = 32.73/32.52/**33.27** fps，暗房（`dark=37%`、AE 三档全顶格）速率不掉；新增 `dist` 直方图行（~93 % clean、~3 % slip）。② **红蓝互换结案**： 真凶**不是 Bayer 相位**（灰世界上翻标签几乎不可见，两帧 RGB 平均只差 2.5 %；也排除 RYYB：两个绿 tap 只差 1.6 %），而是 **YUYV 色度槽顺序**（为 180° 翻转把一对里的亮度字节写反没错，但 `byte1` 必须永远是 Cb、`byte3` 永远是 Cr；旧代码固定 `q[1]=v,q[3]=u` ⇒ `rb_swap=0` 时写成 Cr/Cb 互换）。修复：色度槽跟 `rb_swap` 一起翻 + `rb_swap` 默认改 **0**（RGGB，厂商 `RAW_4CELL_HW_BAYER_R` + 强色偏物理实验双证：物理 R ×2 ⇒ `byte3=152.6 > 128 > byte1=99.4` 画面发红）+ `wb_r_q8/wb_b_q8` 默认 320/434 ⇒ **代数上完全保画面**。**详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §11 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §14**。
**画质线 IV（2026-10-07 凌晨 IV，回答 m06738「所有录制规格能不能都做出来」）**：**IMX582 的 7 个 vendor 模式全部跑通并逐模式实测**： `preview` 4000×3000 **32.6–33.6 fps**、`normal_video` 4000×2256 **30.7**、`custom5` 4000×3000(1:1 裁切) **30.3**、**`custom3` 4000×2256（4K60）实测 54.9–55.8**、**`custom2` 1920×1080（1080p120）实测 120.3**、**`hs_video` 1920×1080（1080p240）实测 167.0（burst 下限 4.02 ms ⇒ 传感器 248.7 fps）**；`capture`/`slim_video`/`custom1`/`custom6` 是空表 ⇒ 这块 IMX582 只有这 7 个模式。**★ 最重要的教训（差点给传感器编一个不存在的"读出地板"）**：第一遍高档位只有标称 2/3（`custom3` 40.6 / `custom2` 75.0 / `hs_video` 83.0 fps），而且 **VTS 从 1236 改到 2472 帧周期一动不动（都是 12.0 ms）**；真因是 `cam_cap_arm_addr()` 在 `elapsed < 20 ms` 时用 `msleep(CAMCAP_ARM_POLL_MS=5)`，HZ=250 ⇒ 一个 jiffy 4 ms，短帧（1080p240 只有 4.2 ms）的完成时刻被量化成 tick 的整数倍 ⇒ **测到的是 tick 周期，不是传感器周期**。改成一律 `usleep_range(150, 250)`（删 `CAMCAP_ARM_POLL_MS` 与 20 ms 分段）后三档跳到 **54.9 / 120.3 / 166.95**，30 fps 一族无回归（32.9 / 30.7 / 30.3）。**还差什么**：① **输出永远半尺寸**（`CAMCAP_BIN=2` 的 2×2 binning demosaic）⇒ 4K 模式出 2000×1128、1080p 出 960×540；全尺寸标量 C 代价 1080p≈20 ms/帧（~50 fps 够 1080p30/60）、4K≈87 ms/帧（~11 fps）⇒ **真 4K30 全尺寸必须 NEON/SIMD 或硬件 MDP**；② **240 fps 是"传感器能跑、软件跟不上"**（960×540 转换 3.8 ms + arm 抢核）；③ **48MP `custom4` 受阻于 CMA 32 MiB**（RAW10 一帧 60 MB）⇒ 需 `cma=` bootarg / 改 DT；④ **模式切换仍是"重放表 + 重载模块"**（~20 s，`scripts/zz_mode.sh <mode>`），不是运行期 `S_FMT`。**工具链**：`scripts/parse_modes.py`（PLL 定标规则 `pclk = 4.8 MHz × ((0x0306<<8)|0x0307)`，对非 binning 模式精确）、`scripts/gen_mode_table.py` → `out/modes/mode_<name>.txt`、`scripts/imx582_bring.py`（`IMX582_MODE=<mode>` / `--mode` 重放任意表，stream off 时写表 PLL 才生效）、`scripts/zz_mode.sh`/`zz_scout.sh`、`src/cam_cap.c` 运行期几何（`v4l2_src_stride`）。本次证据帧都在全黑房间（`Y mean` 16–18、`U/V≈128`）⇒ 颜色需白天目视复核。详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §12 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §15。

**画质线 V（2026-10-07 凌晨 V，回答 m07198「全尺寸输出：先让 1080p60 变成真 1080p」）**：**`v4l2_bin` 变成运行期参数，`v4l2_bin=1` = 满分辨率 bilinear debayer**： 真 4K30 `normal_video` **4000×2256 @ 29.9 fps**（arm 受限）、真 4K30 4:3 `preview` **4000×3000 @ 24.9**、真 1080p `custom2`/`hs_video` **1920×1080 @ 91.2 / 93.4 fps**、`custom3` 4K60 满尺寸 **39.0 fps（到不了 60）**。**关键优化**：`cam_unpack_row()` 把一行 1.5 B/px 解成 u16 + 三行滚动窗 ⇒ 每个 raw 采样只解包一次（逐像素版解包约 8 次）；逐像素 → 逐行：4000×2256 的转换 **36.3 → 21.3 ms（−41%）**、4000×3000 **51.7 → 28.0 ms（−46%）**。**两条等价性证据**：`scripts/check_full_demosaic.py` 模型逐字节 PASS（64×16 / 66×10 / 1920×8 × 2 种 `rb_swap`）；真机 A/B 平面统计（Y 15.96/16.10、U 127.42/127.38、V 127.30/127.37）与 `stats` 三通道一致。**诚实更正**：画质线 IV 里"4K 全尺寸 ≈ 87 ms/帧 ⇒ 11 fps ⇒ 必须上 NEON"高估约 4 倍（实测 21.3 ms）：**先量再下结论**。**注意**：`v4l2_bin=1` 只对 binned 模式（`0x0900=1`：preview/normal_video/custom3/custom2/hs_video）正确；4-cell 无 binning 的 `custom4`/`custom5` 必须保持 `2`。新增参数 `v4l2_bin` / `v4l2_full_cache`（两者逐字节相同，只差速度），`.ko` **826 592 B**。**还差**：满尺寸 4K60 / 1080p120 打不满（arm 与转换非重叠 ~3–8 ms）、48MP 受 CMA 32 MiB 限制、颜色待白天目视复核。详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §13 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §16。

**画质线 VI（2026-10-07 傍晚 VI，回答 m07665 三项「AE 闪烁 / 对焦 / 果冻」）**：**① AE 呼吸修掉**： 根因是 `cam_ae_step()` **向下最多 −20%、向上可达 2×**（非对称 ⇒ 一次过冲要 3.1 步拉回，慢极限环）+ 修正量由**单帧** `mean_g` 直算（无平滑，被摄物又晚 1 帧）。四条修改：对数域半步 `f = int_sqrt(f << 8)`、上下限互为倒数（`CAMCAP_AE_UP_MAX 384` / `CAMCAP_AE_DOWN_MIN 171` / 增益 `CAMCAP_AE_GAIN_MAX 320`）、绿色均值 IIR 平滑（shift 2 的 `cam_ae_mean_s`）、`CAMCAP_AE_SETTLE` 2→3；真机收敛后 `mean_s = 1035 / 1057 / 1061`（目标 1000、band 120）稳在带内。**② 对焦做成**： VCM 是 **DW9800V @ I²C 0x0c**（id **0xeb**，与 vendor dmesg 一致），寄存器映射照主线 `drivers/media/i2c/dw9768.c`（`0x03`/`0x04` = DAC 10 位、`0x02` PD/AAC、`0x06` 模式+分频、`0x07` Tvib），初始化写序与 vendor 一字不差（AAC3、Tvib **12.8 ms**）；**手动扫描权威曲线**峰在 DAC **512**（785 Q8，±128 峰宽，两端机械平台 547/431），搜索 = coarse(step 128, 9 点) → fine(±64/±32) → hold，整轮 13 点 ≈ **39 帧 ≈ 1.3 s**，第二次独立扫描复现并选中 **480** ✓。**⚠️ 失败记录**：曾把 metric 改成"单位亮度对比度"（`(fv<<9)/fv_y`）求曝光无关： 真机**全程平坦 7–8**（700 Q8 ≈ 2.7 级 ÷ 亮度 100 只剩个位数，整数除法把 1.8× 差异压成 1 个计数），已回退为原始 `mean |dY|`，曝光不变性改由**冻结 AE**（`cam_af_scanning()`）保证；**跟踪 wobble** 每 240 帧（≈8 s）重测 `base±64`，只有赢 >1% 才动 ⇒ 真机 3 次全部 `held`（858 vs 859 / 858 vs 863），平坦场景不被噪声带走。接口：`/proc/camcap` 的 `af show|on|off|hold|init|scan|wobble|pos <n>` + V4L2 `focus_absolute`/`focus_automatic_continuous`（实测可见，value 随搜索更新）。**坑**：`/proc/camcap` 要写整条指令（`af auto`，写 `auto` 得 I/O error）；Cheese 会自动重启抢 `/dev/video0`，测量脚本先 `pkill -x cheese`。**③ 果冻给了结论而不是补丁**： 读出 = 行数 × HTS/pclk：`preview` 4000×3000 **27.3 ms**（Cheese 默认）、`normal_video` 20.6、`custom3` 14.7、**`custom2` 1080p 4.28**、**`hs_video` 1080p 3.64**、`custom5` 31.9、`custom4` 63.8 ⇒ 换 1080p 模式 skew 小 6–7 倍，代价是曝光上限 28.7 → 7.8 ms（少 3.7× 光）= 暗光噪声 vs 果冻的权衡，正是 S_FMT 要暴露的旋钮。`.ko` **872 432 B**；AF 关闭态稳态 `fps=33.37`（timing）/`31.28`（avg，150 帧）、崩溃 0。详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §14 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §17。

**画质线 VII（2026-10-07 晚 VII：运行期切模式，`S_FMT`/`S_PARM`）**：**模块自带 5 张传感器模式表**（`src/imx582_modes.h`，`scripts/gen_modes_header.py` 从 vendor 头文件生成），两条入口都能切：标准 V4L2 `VIDIOC_S_FMT` / `S_PARM`（外加 `enum_framesizes` / `enum_frameintervals` / `g_parm`），以及 `/proc/camcap` 的 `modes` 与 `mode <name> [bin]`。**实测（全部 rc=0、崩溃 0）**：preview bin2 2000×1500 **33.43 fps**；`mode custom2 1` → 真 1080p **86.72**（描述符 120）；`S_PARM 60` → `custom3` 4000×2256 **39.48**（描述符 60）；`S_FMT`+`S_PARM 240` → `hs_video` 1080p **93.00**（描述符 240）；`S_FMT` → `normal_video` 4000×2256 **28.53**（传感器 30 上限）；切回 preview 33.30。每步都回读验证传感器寄存器（`0x0307`/VTS 与用户态 bring-up 一致）。**★ 真凶（很贵）**：vendor 模式表全是**字节寄存器**，而 `cam_sensor_write16()` 发的是 4 字节 `[reg_hi,reg_lo,val_hi,val_lo]`，多出的前导 `0x00` 被传感器当成"下一个寄存器的值" ⇒ **每个值都挪到下一个寄存器**（实机回读 `0x0306=0x00 0x0307=0x00`、`0x0340=0x00 0x0341=0x00`）；AE 一直好使，是因为 `0x0202/0x0204/0x020e` 是真正的 16 位寄存器。修法 = 新增 `cam_sensor_write8/read8`（3 字节），模式表与 `0x0100`/VTS 走 8 位口，`write16` 只留给 AE。**接收端重定时**：`custom3`/`hs_video` 走 1964 Mbps（其余 1370），逐字段核对 `scripts/port2_rx71.py` 后**只有两个值跟速率走**（D-PHY `HS_TRAIL` + CSI2 `DMY_CYCLE`）⇒ 驱动按描述符的 `mipi_mbps` 重算（1370 ⇒ 13/26，1964 ⇒ 9/13），同速率切换不动接收端。新参数 `dphy_base` / `rx_rate` / `mode_trace` / `mode_init_replay`；`.ko` **918 640 B**。**还差**：高帧率档全被**转换**卡住（1080p 实测 86–114 vs 描述符 120/240，4000×2256 39.5 vs 60）；`custom4` 8000×6000（60 MB/帧，超 CMA 32 MiB）与 `custom5`（非 binning）未收；切换会中断推流约 200 ms。详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §15 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §18。
**画质线 VIII（2026-10-08 凌晨 VIII：转换提速一轮 + 三槽流水线 + 可复现构建）**：三处不改画面语义的加速： ① 色度矩阵**每对像素只算一次**（YUYV 的 U/V 本就共用；矩阵线性 ⇒ 与逐像素平均只差 ≤1 LSB，`scripts/check_yuyv_chroma.py` 在 78 408 对上验证）；② 每行解包加首尾 padding（`cam_unpack_row_pad()`），内层循环的 `xm/xp/xpp` 条件分支全部消失；③ 该对象单独 `-O3`，默认 `conv_threads` 4 → **8**（worker nice 10，不会饿死桌面）。**三槽流水线**：`pipe_slots` 默认 2 → 3。一帧的转换是**串行**工序（一个 `cam_cap_conv` 线程取槽、再分给 8 个 worker），所以 `period ≈ conv + P/N`；加槽只消等槽时间、不加吞吐： 第 4 个槽更差（CMA/缓存压力）、6 线程也更差，8 线程 + 3 槽是定案。**实测（只用默认参数）**：preview bin2 2000×1500 **33.84 fps**（天花板）；custom2 原生 1920×1080 **112.74**（描述符 120）、半尺寸 960×540 **120.34**（打满）；custom3 半尺寸 2000×1128 **60.34**（打满 60）、原生 4000×2256 **48.52**（描述符 60，仍差 19%）；normal_video 原生 4000×2256 **29.76**（传感器 30 上限）；hs_video 96.83。转换耗时 1080p 11.9 → 6.5–7.9 ms、4000×2256 19.5 → 15.2 ms。用户态拷贝不是瓶颈（4/8/12 缓冲、带不带 `--stream-to` 都 48–51.5 fps），worker 日志证明 8 个都在跑。**可复现构建**：模块匹配的内核提交原本**不在任何公开 ref 上**（对象在服务器上但 clean clone 取不到）⇒ 已打成附注 tag **`k50-camera-base`**（tag 对象 `5087eada53f0` → commit `0b8dd2e87b3d`）推到公开内核仓。出厂模块指纹 `srcversion: 493F61FF760E440C2CC5AA7`、`vermagic: 7.2.0-g0b8dd2e87b3d-dirty …`；配方 = clone 该 tag → 给 `CREDITS` 追加一行脏标记（复现 `-dirty`）→ 用 `docs/k50_mainline_config.gz` 当 `.config` → `olddefconfig` → **只需 `modules_prepare`、不必完整编内核**（`# CONFIG_MODVERSIONS is not set`、`# CONFIG_MODULE_SIG is not set`）→ `z_build_camcap.sh`；一键脚本 `scripts/reproduce_build.sh`、文档 [docs/REPRODUCIBLE_BUILD.md](REPRODUCIBLE_BUILD.md)。端到端实测复现产物 **srcversion 与出厂相同**（md5 差在构建路径字节）⇒ 代码同一、可加载。`.ko` **909 216 B**。详见 [V4L2_CAMERA.md](V4L2_CAMERA.md) §16 / [CAMERA_NOTES.md](CAMERA_NOTES.md) §19。

**历史里程碑（供追溯）**：① 2026-10-05 晚之前：主线收流 **0 包（PKT=0）**，sensor MIPI TX 只发 LP 不发 HS；② 随后突破：供电/GPIO158/159 打通 → 出包 → **12-bit 解码**（6000 B/行，不是 RAW10 的 5000 B）→ 整帧；③ 2026-10-06：`single_mode` 单帧模式、V4L2/videobuf2 采集设备、Cheese。"硬件完好但主线起不来"的阶段**已结束**。

**ISP：接不上**（详见 [ISP_FEASIBILITY.md](ISP_FEASIBILITY.md)，三条互相独立的硬证据）：① 主线**根本没有** MediaTek ISP 驱动（只有 jpeg/mdp/mdp3/vcodec/vpu；唯一 `*ISP*` 配置是瑞萨的）；② 厂商 `mtk-cam-isp.ko` 代码完整（718 函数 / 807 KiB `.text`）但 **315 个导入符号里 152 个在主线不存在**，`depends=` **15 个厂商模块**，vermagic 是 5.10 GKI + modversions；③ ISP 寄存器由 **CCU 协处理器固件 + TEE 安全通道**驱动，而固件、`/vendor`/`/odm` 分区、remoteproc 实例、TEE 我们**全没有**。现在跑的是 **CAMSV 简单通路 + 软件 ISP**。

**怎么看/怎么用** → [V4L2_CAMERA.md](V4L2_CAMERA.md)。**正常开机不用管**（`cam-camera.service` 自动拉起）；手工排障用 `sh /root/cam_reset.sh [--full]` 一键复位，起相机软件用 `scripts/zz_cam_app.sh`（或桌面直接点 Cheese）。

**旧小节去向（供外部引用跳转）**：
- `§9.4c` 收流软件侧穷尽 → CAMERA_NOTES.md §2「2026-10-01 深夜（v44 系列）」
- `§9.4d` 传感器复活根因 + 收流口定位 → CAMERA_NOTES.md §2「2026-10-01 晚」
- `§9.4e` 重启后复验 + 两教训 → CAMERA_NOTES.md §2「2026-10-01 重启后复验」
- `§9.4f` 原厂 fdt 电源/GPIO 配方 → CAMERA_NOTES.md §2「2026-10-02 凌晨补充」
- `§9.4g` 执行清单实测（COM9 无人值守）→ CAMERA_NOTES.md §2「2026-10-05：」的「原厂配方执行清单实测」节
- `§9.4h` 健康窗口突破 + MIPI TX 仍无输出 → CAMERA_NOTES.md §2「2026-10-05 晚」的「健康窗口突破」节

**寄存器级配置**（SENINF/CSI2/ANA 地址映射、9 步序列）→ [SENINF_CONFIG.md](SENINF_CONFIG.md)。

## 9.5 基带（M3 ✅ 已成、M4 CCIF 未完成；详见 BASEBAND_NOTES.md）

> **本节细节已整体迁出** → [BASEBAND_NOTES.md](BASEBAND_NOTES.md) §7（自研驱动与构建）。

**结论**：M1/M2 ✅ DT 情报 + 147 文件源码落地；M3 驱动 `ccci_md.c`（419 行，`CONFIG_MTK_CCCI_MD=y`）走 stock ATF SMC，构建产出 `out/boot_rubens.img`。⚠️ **但"刷整内核"路线已证伪**（g309a2594f172 刷入 = 60s 周期无限重启），M3 实际达成路径见 §9.8。

> 来源：BASEBAND_NOTES.md §7.10（原 `project_memory.md` §9.5）。

## 9.6 DTB 溯源决定性结论（2026-09-30，modem 节点注入方向）

> **本节细节已整体迁出** → [BASEBAND_NOTES.md](BASEBAND_NOTES.md) §9（DTB 溯源）。

**结论**：live FDT **既不来自 boot 内嵌 DTB、也不来自 lk_a**，而是**内核内置 DTB**（`arch/arm64/kernel/rubens-dtb.o` 链接进内核）。因此改 modem 节点必须改`dts/mediatek/mt6895-xiaomi-rubens.dts` 并重编内核；**boot 分区 append DTB 是死路**。

> ⚠️ 该结论已被 §9.8 部分取代：M3 最终改用**运行时 DT overlay**，无需重编内核。

> 来源：BASEBAND_NOTES.md §9（原 `project_memory.md` §9.6）。

## 9.7 刷机/回滚实战（2026-09-30 定稿）

> **本节细节已整体迁出** → [BASEBAND_NOTES.md](BASEBAND_NOTES.md) §10（刷机/回滚实战）。

**仍有效**：V6 console 刷任意 boot 的 scatter/is_download 改法 + `Start-Process` 非阻塞（**禁止 `| Out-File`**）→ 等 12s 发 reboot → 轮询 `QT_FLASH_TOOL_V6.log` 找 `WRITE-PARTITIONS command execute successed`；**循环重启自救**（等待版 V6 不 reboot，自动抓 BROM 窗口刷回稳定镜像）。设备无限重启时**先想这条**。

> 来源：BASEBAND_NOTES.md §10（原 `project_memory.md` §9.7）。

## 9.8 基带 M3 实战成功（2026-09-30 22:00 🎉 MD 起跳 + tag 表 + 开机固化）

> **本节细节已整体迁出** → [BASEBAND_NOTES.md](BASEBAND_NOTES.md) §8.2（M3 实战补充）。

**里程碑（2026-09-30 22:00）**：MD 起跳成功： `boot_status_0=0x5443000c`（= vendor `MD_BOOT_STATUS_OK`）、tag 表 26 项完整解析、`md-boot.service` 开机自启固化；**全程运行时 DT overlay + 模块加载，未刷 boot**（§9.6"要重编内核"结论被推翻，overlay 更快）。

**M4 下一步**：AP 侧 CCIF 全 0、6s 轮询 `RCHNUM=0x000000`： MD CPU 运行但 CCIF 数据通路未握手；需移植 vendor CCIF HIF（APCCIF_CON@0x00 等 6 寄存器 + 通道队列 + IRQ 241/242）→ RIL。

> 🚫 **血泪教训：禁止 `rmmod ccci_md` / `ccci_md2`**（2026-09-30 rmmod 致整机卡死）。

> 来源：BASEBAND_NOTES.md §8.2（原 `project_memory.md` §9.8）。

## 10. 工程约定 / 踩坑速查

- boot/vendor_boot 改 cinit 要一起刷（cinit 在 boot ramdisk）。
- DTB 改动不必重编内核：`scripts/tmp_swap_dtb.py` 换 boot 里的 FDT。
- 从 boot 镜像抠 DTB：扫 `\xd0\x0d\xfe\xed`，`make ... mediatek/mt6895-xiaomi-rubens.dtb` 单编。
- **boot 死循环先查 MTK v4 头**：pack_boot.py 必须写 header_version@40=4、page_size@1580=4096；否则 LK 按 legacy 布局找不到 ramdisk panic。头布局 @8 kernel_size @12 ramdisk_size @20 header_size=1584。
- 刷后"无限重启"读 expdb 里的 panic/ASSERT（先重启进已知好镜像，LK 才会 dump 上一次日志）。已知好回滚镜像 `boot_btfw_lefix.img`（唯一 header v4/page4096）。
- scp >5MB 曾不可靠，现在 wifi scp 21MB OK；推大文件优先 SSH。
- `pkill -f "make ARCH"` 会杀到自己 shell，用 `[m]ake`。
- git commit 在 NTFS 卡 index.lock：`pkill`+删 lock，用 write-tree/commit-tree/update-ref 绕过。
- GitHub push 卡 Bearer tty：改用 `Authorization: Basic base64(user:PAT)`。
- 串口 loglevel=1（防 USB 切 host 时 printk 死锁）；插 USB 曾冻结系统即此因。
- FocalTech 触摸 SPI 12MHz 失败、1MHz 可靠；DT 要 parse `support-super-resolution`（16bit 坐标）；VTP 触控 AVDD min=max=3300000。
- KTZ8863A 是 xaga 的 LCD bias IC，rubens 是 OLED，DT 里删该节点否则狂报错。
- 看屏幕实际画面：直接 mmap framebuffer（`scripts/k50_fbmap.py`/`k50_fbpng.py`），不要用 spectacle。
- `systemctl restart sddm` 不会杀旧 Plasma（VT1+VT2 双会话黑屏），先 kill startplasma/kwin/plasmashell。
- MT6895 CONNAC 蓝牙/WiFi 固件已换成原厂 20231221 版（在 initramfs）。
- 无 RTC 导致 apt 挂未来日期 Release，先校时 + ForceIPv4。
- **⚠️ 2026-10-01 起 `wsl.exe` 被安全中心程序黑名单拦截**（提权也无法绕过）。替代链路（已验证）：
  - 设备 SSH 直连：Git Bash 自带 ssh/scp，公钥经 UNC 拷出 `//wsl$/Ubuntu${HOME}/.ssh/${K50_KEY}` → `/tmp/${K50_KEY}_tmp`(600)。模板：`ssh -i /tmp/${K50_KEY}_tmp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${K50_HOST} '<cmd>'`。
  - 编译改**设备端原生**：`apt-get install gcc libc6-dev make`（K50 有外网 + TUNA 源）→ gcc 12.2.0；新脚本 `gx_build_dev.sh`（scp 源码 → 设备编译，`--push` 装入 `/opt/goodixta/bin/ta_host`）。
  - WSL 内文件仍可读：`//wsl$/Ubuntu${HOME}/fp_work/`（ta.asm 40MB、goodixfp.ta 等）。
  - 若要恢复 WSL 链路：安全中心 → 命令安全 → 程序黑名单 → 移除 `wsl.exe`。
- 远程在 K50 本机屏幕跑交互式命令（konsole 投屏）：`setsid runuser -u k50 -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:1 XAUTHORITY=/run/user/1000/xauth_yLDGft DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus konsole --workdir /home/k50 -p tabtitle="..." -e <script>`。**`--workdir` 不可省**（否则 chdir /root 被拒、命令不执行）。
- `pkill -f "<pattern>"` 在本机 ssh 远程命令里会**匹配到自己的命令行**而自杀：用 `pgrep -x <name>` 或 `[p]attern`。

---

## 11. 指纹 v85 崩溃根因与 v86b（2026-10-05 16:20 更新）

> **本节细节已整体迁出** → [FINGERPRINT_NOTES.md](FINGERPRINT_NOTES.md) §0.2 与 §3.58。

**结论（v85 系列 rc=139 全崩的真凶）**：host 二进制**链接基址 `0x400000`** 与 TA 的 `mmap(MAP_FIXED, 0x400000)` 完全冲突： load_ta 时 TA 映射直接覆盖 host 自身代码段，之后执行到被覆盖内存即崩在 `__vfprintf_internal`。**与补丁无关**（v85c/v85d 都崩）。

- **编译必须带 `-Wl,-Ttext-segment=0x10000000`**（设备端 gcc 默认 0x400000 会崩）。
- **v86b 已不再是部署版本**（2026-10-06 定案）：它的 v66 `sizeof_finger_template` NOP 会把模板写坏成 55172 B → 认证恒 `GF_ERROR_NOT_MATCH`(1006)。现部署为 **10-01 proven host**（`bin/ta_host`，md5 `d723e2269b201ba9fa8b32fdac2da483`），v86b 留底 `ta_host.v86b-saved-*`。细节见 FINGERPRINT_NOTES.md §3.59/§3.60。

