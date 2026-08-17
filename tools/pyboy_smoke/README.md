# Red Rogue PyBoy Smoke Tests

Run from WSL through the project Makefile:

```sh
make smoke
```

The target builds `pokeblue_debug.gbc`, resolves current addresses from
`pokeblue_debug.sym`, and runs the focused smoke suite with Python's standard
`unittest` runner.

Current coverage:

- Debug 2 boot through Indigo Plateau Lobby initialization
- Data-driven contracts for all 22 selectable rogue stages
- Route entry, warp tables, object counts, script state, five trainer classes, and reward trigger
- Explicit Route 24 Nugget Bridge and SS Anne B1F multi-room exceptions
- Registry drift checks against `RogueStageMapTable` and `MiniBossStageSlots`
- Giovanni mini-boss replacement of route object slot 5
- Underground route text width and trainer-class-prefixed `EndBattleText`

Failed emulator tests write a rendered screenshot and JSON state dump under
`tools/pyboy_smoke/artifacts/`. Artifacts include the debug ROM SHA-256 and are
ignored by Git.

PyBoy is installed in WSL for this project. Run `wsl make smoke` from Windows
PowerShell, or `make smoke` from a WSL shell.
