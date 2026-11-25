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

Phase 2 prototype (8 seats drive Sonic Riders' 8 racers; runner with `SRNP_RACERS=1`, see
`src/runtime/srnp_racers.hpp` in the ModernGekko patch):
- `relais.py` takes one or two seats per connection (`SRNP_SEAT=3,4`).
- `lockstep8_local.sh <runners> natif|jit [capture frame] [end frame]`: `SIEGES` seats (8 by default)
  on N runners of one PC (8: one seat each, 4: two each) from a save state (`ETAT`: a race, or the
  "Are you ready?" menu: seat 0 then presses Start through the relay; with `SRNP_PERSOS` and
  `SRNP_NB_RACERS` the race is set up with the lobby's characters and that many racers), test inputs
  `SRNP_INPUT=course:1` (forward, random steering, then the AI takes the racer), each runner's camera
  on its seat; screenshots at the capture frame and at the end, MEM1 compared (measurement PC's
  paths). `REPARTITION="0,1 2,3 4 5 6 7"` gives each runner its seats (two seats: split screen, from
  a 2-player save state, with `PORTS=2`). `CHECK=<n>`: a checksum and a dump of the racers every n
  frames (60 by default). `CHASSIS=<folder>`: runs the runners from another folder (executable,
  `Sys`, `Resources`, module), taken as it is.
- With the native core, the runner steps the relay at the head of the game's main loop (patch 0009):
  inputs are applied, and checksums taken, at the same point of the game's frame on every machine,
  and frame numbers count the game's frames from the save state. `SRNP_CROCHET=0` steps at each
  present instead, as before.
- During a race, racers out of the camera's sight keep their animations (patch 0010: the game's 1P
  drawing picks the next animation only for the racers it sees); `SRNP_ANIM=0` keeps the game's code.
- The seat's head is the one that blinks on the minimap (patch 0011, with the HUD); with a relay the
  runner's menu never pauses the game. `SRNP_PATCH=<address>=<word>,...` writes code words for the
  race (experiments: which HUD task shows what).
- `compare_racers.py <run> <runners>`, `compare_ck.py <run> <runners>`: the racers of the runners at
  the end, and at every checksum (`SRNP_CKDUMP`), without the fields that follow the camera.
- `compare_ab.py <run A> <run B> [runner] [--tout]`: the racers of two runs, frame by frame (the same
  race with another camera, say): the fields that differ and where they first do.
- `depart_8cpu.sh`: makes the save state of a race whose 8 racers are CPUs when it is set up (from the
  "Are you ready?" menu, with `pilote.sh`).
- `pilote.sh`: keeps one runner open and sends it automation commands one by one (how the menus were
  crossed to make the race save states; measurement PC's paths).
- `desas.py`: a disassembler of the combined DOL (`SRNP_DOL`; main.dol plus `_Main.rel` relocated to
  0x803FBD00), with capstone (`pip install capstone`; run without `-I`).

Comments and output are in French.
