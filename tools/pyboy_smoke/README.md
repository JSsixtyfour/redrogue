# Red Rogue PyBoy Smoke Tests

Run from WSL through the project Makefile:

```sh
make smoke
```

Run one test, class, or module with a shell-style test-ID pattern:

```sh
make smoke TEST='*fight2*'
python3 tools/pyboy_smoke/run_smoke.py --list
```

The target builds `pokeblue_debug.gbc`, resolves current addresses from
`pokeblue_debug.sym`, and runs the focused smoke suite with Python's standard
`unittest` runner.

Current coverage:

- Debug 1 boot to Silph Co Dorm with the intro tour complete
- Debug 2 boot through Indigo Plateau Lobby initialization, including automatic and forced AI tiers
- Phase 0 Focus Energy and selective badge-reboost battle mechanics
- Phase 4 `AISelectSendOut` contracts: current and fainted candidates are
  excluded, neutral ties choose the earliest living slot, temporarily borrowed
  battle bytes are restored, and the real `EnemySendOut` selector handoff
  honors effectiveness ranking
- Data-driven contracts for all 22 selectable rogue stages
- Route entry, warp tables, object counts, script state, five trainer classes, and reward trigger
- Explicit Route 24 Nugget Bridge and SS Anne B1F multi-room exceptions
- Registry drift checks against `RogueStageMapTable` and `MiniBossStageSlots`
- Real `SaveGameData` and `LoadMainData` preservation of core run state
- Cave, forest, and cemetery preload/entry generation invariants
- CGB boot-to-lobby defaults, double-speed state, and live HRAM OAM-DMA wait timing
- Giovanni mini-boss replacement of route object slot 5
- Underground route text width and trainer-class-prefixed `EndBattleText`

Failed emulator tests write a rendered screenshot and JSON state dump under
`tools/pyboy_smoke/artifacts/`. Artifacts include the debug ROM SHA-256 and are
ignored by Git. Dumps also include the symbol-file SHA-256, CPU registers,
current bank and nearest symbol, stack bytes, RNG state, and recent named hook
hits. `artifacts/index.json` points to the latest screenshot and state for each
failed test. Harness startup rejects structurally incompatible ROM/symbol pairs and a
symbol file newer than its ROM, which usually indicates mixed build artifacts.

PyBoy is installed in WSL for this project. Run `wsl make smoke` from Windows
PowerShell, or `make smoke` from a WSL shell.

The harness defaults to DMG mode. In that mode it patches only its in-memory ROM
header mirror and starts PyBoy with `cgb=False`, keeping the established battle,
AI, and procedural tests independent of CGB-only work.

Focused CGB tests instantiate `RedRogueHarness(..., cgb_mode=True)`. This retains
the built ROM's CGB header and starts PyBoy with `cgb=True`. The included CGB
speed test boots through Debug 2 to the lobby and verifies:

- saved `wOptions2` bits 6-7 are both on for a new game;
- `rKEY1` bit 7 reports double-speed mode;
- `hDMARoutine.waitCount + 1` contains `$50`, twice the single-speed `$28` wait.

Hardware classification is enforced by the smoke runner. Modules named
`test_cgb_*.py` must construct a CGB harness; every other smoke module must use
the default DMG harness. The selected mode is included in failure state and the
artifact index.

Known but not yet authoritative behavior contracts live in
`pending_contracts.json`. Each entry must state the observation, unresolved
decision, and current test boundary. The smoke suite validates the registry and
resolved entries should be removed when their executable contract lands.

PyBoy proves those machine states but is not final visual acceptance. Use BGB
for palette appearance, fades, title/credits raster effects, walking and NPC
cadence, ledges, and the S.S. Anne departure sequence.

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
destroys it, plus the best-score eligible slots and enemy-switch decision. The
scenario's `expect` object is executable: a failed expectation fails the target.
Supported keys are `enemy_move_slots`, exact `scores`, `tier`, `pick_slot`
(one allowed slot or a list), `never_pick`, `score_lt` and `score_lte` (lists of slot
pairs), `switch`, and `no_switch`. Results are written to
`artifacts/ai_scenarios.json`.
Use `--trials N` for repeated save-state-reset trials; the runner emits both
JSON details and a flat CSV beside it.

Every scenario also declares `phase`, `heuristic`, `case`, `tags`, and
`required_cases`. Cases are `positive`, `negative`, `boundary`, or `regression`.
The runner groups scenarios by `phase:heuristic`, fails before emulation if any
declared required case is missing, and writes `ai_scenarios.coverage.json`.

Telemetry includes a `layer_trace` entry for every scoring layer. Each entry
records whether the layer is enabled at the resolved tier, its before/after
score arrays, and the four signed deltas. This identifies which layer caused a
decision without adding ROM instrumentation or consuming Game Boy RAM.

Phase 4 send-out selection now has both direct structural tests and an
`EnemySendOut` caller-handoff trace. The latter records the previous slot,
winning combined score, ranked slot, and slot actually handed to the battle
core. Whether-to-switch policy remains covered through declarative AI scenarios.

FIGHT 2 still falls back to its seeded random 6v6 generator when the SRAM magic
byte is absent. Seed 17 is a versioned party-generation golden: it detects RNG
call-order drift before party construction and is intentionally independent of
AI behavior. The first enemy sent out is not guaranteed to be generated party
slot 0, so battle-state tests must read the active slot instead of assuming it.
