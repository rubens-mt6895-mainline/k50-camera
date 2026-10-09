# SENINF routing for IMX582 on MIPI CSI port 2 (MT6895 / rubens) → CAMSV

Scope: pure source/log analysis. No device access. Authority = vendor ISP7.1 sources in
`${K50_REPO}\isp71_ref\` and the live HyperOS dmesg at
`${K50_REPO}\hyperos_workstate\dmesg_after_restart.txt`. `SENINF_CONFIG.md` /
`CAMERA_NOTES.md` are treated as working notes only (one of their open questions is answered
here; one of their claims is contradicted and called out in §5).

---

## 1. Answer in one paragraph

**port 2 → SENINF index/intf 4 (`SENINF_5`) → SENINF mux number 1 (`reg_if_mux[1]` =
`0x1a011d00`, `SRC_SEL` = `MIPI_SENSOR + group` = 8) → CAM_MUX 3 (`reg_if_cam_mux_pcsr[3]` =
`0x1a010460`, `CTRL.SRC_SEL` = 1, `CTRL.EN` = 1) → CAMSV1 @ `0x1a110000`.**
The `cam_mux → CAMSV` binding is **fixed hardware wiring**, declared in DT as
`mediatek,cammux-id = <0x03>` on `camsv1@1a110000`; there is no SENINF or CAM register that
selects which CAMSV consumes a given cam_mux. **Our module's hardcoded CAMSV1 = `0x1a110000`
is therefore correct, but only if we drive cam_mux 3**, the vendor's proven-working preview
used cam_mux **0** (VC0/RAW0, 4000×3000) and cam_mux **15** (VC1, 992×1488), which feed
`cam_raw_a` and `mraw1`, i.e. the **RAW/MRAW** path, *not* CAMSV. Any plan that reuses cam_mux 0
or 15 will feed the RAW/MRAW blocks and CAMSV1 will see nothing.

Mux number choice is free (any unused mux works, the allocation is dynamic in vendor code,
`mtk_cam-seninf-drv.c:927-947`). We pick **mux 1** because that is the mux the vendor actually
assigned to port 2 / intf 4 for this sensor (log line 14343), so its field values (FIFO_PUSH_EN
= 0x1f, etc.) are known-proven.

---

## 2. Mechanism

1. **CSI port → SENINF instance.** `mtk_cam-seninf-hw_phy_3_0.c:203-206` maps `CSI_PORT_2` /
   `CSI_PORT_2A` to `ctx->seninfIdx = SENINF_5`, and `SENINF_1` is 0 in the enum
   (`mtk_cam-seninf-def.h:139-144`), so **intf = 4**. That number is the value the vendor writes
   into the TOP mux-select array (see step 3 below), and it matches the log's
   `intf 4`.
2. **PHY/CSI2 → which packets get in.** The port-2 CSI2 block (`0x1a014a00`) filters incoming
   MIPI packets into up to 8 "stream" slots `S0..S7` via `SENINF_CSI2_Sn_DI_CTRL`
   (VC + data-type match), and each slot is assigned to one of 4 groups `CH0..CH3` via
   `SENINF_CSI2_CHn_CTRL`. `SET_DI_CTRL` programs `DT_SEL`, `VC_SEL`, `DT_INTERLEAVE_MODE = 1`,
   `VC_INTERLEAVE_EN = 1`; `SET_CH_CTRL` then sets `CH<group>_S<n>_GRP_EN = 1`
   (`mtk_cam-seninf-hw_phy_3_0.c:42-66`, applied at `:774-823`). For our sensor VC0 / DT 0x2b is
   vcinfo index 0 → slot **S0**, and its group is **0** → **CH0**
   (log `vc[0] vc 0x0 dt 0x2b ... grp 0x0`).
3. **Which source the SENINF mux reads.** There is a flat array of 22 SENINF mux blocks in TOP:
   `reg_if_mux[j] = if_base + 0x0d00 + 0x1000*j` where **j is the mux number**
   (`..._3_0.c:161-162`). Each mux has two selectors that must agree:
   - `SENINF_MUX_CTRL_1.RG_SENINF_MUX_SRC_SEL` = *source group*, programmed as
     `MIPI_SENSOR + vc->group` (`mtk_cam-seninf-drv.c:950-955`; enum values in
     `mtk_cam-seninf-def.h:212-228`: `MIPI_SENSOR = 0x8`, `VIRTUAL_CHANNEL_1 = 0x9`, …). So
     group 0 → **8**, group 1 → 9. (Naming oddity: 8 is documented as "MIPI_SENSOR (1.5G)" and
     9..14 as "VIRTUAL_CHANNEL_n", but the driver formula `MIPI_SENSOR + group` makes them
     numerically one sequence.)
   - `SENINF_TOP_MUX_CTRL_i.RG_SENINF_MUXn_SRC_SEL` (TOP block, `0x1a010010 + 4*i`, one *byte*
     field per mux, 5 bits used) = **which SENINF intf** that mux listens to
     (`mtk_cam-seninf-hw_phy_3_0.c:345-452`, written from `drv.c:957` with `intf`).
   The vendor label is 1-based: `RG_SENINF_MUX2_SRC_SEL` controls **mux number 1**, i.e. the
   field named `RG_SENINF_MUX(n+1)_SRC_SEL` belongs to `SENINF_MUXn` / mux number `n`
   (`mtk_cam-seninf-top-ctrl.h:37-45` + enum `SENINF_MUX1 = 0`, `def.h:155-158`).
   The log shows the result directly: after the vendor routed port 2 to mux 1 and mux 2,
   `TOP_MUX_CTRL_0` reads `0x03040400` = bytes [0]=0, [1]=4, [2]=4, [3]=3, i.e. **byte j of
   `SENINF_TOP_MUX_CTRL_i` holds mux number `4*i + j` and its value is the intf number**.
4. **SENINF mux → CAM_MUX.** The cam_mux (a.k.a. `CAM_MUX_PCSR`) array lives at
   `reg_if_cam_mux_pcsr[k] = if_base + 0x0400 + 0x0020*k` (`..._3_0.c:164-165`). Each cam_mux
   picks one SENINF mux number via `CTRL.RG_SENINF_CAM_MUX_PCSR_SRC_SEL` (bits 0-4;
   `mtk_cam-seninf-cammux-pcsr.h:10-11`, written at `..._3_0.c:755-756` from `drv.c:973-974`),
   filters on VC/DT via `OPT.VC_SEL/DT_SEL/VC_SEL_EN/DT_SEL_EN`
   (`..._3_0.c:663-670`), size-checks against `CHK_CTL.EXP_HSIZE/EXP_VSIZE`
   (`..._3_0.c:757-760`), and is finally switched on by `CTRL.EN` bit 7
   (`..._3_0.c:272-273`). `CTRL.CHK_PIX_MODE` mirrors the mux pixel mode (`..._3_0.c:990-991`).
5. **CAM_MUX → CAMSV (fixed wiring).** Each CAMSV instance has exactly one incoming cam_mux,
   declared in the vendor DT as `mediatek,cammux-id`. `camsv1@1a110000` has
   `mediatek,camsv-id = <0x00>` and `mediatek,cammux-id = <0x03>` (`hyperos_fdt.dts:13185-13192`).
   The CAMSV register file contains **no source-select register**, a grep of
   `isp71_ref/mtk_cam-sv-regs.h` for `SENINF|MUX|SRC|CAMTG` returns only unrelated fields
   (`VFDATA_EN_MUX_0/1_SEL`, `SOF_SRC`, `EOF_SRC`, `DB_LOAD_SRC`, `SUB_SOF_SRC_SEL`);
   `isp71_ref/mtk_cam-regs.h` has no `MUX/SENINF/CAMTG` symbol at all. So the association is
   wiring, and the DT `cammux-id` is the driver's way of *naming* that wire. Corroboration:
   cam_mux 0, 1, 2 are claimed by **no** camsv and **no** mraw node (see the full table in §4),
   which is consistent with them belonging to the three RAW (`cam_raw_a/b/c`) blocks, and the
   live log shows exactly that: `pad 1 … cam 0` → `mtk-cam raw 1a030000.cam_raw_a`
   (log 14426 / 14372) and `pad 6 … cam 15` → `mtk-cam mraw 1a130000.mraw1` (log 14432 / 14434),
   with `mraw1@1a130000` declared `mediatek,cammux-id = <0x0f>` = 15 (`hyperos_fdt.dts:13447`).
   The numbering is thus: **0-2 = RAW A/B/C, 3-14 & 19-22 = CAMSV 1..16, 15-18 = MRAW 1..4.**
6. **Nothing needs to be written on the CAMSV side for routing.** Only the CAMSV *instance
   enable / TG / IMGO DMA* registers need programming (that is the module's job,
   `isp71_ref/mtk_cam-sv-regs.h`); the data path into it is established purely by enabling
   cam_mux 3.

### CAM_MUX ↔ CAMSV table (from `hyperos_fdt.dts`)

| DT node | base | reg size | `camsv-id` | `cammux-id` | DTS line |
| --- | --- | --- | --- | --- | --- |
| camsv1@1a110000 | 0x1a110000 | 0x1000 | 0 | **3** | 13185-13199 |
| camsv2@1a111000 | 0x1a111000 | 0x1000 | 1 | 4 | 13201-13215 |
| camsv3@1a112000 | 0x1a112000 | 0x1000 | 2 | 5 | 13217-13231 |
| camsv4@1a113000 | 0x1a113000 | 0x1000 | 3 | 6 | 13233-13247 |
| camsv5@1a114000 | 0x1a114000 | 0x1000 | 4 | 7 | 13249-13263 |
| camsv6@1a115000 | 0x1a115000 | 0x1000 | 5 | 8 | 13265-13279 |
| camsv7@1a116000 | 0x1a116000 | 0x1000 | 6 | 19 (0x13) | 13281-13295 |
| camsv8@1a117000 | 0x1a117000 | 0x1000 | 7 | 20 (0x14) | 13297-13311 |
| camsv9@1a180000 | **0x1a180000** | 0x1000 | 8 | 21 (0x15) | 13313-13327 |
| camsv10@1a181000 | **0x1a181000** | 0x1000 | 9 | 22 (0x16) | 13329-13343 |
| camsv11@1a182000 | **0x1a182000** | 0x1000 | 10 | 9 | 13345-13359 |
| camsv12@1a183000 | **0x1a183000** | 0x1000 | 11 | 10 | 13361-13375 |
| camsv13@1a184000 | **0x1a184000** | 0x1000 | 12 | 11 | 13377-13391 |
| camsv14@1a185000 | **0x1a185000** | 0x1000 | 13 | 12 | 13393-13407 |
| camsv15@1a186000 | **0x1a186000** | 0x1000 | 14 | 13 | 13409-13423 |
| camsv16@1a187000 | **0x1a187000** | 0x1000 | 15 | 14 | 13425-13439 |
| mraw1@1a130000 | 0x1a130000 | 0x1000 | 0 | 15 (0x0f) | 13441-13455 |
| mraw2@1a140000 | 0x1a140000 | 0x1000 | 1 | 16 (0x10) | 13457-13471 |
| mraw3@1a150000 | 0x1a150000 | 0x1000 | 2 | 17 (0x11) | 13473-13487 |
| mraw4@1a160000 | 0x1a160000 | 0x1000 | 3 | 18 (0x12) | 13489-13503 |

Note the instancing quirk: `camsv9..16` live at `0x1a180000..0x1a187000`, **not**
`0x1a118000..`. (`0x1a1xx800` is each instance's `inner_base`, e.g. `camsv1` second reg entry
`0x1a118000`, dts:13187.)

---

## 3. Exact write list

Absolute addresses assume SENINF TOP base `0x1a010000`, port 2 → intf 4, chosen **mux number 1**,
**cam_mux 3** (→ CAMSV1 @ `0x1a110000`).

Notation: `R` = current 32-bit read value of that address. All registers 32-bit.
Ordering follows the vendor (`config_hw` → `mtk_cam-seninf-drv.c:894-1000`, plus the D-PHY-time
cam_mux SW_RST pulse at `..._3_0.c:1269-1273`).

| # | absolute addr | width | value | mask / RMW | field | justification |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `0x1a010300` | 32 | `R \| 0x1` | `0x1` | CAM_MUX_GCSR_CTRL.SW_RST = 1 | `cammux-gcsr.h:9-11`; vendor pulses this RMW-style at `..._3_0.c:1269-1273` and `:1325-1329` (keeps SLICE_FULL_OPT bit7 / IRQ_CLR_MODE bit8 / IRQ_VERIF_EN bit9). Puts cam_mux in a known state so we know which double-buffer page we write (see §5). |
| 2 | delay ~1 µs, then `0x1a010300` | 32 | `R & ~0x1` | `0x1` | SW_RST = 0 | `..._3_0.c:1271-1273` (`udelay(1)`). |
| 3 | `0x1a010010` | 32 | `(R & ~0x00001F00) \| 0x00000400` | `0x00001F00` | `SENINF_TOP_MUX_CTRL_0.RG_SENINF_MUX2_SRC_SEL` = **4** (mux number 1 ← intf 4) | field: `top-ctrl.h:37-45`. Writer: `..._3_0.c:345-452` (`_set_top_mux_ctrl`), called with `intf` from `drv.c:957`. Log-verified effect: `0x03020400` at `dmesg:14341` (byte1 = 4) evolving to `0x03040400` at `:14344`. |
| 4 | `0x1a011d04` | 32 | `(R & ~0x0000000F) \| 0x00000008` | `0x0000000F` | mux1 `SENINF_MUX_CTRL_1.RG_SENINF_MUX_SRC_SEL` = **8** (`MIPI_SENSOR + group 0`) | field `seninf1-mux.h:17-19`; value formula `drv.c:954` (`MIPI_SENSOR + vc->group`), `MIPI_SENSOR = 0x8` at `def.h:221`; written `..._3_0.c:854`. Log: `mux 1 SENINF_MUX_CTRL_1(0x1f0108)` → low nibble = 8 (`dmesg:14424`). |
| 5 | `0x1a011d04` | 32 | `(R & ~0x00000300) \| 0x00000100` | `0x00000300` | mux1 `SENINF_MUX_CTRL_1.RG_SENINF_MUX_PIX_MODE_SEL` = **1** | field `seninf1-mux.h:20-21`; written `..._3_0.c:858` from `vc->pixel_mode`; **1** is the value observed for this exact sensor/mode in the vendor log (`0x1f0108` → bits[9:8] = 1, `dmesg:14424`). `pixel_mode` is a log2 throughput multiplier (`drv.c:1187-1197`: `dfs_freq << pixelmode`), driver default is `SENINF_DEF_PIXEL_MODE = 2` (`def.h:9`, `drv.c:668`) — see §5 uncertainty U3. |
| 6 | `0x1a011d08` | 32 | `(R & ~0x00030000) \| 0x00000000` | `0x00030000` | mux1 `SENINF_MUX_OPT.HSYNC_POL`=0, `VSYNC_POL`=0 | fields `seninf1-mux.h:42-45`; written `..._3_0.c:864-866` with `hsPol = vsPol = 0` (`drv.c:914-915`). Log shows `SENINF_MUX_OPT(0x0)` (`dmesg:14424`) → normally a no-op. Avoid clobbering `FIFO_FULL_OUTPUT_OPT`/`FIFO_OVERRUN_RST_EN`; the vendor also sets `RESYNC`-related `FIFO_OVERRUN_RST_EN` inside `csirx_seninf_csi2_setting` (`..._3_0.c:1604+`). |
| 7 | `0x1a011d00` | 32 | `R \| 0x6` | `0x6` | mux1 `SENINF_MUX_CTRL_0.SW_RST \| .IRQ_SW_RST` = 1 | `seninf1-mux.h:12-15`; `..._3_0.c:869-871` (`temp \| 0x6`) — the code reads once and writes the OR, then the AND, so the pre-read value is preserved automatically. |
| 8 | `0x1a011d00` | 32 | `R & ~0x6` | `0x6` | same two bits = 0 | `..._3_0.c:871` (`temp & 0xFFFFFFF9`). |
| 9 | `0x1a011d00` | 32 | `R \| 0x1` | `0x1` | mux1 `SENINF_MUX_CTRL_0.SENINF_MUX_EN` = 1 | `seninf1-mux.h:10-11`; `..._3_0.c:938-942`. |
| 10 | `0x1a010048` | 32 | `0x00000001` | `0x00000303` | TOP_PHY_CTRL_CSI2: `DPHY_EN`=1, `CPHY_EN`=0, `RG_PHY_SENINF_MUX2_CPHY_MODE`=0 | `top-ctrl.h:109-115`; `..._3_0.c:1798-1806` (D-PHY branch: CPHY_EN←0, DPHY_EN←1) and `:1723-1726` (CPHY_MODE←0 = "4T"). **This is already correct from the working bring-up — list it as read-verify, do not clobber other bits (bits 1 and 8-9 must end at 0).** |
| 11 | `0x1a010464` | 32 | `0x0000AB80` | `0x0000FFFF` | cam_mux3 `SENINF_CAM_MUX_PCSR_OPT` = `VC_SEL`0 + `VC_SEL_EN`1 + `DT_SEL`0x2b + `DT_SEL_EN`1 | fields `cammux-pcsr.h:25-35`; writer `..._3_0.c:663-670`; call `drv.c:971-972` with `vc_sel = vc->vc = 0`, `dt_sel = vc->dt = 0x2b`, `dt_en = !!dt_sel = 1`. Value `0xab80` is the literal OPT the vendor's live cam_mux 0 read back for VC0/DT 0x2b (`dmesg:14425`); bit16 `VSYNC_BYPASS` = 0. |
| 12 | `0x1a010460` | 32 | `(R & ~0x0000001F) \| 0x00000001` | `0x0000001F` | cam_mux3 `CTRL.RG_SENINF_CAM_MUX_PCSR_SRC_SEL` = **1** (the SENINF mux number) | field `cammux-pcsr.h:10-11`; writer `..._3_0.c:755-756`; call `drv.c:973-974` (passes `vc->mux`). Log-verified: the enabled cam_mux 0 had `SRC_SEL`=1 = its mux (`dmesg:14425`, `out` value `0x1f8181`). |
| 13 | `0x1a010474` | 32 | `0x0BB80FA0` | `0xFFFFFFFF` | cam_mux3 `CHK_CTL`: `EXP_HSIZE`=4000 (0x0FA0) bits0-15, `EXP_VSIZE`=3000 (0x0BB8) bits16-31 | fields `cammux-pcsr.h:57-61`; writer `..._3_0.c:757-760`; call `drv.c:973-974` with `vc->exp_hsize/exp_vsize`. Expected size source: log `vc[0] … exp 4000x3000` (`dmesg:14327`). (`dt == 0x1f` would double hsize at `..._3_0.c:747-748`; ours is 0x2b → no doubling.) |
| 14 | `0x1a010460` | 32 | `(R & ~0x00000300) \| 0x00000300` | `0x00000300` | cam_mux3 `CTRL.RG_SENINF_CAM_MUX_PCSR_CHK_PIX_MODE` = **1** | fields `cammux-pcsr.h:14-15`; writer `..._3_0.c:990-991`; call `drv.c:975-977` with `vc->pixel_mode`. Log shows `CHK_PIX_MODE`=1 in both pages of the live cam_mux 0 (`0x1811f`, `0x1f8181`, `dmesg:14425`). Keep equal to step 5. |
| 15 | `0x1a01046c` | 32 | `0x00000103` | `0x00000103` | cam_mux3 `IRQ_STATUS` write-1-clear: `HSIZE_ERR`(bit0) \| `VSIZE_ERR`(bit1) \| `VSYNC`(bit8) | fields `cammux-pcsr.h:45-51`; writer `..._3_0.c:276-279` (`mtk_cam_seninf_cammux`, inside the enable function itself). |
| 16 | `0x1a010460` | 32 | `R \| 0x00000080` | `0x00000080` | cam_mux3 `CTRL.RG_SENINF_CAM_MUX_PCSR_EN` = **1** → data now flows into CAMSV1 | fields `cammux-pcsr.h:12-13`; writer `..._3_0.c:258-273`; call `drv.c:978` (`_cammux(vc->cam)`). |
| V1 | `0x1a014a00` | 32 | expect `0x0000000F` | read-only | CSI2 `SENINF_CSI2_EN` = `(1 << 4 lanes) - 1` | `..._3_0.c:1572` + `:1590`. Already proven (packets counted). |
| V2 | `0x1a014a20` | 32 | expect `0x002B0011` | read-only | CSI2 `S0_DI_CTRL`: `VC_INTERLEAVE_EN`=1(bit0), `DT_INTERLEAVE_MODE`=1(bits4-5), `VC_SEL`=0(bits8-12), `DT_SEL`=0x2b(bits16-21) | fields `seninf1-csi2.h:99-107`; writer macro `..._3_0.c:42-51`, applied for vcinfo index 0 at `:797-800`. **This is the register that decides that the mux's `SRC_SEL`=8 group actually carries VC0/DT 0x2b.** |
| V3 | `0x1a014a60` | 32 | bit8 = 1 | `0x00000100` | CSI2 `CH0_CTRL.RG_CSI2_CH0_S0_GRP_EN` = 1 (slot S0 belongs to group 0 → mux `SRC_SEL` 8) | fields `seninf1-csi2.h:179-187`; writer `SET_CH_CTRL` `..._3_0.c:53-55`, applied at `:799`. Reset to 0 by `..._3_0.c:783-786` before re-programming. |
| V4 | `0x1a014200` | 32 | bit0 = 1 | read-only | port-2 CTRL page `SENINF_CSI2_CTRL.RG_SENINF_CSI2_EN`=1 (`+0x10`) | `seninf1.h:17-19`; `..._3_0.c:1692` (`csirx_seninf_setting`). `SENINF_CTRL.SENINF_EN` is `+0x00` bit0 (`seninf1.h:9-11`, `..._3_0.c:1695`). |

**Count: 16 writes** (rows 1-16). Rows 1-2 (cam_mux SW_RST pulse) and row 6 (mux OPT
normalization) are defensive; **the 13 load-bearing writes are 3, 4, 5, 7, 8, 9, 11, 12, 13, 14,
15, 16**, of which row 3 is the one people get wrong (the mux→intf byte).

Quick derivation of the addresses used above:

```
reg_if_top              = 0x1a010000
reg_if_mux[1]           = 0x1a010000 + 0x0d00 + 0x1000*1 = 0x1a011d00   ; ..._3_0.c:161-162
reg_if_cam_mux_pcsr[3]  = 0x1a010000 + 0x0400 + 0x0020*3 = 0x1a010460   ; ..._3_0.c:164-165
reg_if_cam_mux_gcsr     = 0x1a010000 + 0x0300            = 0x1a010300   ; ..._3_0.c:167
reg_if_csi2[4]          = 0x1a010000 + 0x0a00 + 0x1000*4 = 0x1a014a00   ; ..._3_0.c:157
reg_if_ctrl[4]          = 0x1a010000 + 0x0200 + 0x1000*4 = 0x1a014200   ; ..._3_0.c:155
SENINF_TOP_MUX_CTRL_0   = 0x1a010010                                     ; top-ctrl.h:37
SENINF_TOP_PHY_CTRL_CSI2= 0x1a010048                                     ; top-ctrl.h:109
cam_mux reg offsets     : CTRL+0x00 OPT+0x04 IRQ_EN+0x08 IRQ_STATUS+0x0c
                          IRQ_TRIG+0x10 CHK_CTL+0x14 CHK_RES+0x18 CHK_ERR_RES+0x1c
                                                              ; cammux-pcsr.h:9,25,37,45,53,57,63,69
mux reg offsets         : CTRL_0+0x00 CTRL_1+0x04 OPT+0x08 IRQ_EN+0x10
                          IRQ_STATUS+0x18 IMG_SIZE+0x20 MUX_SIZE+0x30
                                                              ; seninf1-mux.h:9,17,31,+0x10/0x18...
CS12 reg offsets        : EN+0x00 S0_DI_CTRL+0x20 CH0_CTRL+0x60          ; seninf1-csi2.h:9,99,179
```

### Why not the "CMOS-style" CAM_MUX registers found in camera notes

`CAMERA_NOTES.md` §7.6 and `SENINF_CONFIG.md` step 8 describe a byte-per-cam_mux scheme
(`SENINF_CAM_MUX_CTRL_0..3 = 0x0400/0x0404/0x0408/0x040c`, each byte = a seninf mux number) taken
from the **ISP6S** legacy driver (`isp71_ref/isp6s_seninf/seninf_impl.c:75-81`, where
`SENINF_CAM_MUX0_CHK_CTL_0 = 0x0500` with 0x10 stride). **That layout does not apply to the
HyperOS/ISP7.1 device**: ISP7.1 uses the `PCSR` layout with `0x20` stride and per-cam_mux
`CTRL/OPT/IRQ/CHK` sub-registers, exactly as `mtk_csi_phy_3_0` implements it and exactly as the
live log's `SENINF_CAM_MUX_PCSR_CTRL/OPT` names show. Writing to `0x0400+4*k` as a flat
byte-per-cam_mux array on this device would corrupt cam_mux 0 (which is `cam_raw_a`'s input).
Use `0x0400 + 0x20*k + offset` instead.

---

## 4. Evidence

### 4.1 Live vendor log (authority for the working configuration)

`${K50_REPO}\hyperos_workstate\dmesg_after_restart.txt`, a full HyperOS camera bring-up
(`seninf_csi_port_2` = our sensor). Literal lines:

```
13875: [ 3609.489346] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_get_vcinfo vc[0] vc 0x0 dt 0x2b pad 1 exp 4000x3000 grp 0x0 code 0x3007
13876: [ 3609.489348] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_get_vcinfo vc[1] vc 0x1 dt 0x2b pad 6 exp 992x1488 grp 0x1 code 0x3007
14327: [ 3609.721024] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_get_vcinfo vc[0] vc 0x0 dt 0x2b pad 1 exp 4000x3000 grp 0x0 code 0x3007
14328: [ 3609.721032] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_get_vcinfo vc[1] vc 0x1 dt 0x2b pad 6 exp 992x1488 grp 0x1 code 0x3007
14334: [ 3609.733926] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_disable_all_cammux all SENINF_CAM_MUX_GCSR_MUX_EN 0x0
14340: [ 3609.734096] seninf 1a010000.seninf_top:seninf_csi_port_2: csirx_seninf_csi2_setting data_rate 1370000000 bps cycles 13
14341: [ 3609.734719] seninf 1a010000.seninf_top:seninf_csi_port_2: TOP_MUX_CTRL_0(0x3020400) TOP_MUX_CTRL_1(0x7060504) TOP_MUX_CTRL_2(0xb0a0908) TOP_MUX_CTRL_3(0xf0e0d0c) TOP_MUX_CTRL_4(0x13121110) TOP_MUX_CTRL_5(0x1514)
14342: [ 3609.734723] seninf 1a010000.seninf_top:seninf_csi_port_2: ctx->pad2cam[1] 255 vc->out_pad 1 vc->cam 255, i 0
14343: [ 3609.734727] seninf 1a010000.seninf_top:seninf_csi_port_2: not set camtg yet, vc[0] pad 1 intf 4 mux 1 cam 255
14344: [ 3609.734737] seninf 1a010000.seninf_top:seninf_csi_port_2: TOP_MUX_CTRL_0(0x3040400) TOP_MUX_CTRL_1(0x7060504) TOP_MUX_CTRL_2(0xb0a0908) TOP_MUX_CTRL_3(0xf0e0d0c) TOP_MUX_CTRL_4(0x13121110) TOP_MUX_CTRL_5(0x1514)
14345: [ 3609.734741] seninf 1a010000.seninf_top:seninf_csi_port_2: ctx->pad2cam[6] 255 vc->out_pad 6 vc->cam 255, i 1
14346: [ 3609.734744] seninf 1a010000.seninf_top:seninf_csi_port_2: not set camtg yet, vc[1] pad 6 intf 4 mux 2 cam 255
14347: [ 3609.734747] seninf 1a010000.seninf_top:seninf_csi_port_2: raw cammux usage = 255
14361: [ 3609.744322] FrameMonitor[frm_convert_cammux_id_to_ccu_tg_id] get cammux_id:256(from 1), camsv_id:-1(from 0), ccu_tg_id:256(CAMSV_TG_MIN:5, CAMSV_TG_MAX:21)
14362: [ 3609.744328] imgsensor 8-0010: imgsensor_set_stream: en 1, cammux usage 255
14424: [ 3609.759188] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_update_mux_pixel_mode mux 1 SENINF_MUX_CTRL_1(0x1f0108), SENINF_MUX_OPT(0x0)
14425: [ 3609.759210] seninf 1a010000.seninf_top:seninf_csi_port_2:  mtk_cam_seninf_set_cammux_next_ctrl cam_mux 0 in|out SENINF_CAM_MUX_PCSR_CTRL 0x1811f|0x1f8181 SENINF_CAM_MUX_PCSR_OPT 0x0|0xab80
14426: [ 3609.759226] seninf 1a010000.seninf_top:seninf_csi_port_2: _mtk_cam_seninf_set_camtg: pad 1 mux 1 cam 255 -> 0
14427: [ 3609.759232] seninf 1a010000.seninf_top:seninf_csi_port_2: raw cammux usage = 0
14430: [ 3609.759247] seninf 1a010000.seninf_top:seninf_csi_port_2: mtk_cam_seninf_update_mux_pixel_mode mux 2 SENINF_MUX_CTRL_1(0x1f0009), SENINF_MUX_OPT(0x0)
14431: [ 3609.759266] seninf 1a010000.seninf_top:seninf_csi_port_2:  mtk_cam_seninf_set_cammux_next_ctrl cam_mux 15 in|out SENINF_CAM_MUX_PCSR_CTRL 0x2801f|0x1f8082 SENINF_CAM_MUX_PCSR_OPT 0x0|0xab81
14432: [ 3609.759272] seninf 1a010000.seninf_top:seninf_csi_port_2: _mtk_cam_seninf_set_camtg: pad 6 mux 2 cam 255 -> 15
14442: [ 3609.759615] FrameMonitor[frm_convert_cammux_id_to_ccu_tg_id] get cammux_id:1(from 1), camsv_id:-1(from 0), ccu_tg_id:1(CAMSV_TG_MIN:5, CAMSV_TG_MAX:21)
```

Decoded:

* `14327/14328`, port 2 has two VCs, both DT 0x2b (RAW10), VC0 = 4000×3000 on pad 1, VC1 =
  992×1488 on pad 6, groups 0 and 1.
* `14341` → `TOP_MUX_CTRL_0 = 0x03020400` (byte1 already = 4 = intf for mux 1); `14344`
  → `0x03040400` (byte2 also = 4 for mux 2). All other CTRL words are the untouched identity
  pattern `byte j = 4i+j`. Hence `TOP_MUX_CTRL_0` reset/identity = `0x03020100` (inferred, see
  §5 U1) and the byte j ↔ mux number `4i+j` ↔ value = intf number layout is proven.
* `14343/14346`, **port 2 = intf 4, mux 1 (VC0) and mux 2 (VC1)**.
* `14424`, mux 1 `MUX_CTRL_1 = 0x1f0108`: `SRC_SEL`(bits0-3) = 8 = `MIPI_SENSOR + group 0`;
  `PIX_MODE_SEL`(bits8-9) = 1; `FIFO_PUSH_EN`(bits16-21) = 0x1f.
  `14430`, mux 2 `MUX_CTRL_1 = 0x1f0009`: `SRC_SEL` = 9 = `MIPI_SENSOR + group 1`,
  `PIX_MODE_SEL` = 0. `MUX_OPT = 0` for both.
* `14425/14431`, cam_mux `OPT = 0xab80` (cam_mux 0, VC 0 / DT 0x2b) and `0xab81` (cam_mux 15,
  VC 1 / DT 0x2b): `VC_SEL`(0-4)=0/1, `VC_SEL_EN`(bit7)=1, `DT_SEL`(8-13)=0x2b, `DT_SEL_EN`(bit15)=1.
  The `out` CTRL `0x1f8181` = `SRC_SEL`=1 (= mux 1), `EN`=1, `CHK_PIX_MODE`=1, `CHK_EN`=1,
  `NEXT_SRC_SEL`=0x1f; `0x1f8082` = `SRC_SEL`=2 (= mux 2), `CHK_PIX_MODE`=0.
* `14426/14432`, `pad 1 → cam 0` (RAW0 → cam_raw_a), `pad 6 → cam 15` (→ mraw1).
* `14334`, `SENINF_CAM_MUX_GCSR_MUX_EN` reads `0x0`, and the driver only ever *reads* that
  register (`..._3_0.c:338-340`, `:3165`) → **it is an RO aggregate mirror of the per-cam_mux
  `PCSR.CTRL.EN` bits, not the enable mechanism.** Enabling is done through `PCSR.CTRL.EN`.

### 4.2 Vendor index maps (verbatim)

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-hw_phy_3_0.c`:

```
152: 	ctx->reg_if_top = if_base;
154: 	for (i = SENINF_1; i < _seninf_ops->seninf_num; i++) {
155: 		ctx->reg_if_ctrl[i] = if_base + 0x0200 + (0x1000 * i);
156: 		ctx->reg_if_tg[i] = if_base + 0x0f00 + (0x1000 * i);
157: 		ctx->reg_if_csi2[i] = if_base + 0x0a00 + (0x1000 * i);
158: 	}
161: 	for (j = SENINF_MUX1; j < _seninf_ops->mux_num; j++)
162: 		ctx->reg_if_mux[j] = if_base + 0x0d00 + (0x1000 * j);
164: 	for (k = SENINF_CAM_MUX0; k < _seninf_ops->cam_mux_num; k++)
165: 		ctx->reg_if_cam_mux_pcsr[k] = if_base + 0x0400 + (0x0020 * k);
167: 	ctx->reg_if_cam_mux_gcsr = if_base + 0x0300;
```

Note `reg_if_tg[] = +0x0f00 + 0x1000*i` (line 156), the `0x0f00` block is the **TG** block, which
matches the task brief. `reg_if_cam_mux_pcsr[k] = +0x0400 + 0x0020*k` (line 165) is **not** a
byte-per-cam_mux array.

Port 2 → `SENINF_5`:

```
203: 	case CSI_PORT_2:
204: 	case CSI_PORT_2A:
205: 		ctx->seninfIdx = SENINF_5;
206: 		break;
```

`${K50_REPO}\isp71_ref\mtk_cam-seninf-def.h`:

```
139: enum SENINF_ENUM {
140: 	SENINF_1,
...
144: 	SENINF_5,
```

⇒ `SENINF_1 = 0` ⇒ `SENINF_5 = 4` = the `intf 4` in the log.

```
155: enum SENINF_MUX_ENUM {
156: 	SENINF_MUX1,
...
178: 	SENINF_MUX_NUM,
```
⇒ `SENINF_MUXn` = mux number `n-1`.

```
183: enum SENINF_CAM_MUX_ENUM {
184: 	SENINF_CAM_MUX0,
...
207: 	SENINF_CAM_MUX_NUM,
209: 	SENINF_CAM_MUX_ERR = 0xff
```
⇒ `SENINF_CAM_MUXk` = cam_mux `k`; the log's `cam 255` is `0xff` = "not yet assigned".

```
212: enum SENINF_SOURCE_ENUM { //0:CSI2(2.5G), 3: parallel, 8:NCSI2(1.5G)
213: 	CSI2 = 0x0, /* 2.5G support */
214: 	TEST_MODEL = 0x1,
...
221: 	MIPI_SENSOR = 0x8,/* 1.5G support */
222: 	VIRTUAL_CHANNEL_1 = 0x9,
...
228: };
  9: #define SENINF_DEF_PIXEL_MODE 2
```

### 4.3 The exact vendor ordering (non-dynamic path)

`${K50_REPO}\isp71_ref\mtk_cam-seninf-drv.c:894-1000` (`config_hw`), abridged to the routing
part:

```
 907: 	g_seninf_ops->_reset(ctx, intf);
 909: 	g_seninf_ops->_set_vc(ctx, intf, vcinfo);
 911: 	g_seninf_ops->_set_csi_mipi(ctx);
 914: 	hsPol = 0;
 915: 	vsPol = 0;
 920: 		vc->enable = mtk_cam_seninf_is_vc_enabled(ctx, vc);
 927: 		/* alloc mux by group */
 934: 			mux = mux_by_grp[vc->group] =
 936: 				mtk_cam_seninf_mux_get_pref(ctx,
 937: 						pref_idx,
 938: 						g_seninf_ops->pref_mux_num);
 947: 		vc->mux = mux->idx;
 948: 		vc->cam = ctx->pad2cam[vc->out_pad];
 950: 		if (!skip_mux_ctrl) {
 951: 			g_seninf_ops->_mux(ctx, vc->mux);
 952: 			g_seninf_ops->_set_mux_ctrl(ctx, vc->mux,
 953: 						    hsPol, vsPol,
 954: 				MIPI_SENSOR + vc->group,
 955: 				vc->pixel_mode);
 957: 			g_seninf_ops->_set_top_mux_ctrl(ctx, vc->mux, intf);
965: 		if (vc->cam != 0xff) {
 966: 			vc_sel = vc->vc;
 967: 			dt_sel = vc->dt;
 968: 			dt_en = !!dt_sel;
 971: 			g_seninf_ops->_set_cammux_vc(ctx, vc->cam,
 972: 						     vc_sel, dt_sel, dt_en, dt_en);
 973: 			g_seninf_ops->_set_cammux_src(ctx, vc->mux, vc->cam,
 974: 						      vc->exp_hsize, vc->exp_vsize, vc->dt);
 975: 			g_seninf_ops->_set_cammux_chk_pixel_mode(ctx,
 976: 								 vc->cam,
 977: 								 vc->pixel_mode);
 978: 			g_seninf_ops->_cammux(ctx, vc->cam);
996: 			dev_info(ctx->dev, "not set camtg yet, vc[%d] pad %d intf %d mux %d cam %d\n",
```

This is the order reproduced in §3 rows 4-16. In the log the pipeline arrives with `cam == 255`
(no camtg yet), so only rows 3 (top mux) + 4/5/6/7/8/9 were executed at stream-on; the camtg
arrived later through the **dynamic** path (`_mtk_cam_seninf_set_camtg`), which performs the same
writes plus double-buffer page switching. **We are in the `cam == 0xff` situation only until we
choose a cam_mux ourselves; since we choose it up front, the static path is correct and simpler.**

The dynamic path, for reference
(`${K50_REPO}\isp71_ref\mtk_cam-seninf-route.c:853-888`):

```
 859: 				g_seninf_ops->_set_cammux_next_ctrl(ctx, 0x1f, vc->cam);
 863: 				g_seninf_ops->_set_cammux_vc(ctx, vc->cam,
 866: 				g_seninf_ops->_set_cammux_src(ctx, vc->mux, vc->cam,
 870: 				g_seninf_ops->_set_cammux_chk_pixel_mode(ctx,
 877: 				g_seninf_ops->_cammux(ctx, vc->cam); //enable in next sof
 879: 				g_seninf_ops->_set_cammux_next_ctrl(ctx, vc->mux, vc->cam);
```
with `mtk_cam_seninf_switch_to_cammux_inner_page()` writing
`GCSR_DYN_CTRL.DYN_PAGE_SEL = inner ? 0 : 1` (`..._3_0.c:673-684`).

### 4.4 Register field definitions (verbatim)

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-top-ctrl.h`:

```
 37: #define SENINF_TOP_MUX_CTRL_0 0x0010
 38: #define RG_SENINF_MUX1_SRC_SEL_SHIFT 0
 39: #define RG_SENINF_MUX1_SRC_SEL_MASK (0x1f << 0)
 40: #define RG_SENINF_MUX2_SRC_SEL_SHIFT 8
 41: #define RG_SENINF_MUX2_SRC_SEL_MASK (0x1f << 8)
 42: #define RG_SENINF_MUX3_SRC_SEL_SHIFT 16
 43: #define RG_SENINF_MUX3_SRC_SEL_MASK (0x1f << 16)
 44: #define RG_SENINF_MUX4_SRC_SEL_SHIFT 24
 45: #define RG_SENINF_MUX4_SRC_SEL_MASK (0x1f << 24)
...
 87: #define SENINF_TOP_MUX_CTRL_5 0x0024
 88: #define RG_SENINF_MUX21_SRC_SEL_SHIFT 0
 90: #define RG_SENINF_MUX22_SRC_SEL_SHIFT 8
...
109: #define SENINF_TOP_PHY_CTRL_CSI2 0x0048
110: #define PHY_SENINF_MUX2_DPHY_EN_SHIFT 0
111: #define PHY_SENINF_MUX2_DPHY_EN_MASK (0x1 << 0)
112: #define PHY_SENINF_MUX2_CPHY_EN_SHIFT 1
113: #define PHY_SENINF_MUX2_CPHY_EN_MASK (0x1 << 1)
114: #define RG_PHY_SENINF_MUX2_CPHY_MODE_SHIFT 8
115: #define RG_PHY_SENINF_MUX2_CPHY_MODE_MASK (0x3 << 8)
```

(One-based naming: `RG_SENINF_MUX<n+1>_SRC_SEL` carries mux number `n`. Consistent with
`SENINF_MUX1 = 0` in the enum. **This is the single most common source of off-by-one errors
here.**)

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-seninf1-mux.h`:

```
  9: #define SENINF_MUX_CTRL_0 0x0000
 10: #define SENINF_MUX_EN_SHIFT 0
 11: #define SENINF_MUX_EN_MASK (0x1 << 0)
 12: #define SENINF_MUX_IRQ_SW_RST_SHIFT 1
 13: #define SENINF_MUX_IRQ_SW_RST_MASK (0x1 << 1)
 14: #define SENINF_MUX_SW_RST_SHIFT 2
 15: #define SENINF_MUX_SW_RST_MASK (0x1 << 2)
 17: #define SENINF_MUX_CTRL_1 0x0004
 18: #define RG_SENINF_MUX_SRC_SEL_SHIFT 0
 19: #define RG_SENINF_MUX_SRC_SEL_MASK (0xf << 0)
 20: #define RG_SENINF_MUX_PIX_MODE_SEL_SHIFT 8
 21: #define RG_SENINF_MUX_PIX_MODE_SEL_MASK (0x3 << 8)
 22: #define RG_SENINF_MUX_FIFO_PUSH_EN_SHIFT 16
 23: #define RG_SENINF_MUX_FIFO_PUSH_EN_MASK (0x3f << 16)
...
 31: #define SENINF_MUX_OPT 0x0008
 42: #define RG_SENINF_MUX_HSYNC_POL_SHIFT 16
 44: #define RG_SENINF_MUX_VSYNC_POL_SHIFT 17
```

Note `RG_SENINF_MUX_SRC_SEL_MASK` is `0xf` (4 bits) in the header while the log's value 8/9 fits;
but the mask is **inconsistent** with `SENINF_SOURCE_ENUM` which goes up to `0xE`, 4 bits still
covers 0-15, fine.

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-cammux-pcsr.h` (offsets from
`0x1a010400 + 0x20*k`):

```
  9: #define SENINF_CAM_MUX_PCSR_CTRL 0x0000
 10: #define RG_SENINF_CAM_MUX_PCSR_SRC_SEL_SHIFT 0
 11: #define RG_SENINF_CAM_MUX_PCSR_SRC_SEL_MASK (0x1f << 0)
 12: #define RG_SENINF_CAM_MUX_PCSR_EN_SHIFT 7
 13: #define RG_SENINF_CAM_MUX_PCSR_EN_MASK (0x1 << 7)
 14: #define RG_SENINF_CAM_MUX_PCSR_CHK_PIX_MODE_SHIFT 8
 15: #define RG_SENINF_CAM_MUX_PCSR_CHK_PIX_MODE_MASK (0x3 << 8)
 16: #define RG_SENINF_CAM_MUX_PCSR_CHK_EN_SHIFT 15
 17: #define RG_SENINF_CAM_MUX_PCSR_CHK_EN_MASK (0x1 << 15)
 18: #define CAM_MUX_PCSR_NEXT_SRC_SEL_SHIFT 16
 19: #define CAM_MUX_PCSR_NEXT_SRC_SEL_MASK (0x1f << 16)
 20: #define RG_SENINF_CAM_MUX_PCSR_DYN_SWITCH_EN0_SHIFT 22
 22: #define RG_SENINF_CAM_MUX_PCSR_DYN_SWITCH_EN1_SHIFT 23
 25: #define SENINF_CAM_MUX_PCSR_OPT 0x0004
 26: #define RG_SENINF_CAM_MUX_PCSR_VC_SEL_SHIFT 0
 27: #define RG_SENINF_CAM_MUX_PCSR_VC_SEL_MASK (0x1f << 0)
 28: #define RG_SENINF_CAM_MUX_PCSR_VC_SEL_EN_SHIFT 7
 30: #define RG_SENINF_CAM_MUX_PCSR_DT_SEL_SHIFT 8
 31: #define RG_SENINF_CAM_MUX_PCSR_DT_SEL_MASK (0x3f << 8)
 32: #define RG_SENINF_CAM_MUX_PCSR_DT_SEL_EN_SHIFT 15
 34: #define RG_SENINF_CAM_MUX_PCSR_VSYNC_BYPASS_SHIFT 16
 45: #define SENINF_CAM_MUX_PCSR_IRQ_STATUS 0x000c
 46: #define RO_SENINF_CAM_MUX_PCSR_HSIZE_ERR_IRQ_SHIFT 0
 48: #define RO_SENINF_CAM_MUX_PCSR_VSIZE_ERR_IRQ_SHIFT 1
 50: #define RO_SENINF_CAM_MUX_PCSR_VSYNC_IRQ_SHIFT 8
 57: #define SENINF_CAM_MUX_PCSR_CHK_CTL 0x0014
 58: #define RG_SENINF_CAM_MUX_PCSR_EXP_HSIZE_SHIFT 0
 59: #define RG_SENINF_CAM_MUX_PCSR_EXP_HSIZE_MASK (0xffff << 0)
 60: #define RG_SENINF_CAM_MUX_PCSR_EXP_VSIZE_SHIFT 16
 61: #define RG_SENINF_CAM_MUX_PCSR_EXP_VSIZE_MASK (0xffff << 16)
```

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-cammux-gcsr.h`:

```
  9: #define SENINF_CAM_MUX_GCSR_CTRL 0x0000
 10: #define RG_SENINF_CAM_MUX_GCSR_SW_RST_SHIFT 0
 11: #define RG_SENINF_CAM_MUX_GCSR_SW_RST_MASK (0x1 << 0)
 12: #define RG_SENINF_CAM_MUX_GCSR_IRQ_SW_RST_SHIFT 1
 21: #define SENINF_CAM_MUX_GCSR_DYN_CTRL 0x0004
 26: #define RG_SENINF_CAM_MUX_GCSR_DYN_PAGE_SEL_SHIFT 7
 27: #define RG_SENINF_CAM_MUX_GCSR_DYN_PAGE_SEL_MASK (0x1 << 7)
 59: #define SENINF_CAM_MUX_GCSR_MUX_EN 0x00c0
 63: #define SENINF_CAM_MUX_GCSR_CHK_EN 0x00c4
 64: #define RG_SENINF_CAM_MUX_GCSR_CHK_EN_SHIFT 0
 65: #define RG_SENINF_CAM_MUX_GCSR_CHK_EN_MASK (0x7fffff << 0)
```

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-seninf1-csi2.h`:

```
  9: #define SENINF_CSI2_EN 0x0000
...
 99: #define SENINF_CSI2_S0_DI_CTRL 0x0020
100: #define RG_CSI2_S0_VC_INTERLEAVE_EN_SHIFT 0
102: #define RG_CSI2_S0_DT_INTERLEAVE_MODE_SHIFT 4
104: #define RG_CSI2_S0_VC_SEL_SHIFT 8
106: #define RG_CSI2_S0_DT_SEL_SHIFT 16
107: #define RG_CSI2_S0_DT_SEL_MASK (0x3f << 16)
...
179: #define SENINF_CSI2_CH0_CTRL 0x0060
186: #define RG_CSI2_CH0_S0_GRP_EN_SHIFT 8
187: #define RG_CSI2_CH0_S0_GRP_EN_MASK (0x1 << 8)
```

`${K50_REPO}\isp71_ref\mtk_csi_phy_3_0\mtk_cam-seninf-seninf1.h`:

```
  9: #define SENINF_CTRL 0x0000
 10: #define SENINF_EN_SHIFT 0
 11: #define SENINF_EN_MASK (0x1 << 0)
 17: #define SENINF_CSI2_CTRL 0x0010
 18: #define RG_SENINF_CSI2_EN_SHIFT 0
 19: #define RG_SENINF_CSI2_EN_MASK (0x1 << 0)
 20: #define SENINF_CSI2_SW_RST_SHIFT 4
```

### 4.5 DT evidence (CAMSV ↔ cam_mux wiring, port 2 node)

`${K50_REPO}\hyperos_fdt.dts`:

```
13128: 		seninf_csi_port_2 {
13129: 			compatible = "mediatek,seninf";
13130: 			csi-port = "2";
13131: 			phandle = <0x349>;
13136: 					remote-endpoint = <0x2e2>;
13137: 					phandle = <0x31b>;
```

```
13185: 	camsv1@1a110000 {
13186: 		compatible = "mediatek,camsv";
13187: 		reg = <0x00 0x1a110000 0x00 0x1000 0x00 0x1a118000 0x00 0x1000>;
13188: 		reg-names = "base\0inner_base";
13189: 		mediatek,camsv-id = <0x00>;
13190: 		mediatek,larbs = <0xa9>;
13191: 		mediatek,camsv-hwcap = <0x110051>;
13192: 		mediatek,cammux-id = <0x03>;
```

```
13441: 	mraw1@1a130000 {  …  13447: 		mediatek,cammux-id = <0x0f>;
```

The sensor node (device side, phandle 0x2e2 endpoint) is
`hyperos_fdt.dts:6400-6434` (`sensor0@10`, `sensor-names = "rubensimx582_mipi_raw"` at :6403,
endpoint `remote-endpoint = <0x31b>` at :6431, i.e. it pairs with `seninf_csi_port_2`'s
phandle 0x349 endpoint). So the DT confirms sensor0 → CSI port 2, but **carries no mux/cam_mux
route** (`grep -n "route" hyperos_fdt.dts` has no hits); the route is decided at runtime from the
V4L2 frame descriptor (`get_vcinfo_by_pad_fmt`, `mtk_cam-seninf-route.c:633-637`).

`sensor0@10` `avdd1/dovdd/afvdd` supplies = `<0x2f2>/<0x2f3>/<0x31a>` at `hyperos_fdt.dts:6419-6421`,
which is our FAN53870 chain (fine).

### 4.6 CAMSV has no cam_mux selector

`grep -n "SENINF\|MUX\|SRC\|CAMTG" isp71_ref/mtk_cam-sv-regs.h` → only:
`DB_LOAD_SRC:2` (38), `VF_SRC:1` (231), `SOF_SRC:2` (260), `EOF_SRC:2` (261),
`PXL_CNT_RST_SRC:1` (262), `VFDATA_EN_MUX_0_SEL:1` (298), `VFDATA_EN_MUX_1_SEL:1` (299),
`DB_LOAD_SRC:1` (324), `SUB_SOF_SRC_SEL:2` (335), **none is a cam_mux/source-group selector**.
`grep -n "MUX\|SENINF\|CAMTG" isp71_ref/mtk_cam-regs.h` → no matches.
⇒ the CAM_MUX→CAMSV association cannot be programmed; it is wiring, named in DT by `cammux-id`.

---

## 5. Uncertainties / contradictions

**U1, `SENINF_TOP_MUX_CTRL_0` reset value (LOW risk, inferred).**
`UNCONFIRMED:` the pristine reset value is never printed in the log; `0x03020100` is *inferred*
from the untouched identity pattern of `TOP_MUX_CTRL_1..5` in `dmesg:14341`
(`0x07060504`, `0x0b0a0908`, `0x0f0e0d0c`, `0x13121110`, `0x1514` ⇒ byte j = 4i+j). Consequence
is nil: §3 row 3 is a read-modify-write of one 5-bit field, so any reset value other than
"byte1 already == 4" is handled. *What would confirm it:* read `0x1a010010` before any camera
driver has run (e.g. early boot) on the device.

**U2, CAM_MUX double-buffer page / `DYN_PAGE_SEL` (MEDIUM risk).**
`UNCONFIRMED:` which cam_mux page a plain `PCSR` write lands on when `DYN_CTRL.DYN_PAGE_SEL`
has an unknown value, and how the two pages are swapped. The vendor's dynamic path writes
`NEXT_SRC_SEL`, then flips `DYN_PAGE_SEL`, then writes the live config, then re-enables, and
the resulting `in|out` readback (`0x1811f` vs `0x1f8181` for the *same* cam_mux 0) shows the two
pages hold *different* configurations (idle `SRC_SEL=0x1f, EN=0` vs active `SRC_SEL=1, EN=1`).
What is certain is that the vendor's *static* `config_hw` path (drv.c:971-978) does **not** touch
`DYN_PAGE_SEL` at all and works. Mitigation in §3: pulse `GCSR_CTRL.SW_RST` first (vendor does
exactly this in D-PHY init, `..._3_0.c:1269-1273`) to return both pages to a defined state; if
`CTRL.EN` readback after row 16 is not 1, retry rows 11-16 with `DYN_PAGE_SEL` = 1 (i.e.
`0x1a010304 |= 0x80`). *What would confirm it:* read `0x1a010460`/`0x1a010464` with
`0x1a010304` bit7 = 0 and again with bit7 = 1 on the device.

**U3, `pixel_mode` / `MUX_CTRL_1.PIX_MODE_SEL` and `CTRL.CHK_PIX_MODE` (MEDIUM risk).**
Three candidate values exist in the sources: the driver default `SENINF_DEF_PIXEL_MODE = 2`
(`def.h:9`, `drv.c:668`), the vendor log's **1** for this exact sensor/VC0 (`dmesg:14424`), and
**0** for the VC1/MRAW stream (`dmesg:14430`). `drv.c:1187-1197` shows the value is a *log2*
throughput multiplier (`dfs_freq << pixelmode`), so 1 = 2 px/clk, 2 = 4 px/clk. §3 uses **1**
(the only value proven to move real IMX582 data on this device). `UNCONFIRMED:` whether the
CAMSV path wants the same value, CAMSV has its own packing config (`FMT_SEL`,
`PAK_CON` in `mtk_cam-sv-regs.h`) and the vendor never routed this sensor to CAMSV, so there is
no log evidence. *What would confirm it:* try 1 first; if CAMSV receives a corrupted/overrun
stream, try 2 then 0, and cross-check against CAMSV `FMT_SEL`/`PAK_CON`.

**U4, `CAMSV_TG_MIN:5 … CAMSV_TG_MAX:21` vs the DT cammux-ids (LOW-MEDIUM, not reconciled).**
`dmesg:14348` prints `ccu_tg_id:256(CAMSV_TG_MIN:5, CAMSV_TG_MAX:21)`, i.e. the CCU/FrameMonitor
code treats camtg ids 5..21 as the CAMSV range, which does **not** match the DT cammux-id set for
camsv1..16 = {3,4,5,6,7,8,19,20,21,22,9,10,11,12,13,14}. `UNCONFIRMED:` whether the CCU ids are
a shifted numbering (e.g. `cammux_id + 2`) or whether a CAMSV can be "non-CCU". In that log line
the value being converted was `cammux_id:256` (= invalid/0xff+1) so nothing conclusive can be
read from it, and `camsv_id:-1` just means "no camsv pipeline was matched".
*Why it matters:* if cam_mux 3 (CAMSV1) is deliberately outside the CCU's CAMSV range, CAMSV1 may
be reserved; if so, pick a cam_mux inside 5..21 instead (e.g. cam_mux 5 → `0x1a0104a0` →
`camsv3@1a112000`, or cam_mux 8 → `0x1a010500` → `camsv6@1a115000`). Note the DT is the vendor
kernel driver's own source of truth and lists cam_mux 3 for camsv1, so §3 keeps cam_mux 3 and
matches the module's existing hardcoded CAMSV1. *What would confirm it:* read
`PCSR.CHK_RES`/`CHK_ERR_RES` on cam_mux 3 after a frame, a non-zero received size proves data
arrived even if the CCU ignores it.

**U5, `CTRL.CHK_EN` (bit 15) is never written by the driver (LOW risk).**
`grep RG_SENINF_CAM_MUX_PCSR_CHK_EN` over `mtk_csi_phy_3_0/` finds it only in
`cammux-pcsr.h:16-17`, no code writes it. Yet the live log reads bit15 = 1 on cam_mux 0 in both
pages (`0x1811f`, `0x1f8181`). So either it is a hardware reset default of 1, or the global
`GCSR_CHK_EN` (`cammux-gcsr.h:63-65`, 23 bits = one bit per cam_mux, same shape as the RO
`MUX_EN` mirror) drives it. §3 leaves it alone (matching the vendor). If size checking turns out
to be the thing blocking CAMSV, write `0x1a0103c4` bit3 = 1 (the authoritative global form) and
verify `0x1a010460` bit15 reads 1.

**U6, our notes contradict the sources in two places; the sources win.**
(a) `CAMERA_NOTES.md` §1.6 (line 84) lists as still-open "which cam_mux corresponds to CAMSV0"
and "6S's CAM_MUX_EN write location/mechanism", **answered here**: cam_mux 3 ↔ CAMSV1 by DT
`cammux-id`, and enabling is `PCSR.CTRL.EN` bit7 at `0x1a010400 + 0x20*k` (the ISP6S `0x410`
byte-array layout does not apply to ISP7.1; see §3 "Why not the CMOS-style CAM_MUX registers").
(b) `CAMERA_NOTES.md` §1.6 line 81 calls `0x1a110000` "CAMSV0"; the DT calls it
`camsv1@1a110000` with `mediatek,camsv-id = <0x00>`. Both names refer to the same block (DT node
name is 1-based, the id is 0-based); what matters is that it is `cammux-id = 3`.
(c) The task brief's paraphrase of the vendor route table ("`[0] vc 0 dt 0x2b mux 12 cam 0`,
`[1] vc 1 dt 0x2b mux 0 cam 15`") is **not what the log says and is not in the log at all**:
the log says `mux 1 cam 0` and `mux 2 cam 15` (`dmesg:14343/14326/14432`) and there is no mux 12
and no `cam 15` with `mux 0` anywhere. There is also no `routes` property in the DTB. Treat the
paraphrase as erroneous and use `dmesg:14343`/`:14346`.

**U7, `reg_if_tg[]` (port-2 TG block `0x1a014f00`) is not needed for the CAMSV route.**
The TOP-flat `reg_if_tg[i] = if_base + 0x0f00 + 0x1000*i` block (`..._3_0.c:156`) is the SENINF's
own TG (used with the test-model and the RAW path). `grep reg_if_tg` in `..._3_0.c` hits only
`:1006` (inside `mtk_cam_seninf_set_test_model`), **no streaming path for a real sensor writes
it**, and nothing in §3 touches it. CAMSV has its own TG (`mtk_cam-sv-regs.h` `TG_*`), which the
module programs. So do not add TG writes to the SENINF routing script. (LOW risk; stated because
the brief asked.)

**One genuine contradiction between the vendor source and the log to be aware of:**
`mtk_cam_seninf_disable_cammux()` (`..._3_0.c:305-312`) writes `NEXT_SRC_SEL = 0x1f`,
`SRC_SEL = 0x1f`, `EN = 0` without any page selection, while the *observed* page contents
(`dmesg:14425`) show one page at `SRC_SEL = 0x1f/EN = 0` and the other at `SRC_SEL = 1/EN = 1`.
Both statements are true simultaneously (different pages), but it means **readbacks of cam_mux
registers are page-dependent**, never judge "is cam_mux 3 enabled?" from a single read without
controlling `DYN_PAGE_SEL`. See U2.

---

## 6. Minimal ordered procedure

Preconditions (already true per the brief): sensor streaming, port-2 D-PHY analog+digital RX up,
CSI2 instance 4 counting packets with `ECC_NO_ERR`/`CRC_CORRECT`. At that point **intf 4 exists
and its `S0_DI_CTRL`/`CH0_CTRL` are already carrying VC0/DT 0x2b into group 0**, verify V1-V4
of §3, do not rewrite them.

Run as root, all accesses via `/dev/mem` (or a kernel module using `ioremap`). `R(addr)` = 32-bit
read, `W(addr, val)` = 32-bit write, all constants decimal unless `0x`.

```
# --- 0. address constants
TOP   = 0x1a010000
INTF  = 4                    # port 2 -> SENINF_5 = 4
MUX   = 1                    # chosen seninf mux number
CAM   = 3                    # cam_mux 3 -> CAMSV1 @ 0x1a110000 (DT cammux-id)
MUXB  = TOP + 0x0d00 + 0x1000*MUX        # 0x1a011d00
PCSR  = TOP + 0x0400 + 0x0020*CAM        # 0x1a010460
GCSR  = TOP + 0x0300                     # 0x1a010300
CSI2B = TOP + 0x0a00 + 0x1000*INTF       # 0x1a014a00
CTRLB = TOP + 0x0200 + 0x1000*INTF       # 0x1a014200

# --- 1. verify the already-working context first (do NOT rewrite these blindly)
assert R(CSI2B + 0x00) & 0x3F == 0x0F          # CSI2_EN = 4 lanes      (_3_0.c:1572,1590)
assert R(CSI2B + 0x20) == 0x002B0011           # S0_DI_CTRL VC0/DT 0x2b (seninf1-csi2.h:99-107)
assert R(CSI2B + 0x60) & 0x100 == 0x100        # CH0_S0_GRP_EN          (seninf1-csi2.h:186-187)
assert R(TOP  + 0x48) & 0x1 == 0x1             # PHY_CTRL_CSI2 DPHY_EN  (top-ctrl.h:110-111)
assert R(CTRLB + 0x10) & 0x1 == 0x1            # SENINF_CSI2_CTRL CSI2_EN(seninf1.h:17-19)
assert R(CTRLB + 0x00) & 0x1 == 0x1            # SENINF_CTRL SENINF_EN  (seninf1.h:9-11)

# --- 2. put cam_mux into a known state (defined double-buffer page)
W(GCSR + 0x00, R(GCSR + 0x00) | 0x1); usleep(1); W(GCSR + 0x00, R(GCSR+0x00) & ~0x1)

# --- 3. point mux 1 at intf 4  (TOP_MUX_CTRL_0, byte1 = "MUX2", bits 8-12)
W(TOP + 0x10, (R(TOP + 0x10) & ~0x00001F00) | (INTF << 8))   # expected 0x03020400

# --- 4. seninf mux 1: source group 8 (MIPI_SENSOR+grp0), pixel mode 1, polarities 0
W(MUXB + 0x04, (R(MUXB + 0x04) & ~0x0000030F) | 0x00000108)  # SRC_SEL=8, PIX_MODE_SEL=1  (keeps FIFO_PUSH_EN)
W(MUXB + 0x08,  R(MUXB + 0x08) & ~0x00030000)                # HSYNC_POL=0, VSYNC_POL=0
t = R(MUXB + 0x00)
W(MUXB + 0x00, t | 0x6)                                      # SW_RST|IRQ_SW_RST = 1
W(MUXB + 0x00, t & ~0x6)                                     #           = 0   (t preserved)
W(MUXB + 0x00, R(MUXB + 0x00) | 0x1)                         # SENINF_MUX_EN = 1

# --- 5. cam_mux 3 -> CAMSV1
W(PCSR + 0x04, 0x0000AB80)                                   # OPT: VC_SEL=0,VC_SEL_EN=1,DT_SEL=0x2b,DT_SEL_EN=1
W(PCSR + 0x00, (R(PCSR + 0x00) & ~0x0000001F) | MUX)          # CTRL.SRC_SEL = 1 (= mux 1)
W(PCSR + 0x14, (3000 << 16) | 4000)                          # CHK_CTL EXP_VSIZE=3000 EXP_HSIZE=4000 -> 0x0BB80FA0
W(PCSR + 0x00, (R(PCSR + 0x00) & ~0x00000300) | 0x00000300)   # CTRL.CHK_PIX_MODE = 1
W(PCSR + 0x0C, 0x00000103)                                   # IRQ_STATUS clr HSIZE|VSIZE|VSYNC
W(PCSR + 0x00, R(PCSR + 0x00) | 0x00000080)                   # CTRL.EN = 1   <<< data now flows into CAMSV1

# --- 6. confirm
assert R(PCSR + 0x00) & 0x80 == 0x80            # cam_mux 3 enabled
assert R(TOP + 0x10) >> 8 & 0x1F == 4           # mux 1 <- intf 4
assert R(MUXB + 0x04) & 0xF == 8                # mux 1 source group = MIPI_SENSOR+0
# optional live proof: cam_mux size checker counts real pixels
assert R(PCSR + 0x18) & 0xFFFF > 0              # CHK_RES.RCV_HSIZE (cammux-pcsr.h:63-67)
```

**End state: SENINF CSI port 2 (intf 4) → mux 1 → CAM_MUX 3 → CAMSV1 @ `0x1a110000`.**
The next step (separate task, module-side) is the CAMSV instance bring-up:
`CLK_EN 0x60`, `MODULE_EN 0x40`, `FMT_SEL 0x44`, `TG_SEN_MODE 0x100`, `TG_VF_CON 0x104`,
`TG_SEN_GRAB_PXL 0x108`/`_LIN 0x10C`, `TG_PATH_CFG 0x110`, `IMGO_BASE_ADDR 0x700`,
`IMGO_XSIZE 0x710`, `IMGO_YSIZE 0x714`, `IMGO_STRIDE 0x718`, `IMGO_BASIC 0x71C`, all per
`isp71_ref/mtk_cam-sv-regs.h`, with the frame sequence in `CAMERA_NOTES.md` §8.8.

Sanity fallbacks if step 6 fails:
1. `CTRL.EN` didn't stick → cam_mux page issue (U2): set `GCSR DYN_CTRL` bit7 and redo step 5.
2. `CHK_RES.RCV_HSIZE` stays 0 → the mux isn't producing data: re-check §3 row 3 (byte 1 must
   be 4, *not* the reset value 1) and the `S0_DI_CTRL`/`CH0_CTRL` verification in step 1.
3. `CHK_ERR_RES` non-zero → size mismatch: re-check `EXP_HSIZE/EXP_VSIZE` against the sensor's
   actual output (read IMX582 `0x034C`/`0x034E`), and re-check `pixel_mode` (U3).
4. CAMSV1 still idle while cam_mux 3 is verifiably enabled and delivering → try a cam_mux inside
   the CCU's 5..21 CAMSV window with its matching instance (U4): e.g. cam_mux 5 → `camsv3@1a112000`
   (`PCSR` = `0x1a0104a0`) or cam_mux 8 → `camsv6@1a115000` (`PCSR` = `0x1a010500`); only rows 11-16
   change, row 12's `SRC_SEL` stays 1.

---

## 附录 A：D-PHY 接收机初始化序列（并入自已删除的 `SENINF_CONFIG.md`）

`SENINF_CONFIG.md` 里被实测推翻的三条**不要再用**：`step 8` 的 CAM_MUX 布局（写成 `0x400` 区每 4 bit
一个源选择： 实际是 `PCSR 0x400 + 0x20 * cam_mux`，见本文件正文）、`step 6` 的 "RAW10 ⇒ 2 px/周期"
（实测 `route_pix_mode = 2` 对应 12-bit 打包）、以及探针地址 `CSI2_PACKET_CNT = 口基 + 0x8D8`
（正确是 per-CSI2 + `0xDC`，口 2 = `0x1a014adc`）。下面这几段是当时**正确**的部分。

### A.1 基址风格：2_0 风格基址 + 3_0 语义

端口 2 的 ANA/D-PHY 块在 `0x11c88000` / `0x11c89000` / `0x11c8a000` 一带（即"2_0 风格基址"），
但语义按 `phy_3_0`：时钟 lane settle、`SPARE0 = 0xf1`、trail 计算、RESYNC full-write、
`CDR_CK_DELAY = 4`、没有 RESERVE/RST_MODE。**3_0 头文件里的基址表属于别的芯片，不要用**
（它把 port2 写成 `0x4000/5000/6000`，实测那块全静默）。

### A.2 配置顺序（从 `hw_phy_2_0.c` 提取）

1. **模拟 BG 上电**：`ANA_8` 的 6 个 `EQ_OS_CAL_EN = 0`；`ANA_0` 的 `BG_LPF_EN = 0`、
   `BG_CORE_EN = 0` → `udelay(200)` → `BG_CORE_EN = 1` → `udelay(30)` → `BG_LPF_EN = 1` →
   `udelay(1)` → 6 个 `EQ_OS_CAL_EN = 1` → `udelay(1)`。
2. **EQ tune**：`ANA18/1C/20` 的 `EQ_IS = 1`、`EQ_BW = 1`（每 lane）。
3. **D-PHY init**：每 lane `HS_PARAMETER`：`settle_delay_dt`（默认 0x23 左右）、`HS_PREPARE = 2`、
   **`HS_TRAIL = 0x1a`（26）**： 计算链 `dphy_trail = 68 / ui_224 = 163 / SENINF_CK = 273 MHz`
   ⇒ `ceil((163-68) × 273e6 / 1e9) = 26`；`data_rate < 800M` 时 `HS_TRAIL_EN = 1`。
   （笔记里出现过的 `0x34`、`0x20` 都与实测 26 冲突，以 26 为准。）
4. **CSI2 数字**：`DBG_CTRL.RG_CSI2_DBG_PACKET_CNT_EN = 1`（后面测包计数就靠它）；
   `RESYNC_MERGE_CTRL.CYCLE_CNT_OPT = 1`；4 lane 时 `CSI2_EN = 0xF`；
   `CSI2_OPT.CPHY_SEL = 0`；`HDR_MODE_0` 的 `HEADER_MODE = 0`、`HEADER_LEN = 0`。
5. **SENINF CTRL**：`SENINF_CSI2_CTRL.RG_SENINF_CSI2_EN = 1`，随后 `SENINF_EN = 1`。
6. **mux**：`CTRL_1` 写 `MUX_SRC_SEL` + `PIX_MODE_SEL`；`MUX_OPT` 写 HSYNC/VSYNC 极性；
   `CTRL_0` 先 `|0x6`（`SW_RST` + `IRQ_RST`）再 `&~0x6`；最后 `MUX_EN`（`CTRL_0` b0）= 1。
7. **TOP mux**：`TOP_MUX_CTRL_0..3` 里每 8 bit 一个 SENINF mux 的源选择。
8. **CAM_MUX**：见本文件正文（`PCSR` 页，`SRC_SEL = 8` 表示 `MIPI_SENSOR + group`）。
9. **CAMSV TG + DMA**：见 `CAMERA_NOTES.md §8` 与 §附录 A。

### A.3 帧缓冲协议（`cam_view.c`）

`/tmp/frame.rgb` = 头 `"K50F"` + u32 宽 + u32 高 + RGB888 数据；`cam_view.c` 最近邻放大写到
`/dev/fb0`，每 0.5 s 重刷。抓帧侧负责 12-bit 解包 + nearest 邻去马赛克（RGGB）后写这个文件
（`src/cam_view.c` + `src/cam_view.py` 里的 python 版）。
