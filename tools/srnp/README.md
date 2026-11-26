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
- The seat's racer has no label over it (patch 0012: the 1P labels, 0x8042F47C, left out racer 0); the
  label numbers stay the racer's index on every machine. The minimap's three words of code now sit at
  0x80002D80 (0x80002E00-0x80002FBC is kept for the 5P-8P labels).
- The player's sound and view camera follow the seat (patch 0013, two paths of the race logic);
  `SRNP_JOUEUR=0` keeps the game's. `SRNP_WATCH=<addresses>` logs guest words when they change,
  `SRNP_TRACE=<addresses>` which racer takes a path. `SON="0"` in the lockstep script keeps runner 0's
  sound (all runners are muted otherwise; muting does not change the emulation).
- The 5P-8P labels over the players' racers (patch 0014, from the labels session: a texture of our own
  in the GTSE of the srnp_etiquettes file mod; nothing changes without it). `ETIQ="0 3"` (or all) in the
  lockstep script mounts the mod on those runners (and srnp_etiquettes_hd with `HD`); start from a save
  state taken before the race loads (pret1p...).
- Start together (patch 0015): the relay answers each HELLO with `WAIT <present> <seats>` (again every
  2 s while a seat is missing) and sends `GO` once every seat is there; the runners wait at their first
  frame. Until every seat has sent an input, no frame is closed without it. `ECART=<s>` in the lockstep
  script launches the runners that many seconds apart.
- The waiting screen (patch 0016, Gibax's mockup): `WAIT` carries each seat's state (O expected, V
  there, X left); a seat that leaves before the start no longer holds it: `GO` names it with a character
  the relay drew at random, and the AI races it. `test_attente.sh`: four seats, one leaves, photos of the
  real window (`capture_fenetre.ps1`, PrintWindow: the runner's own screenshots leave out its interface).
- Patch 0018: `SRNP_IA_JOUEUR=1` makes the racers that the AI takes over (a seat with the AI's pad,
  one that left) keep their "nP" label instead of COM: simulated players, to see the 2P-8P labels with
  no one at the pads. `SRNP_PAUSE_JEU=1`: an automation pause (`pad_frames pause_at=<n>`) waits for
  that frame of the game, the same on every runner in lockstep (their present counts differ: each one
  waited its own time). The racers' checksum also leaves out three fields that only the characters'
  drawing writes (+0x84C-0x857, +0x8BC, +0x8DB). The waiting screen's pictures are no longer freed
  at exit (the video backend is gone by then: the runner crashed).
- Patches 0019-0024: the labels session's player tags (`SRNP_TAGS=TAG0,TAG1,...`, seat k = racer k) over
  the labels and in place of the names on the results screen (needs the srnp_etiquettes mod, version 5).
- Patch 0025:
  - `SRNP_INPUT=manette`: the machine's real pad, read on a port the game does not see (GCPad4,
    `SRNP_MANETTE_PORT`, SI device None), is the seat's input; the game only gets it through the relay,
    on every machine at once. `test_manette.sh`: two runners, the pad drives racer 0 on runner 0,
    runner 1 stays neutral with its camera on racer 0 (no pad reaches the game directly);
  - `SRNP_TOUS_CPU=1` flags the players' racers CPU at setup (`+0xBD` = 1: the AI's data is made) and
    leaves them driven as humans (`+0xBC` = 0); the AI takes them at the start (with `+0xBD` = 0 at
    setup, the AI crashes). `SRNP_TOUS_CPU=ancien`: the old way;
  - test switches: `SRNP_IA_JOUEURS=<n>` (seats 0 to n-1 simulated players), `SRNP_HUMAINS=<hex mask>`
    (the humans' flag at the start). With them: the stage's scenery went missing (roads, tubes,
    buildings after ~14") as soon as racer 5 was a human, whatever its character, and with no human at
    all. `ram_masque.sh <mask> <frames>`: MEM1 at frames of the game, one runner, for such comparisons.
- Patch 0026, the missing scenery fixed: the racers' update (0x8040E644) stores, for each human racer,
  the zone of "its" camera in tables of 4 cameras (0x80612BC8, 0x80612BC4); a human racer 4-7 wrote
  past them, racer 5 over camera 0's zone, which the drawing goes by (and with no human, camera 0's zone
  was never updated). During races racer 0 alone takes the humans' path there, every other racer the
  CPUs': camera 0's zones come from the machine's own camera, as in a 1P game, the same code on every
  machine (`SRNP_ZONES=0` keeps the game's). Found with `SRNP_BD5=<addresses>` (those reads of `+0xBD`
  see racer 5 as a CPU, through code in free low memory) by halving the game's 128 reads, after MEM1
  and ARAM dumps (`SRNP_ARAMDUMP=<frames>:<folder>`). 8-player demo, 8 simulated players: the 8 views
  whole, 0 divergences, the race unchanged.
- Patch 0027 (the labels session's, merged): the waiting screen's counts on one line, each seat's tag
  (`SRNP_TAGS`) under its card and "YOU" in yellow, in the font of the game's names (GoalResult_01_E,
  read from the player's GTSE; the ImGui text without it).
- Gibax's controller test (2026-11-25, `test_manette.sh`): his Xbox pad read through SDL (`XInput/0/Gamepad`
  gave nothing), from a race already running (`ETAT=...course1p...`): his inputs drive racer 0 on both
  runners, 147 checksums equal over 8848 frames, racer 0 at the same place on both. Not yet: the menu's
  Start from the pad (with no device on GCPad1 the relay's Start does not reach the menu). Patch 0028:
  the runner logs what the pad gives.
- Patches 0029-0032 (2026-11-25 evening): "1P" over racer 0 on the other machines (the label loop's own
  "racer 0" test, 0x8042F5B4); the relay's Start reaches the menus without an automation folder (a
  player's runner); the players' tags through the relay (`TAG <seat> <tag>` after HELLO, the relay sends
  `TAGS` to everyone; `SRNP_TAG` for a runner's own, `SRNP_TAGS` as before; textures drawn again when they
  change); offline 2-4 players: a GameCube port whose controller profile names a pad gets a controller
  (not with a relay, nor when Dolphin.ini sets the port). `demo_8.sh`: `TAGS_RELAIS=T0,T1,...` gives each
  runner its own tag only.
- `demo_8.sh [frame 1] [frame 2] [frame 3]`: the 8-player demo on one PC (leftovers of an earlier demo
  are stopped, other sessions' runners waited for; `N=<seats>`, `TOUS_CPU`): the waiting screen fills up, then the race, photos of the 8 windows at
  three frames of the game, and contact sheets.
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
- `absolus.py`: in a text disassembly of the REL, the instructions that address an absolute address
  or range (lis then addi/lbz/lwz/stw... on the same register).
- `zones_objets.py`: the objects' drawing sites that follow racer 0's zone (0x80612BD8) and flags,
  alone or in a loop over the views: the list behind the runner's `kObjectZoneSites` (2026-11-26).

Comments and output are in French.
