# Tournament Edition (phase 2.5)

The online mod's code is written with Sonic Riders US's addresses; `src/runtime/srnp_game.hpp` gives them in
Tournament Edition 2.4.6.1 (GXSRTE) from a table of ranges, `srnp_game_te.inc`, made here from the player's
own two games (nothing of the games is in this repository):

    python -I carte.py <US main.dol with _Main.rel merged> <TE main.dol> <src/runtime> <out>
    python -I genere_inc.py <out>/plages_code.txt <out>/donnees.txt manuel.txt <out>/srnp_game_te.inc

- `carte.py`: code matched by the instructions' shape (opcode and registers), anchors of 12 extended both
  ways; data by the address pairs (`lis`/`addi`, `r13`/`r2`) inside the matched code; the mod's addresses
  listed with their translation (`carte.txt`).
- `manuel.txt`: what was found by hand (TE's main loop, the low-memory caves, the REL's BSS as one block,
  16 camera reads in functions TE changed).
- `lockstep_te.sh`, `demo_8_te.sh`, `pilote.sh`: the test scripts used on 2026-11-26 (paths of the measuring
  machine).
