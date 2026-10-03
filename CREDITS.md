# Credits and third-party components

This core combines new RTL with proven open-source components. Every
third-party component retains its own license and copyright headers in
place; the combined work is distributed under GPL-3.0-or-later (see
LICENSE). Local modifications to vendored cores are documented in
`rtl/vendor/PATCHES.md`.

## New work in this repository

- Imagetek I4220 VDP (`rtl/i4220_vdp.sv`, `rtl/i4220_render.sv`,
  `rtl/i4220_blitter.sv`): first FPGA implementation of any Imagetek
  video chip. GPL-3.0-or-later.
- TEC442-A board glue (`rtl/hyprduel_sys.sv`), SDRAM controller
  (`rtl/hyprduel_sdram.sv`), BRAM wrappers, MiSTer shell
  (`Arcade-Hyprduel.sv`), simulation and verification harness (`sim/`),
  tooling (`tools/`). GPL-3.0-or-later.

## Vendored cores (`rtl/vendor/`)

| Component | Author | License | Upstream |
|---|---|---|---|
| fx68k (68000, cycle-accurate, x2) | Jorge Cwik | GPL-3.0 | https://github.com/ijor/fx68k |
| jt51 (Yamaha YM2151) | Jose Tejada (@topapate / jotego) | GPL-3.0-or-later | https://github.com/jotego/jt51 |
| jt6295 (OKI MSM6295) | Jose Tejada (@topapate / jotego) | GPL-3.0-or-later | https://github.com/jotego/jt6295 |

The jt51 core is used unmodified except for the build accommodations
listed in `rtl/vendor/PATCHES.md` (Verilator lint pragmas); the core's
bus glue holds each YM2151 write until jt51's cen_p1 so its busy flag
works. jt6295 has the same build accommodation (a lookup table kept in
logic for Quartus 17 RAM inference) and three behavioural patches,
matching MAME's M6295 model: a phrase ends after the second nibble of
its stop byte, a start command to a channel that is still playing is
ignored, and the busy status is timed as the MSM6295 datasheet
describes, with a decoder reset on every start
(`rtl/vendor/PATCHES.md`, `docs/ACCURACY.md` 3.7 and 3.8). fx68k
carries a packed-struct portability patch for Verilator, also
documented there.

If you enjoy this core, consider supporting Jose Tejada's FPGA work:
https://www.patreon.com/jotego

## MiSTer framework (`sys/`)

The MiSTer template and framework files are copyright their respective
authors (Sorgelig and MiSTer-devel contributors), GPL-2.0-or-later.
https://github.com/MiSTer-devel

## Reference material

- MAME's `imagetek_i4100.cpp` / `hyprduel.cpp` / `metro.cpp`
  (BSD-3-Clause, copyright Luca Elia, David Haywood, Angelo Salese and
  contributors) are vendored under `reference/mame/` as the behavioural
  documentation of record. This core would not exist without that
  reverse-engineering work. https://github.com/mamedev/mame
- Real-hardware references used for verification (see docs/ACCURACY.md):
  a TEC442-A board photograph by Stefan Lindberg (arcade-museum.com)
  and an original-PCB one-credit-clear recording by STG cvlt.

## The game

Hyper Duel is copyright Technosoft (1993). This repository contains no
game ROM data in any form; the core loads a user-supplied MAME ROM set
(`hyprduel`) at runtime via the MRA file.
