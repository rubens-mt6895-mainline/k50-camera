# MediaTek CAMSV register sequence: reverse-engineered from `isp_ko.asm`

Source: `${K50_REPO}\isp_ko.asm` (`objdump -d` of vendor `mtk-cam-isp.ko`, ARM64, AArch64 PAC-enabled).
Names: `${K50_REPO}\isp71_ref\mtk_cam-sv-regs.h`.
Base pointer: `dev->base` = `[x0 + 0x18]` (ioremap'd CAMSV block). `bl` targets are zeroed in this listing, every `bl` below is **unresolved**.
All register ops are on a 32-bit word at `base + offset`. Where the compiler emitted an atomic RMW
(`ldr w8,[x2]` / `orr|and|bic` / `str w8,[x9]`, `x2=x9=base+off`) it is written as `RMW:R|W` or `RMW:C|W`.
The long block of `bti j` stubs after each function's final `ret` is the compiler's atomic-helper replay
code, not part of the function; ignored throughout.

---

## 1. `mtk_cam_sv_pipeline_config` (0x450fc, lines 71523–71588)

**No MMIO.** Pure C helper.

| offset | register | operation | value / bits |
|---|---|---|---|
| — | — | `str w3,[x20,#0xf18]` | driver-side bitmask `1 << (disp_num-3)` (not a HW reg) |
| — | — | loop `x23 = 0..0xf` | `bl` (unresolved) once per set bit in that mask |
| — | — | `str w3,[x19 + x21*4 + 0x30c]` | driver ctx array, not HW |
| — | — | `bl` (unresolved) | trace/log |

**Achievement:** records the enabled CAMSV-video-node bitmask in the driver context and dispatches one
sub-device callback per enabled bit. Touches no CAMSV register.

---

## 2. `mtk_cam_sv_format_sel` (0x451e4, lines 71613–71713)

**No MMIO.** Pure C: a FOURCC (`w0`) → `TG1_FMT` code selector.

| argument value (w0) | returned code |
|---|---|
| `0x4141_xx` GR/BG family (10/12-bit) | **1** |
| `0x4142_xxxx` BA family | **2** |
| `0x4342_xxxx` RG family | **2** |
| `0x4141_3138` / `0x4142_3138` (`"8\0AB"` = MTISP 8AB1) | **4** |
| anything else | **0** |

Branch tree is a compare-chain on the raw FOURCC dword (`cmp w8,#imm; b.gt/b.eq`).
Values map 1 = `TG1_FMT=001`, 2 = `010`, 4 = `100`.

**Achievement:** translates a V4L2/MTISP fourcc into the 3-bit `FMT_SEL.TG1_FMT` field code.

---

## 3. `mtk_cam_sv_pak_sel` (0x4526c, lines 71714–71815)

**No MMIO.** Pure C: FOURCC → PAK mode byte.

| value | returned |
|---|---|
| default / GR family | **0x80** |
| BA family | **0x81** |
| RG family | **0x82** |
| MTISP `8AB1` (`0x41423138`) | **0x8F** |

Tail: `bfi w0, w1, #8, #2`, folds a 2-bit `TG1_SW` (from the caller-supplied value in `w1`) into
bits [9:8] of the returned word, so the caller gets `PAK_MODE | (TG1_SW << 8)` ready for 0x007C/0x01C0.
No register is touched; returns the value in `w0`.

**Achievement:** computes the PAK mode byte + packed-mode select nibble for `FMT_SEL`/`PAK`/`PAK_CON`.

---

## 4. `mtk_cam_sv_xsize_cal` (0x45308, lines 71816–71952)

**No MMIO.** Pure C: line-size (bytes per line) from the image descriptor at `x0`.

| step | operation | value |
|---|---|---|
| read | `ldurh w8,[x0,#0xd]` | image width `w` |
| 422 (YUV) | `add w8,w8,w8,lsl #1` then `ubfx w8,w8,#1,#29` | `(3*w)/2` |
| 420 (YUV) | `add w8,w8,w8,lsl #2` then `ubfx w8,w8,#2,#29` | `(5*w)/4` |
| 420 14-bit | `mov w9,#0xe; mul w8,w8,w9; lsr w8,w8,#3` | `(14*w)/8` |
| align | table lookup at `adrp 0x45000` | round up to the required alignment |
| return | `w0` | aligned xsize |

**Achievement:** converts a pixel width into the DMA line stride/xsize in bytes per pixel format.

---

## 5. `mtk_cam_sv_tg_config` (0x4578c–0x45c0c; body ends `b 0x45aa0`, epilogue at 0x45c0c)

Arg `x1` = sensor/param struct: `[x1+0x06]` = format enum 0..3, `[x1+0x08]` = frame period,
`[x1+0x09]` = w1, `[x1+0x0b]` = w2, `[x1+0x0d]` = h2, `[x1+0x0f]` = h3.
Sensor mode info comes from `x0+0x38` → `[+0xf2c]` (bits 6:4/5:4 flags) and `[+0xf34]` (mode index).

| offset | register | operation | value / bits |
|---|---|---|---|
| 0x0100 | `TG_SEN_MODE` | RMW:C | `&= 0xfffffffe` (CMOS_EN b0 = 0) |
| 0x0100 | `TG_SEN_MODE` | RMW:S | `\|= 0x00040000` if `[x1+8] != 0` (VS_SUB_EN b18) |
| 0x0100 | `TG_SEN_MODE` | RMW:S | `\|= 0x00020000` if `[x1+8] != 0` (SOF_SUB_EN b17) |
| 0x0100 | `TG_SEN_MODE` | RMW:C | `&= 0xfffbffff` if `[x1+8] == 0` (clear b18) |
| 0x0100 | `TG_SEN_MODE` | RMW:C | `&= 0xfffdffff` if `[x1+8] == 0` (clear b17) |
| 0x0164 | `TG_SUB_PERIOD` | RMW | `(raw & 0xffffff00) \| ([x1+8] & 0xff)` → VS_PERIOD b7:0 |
| 0x0164 | `TG_SUB_PERIOD` | RMW | `(raw & 0xffff00ff) \| (([x1+8] & 0xff) << 8)` → SOF_PERIOD b15:8 |
| 0x0100 | `TG_SEN_MODE` | RMW:S | `\|= 0x00400000` (STAGGER_EN b22) if mode index `[+0xf34] != 0` |
| 0x0100 | `TG_SEN_MODE` | RMW:C | `&= 0xffbfffff` (clear b22) if mode index `== 0` **or** `([+0xf2c] & 0x70) == 0` |
| 0x0110 | `TG_PATH_CFG` | RMW:C | `&= 0xffcfffff` (clear SUB_SOF_SRC_SEL b21:20) on every path above |
| 0x0100 | `TG_SEN_MODE` | RMW:S | `\|= 0x00010000` (TIME_STP_EN b16) — unconditional, at 0x45a58 |
| 0x0104 | `TG_VF_CON` | RMW:C | `&= 0xfffffffd` (clear SINGLE_MODE b1) |
| 0x0100 | `TG_SEN_MODE` | RMW:C+S | format switch 0 → `&= 0xffffffcf` (DBL_DATA_BUS b5:4 = 0) |
| 0x0100 | `TG_SEN_MODE` | RMW:C+S | format switch 1 → `&= 0xffffffcf; \|= 0x00000020` (b5:4 = 2) |
| 0x0100 | `TG_SEN_MODE` | RMW:S | format switch 2 → `\|= 0x00000030` (b5:4 = 3) |
| 0x0100 | `TG_SEN_MODE` | RMW:C+S | format switch 3 → `&= 0xffffffcf; \|= 0x00000010` (b5:4 = 1) |
| 0x0108 | `TG_SEN_GRAB_PXL` | W | `((w1+h2) << 16) \| w1` — PXL_END b31:16, PXL_START b15:0 |
| 0x010C | `TG_SEN_GRAB_LIN` | W | `((w2+h3) << 16) \| w2` — LIN_END b31:16, LIN_START b15:0 |
| — | — | `bl` (unresolved) | debug/trace with w2=`[x1+6]`, w3=`[x1+8]`, w4=`[x1]`, stack = w1,w2,h2,h3 |

Switch dispatch is `br x11` on `[x1+0x06]`, guarded `cmp w8,#0x3; b.ls` (0..3 valid).

**Achievement:** programs the timing generator's capture window and sensor mode: CMOS off, optional
sub-frame (VS/SOF) timing, stagger/HDR mode, SOT/DBL data-bus mode, and the GRAB pixel/line windows.

---

## 6. `mtk_cam_sv_top_config` (0x4699c–0x470b8; stubs end 0x47ab0)

Arg `x19` = config struct: `[x19]` = FOURCC, `[x19+0x6]` = fmt code, `[x19+0x8]` = down-sample period.

| offset | register | operation | value / bits |
|---|---|---|---|
| 0x0040 | `MODULE_EN` | RMW:S | `\|= 0x00000001` (TG_EN b0) |
| 0x0040 | `MODULE_EN` | RMW:C | `&= 0xbfffffff` (DB_EN b30 = 0) |
| 0x0040 | `MODULE_EN` | RMW:C+S | `&= 0xcfffffff; \|= 0x20000000` (DB_LOAD_SRC b29:28 = 2) |
| 0x0078 | `SUB_CTRL` | RMW:S | `\|= 0x00000001` (CENTRAL_SUB_EN b0) if `[x19+8] != 0`, else `&= 0xfffffffe` |
| 0x0074 | `DCIF_SET` | RMW:C | `&= 0xffffff7f` (MASK_DB_LOAD b7 = 0) |
| 0x0074 | `DCIF_SET` | RMW:S | `\|= 0x00008000` (b15) if `([x0+0x38]→[+0xf2c] & 0x50) != 0` |
| 0x0074 | `DCIF_SET` | RMW:S | `\|= 0x00000100` (ENABLE_OUTPUT_CQ_START_SIGNAL b8) same condition |
| 0x0074 | `DCIF_SET` | RMW:C | `&= 0xffff7fff`, then `&= 0xfffffeff` if condition false |
| 0x0088 | `MISC` | RMW:C | `&= 0xfffffffe` (VF_SRC b0 = 0) |
| 0x0088 | `MISC` | RMW:S | `\|= 0x00000001` (VF_SRC b0 = 1) if `([+0xf2c]&0x60) && ([x20+0x10]&~1)==8 && [+0xf34]==2` |
| 0x0044 | `FMT_SEL` | W (plain) | fmt code from FOURCC: 1 (GR/BG), 2 (BA/RG), 4 (8AB1), 0 (default) |
| 0x0048 | `INT_EN` | W (plain) | **`0x00011070`** (`mov #0x1070; movk #0x1,lsl#16`) |
| 0x0040 | `MODULE_EN` | RMW:S | `\|= 0x01000000` (DOWN_SAMPLE_EN b24) if `[x19+8] != 0` |
| 0x0040 | `MODULE_EN` | RMW | `(raw & 0xff00ffff) \| (([x19+8] & 0xff) << 16)` — DOWN_SAMPLE_PERIOD b23:16 |
| 0x0040 | `MODULE_EN` | RMW:C | `&= 0xfeffffff` and same DOWN_SAMPLE_PERIOD insert, if `[x19+8] == 0` |
| 0x0040 | `MODULE_EN` | RMW:S | `\|= 0x00000004` (PAK_EN b2) |
| 0x0040 | `MODULE_EN` | RMW:C | `&= 0xfffffff7` (PAK_SEL b3 = 0) |
| 0x01C0 | `PAK_CON` | RMW | `(raw & 0xffe0ffff) \| 0x000e0000` → PAK_IN_BIT b20:16 = `0b01110` (14) |
| 0x007C | `PAK` | W (plain) | `pak_sel \| ((([x19+6] & 0x3) << 8))` — PAK_MODE b7:0 + PAK_DBL_MODE b9:8 |
| 0x0040 | `MODULE_EN` | RMW:C | `&= 0xffffffbf` (QBN_EN b6 = 0) |
| 0x0600 | `SPECIAL_FUN_EN` | W (plain) | **`0x04000000`** (DCM_MODE b26 = 1) |
| — | — | returns 0 | |

`pak_sel` values written into 0x007C b7:0: 0x80 (GR/BG), 0x81 (BA), 0x82 (RG), 0x8F (8AB1).

**Achievement:** top-level module bring-up, enables TG and PAK, configures the data-bus load source,
down-sample period, DCIF/sub-sample/CQ-start signalling, VF source, format, interrupt mask, PAK mode
and DCM mode.

---

## 7. `mtk_cam_sv_cal_cfg_info` (0x499ac–0x49db4)

**No MMIO.** Pure C: fills the driver's computed config struct (`x19`) from params (`x1`) and `dev` (`x0`).

| step | operation | value |
|---|---|---|
| FOURCC `[x1+0x10]` → `w21` | compare chain | **1** GR/BG, **2** BA/RG, **4** 8AB1-family, else 0 |
| `ldp w8,w10,[x1,#0x8]` | width/height-like pair | `w8`, `w10` |
| `strb w9,[sp,#0x16]` | stack struct | `3` |
| `and w26,w10,#0xffff` | | low 16 bits of `w10` |
| `lsl w22,w8,#16` / `lsl w23,w26,#16` | | `w8<<16`, `(w10&0xffff)<<16` |
| `sturh w8,[sp,#0x1d]` / `sturh w10,[sp,#0x1f]` | stack struct | `w8`, `w10` |
| `strb w11=1,[x19]` | out ctx | offset 0x00 = 1 |
| `stp w22,w23,[x19,#0x4]` | out ctx | 0x04 = `w8<<16`, 0x08 = `(w10&0xffff)<<16` |
| `str w21,[x19,#0xc]` | out ctx | 0x0C = format code 1/2/4 |
| `str w24,[x19,#0x10]` | out ctx | 2nd FOURCC switch: **0x380**, **0x381**, **0x382**, **0x38F**; default **0x300** |
| `bl` (unresolved) | | computes xsize from `sp+0x10`; returns in `w0` |
| `sub w25,w0,#1` | | xsize-1 |
| `sub w26,w26,#1` | | height-1 |
| `stp w25,w26,[x19,#0x14]` | out ctx | 0x14 = xsize-1, 0x18 = height-1 |
| `bl` (unresolved) | | second size computation → `str w0,[x19,#0x1c]` |
| `bl` (unresolved) | | trace/log (w3=w22, w4=w23, w5=w21, w6=w24, w7=w25, stack=w26) |
| return 0 | | |

PAK byte table for `[x19+0x10]`: 0x380 = GR/BG 10-bit, 0x381 = BA 10-bit, 0x382 = RG 10-bit,
0x38F = 8AB1, 0x300 = unknown/default.

**Achievement:** derives the per-node CAMSV configuration record (fmt code, PAK byte, xsize-1,
height-1, stride) consumed later by `setup_cfg_info`. No register access.

---

## 8. `mtk_cam_sv_setup_cfg_info` (0x49dbc–0x49ed0)

`x1` = ctx; guard `ldrb w8,[x1+0xcafc]`, if 0, returns 0 immediately (no writes).
`x9 = x1 + 0xcafc`, the staged register image lives at `x9+0x4 … x9+0x1c`.

| offset | register | operation | value / bits |
|---|---|---|---|
| 0x0110 | `TG_PATH_CFG` | RMW:S | `\|= 0x00000800` (DB_LOAD_HOLD b11 = 1 — hold while loading) |
| 0x0108 | `TG_SEN_GRAB_PXL` | W (plain) | `[x9+0x04]` |
| 0x010C | `TG_SEN_GRAB_LIN` | W (plain) | `[x9+0x08]` |
| 0x0044 | `FMT_SEL` | W (plain) | `[x9+0x0c]` |
| 0x007C | `PAK` | W (plain) | `[x9+0x10]` |
| 0x0710 | `IMGO_XSIZE` | W (plain) | `[x9+0x14]` |
| 0x0714 | `IMGO_YSIZE` | W (plain) | `[x9+0x18]` |
| 0x0718 | `IMGO_STRIDE` | W (plain) | `[x9+0x1c]` |
| 0x0110 | `TG_PATH_CFG` | RMW:C | `&= 0xfffff7ff` (DB_LOAD_HOLD b11 = 0 — release) |
| — | — | returns 0 | |

**Achievement:** atomically latches the pre-computed TG capture window, format, PAK mode and IMGO
geometry into hardware inside a DB_LOAD_HOLD window. This is the one function that must not be
reordered relative to the 0x0110 hold/release pair.

---

## `Sequence order for a single-frame capture`

Deduced from the caller `mtk_cam_sv_dev_config` (0x4acc4) at 0x4b18c–0x4b274 and the enable/disable
families (all `bl` targets zeroed, but every callee body is identifiable by its own symbol/offset).
`mtk_cam_sv_dev_config` is the only writer of 0x0100 b0 and 0x0040 b4 before streaming.

**Configuration phase** (call order inside `mtk_cam_sv_dev_config`):

| # | call | what it does |
|---|---|---|
| 1 | `mtk_cam_sv_cal_cfg_info` (extra-arg) | computes cfg record: fmt/PAK byte, xsize-1, height-1, stride |
| 2 | `mtk_cam_sv_setup_cfg_info` (extra-arg) | writes 0x110 hold, **0x108 / 0x10C / 0x44 / 0x7C / 0x710 / 0x714 / 0x718**, 0x110 release |
| 3 | `mtk_cam_sv_pipeline_config` | no MMIO; records enabled video-node mask |
| 4 | `mtk_cam_sv_format_sel` | no MMIO; FOURCC → `TG1_FMT` code |
| 5 | `mtk_cam_sv_pak_sel` | no MMIO; FOURCC → PAK mode byte |
| 6 | `mtk_cam_sv_xsize_cal` | no MMIO; width → xsize bytes |
| 7 | `mtk_cam_sv_tg_config` | **0x100 / 0x104 / 0x108 / 0x10C / 0x110 / 0x164** — TG window + sensor mode |
| 8 | `mtk_cam_sv_top_config` | **0x40 / 0x44 / 0x48 / 0x74 / 0x78 / 0x7C / 0x88 / 0x1C0 / 0x600** — top bring-up |
| 9 | `mtk_cam_sv_dmao_config` | **0x710 / 0x714 / 0x718 / 0x71C? / 0x74C=0 / 0x720..0x730** (CON0..CON4 burst thresholds) |
| 10 | `mtk_cam_sv_fbc_config` | **0x240 = 0** (FBC reset) |
| 11 | `mtk_cam_sv_tg_enable` | **0x100 \|= 0x1** (CMOS_EN) |
| 12 | `mtk_cam_sv_top_enable` | **0x60 \|= 0x1, \|= 0x2, \|= 0x4, \|= 0x8000** (TG/QBN/PAK clock + IMGO clock), then sub-calls `dmao_enable` and `fbc_enable` |

**`mtk_cam_sv_top_enable` internals** (0x485ec): clock enables first, then two sub-calls, then FBC,
then the optional VF:

| offset | register | operation | value |
|---|---|---|---|
| 0x0060 | `CLK_EN` | RMW:S | `\|= 0x1` (TG_DP_CK_EN) |
| 0x0060 | `CLK_EN` | RMW:S | `\|= 0x2` (QBN_DP_CK_EN) |
| 0x0060 | `CLK_EN` | RMW:S | `\|= 0x4` (PAK_DP_CK_EN) |
| 0x0060 | `CLK_EN` | RMW:S | `\|= 0x8000` (IMGO_DP_CK_EN b15) |
| — | — | `bl` | `mtk_cam_sv_dmao_enable`: **0x0040 \|= 0x10** (IMGO_EN b4) |
| — | — | `bl` | `mtk_cam_sv_fbc_enable` (below) |
| 0x0240 | `FBC_IMGO_CTL1` | RMW:S | `\|= 0x200` (FBC_DB_EN b9) |
| 0x0100 | `TG_SEN_MODE` | read | `tbz w8,#0` — only continue if CMOS_EN is already set |
| 0x0104 | `TG_VF_CON` | RMW:S | `\|= 0x1` (VFDATA_EN) if `[dev+0x98] != 0` (VF requested) |

**`mtk_cam_sv_fbc_enable`** (0x48b8c):
| offset | register | operation | value |
|---|---|---|---|
| 0x0104 | `TG_VF_CON` | read | `tbnz w8,#0` → **bail out with -1** if VF already on |
| 0x0240 | `FBC_IMGO_CTL1` | RMW | `(raw & 0xffffff) \| ([x1+8] << 24)` — SUB_RATIO b31:24 |
| 0x0240 | `FBC_IMGO_CTL1` | RMW:S | `\|= 0x8000` (FBC_EN b15) |
| 0x0240 | `FBC_IMGO_CTL1` | RMW:C | `&= 0xfffffdff` (FBC_DB_EN b9 = 0) |

**Per-frame buffer enqueue**, `mtk_cam_sv_enquehwbuf` (0x49790), `x1` = 64-bit DMA addr, `w2` = frame no:

| offset | register | operation | value |
|---|---|---|---|
| 0x075C | `FRAME_SEQ_NO` | W | `w2` (frame sequence number) |
| 0x0700 | `IMGO_BASE_ADDR` | W | `w1 & 0xffffffff` (low 32 bits of buffer PA) |
| 0x0704 | `IMGO_BASE_ADDR_MSB` | W | `(w1 >> 32) & 0xf` (high 4 bits) |
| 0x0014 | `TOP_FBC_CNT_SET` | W | `0x1` (RCNT_INC1 — kick the ring counter / frame) |

`mtk_cam_sv_write_rcnt_sv_dev` (0x4994c) and `mtk_cam_sv_write_rcnt` (0x498c0) do the same
**0x0014 = 0x1** write (the latter first resolving the sv_dev by index, guarded `w1-3 < 0x10`).
`mtk_cam_sv_frame_no_inner` (0x4a12c) reads back **0x075C** (note: uses `[x0+0x20]`, not `[x0+0x18]`).

**Stream-on**, `mtk_cam_sv_dev_stream_on` (0x4b3e0): when `w19 == 0` (this is the power-on path)
| offset | register | operation | value |
|---|---|---|---|
| — | — | `str wzr,[x21,#0x98]` | driver flag |
| — | — | `bl` | `mtk_cam_sv_vf_on` — sets/clears **0x104 b0** per the VF request (no-op if already in that state) |
| 0x0240 | `FBC_IMGO_CTL1` | W | `0` (FBC reset again before enabling VF) |
| 0x0040 | `MODULE_EN` | RMW:C | `&= 0xffffffef` (IMGO_EN b4 = 0) |
| 0x0100 | `TG_SEN_MODE` | RMW:C | `&= 0xfffffffe` (CMOS_EN b0 = 0) |
| — | — | `bl` | `mtk_cam_sv_vf_on(dev, 1)` — **0x104 \|= 0x1** (start video frames) |

**Stream-off**, `mtk_cam_sv_top_disable` (0x48f0c):
| offset | register | operation | value |
|---|---|---|---|
| 0x0104 | `TG_VF_CON` | RMW:C | `&= 0xfffffffe` (VFDATA_EN = 0), only if currently set |
| — | — | `bl` | `mtk_cam_sv_disable`-family (`dmao_disable`, `fbc_disable`) |
| 0x0040 | `MODULE_EN` | RMW:C | `&= 0xbfffffff` (DB_EN = 0) |
| 0x0040 | `MODULE_EN` | W | `0` |
| 0x0044 | `FMT_SEL` | W | `0` |
| 0x0048 | `INT_EN` | W | `0` |
| 0x0240 | `FBC_IMGO_CTL1` | W | `0` |
| 0x0040 | `MODULE_EN` | RMW:S | `\|= 0x40000000` (DB_EN = 1) |
| 0x0060 | `CLK_EN` | RMW:C | `&= 0xfffffffe` (TG_DP_CK_EN off) |
| 0x0060 | `CLK_EN` | RMW:C | `&= 0xfffffffb` (PAK_DP_CK_EN off) |
| 0x0060 | `CLK_EN` | RMW:C | `&= 0xffff7fff` (IMGO_DP_CK_EN off) |

`mtk_cam_sv_tg_disable` (0x48e44) = **0x100 &= 0xfffffffe** (CMOS_EN off).
`mtk_cam_sv_dmao_disable` (0x493bc) = **0x40 &= 0xffffffef** (IMGO_EN off).
`mtk_cam_sv_fbc_disable` (0x49484) = **0x240 = 0**.
`mtk_cam_sv_toggle_tg_db` (0x48084) = 0x110 `\|= 0x100` then `&= 0xfffffeff` (b8 DB_LOAD_DIS pulse).
`mtk_cam_sv_toggle_db` (0x48338) = 0x40 `&= 0xbfffffff` then `\|= 0x40000000` (DB_EN low pulse).

**Net capture order:**

```
dev_config:
  cal_cfg_info → setup_cfg_info(0x110 hold, 0x108/0x10C/0x44/0x7C/0x710/0x714/0x718, 0x110 release)
  pipeline_config → format_sel → pak_sel → xsize_cal            (no MMIO)
  tg_config(0x100,0x104,0x108,0x10C,0x110,0x164)
  top_config(0x40,0x44,0x48,0x74,0x78,0x7C,0x88,0x1C0,0x600)
  dmao_config(0x710,0x714,0x718,0x74C,0x720..0x730)
  fbc_config(0x240 = 0)
  tg_enable(0x100 |= 0x1)
  top_enable(0x60 |= 0xF805 ; dmao_enable: 0x40 |= 0x10 ; fbc_enable: 0x240 = (ratio<<24)|0x8000 ; 0x104 |= 0x1 if VF)
per frame:
  enquehwbuf(0x75C = frame_no, 0x700 = addr[31:0], 0x704 = addr[35:32] & 0xF, 0x14 = 1)
stream_on:
  vf_on(0x104 = 0) → 0x240 = 0 → 0x40 &= ~0x10 → 0x100 &= ~0x1 → vf_on(0x104 |= 0x1)
stream_off (reverse):
  0x104 &= ~0x1 → dmao_disable(0x40 &= ~0x10) + fbc_disable(0x240 = 0) → 0x40 &= ~0x40000000 → 0x40 = 0
  → 0x44 = 0 → 0x48 = 0 → 0x240 = 0 → 0x40 |= 0x40000000 → 0x60 &= ~0x8001 (TG+IMGO clocks off)
```

---

### Caveats

* All `bl` symbols were stripped to self-address; callee identification above is by *symbol name of
  the enclosing function range* (each callee body was read and matches the label), not by the branch
  target. Where the listing shows a `bl` inside `dev_config`, the nearest following labelled function
  whose signature matches the argument setup was used.
* `mtk_cam_sv_dmao_config` writes 0x071C?, the read of `str` to 0x71C was **not** observed in the
  body; only 0x710, 0x714, 0x718, 0x74C=0 and 0x720/0x724/0x728/0x72C/0x730 are written.
  Values for the CON0..4 group: `0x10000300, 0x00c00060, 0x01800120, 0x820001a0, 0x812000c0`
  when `[x19+0x10] <= 9`, else `0x10000080, 0x00200010, 0x00400030, 0x80550045, 0x80300020`.
* Bytes after each function's final `ret` (+`bti j`) are `ldar`/`bti j` fill and were excluded.
