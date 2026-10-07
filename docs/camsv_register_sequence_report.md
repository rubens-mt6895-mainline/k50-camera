# CAMSV hardware register sequences: reconstructed from `isp_ko.asm`

Source: `${K50_REPO}\isp_ko.asm` (`objdump -d` of vendor `mtk-cam-isp.ko`), functions at lines 74533–76160.
Register names/bitfields: `${K50_REPO}\isp71_ref\mtk_cam-sv-regs.h`.

**Conventions used below**

- `dev->base` (the ioremap'd CAMSV register block) is always `x8 = [x0, #0x18]`; every `add xN, base, #IMM` is the register offset in the table.
- A **second, read-only** pointer at `[x0, #0x20]` appears only in `mtk_cam_sv_toggle_tg_db` / `mtk_cam_sv_toggle_db`. It is read before and after the actual RMW and the two values are handed to the trailing log call, it is **not** written. (It is either a sibling CAMSV block or a shadowed copy; treat it as a debug snapshot.)
- All `bl` targets are zeroed by the vendor stripping step (`bl <own-address>`), so callees **cannot** be resolved. They are recorded as `bl (unresolved)` with the likely callee marked `[inferred]` where the pattern is unambiguous.
- Each function's **real body ends at its final `ret`**. Everything after it (a run of `bti j`, `ldar`, and duplicated instrumented accessor stubs with `mov w0, #0x20`) is out-of-line helper/KASAN code, not body, it was not treated as part of the sequence.
- `op` meanings: **OR-set** = read-modify-write with `orr` (mask shown = bits asserted to 1), **AND-clear** = read-modify-write with `and` (mask shown = bits forced to 0), **write** = plain `str` of a full value, **read** = load only.

---

## 1. `mtk_cam_sv_tg_enable` (lines 74533–74554, 0x47fbc–0x4800c)

Summary: one RMW, asserts `TG_SEN_MODE.CMOS_EN`, which powers/arms the TG sensor interface. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x100 | `TG_SEN_MODE` | OR-set | `0x1` — **CMOS_EN (b0)** |

---

## 2. `mtk_cam_sv_toggle_tg_db` (lines 74585–74632, 0x48084–0x4813c)

Summary: pulses the TG path's DB-load-disable field, set then immediately clear, i.e. a "toggle" of DB load on `TG_PATH_CFG`, followed by a logging call.

| offset | register | op | value / bits |
|---|---|---|---|
| (0x110) | `TG_PATH_CFG` (via `[x0,#0x20]`) | read | pre-snapshot → w3 |
| 0x110 | `TG_PATH_CFG` | OR-set | `0x100` — **DB_LOAD_DIS (b8) = 1** |
| 0x110 | `TG_PATH_CFG` | AND-clear | `0x100` — **DB_LOAD_DIS (b8) = 0** |
| (0x110) | `TG_PATH_CFG` (via `[x0,#0x20]`) | read | post-snapshot → w4 |
| — | — | `bl` (unresolved) | log call: `x0 = [x0]` (dev->dev), `x1`/`x2` = rodata strings (w3/w4 as payload) |

Net effect: `TG_PATH_CFG.DB_LOAD_DIS` ends at 0 (DB load allowed).

---

## 3. `mtk_cam_sv_toggle_db` (lines 74760–74807, 0x48338–0x483f0)

Summary: drops then re-asserts `MODULE_EN.DB_EN (b30)`, a clean 0→1 edge on the DB engine enable.

| offset | register | op | value / bits |
|---|---|---|---|
| (0x040) | `MODULE_EN` (via `[x0,#0x20]`) | read | pre-snapshot → w3 |
| 0x040 | `MODULE_EN` | AND-clear | `0x40000000` — **DB_EN (b30) = 0** |
| 0x040 | `MODULE_EN` | OR-set | `0x40000000` — **DB_EN (b30) = 1** |
| (0x040) | `MODULE_EN` (via `[x0,#0x20]`) | read | post-snapshot → w4 |
| — | — | `bl` (unresolved) | log call (same shape as §2) |

---

## 4. `mtk_cam_sv_top_enable` (lines 74935–75037, 0x485ec–0x48780)

Summary: the top-level bring-up, enable all four DP clocks, call TG-enable then DMAO-enable, arm FBC `DB_EN`, then (conditionally) raise `VFDATA_EN` on the TG VF control. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x060 | `CLK_EN` | OR-set | `0x1` — **TG_DP_CK_EN (b0)** |
| 0x060 | `CLK_EN` | OR-set | `0x2` — **QBN_DP_CK_EN (b1)** |
| 0x060 | `CLK_EN` | OR-set | `0x4` — **PAK_DP_CK_EN (b2)** |
| 0x060 | `CLK_EN` | OR-set | `0x8000` — **IMGO_DP_CK_EN (b15)** |
| — | — | `bl` (unresolved) | `x0 = dev` → likely `mtk_cam_sv_tg_enable` `[inferred]` |
| — | — | `bl` (unresolved) | `x0 = dev` → likely `mtk_cam_sv_dmao_enable` `[inferred]` |
| 0x240 | `FBC_IMGO_CTL1` | OR-set | `0x200` — **FBC_DB_EN (b9) = 1** |
| 0x240 | `FBC_IMGO_CTL1` | read | w3 (payload for log) |
| 0x244 | `FBC_IMGO_CTL2` | read | w4 — counters (`IMGO_RCNT/WCNT/FBC_CNT/DROP_CNT`) |
| — | — | `bl` (unresolved) | log call: `x0 = [x19]` (dev->dev) |
| 0x100 | `TG_SEN_MODE` | read | test **CMOS_EN (b0)** |
| — | `dev+0x98` | read | flag test (host-side "vf wanted" style flag; not a register) |
| 0x104 | `TG_VF_CON` | OR-set | `0x1` — **VFDATA_EN (b0)** — **only if CMOS_EN(b0) is set AND `dev+0x98 != 0`** |

Note: the four `CLK_EN` writes are independent RMWs (bits accumulate), and the final `VFDATA_EN` write is guarded, so on a cold path `top_enable` alone may not start streaming.

---

## 5. `mtk_cam_sv_dmao_enable` (lines 75247–75268, 0x48ac4–0x48b14)

Summary: one RMW, asserts the IMGO DMA output enable. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x040 | `MODULE_EN` | OR-set | `0x10` — **IMGO_EN (b4)** |

---

## 6. `mtk_cam_sv_fbc_enable` (lines 75299–75348, 0x48b8c–0x48c4c)

Summary: **refuses to run once the VF is already streaming** (returns `-1` if `VFDATA_EN` is set); otherwise writes the FBC sub-ratio, sets `FBC_EN`, and clears `FBC_DB_EN`. Signature: `(dev, const void *cfg)` with `cfg+8` supplying the ratio byte.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x104 | `TG_VF_CON` | read | if **VFDATA_EN (b0) == 1** → `bl` log, **return -1** (no register writes) |
| 0x240 | `FBC_IMGO_CTL1` | write | `(old & 0x00FFFFFF) \| ((*(u8*)(x1+8)) << 24)` — **SUB_RATIO (b24..31)** = `cfg[8]`, bits above 24 replaced |
| 0x240 | `FBC_IMGO_CTL1` | OR-set | `0x8000` — **FBC_EN (b15) = 1** |
| 0x240 | `FBC_IMGO_CTL1` | AND-clear | `0x200` — **FBC_DB_EN (b9) = 0** |

---

## 7. `mtk_cam_sv_tg_disable` (lines 75475–75496, 0x48e44–0x48e94)

Summary: mirror of §1, clears `TG_SEN_MODE.CMOS_EN`. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x100 | `TG_SEN_MODE` | AND-clear | `0x1` — **CMOS_EN (b0) = 0** |

---

## 8. `mtk_cam_sv_top_disable` (lines 75527–75631, 0x48f0c–0x490a8)

Summary: the top-level teardown, stop VF first (clear `VFDATA_EN`, then call the TG-disable helper), drop `DB_EN`, **zero MODULE_EN / FMT_SEL / INT_EN / FBC_IMGO_CTL1 wholesale**, re-assert `DB_EN`, then gate the DP clocks. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x104 | `TG_VF_CON` | read | test **VFDATA_EN (b0)** |
| 0x104 | `TG_VF_CON` | AND-clear | `0x1` — **VFDATA_EN (b0) = 0** — *only if b0 was set* |
| — | — | `bl` (unresolved) | `x0 = dev`, inside the VFDATA_EN branch (vf/irq stop helper) |
| — | — | `bl` (unresolved) | `x0 = dev`, unconditional → likely `mtk_cam_sv_tg_disable` `[inferred]` |
| 0x040 | `MODULE_EN` | AND-clear | `0x40000000` — **DB_EN (b30) = 0** |
| 0x040 | `MODULE_EN` | **write** | `0x0` — clears **TG_EN(b0), PAK_EN(b2), PAK_SEL(b3), IMGO_EN(b4), UFE_EN(b6), QBN_EN(b7), DOWN_SAMPLE_EN(b24), DB_LOAD_*(b25-29)** in one shot |
| 0x044 | `FMT_SEL` | **write** | `0x0` — TG1_FMT/TG1_SW/LP_MODE/HLR_MODE cleared |
| 0x048 | `INT_EN` | **write** | `0x0` — all interrupts masked (incl. **INT_WCLR_EN (b31)**) |
| 0x240 | `FBC_IMGO_CTL1` | **write** | `0x0` — FBC fully off (incl. FBC_EN b15, FBC_RESET b8, VALID_NUM/SUB_RATIO) |
| 0x040 | `MODULE_EN` | OR-set | `0x40000000` — **DB_EN (b30) = 1** (re-arm DB after the zeroing write) |
| 0x060 | `CLK_EN` | AND-clear | `0x1` — **TG_DP_CK_EN (b0) = 0** |
| 0x060 | `CLK_EN` | AND-clear | `0x4` — **PAK_DP_CK_EN (b2) = 0** |
| 0x060 | `CLK_EN` | AND-clear | `0x8000` — **IMGO_DP_CK_EN (b15) = 0** |

Asymmetries worth flagging: `QBN_DP_CK_EN (b1)` is **set** by `top_enable` but **never cleared** here; `UFEO_DP_CK_EN (b4)` is never touched by either. The `0x240` zeroing also makes the separate `mtk_cam_sv_fbc_disable` (§10) redundant when reached via `top_disable`.

---

## 9. `mtk_cam_sv_dmao_disable` (lines 75829–75850, 0x493bc–0x4940c)

Summary: mirror of §5, clears IMGO DMA output enable. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x040 | `MODULE_EN` | AND-clear | `0x10` — **IMGO_EN (b4) = 0** |

---

## 10. `mtk_cam_sv_fbc_disable` (lines 75881–75896, 0x49484–0x494bc)

Summary: plain full-register zero of the FBC control (no read-modify-write, no guard). Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x240 | `FBC_IMGO_CTL1` | **write** | `0x0` — FBC_RESET/FBC_DB_EN/LOCK_EN/FBC_SUB_EN/**FBC_EN(b15)**/VALID_NUM/SUB_RATIO all cleared |

---

## 11. `mtk_cam_sv_vf_on` (lines 75906–75949, 0x494e0–0x49588)

Summary: **the capture start/stop trigger.** Called as `mtk_cam_sv_vf_on(dev, on)`; RMWs exactly one bit, and is idempotent, it writes only when the bit is in the wrong state. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x104 | `TG_VF_CON` | read | test **VFDATA_EN (b0)** |
| 0x104 | `TG_VF_CON` | OR-set | `0x1` — **VFDATA_EN (b0) = 1** — **`w1 (on) != 0` and b0 currently 0** |
| 0x104 | `TG_VF_CON` | AND-clear | `0x1` — **VFDATA_EN (b0) = 0** — **`w1 (on) == 0` and b0 currently 1** |
| 0x104 | `TG_VF_CON` | (no write) | if state already matches `w1`, nothing is written |

---

## 12. `mtk_cam_sv_is_vf_on` (lines 76049–76065, 0x49714–0x49750)

Summary: pure read, returns the VF streaming bit. No writes, no calls.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x104 | `TG_VF_CON` | **read** | `return w8 & 0x1` → **VFDATA_EN (b0)** |

It reads offset **0x104** and tests bit **0** (`and w0, w8, #0x1`).

---

## 13. `mtk_cam_sv_enquehwbuf` (lines 76082–76111, 0x49790–0x49800)

Summary: hands one hardware buffer to the IMGO DMA engine, programs the frame sequence number, the 36-bit destination address (low word + 4-bit MSB), then kicks the FBC/ring counter. Signature `(dev, dma_addr_t addr /*x1*/, u32 seq /*w2*/)`. Returns 0.

| offset | register | op | value / bits |
|---|---|---|---|
| 0x75C | `FRAME_SEQ_NO` | **write** | `w2` — frame sequence number |
| 0x700 | `IMGO_BASE_ADDR` | **write** | `w1` — destination address bits **[31:0]** |
| 0x704 | `IMGO_BASE_ADDR_MSB` | **write** | `ubfx x1, #32, #4` — address bits **[35:32]** (upper nibble of the 36-bit address) |
| 0x014 | `TOP_FBC_CNT_SET` | **write** | `0x1` — **RCNT_INC1 (b0) = 1** (kick) |

(The same `0x014 = 1` RCNT kick is performed by the sibling `mtk_cam_sv_write_rcnt`/`mtk_cam_sv_write_rcnt_sv_dev`, confirming the field's meaning.)

---

## Minimal capture start sequence

Exact ordered register writes to start **one** CAMSV capture, as deduced from the enable functions above. All offsets are from `dev->base`; `|=` / `&=~` denote read-modify-write as the driver performs them.

1. **0x060 `CLK_EN`**, `|= 0x1` (TG_DP_CK_EN), `|= 0x2` (QBN_DP_CK_EN), `|= 0x4` (PAK_DP_CK_EN), `|= 0x8000` (IMGO_DP_CK_EN)  ← `mtk_cam_sv_top_enable` step 1
2. **`bl` → `mtk_cam_sv_tg_enable`**, **0x100 `TG_SEN_MODE`** `|= 0x1` (**CMOS_EN**)  ← arms the TG/sensor interface
3. **`bl` → `mtk_cam_sv_dmao_enable`**, **0x040 `MODULE_EN`** `|= 0x10` (**IMGO_EN**)  ← arms the output DMA
4. **0x240 `FBC_IMGO_CTL1`** `|= 0x200` (**FBC_DB_EN**)  ← `mtk_cam_sv_top_enable` step 2
5. *(outside these 13 functions)* the window/format programming must already have been done: `0x044 FMT_SEL`, `0x108 TG_SEN_GRAB_PXL`, `0x10C TG_SEN_GRAB_LIN`, `0x110 TG_PATH_CFG`, `0x1C0 PAK_CON`, `0x700..0x730` IMGO window/stride/basic/CON0-4. Note `MODULE_EN.TG_EN (b0)` and `MODULE_EN.PAK_EN (b2)` are **never** written by any of the 13 functions, they must be set by that same config path (or by hardware default), so do not assume the §1–§4 subset is sufficient alone.
6. **`mtk_cam_sv_enquehwbuf(dev, addr, seq)`**, **0x75C** = seq, **0x700** = addr[31:0], **0x704** = addr[35:32], **0x014** = 1 (RCNT_INC1 kick)
7. **`mtk_cam_sv_fbc_enable(dev, cfg)`**, **0x240** = `(0x240 & 0x00FFFFFF) | (cfg[8] << 24)`; **0x240** `|= 0x8000` (**FBC_EN**); **0x240** `&= ~0x200` (clear FBC_DB_EN). **Must come before step 8**, the function aborts with `-1` if `0x104 b0` is already set.
8. **`mtk_cam_sv_vf_on(dev, 1)`**, **0x104 `TG_VF_CON`** `|= 0x1` (**VFDATA_EN**)  ← **final "go" / start-capture trigger**; then `mtk_cam_sv_is_vf_on()` reads `0x104 b0` to confirm streaming.

**Ordering rationale.** `VFDATA_EN` is the last thing raised and the first thing dropped; both `fbc_enable` (guard) and `top_enable` (conditional write) treat `0x104 b0` as the "already streaming" flag, so everything that can be configured only while idle (FBC ratio/enable, buffer enqueue) must precede step 8.

**Stop sequence (reverse, from `mtk_cam_sv_top_disable`).** `0x104 &= ~0x1` (stop VF) → calls → `0x040 &= ~0x40000000` (DB_EN=0) → **`0x040 = 0`** (all module enables incl. TG_EN/IMGO_EN) → **`0x044 = 0`** → **`0x048 = 0`** (all IRQs masked) → **`0x240 = 0`** (FBC off) → `0x040 |= 0x40000000` (re-arm DB_EN) → `0x060 &= ~0x1`, `&= ~0x4`, `&= ~0x8000` (gate DP clocks). Fine-grained alternatives: `tg_disable` (0x100 `&= ~1`), `dmao_disable` (0x40 `&= ~0x10`), `fbc_disable` (0x240 = 0), `vf_on(dev, 0)`.
