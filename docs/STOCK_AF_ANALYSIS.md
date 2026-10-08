# Stock HyperOS AF stack analysis: Redmi K50 / MT6895 ("rubens")

Read-only static RE of the vendor camera libraries + kernel modules from the HyperOS vendor partition.
No workspace file was modified; `src/cam_cap.c` was not opened.

**Confidence keys**, `[BIN]` = read from dynsym/disassembly/rodata (high) · `[STR]` = string literal recovered
from rodata: the *feature* is certain, its numeric value usually is not · `UNKNOWN` = not determined, not guessed.
Evidence dumps `out/re/r1.out` … `r17.out` (from `out/re/r1_*.sh` … `r17_*.sh`); tools
`aarch64-linux-gnu-objdump/-nm/-readelf/-c++filt`, `strings`, `python3` in WSL. Core rodata carries
`$Rev: 7731 $` / `$DateUTC: 2023-07-04 06:06:45Z $` `[STR]`; `lib3a.af.core.so` is stripped except
`af_Init` / `af_Process` / `af_Finalize` `[BIN]`.

---

## 1. Data flow and architecture

### 1.1 Libraries

| Library | Role |
|---|---|
| `lib3a.af.core.so` (1.22 MB) | **The algorithm.** Exports only `af_Init`, `af_Process`, `af_Finalize` `[BIN]`; all else is command ids `AF_INIT`, `AF_HANDLE(_V2)`, `AF_TRIGGER`, `AF_SET_MODE`, `AF_GET_HW_CONFIG`, `AF_GET_TUNING_PARAM`, `AF_CUSTOMER_HANDLE` `[STR]`. |
| `libcam.afmgr.so` (345 KB) | **State machine / policy.** `AfMgr` (`IFace IAfMgr`, `AfMgr::GetInstance(int)`) + `AfCPU` (`IAfCxU::getInstance(int,int)`) `[BIN]`. |
| `libcam.hal3a.lensdrv.so` (23.8 KB) | **The only thing that moves the lens** — class `VCMDrv`, `SetFocusPosition(int)` `[BIN]`. |
| `libcameracustom.lens.so` (28 KB) | VCM/Iris/OIS driver *name* lookup: `GetVcmDriverName(...)`, tables `vcm_list_0..5` `[BIN]`. |
| `libcameracustom.so` | `get_Dualzoom_AF_TeleDACTh/Thresholds`, `FSCCustom::getAfDampTimeOffset` `[BIN]`. |
| `libcamera.customaf.so` | Defines `T ForceEnableFVInFixedFocus(int)` @ `0xc07c` `[BIN]` (§6). |
| `lib3a.stat.so` (161 KB) | Cam-ISP statistics front end (`aaa_stat_init/main/ctrl`) `[BIN]`. |
| `lib3a.af.assist*.so` + `models{1d,2d}.so` (33/40 MB) | PDAF / AI assist (§5). |
| `libcam.hal3a.so`, `v3.*.so`, `ctrl/policy/utils` | 3A HAL plumbing, not the AF algorithm. |

The core loads tuning at runtime from a SQLite DB: imports `sqlitemod::sqlhandle::{allocate,select,execute,closeDB}`,
`sqlitemod::getCStructInfo`, path `DataSet/SQLiteModule/db/af/ParameterDB_af.db`, log
`%s load parameter from %s ,nvram addr is ` `[BIN]`/`[STR]` ⇒ **the numbers are not in these .so files**.

### 1.2 Who owns what

* **Kernel: only the VCM driver.** No AF algorithm in kernel space at all.
* `AfMgr` owns state: `UpdateState(AF_EVENT_T)` + `UpdateState{Auto,Continuous,MF,OFF}Mode`, `triggerAF`,
  `cancelAutoFocus`, `setAFMode`, `MoveLensTo(int&,unsigned int)`, `checkAutoFocus`, `checkPrecapture` `[BIN]`.
  Progress markers `Start_AF_Search:` / `Ing___AF_Search:` / `End___AF_Search:`, events
  `EVENT_SEARCHING_START` / `EVENT_SEARCHING_END` `[STR]`.
* `AfMgr` → core via `Config/DoCalculation/GetResult` (per-device id) → lens via `VCMDrv::SetFocusPosition(int)`.
* **`AfMgr::getMaxLensPos()` @`0x3a670` and `getMinLensPos()` @`0x3a678` are stubs returning 0** `[BIN]`
  (`mov w0,wzr; ret`), the real range comes from tuning.

### 1.3 How the focus value reaches the algorithm

* FV comes from the **MTK ISP/DIP hardware statistics block** (index 8, `cmp w0,#0x8`) parsed by
  `lib3a.stat.so`: `[get_aaho_unit_op] error, bin cnt invalid, in=%x, out=%x, twin_seq=%d`,
  `[get_aao_raw_data] stat w/h: %d/%d hdr_mode:%d`, `Func_44 C-Code run through.(AE,AF,AWB Pre-process)` `[STR]`.
* Window/stat config via `AF_GET_HW_CONFIG` / `AF_INIT_HW_CONFIG(_V2)`; `[AFHW] Configure number should not be zero`,
  `[UpdateCenFvSubWin] FV result, subW FV(%d,%d) num %dx%d mulExt %dx%d` `[STR]`.
* FV is a shifted integer with window variants: `[FS_FV]%d,{%d<<%d}`, `[FS_FV_CEN]`, `[FS_FV_CEN_SUB]`,
  `[FS_FV_FD]`, `[FS_FV_AP2]`, `[CAFFV]%d,{%ld},{%ld},{%ld}`, `[AFShowItem][FV]%ld`, `Pos(%d -> %d), FV %ld` `[STR]`.
  FV data type / stat pixel format: **UNKNOWN**.
* Per-frame entry `AF_HANDLE(_V2)`; the `[handleAF] tg:%d dev:%d frame:%d,%d … fv:%ld pdVaild:%d …` record `[STR]`
  lists what the core receives: frameT, LV, AEstable, ISO, shutter, zoom, posture, temperature, gyro, FV,
  PD validity/conf, FD status.

### 1.4 How the lens is moved: instruction level

`VCMDrv::SetFocusPosition(int)` @ `0x3530` `[BIN]`:
```
3570: ldr w8,[x19,#60]            ; last commanded position
3574: cmp w8,w1 / b.eq 3a6c       ; identical -> return, NO ioctl
```
fast/retry path (armed when `[x19+112]==1 && [x19+116]==pos`):
```
3598: mov w8,#0x90a ; movk w8,#0x9a,lsl#16   ; id = 0x009A090A = V4L2_CID_FOCUS_ABSOLUTE
35a0: sub w9,w21,#0x1 / csinc                 ; value = pos-1
35ac: stp w8,w9,[sp] ; mov w1,#0x561c ; movk w1,#0xc008,lsl#16 ; bl ioctl
```
main path:
```
35c4: mov w8,#0x90a ; movk w8,#0x9a,lsl#16   ; id = 0x009A090A
35cc: str x8,[sp] ; 35d8: str w21,[sp,#4]     ; value = pos  (NOT pos-1)
3638: mov w1,#0x561c ; movk w1,#0xc008,lsl#16 ; bl ioctl
```
`0xC008561C`: size `(>>16)&0x3FFF = 8`, type `'V'=0x56`, nr `0x1C`, dir `_IOWR`
⇒ **`_IOWR('V',0x1c,8)` = `VIDIOC_S_CTRL`** with an 8-byte `struct v4l2_ext_control {__u32 id; union{__s32 value;…};}`.
**Correction to the prior note:** `value = pos-1` is only the *fast/retry* path; the regular path writes `pos`.
Timing: `clock_gettime(CLOCK_MONOTONIC=1)` before/after, logged `<time> [CAT][AF] control_lens_time:%lld` `[STR]`.
**No retry, no sleep, no minimum-interval in `SetFocusPosition`**, the only gate is "same position ⇒ no ioctl".
Also present: `VcmFocusInformation*`, `GetFocusInformation`, `IsVcmSupported`, `PowerOnParkLens`,
`PowerOffParkLens`, a `__thread_proxy` (VCMDrv has a worker thread) `[BIN]`. `InitDrv` selects the driver name via
`GetVcmDriverName`, stores `1` at `[x19+112]` (fast path armed) and on one path calls `SetFocusPosition(20000)`;
the meaning of `20000` is **UNKNOWN** (far outside the 10-bit DAC range). `PowerOnParkLens`/`PowerOffParkLens`
bodies: **UNKNOWN** (`0x2c28`, `0x33b0`).

### 1.5 VCM chosen by name; DT binding

`libcameracustom.lens.so` `[BIN]`: name pool `Dummy, lc898229, gt9764, bu64253, dw9718s, bu64253gwz, gt9772a,
gt9772b, ak7377a, ak7375c, dw9800w, dw9800v, dw9825a, ak7314`; `vcm_list_0` (main sensor) = **`dw9800v`**.
Stock DT `${K50_REPO}\dt\hyperos_fdt.dts`: `i2c@11d05000` (mediatek,mt6983-i2c, 1 MHz) holds
`compatible="mediatek,dw9800v"` `reg=<0x0c>`, `camera_eeprom0@51`, `sensor0@10` = `rubensimx582_mipi_raw`.
DT aliases map that controller to `i2c8`; the runtime `i2c-N` index is why userspace sees bus 10.

---

## 2. Contrast-AF search strategy

### 2.1 Certainty: hybrid, coarse→fine, direction-reversing hill-climb

* Coarse then fine `[STR]`: `[AFTempCali]Coarse search end, %d` · `[AFTempCali]Coarse search ing, %d` ·
  `[AFTempCali]Fine search end, %d %d`. Entry points `[AF][Seek]`, `[AF][FineSearch]`, `[AF][Prepare]`.
* Reversal hill-climb `[STR]`: `[PLF DIRCHG on account of PLFV] start at %d and move to %d`,
  `[PLF DIRCHG] start at %d and move to %d`, `[PLF DIRCHG on account of Boundary Stop] start at %d and move to %d`,
  `[PLF Stop1]PLFV find maximum value, move to %d.totIdx= %d`, `[PLF Stop2]…`.
* No-peak fallback = traverse everything `[STR]`: `[No peak stop] Full path searched`.
* Full sweep is **not** the default, it is a debug override: `vendor.debug.af.fullscan.step`,
  `vendor.debug.af_mgr.fullscan`, `vendor.debug.af.localfullscan[.{dual,auto,width,height}]`,
  `vendor.debug.af_mgr.roi_of_tg`, `vendor.debug.afcalib.{ScanMode,Range,trig}`; messages
  `[runAFFullScan]Scan range NG or Scan %d ~ %d!!`, `[runAFFullScan]Scan step NG %d !! fixed to %d`,
  `[Cmd_setAFMode][chg Mode for fullscan]%d` `[STR]`.
* Step is a parameter: `[AFMODE]%d step %d`, `HBTrackM3_%d fs___ing step %d. keep (default)`,
  `fsc to next pos %d, (%d/%d) delay to reverse %d`,
  `[ADP_Alarm] ori_step:%d eq_step:%d adp_alarm: %d  ADP_ALARM_RATIO: %d`,
  `[MDAF-DBG: DAC (%d)%d to (%d)%d ; roi_id(%d), md_enable(%d), midx(%d)]`; step count bounded by
  `[ERROR][af_search] exceed maximun of steps` `[STR]`.
* Low-light skip `[STR]`: `[af_search] Skip: isEnabled %d isSearchMode %d disableSearch %d disableSeekLowLv %d`;
  `[AFALGO_search_type] set type from %d to %d, KeepLVDiff %d`; `[AF] search disable by ot`; `night %d(%d), ROI %d res %d`.
* **Adaptive lens-settle** (not a fixed delay) `[STR]`:
  `[AdpComp]Adaptive input error, dev:%d, BeforeMove:%d, Moving:%d, AfterMove:%d, pixel_in_line:%d,
   u32_pixel_clk:%u, ts_ml_start:%lu, TS_AFROIBottom:%lu`;
  `[AdpComp]Lens moving time error2, dev:%d, Adj_PSample:%d, Eq_Lens_Pos:%d`;
  `[Speed][MoveToBest]Done delay %d TG %d`. The readout time is derived from `pixel_in_line`/`pixel_clk`, so FV
  is only trusted after the lens has arrived **and** the next frame is read out.
* Failure/refinement `[STR]`: `[FailPos] keep fine search result`, `[FailPos] nearC=%d nearAvgConf=%d`,
  `[FailPos][Fallback] finalTarget: Target info pos %d, tableMacroThr %d(%d) BestPos %d`;
  `[AfOffset]bestPos:%d=(%d-%d) confRatio:%d (%d in %d/%d) offsetRatio:%d in tableRange(%d~%d) farRatio/nearRatio= %d/%d`.

### 2.2 Re-trigger / "don't refocus too often"

An explicit **AE-change + scene-stability + gyro** gate `[STR]`: `CAF_Prepare i4AEsCdCnt(%d) before seek,
afStatus(%d)`; `caf_searching=%d, caf_ev_diff_req=%d, caf_evdiff_x1000=%d` (EV difference, ×1000);
`AETarDiff=%d(thr=%d)`, `softAEstable=%d`, `LvDiffLarge=%d`, `AEstable=%d`, `AISConstrain=%d`,
`aisNotConstrainedCnt=%d(%d)`, `aisFirstBvStable=%d BvStable=%d`;
`[AF][launchCamTrigger] triggerSceneUnstableCnt %d(%d)`;
`[AF][launchCamTrigger] hbFdValid %d waitHbFace %d sceneStb %d fdRoiStb %d conf %d(%d)`;
`Gyro is Stable for oneshot judgement, GyroValue %d`; `Phone Moving while TRACKING, ForceCapture: LensState = %d`;
`[%d][MGR] Don't do AF searching after TAF`; `Do one time searching when next time start preview.`;
`SEARCHING_END because of getting out of AF_SEARCH_CONTRAST`. Corresponding knobs are listed in §3.3.

### 2.3 Numeric values

**UNKNOWN**, they live in `ParameterDB_af.db` / NVRAM / the per-sensor `*_tuning.so` blob (§3, §7).
Recoverable: the per-sensor DAC limits + (position,distance) table uploaded as `af_dac_inf`, `af_dac_marco`,
`af_dac_min`, `af_dac_max`, `af_distance_inf`, `af_distance_marco`, with a step table:
`getAFTable input CHK ERROR. str, end, step (%d, %d, %d)` · `getAFTable invalid step_count %d -> %d` ·
`getAFTable step over range (%d, %d, %d) %d` · `getAFTable --> step_count %d [%d]%d [%d]%d` ·
`[getFocusRange] [%f, %f] tbl %d, pos %d,idx %d, dis %d, range %d` `[STR]`.

---

## 3. Tunable parameters (names exact; values UNKNOWN unless quoted)

**3.1 Global NVRAM/AF param block** `[STR]`:
```
[AFParam][NVRAM][param] spot_roi(%d,%d) normal_num(%d) macro_num(%d) fail_pos(%d) i4StatGain(%d)
   m_i4HWConfigLatency(%d)
i4InfPos(%d) frameT(%d) i4AfDoneDelay(%d) i4FSCFrameDelay(%d) UserLoadOpt(%d)
i4PostureComp(%d) PostureCompMode(%d)
flatFVActiveIdx(%d) CAFWinFvExtISO(%d) CAFWinFvExtW(%d) CAFWinFvExtH(%d) SkySceneAngle(%d)
cafLowLv(%d) cafLowLvExceotionType(%d) SkySceneLV(%d) NightSceneLV(%d) SkyTouchMode(%d)
CenAllSkyMode(%d) TempError(%d) softEvDiffThr(%d) CoreProCtrl(%d)
[AfOffset] AfOffsetEnable(%d) AfOffsetConfLow(%d) AfOffsetConfHigh(%d) AfOffsetDacFar(%d)
   AfOffsetDacNear(%d) AfOffsetWeightFar(%d) AfOffsetWeightNear(%d)
[AFParam][Full frame AF][Param]Width %d Height %d / [AFParam] d-zoom check %d ratio %d
[initAF] param ver %d / [initAF] max dac %d / [initAF]Build type %s
[AFParam] | (1)Hybrid (2)PD (3)LD (5)Scene2 (6)FD (7)Hybrid2 (8)common
```
**3.2 Core modules** (`[AF_Create][X] dev %d`): `Main, Stats, Hybrid, LTC, PL, ZoomTrack, SyncAF, MF, IF,
Scene, AISEG, FDAF, CusAlgo, Log, Table, ZoomEffect` `[STR]`.
**3.3 Debug knobs** `[STR]`, core: `af.disable_module`, `af.cus_algo`, `af.assist_roi`, `af.nxn_roi`,
`af.stat.area`, `af.md3x3`, `af.mdchgcnt[fd]`, `af.fv_opt`, `af.{enable,set,lock,soft,frame}`, `af.zeccalib`,
`af.posture.mode`, `af.zoomtrack.mode`, `af.zoom_manualaf`, `af.zoom_smoothlevel`, `af.zoom_target_factor`,
`afsync.mode`, `hybrid.mode`, `af.log.{enable,type}`, `af.logstat`, `af.log_off_cam/dev`, `af.systrace`,
`af.{fdnvram,hbnvram,hbnvram2,plnvram}`, `af.pdsubidx`, `af.scalable_pd`, `af.pldetect`, `af.laser_input`,
`af.aiseg.mode`, `af.is.plscene.enable|isap.plscene|iscen.plscene`, `af.dyn.history.enable`, `af.dumpif[_dev]`,
`af.dumpdata`, `af.lens.{control,disable,master,slave,position,push}`, `af.lensmovetime`.
afmgr: `af_mgr.{enable,fullscan,lock,thr,sat,tar,roi_of_tg,adpalarm,log.level}`, `af_mgr_oneshot.enable`,
`af.localfullscan[.{width,height,scalex,scaley}]`, `af.{force.disable,nvram.idx,rtv.*}`, `af_fv.switch`,
`af_alg.log.level`, `af_motor.{disable,position}`, `af_ois.position`, `af_rtv.data`, `afegainqueue`,
`pd_verify_flow.*`, `afassist.lockae`, `af.oneshot.{en,num,gyro,acce,overlap}`,
`vendor.debug.fsc.af_damp_time.offset`.
assist: `af.assist.ai.*` (30+ knobs), `pd.{enable,algo,c0..c4,downsampling,…}`, `aiaf.enable`.
**3.4 Unnamed numeric fields** in the `[handleAF]` record: `fv`, `mdPos/refPos/mdThr/range/overlap`,
`pdTar/pdConf/pdSrc/pdRoiMode`, `hbState`, `gmv/gmv_conf`, `gyro/acce/gsum/hist/aer`, `AFreq`, `reTrig`,
`plScnt/plWarea/plGsum/plGpixel`, `searchRange(%d,%d)`, `spot_win(%d,%d,%d,%d)`, `fdRef/fdPri/otRef/otPri`.
**3.5 Per-sensor vs global**, per-sensor: the `*_tuning.so` (`rubensimx582_mipi_raw[_2]`,
`rubensimx596_mipi_raw`, `rubenss5k4h7_mipi_raw`, `rubensgc02m1_mipi_raw`, `mtk000_mipi_raw`) + `*_IdxMgr.so`
companions. They expose only the template (`NSFeature::RAWSensorInfo<1410,0>::impGetDefaultData/impGetFlickerPara`,
sensor-ID table `GC02M1/IMX582/IMX596/S5K4H7_SENSOR_ID`), scenario strings (`Wechat_Scan`, `XM_*`) and a binary
`RAWSensorInfo` blob `[BIN]`; **which offset is the AF block is UNKNOWN**, and no ASCII AF value exists.
Global: §3.1–3.3. DB key tuple: `DB-Key (sid, act, prj, mod, cus, app, mdu) %d …` `[STR]`.

---

## 4. DW9800V kernel driver (`dw9800v.ko`): exact protocol

`vermagic "5.10.198-android12-9-gb80b558ee02f SMP preempt mod_unload modversions aarch64"`, clang 12.0.5,
author "Po-Hao Huang", "DW9800V VCM driver", GPL v2, `i2c:dw9800v`, OF `mediatek,dw9800v`;
`.text=0xac0`, `.rodata=0x648`. Symbols `[BIN]`: `dw9800v_probe@0x1f0`, `_remove@0x158`, `_vcm_suspend@0x444`,
`_vcm_resume@0x470`, `_power_off@0x768`, `_set_ctrl@0x89c`, `_open@0x944`, `_close@0xa10`; rodata
`_pm_ops@0x4c0`, `_ops@0x5c0`, `_int_ops@0x600`, `_vcm_ctrl_ops@0x628`, `_of_table@0x330`, `_id_table@0x580`.

**4.1 V4L2 control**, `v4l2_ctrl_new_std` at `probe+0x35c`: **id `0x9a090a` = `V4L2_CID_FOCUS_ABSOLUTE`,
min 0, max `0x3ff` (1023), step 1, default 0** (generic defaults, not the mechanical range). Ctrl ptr at
`struct+544`. Also `v4l2_i2c_subdev_init(subdev@+0xe0, client, _ops)`, `media_entity_pads_init(1, NULL)`,
`v4l2_async_register_subdev`, `pm_runtime_enable`.

**4.2 Programming = direct 16-bit DAC write to reg 0x03**, `dw9800v_set_ctrl@0x89c`:
```
if (ctrl->id != 0x009A090A) return 0;                       /* all other ids ignored */
0x91c: i2c_smbus_write_word_data(client, 3, bswap16(ctrl->val));
```
⇒ register **0x03**, **16-bit big-endian** (`[0x03, val>>8, val&0xFF]`). No other register is touched by
`set_ctrl`. **There is no AAC / ring-mode / auto-oscillation support in this driver.** UNKNOWN whether stock
userspace writes further registers.

**4.3 Power-on + init, `_vcm_resume@0x470`** (confirms the task statement; one correction below):
```
regulator_enable("vin") [rodata+0x121 -> +552]; regulator_enable("vdd") [rodata+0xcd -> +560]
pinctrl_select_state("vcamaf_on") [rodata+0x185 -> +576]
usleep_range(10000, 10100)                 ; 10 ms
i2c raw write  reg 0x00 <= 0x01
i2c raw read   reg 0x00                    ; vendor/HW version -> g_vendor_id; log "vendor id: %x"
i2c write      reg 0x02 <= 0x01
i2c write      reg 0x02 <= 0x00
__const_udelay(0x68dbc)                    ; ~100 ms
i2c write      reg 0x02 <= 0x02
i2c write      reg 0x06 <= 0x40
i2c write      reg 0x07 <= 0x01
__const_udelay(0x68dbc)                    ; ~100 ms
```
**Correction:** the "`0x00`" in your sequence is the *read-back* of reg 0x00 (version), not a write of 0.
Any I2C failure ⇒ log, disable both regulators, `pinctrl_select_state("vcamaf_off")`, return −1.

**4.4 Power-off / park, `_power_off@0x768`**:
```
val = ctrl->val & ~0xF                     ; ldr w8,[ctrl+184]; ands w21,w8,#0xfffffff0
loop: i2c_smbus_write_word_data(client, 3, bswap16(val))
      usleep_range(8400, 9400)             ; 8.4–9.4 ms settle per step
      val -= 0x10                          ; 16 counts per step
until val < 0                              ; ramp to 0 = park at infinity
i2c write reg 0x02 <= 0x20                 ; standby
msleep(20); usleep_range(11600, 12600)
regulator_disable("vin"); regulator_disable("vdd"); pinctrl_select_state("vcamaf_off")
```
**4.5** `_open@0x944: pm_runtime_resume(dev,4)` · `_close@0xa10: pm_runtime_idle(dev,5)`.
`_vcm_suspend@0x444`: **UNKNOWN** (not disassembled in detail).
**4.6 Registers this driver owns:** `0x00` init write + version read · `0x02` = `0x01`, `0x00`, `0x02`, `0x20` ·
`0x03` 16-bit DAC · `0x06 <= 0x40` · `0x07 <= 0x01`. Nothing else. The semiconductor semantics of
0x00/0x02/0x06/0x07 and the true mechanical DAC range are **UNKNOWN** from the binary.

---

## 5. MTK ISP / PDAF / AI dependencies vs plain contrast AF

**Not reproducible on mainline, do not chase:**
* **FV itself comes from the MTK ISP/DIP statistics block** (`lib3a.stat.so` AAO parsing, `AF_GET_HW_CONFIG`,
  `[UpdateCenFvSubWin]`, `[do_stat_main_v7_0]`) `[STR]`. No MTK stat block ⇒ you must compute FV yourself.
* **PDAF/Hybrid**: `[InitHB] pd %d ld %d`, `[HB][PD Classify] input dac/conf %d/%d`,
  `[UpdatePdCfg] weak thr:%d by LV:%d(%d)`, `getPdBlocks`, `pdVaild/pdTar/pdConf/pdSrc` `[STR]`.
* **AI assist**: `lib3a.af.assist.so` + the 33 MB / 40 MB `models{1d,2d}.so` weights,
  `libcamera.custom.af_assist_{mgr,buf_mgr,pdp}.so`, `vendor.debug.af.assist.ai.*` (30+ knobs),
  AI-scene/Sky/AISEG/portrait modules, all need the MTK NPU/APU and ML models.
* **FDAF / AISEG** (face/segmentation-driven windows), **LTC** thermal calibration, posture compensation,
  zoom-track sync, dual-zoom (`get_Dualzoom_AF_*`), sensor-specific PDAF wrappers.

**Plainly imitable:** coarse→fine search; FV-maximum selection; direction reversal, boundary stop and
"no peak ⇒ full path"; bounded step count; confidence/offset refinement; the "keep the fine result" fallback;
**adaptive lens-settle compensation**; CAF gating on AE change + scene stability + gyro; low-light search
suppression; multi-window FV with a selection rule.

---

## 6. Vendor fixed-focus handling

`libcamera.customaf.so` defines `T ForceEnableFVInFixedFocus(int)` @ `0xc07c` `[BIN]`; `libcam.afmgr.so` imports
it (`U _Z25ForceEnableFVInFixedFocusi`) and calls it at **`0x3a34c`** and **`0x3a61c`** `[BIN]`:
```
3a32c: bl getAfSupport              ; real AF lens?
3a338: mov w0,#1 ; b ...            ; yes -> AF enabled
3a348: ldr w0,[x21]                 ; device id / sensor index
3a34c: bl ForceEnableFVInFixedFocus
3a350: str w0,[x20]                 ; -> m_i4IsEnableFVInFixedFocus
3a354: ldr <debug prop str> ; bl property_get_int32   ; 1 = force enable, 2 = force disable
```
⇒ for a sensor reporting **no AF support**, the manager asks `ForceEnableFVInFixedFocus(dev)`, caches the result
in `m_i4IsEnableFVInFixedFocus`, and a property can override it (1 enable / 2 disable); the exact property key is
**UNKNOWN** (the adjacent rodata string belongs to the `vendor.debug.af.localfullscan.*` family).
When set, the log `[%d][MGR] AF-%-15s: m_i4IsEnableFVInFixedFocus(%d), set full tg` `[STR]` shows the
**whole target group becomes one FV window**, so the camera still produces an FV, it is simply never used to move
a lens (it feeds EDOF/bokeh/depth and lets the manager report "focused"). Related branches `[STR]`:
`Dev(0x%04x), set CurAFMode to EDOF to enable LaunchCamTrigger`, `autofocus : dummy lens`, `no focus lens`,
`skip af for EDOF mode`, `skip af for high fps flow`, `skip AF region in continuous mode`.
The fixed-focus sensors are exactly the tuning libs with no VCM entry: `rubenss5k4h7_mipi_raw` (ultra-wide),
`rubensgc02m1_mipi_raw` (macro), `rubensimx596_mipi_raw` (front); the AF one is `rubensimx582_mipi_raw`
(`vcm_list_0 = dw9800v`). **Path summary:** `getAfSupport()==0` ⇒ `ForceEnableFVInFixedFocus(dev)`
(+property override) ⇒ if enabled set `m_i4IsEnableFVInFixedFocus=1`, use the full target group as the FV window,
mark AF mode EDOF, never move a lens; if disabled, skip AF entirely.

---

## 7. Not recoverable from this material

* All numeric tuning: coarse/fine step sizes, `normal_num`/`macro_num`, `i4InfPos`, `fail_pos`, EV thresholds,
  confidence ratios, FV gain, `searchRange` limits, they come from `ParameterDB_af.db` (absent from the vendor
  snapshot), NVRAM, and the binary `RAWSensorInfo` blob in the per-sensor `*_tuning.so`.
* Exact struct layouts passed between `AfMgr`, `lib3a.af.core.so` and the stat module (`af_*_t`,
  `AFTuningInfo_t`, `AFTuningSet_t` appear only as demangled argument types).
* DW9800V register semantics for 0x00/0x02/0x06/0x07 and the true mechanical DAC range.
* `PowerOnParkLens`/`PowerOffParkLens` bodies; meaning of `SetFocusPosition(20000)`;
  `dw9800v_vcm_suspend` beyond "exists".

---

## 8. Actionable for our driver

Our driver computes FV on the CPU from the raw Bayer frame, drives the DW9800V over I2C (bus 10, addr 0x0c) with
coarse sweep + fine sweep + periodic ±wobble, and must avoid hunting on static scenes and getting stuck where
there is no contrast. Each item is the action, then *why*.

1. **Run the full DW9800V init before the first focus write**, reg 0x00⇐0x01, read 0x00, 0x02⇐0x01, 0x02⇐0x00,
   ~100 ms, 0x02⇐0x02, 0x06⇐0x40, 0x07⇐0x01, ~100 ms, after ~10 ms of regulator settle. *Why:* this is exactly
   what `dw9800v_vcm_resume` does to make the actuator respond; skipping it leaves the lens dead.
2. **Park by ramping in steps of 16 with ~9 ms per step**, not one write of 0. *Why:* `dw9800v_power_off` does
   that to avoid the click and the mechanical shock of a hard zero.
3. **Never re-issue the same DAC value.** *Why:* `SetFocusPosition` short-circuits when the new position equals
   `[x19+60]` and issues no ioctl, "same position" means "nothing to do".
4. **One move per frame; only trust FV from the frame after the lens has arrived.** *Why:* the `[AdpComp]` block
   derives the lens-travel + readout delay from `pixel_in_line`/`pixel_clk`; sampling early misplaces the peak.
5. **Coarse→fine, never a full sweep.** *Why:* a full sweep exists only as a debug override
   (`vendor.debug.af.fullscan.step`, `[runAFFullScan] …`); the normal path is a short coarse then a fine phase.
6. **Implement the three stock stop conditions**, reverse on FV decrease, stop at a boundary, and on "no peak"
   finish the path. *Why:* these are verbatim the stock exits (`[PLF DIRCHG…]`, `… Boundary Stop`,
   `[No peak stop] Full path searched`).
7. **Cap the number of steps and bail out with a defined result.** *Why:* `[ERROR][af_search] exceed maximun of
   steps` exists because an uncapped sweep in a low-texture scene never terminates.
8. **Gate a re-sweep on a change in scene luma (an AE proxy) plus frame-to-frame stability, not on every frame.**
   *Why:* the stock manager requires `caf_ev_diff_req`/`caf_evdiff_x1000`, `AEstable`, scene-stability flags and
   gyro stillness before searching, that is what stops the vendor camera hunting. Cheap proxy: rolling average
   luma, re-sweep only if it moves > N% for M consecutive frames.
9. **Suppress or defer the search below a light/contrast floor.** *Why:* `disableSeekLowLv` and
   `[AFALGO_search_type] … KeepLVDiff` show the vendor does this; with (10) it prevents endless sweeps in a dark
   room or on a blank wall.
10. **Detect "no contrast" from the FV curve and give up gracefully**, if `max(FV)/min(FV)` over the sweep is
    below a floor, or the peak sits on a range boundary, keep the current position and report "AF failed / EDOF"
    instead of resweeping. *Why:* the stock `[FailPos] keep fine search result` +
    `[FailPos][Fallback] … BestPos %d` path does exactly this.
11. **Only wobble when already near focus, and disable wobble while the FV gradient stays below the floor.**
    *Why:* wobble is fine-tracking only, and the stock `HBTrackM3_%d fs___ing step %d. keep (default)` shows a
    deliberate "re-use the previous result" decision.
12. **Do the coarse sweep on a narrow centre window, add sub-windows only in the fine phase, log the
    (position, FV) curve per search, and clamp the DAC to a calibrated infinity/macro span.** *Why:* the core
    distinguishes `[FS_FV_CEN]` from `[FS_FV_CEN_SUB]`/`[FS_FV_FD]` and only widens in fine search;
    `[AFShowItem][FV]%ld` exists because the curve is the only way to tune steps and thresholds; and `max=1023`
    in the kernel is just V4L2's default while the stock stack uploads real `af_dac_inf`/`af_dac_marco`/
    `af_dac_min`/`af_dac_max` from tuning.
