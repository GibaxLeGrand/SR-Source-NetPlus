# SR-Source Net Plus: measurement tools (Windows, Python 3, no dependencies; run with `python -I`)

- `echantillonneur.py <automation dir> <first command> <last command> <out>`: a sampling profiler for
  `moderngekko-run.exe` (SuspendThread + GetThreadContext, ~500-1000 samples/s on the busiest
  threads), between two automation commands. Writes `<out>.bin` and `<out>.json`.
- `analyse_echantillons.py <out> --carte <module>=<file.map> …`: splits the samples by thread, module,
  symbol and recompiled PowerPC function. Symbols come from linker maps (`link.exe /MAP`,
  `lld-link /map`), which, unlike `/DEBUG`, leave `.text` unchanged; system DLLs by their exports.
- `sections_pe.py <a> <b>`: compares the sections of two PE files (to check that a relink with a map
  left the code identical).
- `rsp_lien.py <build.ninja> <output> <file.rsp> [newline]`: writes the response file of a CMake/Ninja
  link step, to relink by hand.
- `compare_ram.py <run a> <run b>`: compares two MEM1 dumps (`mem1_lo.bin`, `mem1_hi.bin`) and reads
  Sonic Riders' frame counter (0x801AF9F0) to say whether both were taken at the same frame.
- `diff_zone.py`, `chercher_compteur.py`: the differing words of a zone; small integer deltas between
  two dumps (to find frame counters).
- `compare_lockstep.py <run a> <run b>`: compares the divergences reported by
  `STATICRECOMP_LOCKSTEP=1` in two runner logs, by entry point and by kind.
- `analyse_sites.py <run> <generated.h> <main.dol>`: classifies the dispatch sites printed with
  `STATICRECOMP_DISPATCH_SAMPLES=1` (return after a call, function entry, middle of a function with a
  jump table).

Phase 1 prototype (lockstep through a relay):
- `relais.py --sieges N [--delai-ms 50] [--port 7845] [--journal file]`: closes each frame when every
  seat has sent its input, or `--delai-ms` after its first input (a late seat's last input is
  repeated, so a slow machine does not hold the others back); compares the seats' checksums.
  (`--cadence` closes frames on a fixed clock instead; it fell behind its own start-up and is not
  used.)
- `lockstep_local.sh <seats> natif|jit [pause frame]`: starts the relay and N runners on one PC from
  the same save state, pauses them all at the same frame and compares their MEM1 (paths are the
  measurement PC's).

Comments and output are in French.
