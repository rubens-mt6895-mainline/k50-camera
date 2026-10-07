# CAMSV frame parameters: IMX582 RAW10 4000x3000 on MT6895 (Redmi K50)

Research only; nothing here was verified on hardware. Evidence base:

- `${K50_REPO}\isp_ko.asm`, disassembly of the vendor `mtk-cam-isp.ko` (symbol names present,
  **all `bl` targets zeroed**, so callees must be identified by body). Line numbers below are
  this file's line numbers.
- `${K50_REPO}\isp71_ref\mtk_cam-sv-regs.h`, register header (bitfield truth for offsets/bit positions).
- `${K50_REPO}\camsv_report.md`, `camsv_register_sequence_report.md`, `CAMERA_NOTES.md`,
  `rubensimx582_Sensor.h`.

Confidence words: **high** = literal constant in vendor code; **med** = decoded from vendor code but
one input is unknown; **low** = inference only. Two earlier reports are corrected in §11.

## Quick table

| register | offset | value | confidence |
|---|---|---|---|
| FMT_SEL (TG1_FMT = 1) | 0x044 | `0x00000001` | high |
| TG_SEN_MODE (b5:4 DBL_DATA_BUS = 1) | 0x100 | `0x00010010` (before TG_EN); `0x00010011` after | med-high |
| PAK (PAK_DBL_MODE = 3, PAK_MODE = 0x81) | 0x07c | `0x00000381` (alt `0x0000038f`) | med-high |
| TG_SEN_GRAB_PXL | 0x108 | `0x0FA00000` (= (0+4000)<<16 \| 0) | med-high |
| TG_SEN_GRAB_LIN | 0x10c | `0x0BB80000` (= (0+3000)<<16 \| 0) | med-high |
| IMGO_XSIZE | 0x710 | `0x00001387` (= 5000-1) then `0x0000138F` if 16B-aligned | med |
| IMGO_YSIZE | 0x714 | `0x00000BB7` (= 3000-1) | high |
| IMGO_STRIDE | 0x718 | `0x00001388` (= 5000 B/line) | med |
| IMGO_CON0 | 0x720 | `0x10000300` | med |
| IMGO_CON1 | 0x724 | `0x00c00060` | med |
| IMGO_CON2 | 0x728 | `0x01800120` | med |
| IMGO_CON3 | 0x72c | `0x820001a0` | med |
| IMGO_CON4 | 0x730 | `0x812000c0` | med |
| FBC_IMGO_CTL1 | 0x240 | `0x00000000` (FBC off) | high |
| INT_EN | 0x048 | `0x00011070` | high |

Register-value convention: CAMSV section base `0x1a110000 + n*0x1000` (camsv1 on K50; CAMERA_NOTES.md:893).
Offsets are section offsets; the header's offsets match (`isp71_ref/mtk_cam-sv-regs.h:47,248,306,396,473,520`).

## 1. `FMT_SEL` / `TG1_FMT` (0x044): RAW10 ⇒ **1** (high)

`0x044` is a **plain write** of the TG1_FMT code (`isp_ko.asm:73356`, in `mtk_cam_sv_top_config`).
The code is produced by three mutually independent, constant-for-constant identical switches:

- `mtk_cam_sv_format_sel` (`isp_ko.asm:71613`).
- `mtk_cam_sv_cal_cfg_info` first switch (`isp_ko.asm:76223`): `1` for `{pBAA,pGAA,pRAA,pgAA,
  MBBA,MBGA,MBRA,MBgA}`; `2` for `{MBBC,MBGC,MBRC,MBgC}`; `4` for `{MBBE,MBGE,MBgE,MBRE,LBBE,LBRE}`;
  else `0`; stored at cfg-record +0xc.
- `mtk_cam_sv_top_config` repeats the same tree (`isp_ko.asm:73259-73356`) then writes `0x044 = w9`.

Fourcc naming (from `isp_ko.asm` constants + .rodata name strings such as "10-bit Bayer BGGR MTISP
Packed"): in `MBxy` the last letter is the depth (A/C/E = 10/12/14-bit) and the three in each group
differ only in the third letter, i.e. they are the four Bayer-order variants of one depth (the vendor's
strings label the four as BGGR/GBRG/RGGB/GRBG; which letter denotes which order is not independently
confirmed, but it does not matter here, every group covers all four orders). `p*AA` = "10-bit
Enhanced"; bare `BA81/GRBG/GBRG/RGGB` = 8-bit V4L2 codes.

That depth ladder is confirmed independently by `mtk_cam_sv_xsize_cal` (`isp_ko.asm:71816`), which
buckets the *same* fourcc groups into 1, 1.25, 1.5 and 1.75 bytes/pixel (§5). So TG1_FMT is a
**bit-depth code**: 0 = 8-bit, 1 = 10-bit, 2 = 12-bit, 4 = 14-bit. RAW10 (M*A or p*AA family) ⇒ `1`.
(The earlier report's reading "1 = GR/BG, 2 = BA/RG, 4 = 8AB1" happens to give the same answer for
RAW10; §11 explains why its *labels* are wrong.)

## 2. `TG_SEN_MODE` b5:4 DBL_DATA_BUS (0x100): **case 3 ⇒ field = 1** (med-high)

`mtk_cam_sv_tg_config` selects on the descriptor's format-code byte `desc+0x06`
(`isp_ko.asm:72147-72161`: `ldrb w8,[x1,#0x6]; cmp w8,#3; b.ls` else return -1):

| desc[6] | code body | effect on 0x100 b5:4 |
|---|---|---|
| 0 | `isp_ko.asm:72163-72173` | `&= 0xffffffcf` (0) |
| 1 | `isp_ko.asm:72175-72186` | `= (raw & 0xffffffcf) \| 0x20` (2) |
| 2 | `isp_ko.asm:72188-72198` | `\|= 0x30` (3) |
| 3 | `isp_ko.asm:72200-72210` | `= (raw & 0xffffffcf) \| 0x10` (1) |

Which case applies is decided by `desc[6]`. Best-supported value: **3**, because the vendor's own
config record stores PAK = `0x300 | pak_sel(fourcc)` for this path (§3) and `pak_sel` folds its second
argument into PAK bits 9:8 (`bfi w0, w1, #8, #2`, `isp_ko.asm:71812`), i.e. the same descriptor byte is
TG1_SW/PAK_DBL_MODE = 3 in the vendor's own record. Case 3 ⇒ DBL_DATA_BUS b5:4 = **1**.

Full register state from `tg_config` (b5:4 replaced by the field; other bits): `0x100 &= ~1` (CMOS_EN=0,
`isp_ko.asm:71963-71969`), `0x100 |= 0x10000` (TIME_STP_EN b16, unconditional, `isp_ko.asm:72127-72136`),
b17/b18 (SOF_SUB/VS_SUB_EN) only if `desc[8] != 0` else cleared (`isp_ko.asm:72018-72060`), b22
STAGGER_EN only if the sensor reports stagger (`isp_ko.asm:72061-72108`; IMX582 is non-staggered) ⇒
`TG_SEN_MODE = 0x00010010`; `mtk_cam_sv_tg_enable` later sets b0 (`0x100 |= 1`) ⇒ `0x00010011`.

*Alternative* (low confidence): if the HAL passes `desc[6] = 1` (depth code) instead of 3, the pair
becomes DBL_DATA_BUS = 2 (`0x20`) with PAK = `0x00000181` (bits 9:8 = 1). The two fields are coupled;
try the (3, 0x10, 0x381) combination first.

## 3. `PAK` (0x07C): **0x00000381** (med-high)

`mtk_cam_sv_pak_sel` (`isp_ko.asm:71714-71812`) is fully decoded. It takes `w0` = fourcc, `w1` =
TG1_SW/PAK_DBL_MODE, returns `((w1 & 3) << 8) | <code>` (`isp_ko.asm:71812`):

| returned low byte | fourccs (literal constants in code) | meaning |
|---|---|---|
| `0x80` | `BA81`=`0x31384142` (`71730-71733`), `RGGB`=`0x42474752` (`71748-71750`), `GBRG`=`0x47524247` (`71803-71806`), `GRBG`=`0x47425247` (`71807-71811`) | 8-bit Bayer family |
| `0x81` | `MBgA`=`0x4167424d` (`71744-71747`), `MBBA`=`0x4142424d` (`71759-71761`), `MBGA`=`0x4147424d` (`71793-71796`), `MBRA`=`0x4152424d` (`71797-71802`) | 10-bit MTISP Bayer family |
| `0x82` | `MBRC`=`0x4352424d` (`71766-71769`), `MBgC`=`0x4367424d` (`71770-71772`), `MBBC`=`0x4342424d` (`71783-71786`), `MBGC`=`0x4347424d` (`71787-71792`) | 12-bit MTISP Bayer family |
| `0x8f` | `pgAA`=`0x41416770` (`71755-71758`), `pGAA`=`0x41414770` (`71773-71776`), `pRAA`=`0x41415270` / `pBAA`=`0x41414270` (`71734-71735` + shared `71777-71782`) | 10-bit "Enhanced" family |
| `0x00` | anything else (incl. all 14-bit `M*E`) | unmapped |

The low byte is therefore a **format/packing class, not a Bayer order**: each group covers all four
orders. `mtk_cam_sv_cal_cfg_info` stores `cfg[0x10] = 0x300 | pak_sel(fourcc)` (its second switch maps
the same groups to `0x380/0x381/0x382/0x38F`, i.e. TG1_SW = 3), and `mtk_cam_sv_setup_cfg_info`
(`isp_ko.asm:76485`) writes that record field straight to `0x07C`. `mtk_cam_sv_top_config` writes
`0x07C` again, later, from `pak_sel(desc)`; call order in `mtk_cam_sv_dev_config` is
cal_cfg_info → setup_cfg_info → … → top_config (`isp_ko.asm:77465+`), so **top_config's value is final**.

Chosen value: PAK_MODE b7:0 = `0x81` (10-bit MTISP; `0x8f` if the format id is the "Enhanced" `p*AA`
family), PAK_DBL_MODE b9:8 = `3` ⇒ **`0x00000381`** (alt `0x0000038f`). Header field names:
`PAK_MODE` b7:0 / `PAK_DBL_MODE` b9:8 (`isp71_ref/mtk_cam-sv-regs.h:220-221`).
Related fixed write from the same path: `0x1C0` PAK_IN_BIT = 14 (`isp71_ref/mtk_cam-sv-regs.h:389`).

## 4. `TG_SEN_GRAB_PXL` (0x108) / `TG_SEN_GRAB_LIN` (0x10C): full frame, **no −1** (med-high)

Literal code, `isp_ko.asm:72211-72228`:

```
ldurh w8,[x1,#0xd]   ; width      ldurh w11,[x1,#0x9]  ; startx
ldurh w9,[x1,#0xf]   ; height     ldurh w12,[x1,#0xb]  ; starty
add  w8,w11,w8       ; startx+width
add  w14,w12,w9      ; starty+height
lsl  w9,w8,#16   / bfxil x9,x11,#0,#16     -> str w9,[..+0x108]
lsl  w8,w14,#16  / bfxil x8,x12,#0,#16     -> str w8,[..+0x10c]
```

So the register layout is `(END << 16) | START` and the vendor uses **width/height directly**
(END = start + size), *not* size−1. `mtk_cam_sv_cal_cfg_info` builds the same two words for the
setup path (`cfg[0x04] = width<<16`, `cfg[0x08] = height<<16`), which `mtk_cam_sv_setup_cfg_info`
writes to 0x108/0x10C, consistent for start = 0.

For a full 4000x3000 frame with startx = starty = 0 (the vendor zeroes startx/starty in
`mtk_cam_sv_dev_config`, `isp_ko.asm:77587-77620`):

- `0x108 = 0x0FA00000` (4000 = 0x0FA0 in bits 31:16, start 0 in 15:0)
- `0x10C = 0x0BB80000` (3000 = 0x0BB8, start 0)

*Flag:* if the TG treats END inclusively this window is 4001x3001. The vendor's own code says
start+size, so program that first; the fallback is END = start + size − 1 (`0x0F9F0000` /
`0x0BB70000`).

## 5. `IMGO_XSIZE` (0x710) / `IMGO_YSIZE` (0x714) / `IMGO_STRIDE` (0x718): **packed, 5000 B/line** (med)

`mtk_cam_sv_dmao_config` (`isp_ko.asm:74207`):

```
bl   <xsize helper>            ; 74220, x0 = desc
sub  w8, w0, #1 ; str w8,[..+0x710]     ; 74222-74225   XSIZE = helper(desc) - 1
ldurh w8,[x22,#0xf] ; sub w8,w8,#1 ; str w8,[..+0x714]  ; 74226-74232  YSIZE = height - 1
bl   <stride helper> ; str w0,[..+0x718]                ; 74231-74239  STRIDE = helper2(desc)
tst  w21,#0x2f0 ; if set: bl <helper3>; if (w0 < w3) -> log and 0x718 = w3  ; 74237-74255
```

**Byte count per line:** the size helper is `mtk_cam_sv_xsize_cal` (`isp_ko.asm:71816-71951`), which
switches on the fourcc at `desc+0x00` and returns a **byte count**:

- 8-bit `{BA81,GBRG,GRBG,RGGB}` → `w8 = width` (1 B/px, body at `isp_ko.asm:71901-71902`, reached from 71888/71892/71897);
- 10-bit `{pBAA,pGAA,pRAA,pgAA,MBBA,MBGA,MBRA,MBgA}` → `ldurh w8,[x0,#0xd]; add w8,w8,w8,lsl#2;
  ubfx w8,w8,#2,#29` = **5*width/4** (`isp_ko.asm:71923-71926`, reached e.g. from 71869/71873/71894
  pBAA at 71898-71900 and 71904/71918/71922);
- 12-bit `{MBBC,MBGC,MBRC,MBgC}` → `(w8 + w8<<1) >> 1` = 3*width/2 (`isp_ko.asm:71911-71914`);
- 14-bit `{MBBE,MBGE,MBgE,MBRE}` → `mov w9,#0xe; mul; lsr #3` = 14*width/8 (`isp_ko.asm:71935-71938`);
- finally `ldrsb x9,[x0,#6]; cmp #3; b.hi -> 0; t0 = table[x9]; return (w8 + t0) & ~t0` via
  `add w8,w9,w8; bic w0,w8,w9` (`isp_ko.asm:71939-71948`), an alignment step whose 4-entry table
  (`adrp` at `isp_ko.asm:71942-71944`) lives at an address that cannot be recovered from
  `isp_ko.asm` (the `adrp` targets are unresolvable in the stripped object).

**There is no 2*width (16-bit container) branch anywhere in this function**, and the generic sibling
`mtk_cam_dmao_xsize(width, fmt_idx, shift)` (`isp_ko.asm:41596-41630`) computes the same kind of
value for the same driver: `line_bytes = bpp*width/8` rounded up, aligned to `((bpp+15)&~15)/8` bytes,
and returns `aligned - 1`. For bpp = 10 that alignment is 2 bytes, so 4000 px RAW10 ⇒
`5*4000/4 = 5000` bytes, already 8-byte (and 2-byte/4-byte) aligned.

Conclusion: **CAMSV writes packed RAW10: 4000 px ⇒ 5000 bytes/line** (not 8000). Therefore:

- `IMGO_XSIZE (0x710) = 5000 - 1 = 4999 = 0x1387`. If the unrecovered alignment table entry for
  `desc[6]=3` turns out to be 16-byte alignment, 5000 is not a multiple of 16 (5000/16 = 312.5) and the
  value becomes `5008-1 = 5007 = 0x138F`. Priority: `0x1387`, then `0x138F`.
- `IMGO_YSIZE (0x714) = 3000 - 1 = 2999 = 0x0BB7` (high: literal `height-1`). Note the asymmetry with
  GRAB_LIN, which gets the full height.
- `IMGO_STRIDE (0x718)` comes from a *second* helper call that I could not identify (the two later
  calls in `dmao_config` take the same descriptor and, being unrelocated, cannot be resolved to
  symbols; there is no `mtk_cam_sv_stride_cal` symbol in the module). Priority order to try:
  1. `5000 = 0x1388`, stride == packed line bytes; matches `mtk_cam_dmao_xsize` for RAW10.
  2. `5008 = 0x1390` / `5024 = 0x13A0` / `5120 = 0x1400`, only if the IMGO bus needs 16/32/256-byte
     line alignment.
  3. `8000 = 0x1F40`, 16-bit container; **contradicted by the code**, try last, and see §8 (it would
     also blow the 16 MiB buffer).

## 6. `IMGO_CON0..4` (0x720..0x730): set A (≤ 9) (med)

`isp_ko.asm:74283-74287`: `ldr w8,[x19,#0x10]; cmp w8,#9; b.hi <set B>`, where `x19` is the CAMSV
device/state struct (`[x19+0x18]` is the register base, `[x19]` is the `struct device *` used for
`dev_info`). Both hard-coded sets:

| reg | `[x19+0x10] <= 9` (set A) | else (set B) |
|---|---|---|
| 0x720 | `0x10000300` (`isp_ko.asm:74289-74291`) | `0x10000080` (`74318-74320`) |
| 0x724 | `0x00c00060` (`74295-74297`) | `0x00200010` (`74324-74326`) |
| 0x728 | `0x01800120` (`74301-74303`) | `0x00400030` (`74330-74332`) |
| 0x72c | `0x820001a0` (`74307-74309`) | `0x80550045` (`74333+`) |
| 0x730 | `0x812000c0` (`74313-74315`) | `0x80300020` |

`[x19+0x10]` is **not** the fmt-config record field that `cal_cfg_info` fills with `0x380…0x38F` (that
record's +0x10 is PAK; here +0x18 is the register base, so `x19` is the device struct, not the record).
Its identity is unresolved, a device/state `u32` that the vendor treats as 8 or 9 in the normal case:
`mtk_cam_sv_top_config` reads the same `[dev+0x10]`, masks `& 0xfffffffe` and compares against 8
(`isp_ko.asm:73111+`, ~0x46ba4). Since the vendor's own "known" values are 8–9, **set A is the expected
set** on MT6895; use set B only if the IMGO tiling/pattern is wrong.

## 7. `FBC_IMGO_CTL1` (0x240): **0** (high)

`mtk_cam_sv_fbc_config` (`isp_ko.asm:74508`) and `mtk_cam_sv_fbc_disable` (`isp_ko.asm:75881`) write
`0x240 = 0`; `mtk_cam_sv_dev_stream_on`'s OFF path also writes 0 (`isp_ko.asm:77922+`). Writing
`0x00000000` (no FBC) is the correct choice for a plain RAW10 capture.
If FBC were wanted, `mtk_cam_sv_fbc_enable` (`isp_ko.asm:75299`) writes
`0x240 = (raw & 0x00ffffff) | (cfg[8] << 24)`, i.e. **SUB_RATIO (b31:24, `isp71_ref/mtk_cam-sv-regs.h:409`)
= the FBC config byte 8**, plus `|= 0x8000` (FBC_EN b15) and `&= 0xfffffdff` (FBC_DB_EN b9 cleared),
and it refuses with -1 while `0x104` bit0 is set. With FBC off, SUB_RATIO must be 0.

## 8. Frame-size sanity check (high)

Packed RAW10 4000x3000 = 4000*3000*10/8 = **15,000,000 bytes** (14.31 MiB), note the 12 MB figure in
CAMERA_NOTES §9 is the pixel count, not bytes. CAMSV writes `stride * (ysize_reg+1)`
= 5000 * 3000 = 15,000,000 bytes ≤ 16 MiB (16,777,216), leaving 1,777,216 bytes of headroom. With the
16-byte-aligned stride 5008 it is 15,024,000 bytes, still fine. With a hypothetical 8000-byte stride it
would be 24,000,000 bytes = 22.9 MiB, which does **not** fit the 16 MiB buffer (it would fit the
28,576 kB free CMA pool, CAMERA_NOTES §9), a useful discriminator: if a 16 MiB buffer works, the
output really is packed.

DMA setup (already recovered): `0x75C = seq`, `0x700/0x704 = base addr[31:0]/[35:32]`,
`0x014 = 1` (`mtk_cam_sv_enquehwbuf`, `isp_ko.asm:76082`).

## 9. `INT_EN` (0x048) = `0x00011070` (high)

`mtk_cam_sv_top_config` writes it plainly (`isp_ko.asm:73360-73362`). Decoded with
`isp71_ref/mtk_cam-sv-regs.h:62-93`:

| bit | field | meaning |
|---|---|---|
| 4 | `TG_ERR_INT_EN` (`:69`) | TG error |
| 5 | `TG_GBERR_INT_EN` (`:70`) | TG group-buffer error |
| 6 | `TG_SOF_INT_EN` (`:71`) | start of frame |
| 12 | `SW_PASS1_DON_INT_EN` (`:77`) | SW pass1 done |
| 16 | `DMA_ERR_INT_EN` (`:81`) | DMA error |
| 20 | `IMGO_DONE_INT_EN` (`:85`) | IMGO frame written |

b0 `VS_INT_EN` and b31 `INT_WCLR_EN` are **not** set: VS is not enabled and INT_STATUS is not
auto-cleared on read, clear by writing the status bits back. Poll `INT_STATUS` (0x04C) for:

- **frame complete: b20 `CAMSV_INT_IMGO_DONE_ST` (`isp71_ref/mtk_cam-sv-regs.h:115`)**, and/or
  b12 `CAMSV_INT_SW_PASS1_DON_ST` (`:108`), b11 `CAMSV_INT_PASS1_DON_ST` (`:107`);
- errors: b4 `CAMSV_INT_TG_ERR_ST` (`:103`), b5 `CAMSV_INT_TG_GBERR_ST` (`:104`),
  b16 `CAMSV_INT_DMA_ERR_ST` (`:111`); also watch b17 `IMGO_OVERR` (`:112`) and b19 `IMGO_DROP` (`:114`).
  The header's aggregate error mask is `TG_ERR|TG_GBERR|DB_LOAD_ERR|DMA_ERR|IMGO_OVERR`
  (`isp71_ref/mtk_cam-sv-regs.h:621-625`).

## 10. Residual unknowns (do not treat as fact)

1. `desc[6]`'s exact value from the HAL (`3` assumed), couples TG_SEN_MODE b5:4 with PAK b9:8.
2. The 4-entry alignment table used by `xsize_cal` (unrecoverable `adrp` target), affects XSIZE
   (`4999` vs `5007`) only if it is 16-byte alignment.
3. The identity of `dmao_config`'s stride helper (and of the conditional third helper), affects
   STRIDE (5000 vs an aligned/padded value).
4. `[dev+0x10]`'s identity, decides IMGO_CON set A vs B.
5. Whether the TG treats `TG_SEN_GRAB_*` END inclusively (start+size vs start+size-1).

## 11. Corrections to the earlier reports

- `pak_sel`'s low byte is not a Bayer-order code ("0x80 GR/BG, 0x81 BA, 0x82 RG, 0x8F 8AB1"); it is a
  format/packing class covering **all four** Bayer orders (8-bit / 10-bit MTISP / 12-bit MTISP /
  10-bit Enhanced), see §3 for the literal fourcc membership.
- `format_sel`'s return is likewise a bit-depth code (0/1/2/4 = 8/10/12/14-bit), consistent with the
  bytes-per-pixel arithmetic in `xsize_cal`.
- CAMERA_NOTES.md:1061's assumption that the stride is the packed RAW10 bytes/line is **correct**;
  §8 above fixes the arithmetic (15,000,000 bytes, not ~12 MB).
- FBC is not used: `0x240 = 0`, no SUB_RATIO (CAMERA_NOTES §8.9 confirmed).
