# Vendor patches

## fx68k (github.com/ijor/fx68k, cloned 2026-07-04)

- `fx68k.sv`: all three `typedef struct` made `typedef struct packed`.
  Reason: Verilator 5.x rejects mixed blocking (`assign`) and non-blocking
  (`<=`) writes to different fields of the same UNPACKED struct
  (BLKANDNBLK on `Nanod`); packed structs are splittable and accepted.
  No functional change; Quartus accepts packed structs equally.

- `fx68k.sv`, `fx68kAlu.sv`: all `unique case` changed to `case`.
  Reason: Verilator enforces unique-case no-match as a runtime $stop; the
  ALU hits a benign no-match at time 0 before reset settles (X-init).
  Behaviour-neutral: the alternatives are mutually exclusive by
  construction; `unique` only added checking.

## fx68kAlu.sv ccrTable default (2026-07-05)
The `unique case` -> `case` Verilator patch removed the full-coverage
guarantee on the col-2/3 `case (1'b1)` in ccrTable, so Quartus 17.0.2
inferred a latch inside always_comb (Error 10166). Restored the
commented-out `default: ccrMask = CUNUSED;` which is behavior-neutral
(the branch was unreachable under the original unique semantics).

## jt6295_adpcm.v ramstyle attributes (2026-07-06)
Added `(* ramstyle = "logic" *)` to `lut[0:48]` and `gain_lut[0:15]`.
Reason: Quartus 17.0 inferred the 49-entry lut as a memory, padded the
depth to 64 but emitted a 49-deep .mif (Critical Warning 127005 depth
mismatch), immediately before quartus_map died with an access violation
(compile 7). Both tables are tiny; keeping them in logic is what
compile 6 did anyway ("uninferred, inappropriate RAM size") and
sidesteps the buggy path. Verilator ignores the attribute; no
functional change.

## fx68k.sv packed structs made Verilator-only (2026-07-06)
The 2026-07-04 packed-struct patch is now wrapped in `ifdef VERILATOR`
so Quartus elaborates the upstream UNPACKED structs. Working theory for
the 1h / 20-50GB Quartus 17 elaboration phase: s_nanod is ~90 fields
referenced throughout two CPU instances, and packing it turns every
field reference into part-select arithmetic in the Quartus front end.
Upstream unpacked structs are what every other MiSTer fx68k core
compiles. Verilator sees the packed form, unchanged, so sim behaviour
is bit-identical.

## ikaopll vendored (2026-07-19, magerror branch)
IKAOPLL (cycle-accurate, die-shot based YM2413) by Sehyeon Kim
(ika-musume), BSD-2-Clause, vendored UNMODIFIED from upstream commit
4d393238d1be33ea428a454956270504f037dfa3 (2025-01-04). Selected over
jtopl's jt2413 for the die-derived cycle accuracy; licence sits fine
beside the GPL cores (BSD-2 is GPL-compatible). Verilator 5.050 lint:
0 errors, 16 benign width warnings, no UNOPTFLAT/BLKANDNBLK/LATCH.

## jt6295_serial.v: phrase end, start on a busy channel, busy timing (2026-10-03)
Three behavioural patches, ported from the 1945k III core (patches 1
and 2, its `rtl/vendor/jt6295/PROVENANCE.md`) and the Tecmo 16 core
(patch 3, its `rtl/vendor/SOUND_PROVENANCE.md`), applied identically
here. Verification for this core
is in `docs/ACCURACY.md` 3.7.

1. Phrase end, stop byte inclusive. Original
   `assign over = rom_addr >= stop_out;` ends a voice when its byte
   address reaches the stop address, after only the first nibble of the
   stop byte: 2 * (stop - start) + 1 samples. The MSM6295 phrase table
   gives the last byte of the phrase as the stop address, and MAME's
   okim6295 plays 2 * (stop - start + 1) samples. Patched to
   `assign over = cnt >= {stop_out, 1'b1};`. Measured in the 1945k III
   core: the busy bit now lasts the nominal length (it ended 137 enables,
   about one sample, early before the patch).
2. Start command to a channel that is still playing is ignored. The
   original reloads the channel (start, stop, attenuation) whenever its
   start request comes round, busy or not, restarting the phrase.
   Patched: `start_ok = up_start & ~busy_out` replaces `up_start` in the
   reload terms; the request is still acknowledged so jt6295_ctrl clears
   it, and a stop on the same cycle still wins. Evidence: MAME 0.288
   okim6295.cpp L281-284 (the start is not performed), jt6295's own
   README lines 31-33 ("ignore commands to the same channel as long as
   the playback has not ended"; the code did not do this, and upstream
   jotego/jt6295 master has the same code), and games that re-send a
   start every frame (Solite Spirits, 1945k III) which only sound as in
   MAME with the start ignored. The MSM6295 datasheet was not checked;
   the real chip's behaviour stays a research item.
3. Busy flags committed at cen4. Upstream updates the per-channel
   `busy` flags on every clock of the channel's slot, so a pending stop
   reads as idle for up to one slot before it is committed; a start
   command's first byte clears the pending stop in jt6295_ctrl, so a
   start written in that window cancels the stop (the old phrase plays
   on, the new start is ignored as busy). Patched: the `case( ch )`
   update of `busy` runs only on `cen4`, with the channel state in the
   CSR shift register. Found in Ganbare Ginkun, whose fade-outs (stop,
   poll until idle, restart at the next attenuation) were lost; there
   the patch brings the M6295 level to MAME's within 0.03 dB.

Related change outside the vendor tree (`rtl/hyprduel_sys.sv`, also
2026-10-03): a CPU write to the YM2151 is held until jt51's next cen_p1
instead of a one-clock strobe, because jt51 sets its busy flag only for
a write that lands on cen_p1. jt51 itself is unmodified.
