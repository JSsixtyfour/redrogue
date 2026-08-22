# Red Rogue PyBoy Smoke Tests

Run from WSL through the project Makefile:

```sh
make smoke
```

The target builds `pokeblue_debug.gbc`, resolves current addresses from
`pokeblue_debug.sym`, and runs the focused smoke suite with Python's standard
`unittest` runner.

Current coverage:

- Debug 1 boot to Silph Co Dorm with the intro tour complete
- Debug 2 boot through Indigo Plateau Lobby initialization
- Data-driven contracts for all 22 selectable rogue stages
- Route entry, warp tables, object counts, script state, five trainer classes, and reward trigger
- Explicit Route 24 Nugget Bridge and SS Anne B1F multi-room exceptions
- Registry drift checks against `RogueStageMapTable` and `MiniBossStageSlots`
- Real `SaveGameData` and `LoadMainData` preservation of core run state
- Cave, forest, and cemetery preload/entry generation invariants
- Giovanni mini-boss replacement of route object slot 5
- Underground route text width and trainer-class-prefixed `EndBattleText`

Failed emulator tests write a rendered screenshot and JSON state dump under
`tools/pyboy_smoke/artifacts/`. Artifacts include the debug ROM SHA-256 and are
ignored by Git.

PyBoy is installed in WSL for this project. Run `wsl make smoke` from Windows
PowerShell, or `make smoke` from a WSL shell.

The harness always starts PyBoy with `cgb=False`. Tests therefore exercise the
supported monochrome Game Boy path even if unfinished CGB work changes the ROM
header.

The slower integration tier drives complete gameplay interactions and is kept
separate from the fast smoke suite:

```sh
make integration
```

Current integration coverage walks through Lobby Door 1 into Route 1, enters
the first trainer's sight line, wins the battle through battle-menu inputs,
handles replacement and natural level-up prompts, and verifies experience,
move-learning checks, the trainer event, battle count, and return to the route
script.

## AI scenarios

`make ai_scenarios` loads declarative fixtures from `ai_scenarios.json`. Each
fixture names exact species, levels, moves, trainer class, and AI tier. The
harness writes the compact team block to debug-only SRAM, starts FIGHT 2, and
records the untouched four-move AI score array before the selection loop
destroys it. Results are written to `artifacts/ai_scenarios.json`.
Use `--trials N` for repeated save-state-reset trials; the runner emits both
JSON details and a flat CSV beside it.

FIGHT 2 still falls back to its seeded random 6v6 generator when the SRAM magic
byte is absent, so its existing deterministic smoke test remains valid.
