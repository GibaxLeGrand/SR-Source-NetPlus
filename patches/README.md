# SR-Source Net Plus: patches for the submodules (phase 0, native core)

This branch (`srnp/phase0-natif`) keeps `external/ModernGekko` at the same commit as SR-Source, so that
a fresh clone builds. Our changes to the submodules and to the recompiler are here as `git am`
patches. Measured on Sonic Riders (GXEE8P), demo race loaded from a save state, 1800 frames,
uncapped, one PC (Ryzen 5 5600X), November 2026.

| Folder | Applies to | Base |
|---|---|---|
| `ModernGekko/` | `external/ModernGekko` | `953c0cf` (SR-Source 0.2.5) |
| `RecompCore/` | `external/ModernGekko/vendor/dolphin` | `cf8ceb81b4` (ExpansionPak/RecompCore, `moderngekko-vendor`) |
| `DolRecomp-piconet/` | [piconet-live/dolrecomp](https://github.com/piconet-live/dolrecomp), branch `piconet` | `5787304` |

```sh
git -C external/ModernGekko am ../../patches/ModernGekko/*.patch
git -C external/ModernGekko/vendor/dolphin am ../../../../patches/RecompCore/*.patch
git -C <piconet's dolrecomp checkout> am <this repo>/patches/DolRecomp-piconet/*.patch
```

## What they do

**ModernGekko**
- (phase 2 prototype, branch `srnp/phase2`) with `SRNP_RACERS=1`, seat k drives Sonic Riders' racer k
  instead of pad k: the runner fills a controller structure per seat the way the game does (main.dol
  0x80006778; `SRNP_PADCHECK=1` compares them), points the racer to it and makes it human (+0xBC = 0);
  a seat can give its racer to the AI; viewport 0's camera follows the local seat. Several seats per
  runner (`SRNP_SEAT=3,4`), racing test inputs (`SRNP_INPUT=course:<seed>`), a checksum of the 8
  racers without the fields that follow the camera, `SRNP_CKDUMP=<dir>`. On one PC: 8 native runners,
  one seat each, a whole race (Metal City, 1 lap, from a race set up with 8 CPUs), 143 checksums
  equal, the same results on all 8.
- (phase 1 prototype, branch `srnp/phase1-relais`) a relay client in the runner: with
  `SRNP_RELAY=<host>:<port> SRNP_SEAT=<k> SRNP_SEATS=<n>`, after every present it sends its input for
  the frame `SRNP_DELAY` (2) frames ahead to `tools/srnp/relais.py`, waits for the next frame's official
  inputs and gives seat k's input to the emulated pad of port k (Dolphin's input overrider), on the
  emulation thread. Checksums of `_Main.rel`'s BSS every 60 frames. Test inputs only
  (`SRNP_INPUT=random:<seed>`).
- `pad_frames … pause_at=<frame>`: the automation pauses the emulated CPU exactly when the
  presenter's frame counter reaches `<frame>` (from the emulation thread), instead of some time after
  the automation thread has counted the frames. With it, two runs from the same save state give the
  same MEM1 bit for bit (native core and JIT64); the asynchronous pause made thousands of words
  differ.

**RecompCore** (StaticRecomp core; most of it taken from
[Piconet's RecompCore](https://github.com/piconet-live/recompcore), GPL-2.0-or-later)
1. Exact float helpers on MSVC; `SRNP_FALLBACK_STATS=1` counter (measurement only).
2. Cache lines with no module code and no fallback-JIT block skip the icache invalidation
   (Piconet's fast reject). ~+14 %.
3. A runtime cycle budget for modules built with `DOLRECOMP_BUDGET_CYCLES=runtime`, with the clock
   brought up to date at every hardware access.
4. The module is told which chunks are verified (`staticrecomp_set_native_valid`) and gets the
   write-gather pipe (`staticrecomp_set_gather_pipe`); needed by `DOLRECOMP_INDIRECT_CALLS=native`,
   closed bodies and `DOLRECOMP_GATHER_PIPE=inline`.
5. Guest busy-wait loops found by Dolphin's analyzer are skipped (RecompCore PR #19, as Piconet has
   it). `SRNP_NO_BUSYWAIT=1` turns it off.
6. `dcbst`/`dcbf`/`dcbi` over data return at the cache hook. ~+6 %.
7. The module gets Dolphin's exception word (`staticrecomp_set_exceptions`), for
   `DOLRECOMP_EE_EXIT=pending`.

**DolRecomp (Piconet's fork)**
- `DOLRECOMP_EE_EXIT=pending`: where a write sets MSR[EE], generated code leaves for the run loop only
  when an external interrupt is pending (the only case where the run loop delivers one there).

## The module

`tools/dolrecomp/recompile.sh` takes `SRNP_RECOMP_OUT=<folder>` (an output of its own, nothing
replaced) and `FASTLOOKUP=<Piconet's tools/fastlookup.py>` (its O(1) lookup and `native_tables.c`).
`src/recompiled/CMakeLists.txt` takes `-DSRNP_GENERATED_ROOT=<folder>`. `_Main.rel` is added to the DOL
as a code section before recompiling (Piconet's method), with `tools/dolrecomp/merge_rel.py`'s
relocation.

Fastest setting measured (`DOLRECOMP_*`, on top of Piconet's switches that need no runtime:
`SCALAR_FP=inline PAIRED_FP=jit64 FMA=hw PS_MADD=guarded FPRF=lazy FPSCR=inline CYCLES=deferred
STATE_SYNC=changed STATE_ALIAS=scoped ENTRY_LOADS=split CALL_COUNTERS=registers PRESERVE_NONE=1
RESERVATION=stwcx-only PSQ_GQR=0:0 ENTRY_QUERY=off LLVM_CHUNK_INSTRUCTIONS=4096`):

```
BUDGET_CYCLES=runtime INDIRECT_CALLS=native CLOSED_ROOTS=all CLOSED_DEFER=1
CLOSED_EXCLUDE=80010428,800A50C0 GATHER_PIPE=inline EE_EXIT=pending   + FASTLOOKUP, + PGO
```

| Configuration (same quarter of an hour) | frames/s |
|---|---|
| Piconet's switches that need no runtime + PGO | 167.6-172.0 |
| all of the above without `CLOSED_DEFER` + PGO | 229.3-233.4 |
| **all of the above + PGO** | **273.3-276.6** |
| JIT64 | 318.0-322.9 |

`CLOSED_DEFER` delays interrupts until the outermost closed body returns: deterministic, same race,
but 15 words of `_Main.rel`'s BSS that depend on interrupt timing differ from the settings without it
(the JIT64 has other values there too).
