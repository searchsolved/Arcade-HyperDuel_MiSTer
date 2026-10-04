# Releases

Released bitstreams and MRA files, in the MiSTer-devel arcade layout.

Copy `Arcade-Hyprduel_YYYYMMDD.rbf` to `/media/fat/_Arcade/cores/`, the
MRA files to `/media/fat/_Arcade/`, and the ROM set (MAME 0.288 naming,
`hyprduel.zip`) to `/media/fat/games/mame/`.

Alternative versions live in `_alternatives/_Hyper Duel/` and are copied
to `/media/fat/_Arcade/_alternatives/_Hyper Duel/`.

| File | md5 | Notes |
|------|-----|-------|
| `Arcade-Hyprduel_20261004.rbf` | `1a43eebf55e0c6ca3e6b4a3f1137b5f0` | M6295 (jt6295) BUSY timed as the datasheet, phrase end and start handling as MAME; YM2151 write held to jt51 cen_p1 (docs/ACCURACY.md 3.7, 3.8). Video sync keeps running (black) during the ROM download instead of stopping. Board A/B against the previous RTL (601 frames, frame dumps and write logs identical) and timing (all clocks non-negative) passed; on-hardware verification pending. |
| `Arcade-Hyprduel_20260927.rbf` | `61ffd24598df77d4a0ed8d1b3f068232` | Previous release. One RBF for Hyper Duel and Magical Error (MRA mod byte). Magical Error YM2413 music fixed. HDMI video options (aspect, scale, 216p crop). |

Every released RBF passed, in order: the full Verilator parity suite,
the always-on integrity gates over a 2,200-frame SDRAM-model soak with
the hardware DIP configuration, a clean Quartus timing summary (all
clocks non-negative, report timestamps matched to the bitstream), an
md5-verified deploy, and on-hardware verification on a CRT.

## Magical Error wo Sagase

`Magical Error wo Sagase.mra` runs on the same RBF as Hyper Duel. Its
`<rom index="1">` mod byte (01) selects the game at load time; see
`../docs/single_rbf.md`. It needs `magerror.zip` (MAME 0.288 naming).

