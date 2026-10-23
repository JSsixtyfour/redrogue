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
`pokeblue_debug.sym`, and runs the suite with Python's standard `unittest`
machinery in parallel worker processes (`--jobs N`, default every CPU; about
80 seconds for ~1000 tests on 6 cores). Modules are packed into batches using
the previous run's timings (`builds/smoke_durations.json`). Passing batches
print one line each; failures print their tracebacks (`--verbose` prints
everything).

Every test runs under a hang watchdog (`--test-timeout`, default 180 s). A test
that hangs dumps its Python stack, is reported as `TIMEOUT`, and the rest of
its batch carries on in a fresh worker, so a hang never stalls `make release`.

Slow modules that never start an emulator (`SOURCE_ONLY_MODULES` in
`run_smoke.py`) run under `make audit` instead (`run_smoke.py --source-only`).
An explicit `TEST=` pattern still reaches them.

`call_routine` refuses to hijack a park point that an earlier call corrupted
(SP outside the stack, away from the SP-copy routines) and fails with a
message instead of hanging. The fix is to reload a saved baseline between
calls; `test_rental_zones.RentalZoneTest.baseline_steps` shows the pattern.

Deterministic seeds make failures reproducible; they do not make an incidental
RNG sequence an API. Random-generation tests should assert structural and
gameplay invariants unless an exact sequence is itself an intentional contract.

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
script. It also plays the first three stages of a seeded autoplay run (see
below).

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

## AI benchmark

`make ai_benchmark` runs complete deterministic FIGHT 2 battles and writes
per-trial JSON and CSV reports. It defaults to T3 and a deterministic
highest-base-power player policy so the default command exercises the complete
AI. Override the tier, policy, seed, trial count, or safety limit through
`BENCHMARK_ARGS`:

```sh
make ai_benchmark BENCHMARK_ARGS='--tier all --seed 17 --trials 5 --player-policy best_power'
```

Use `--tier auto` to measure the normal round-based tier and `--player-policy
first_slot` for the old weak baseline. `--tier all` emits one directly
comparable summary row for T0 through T3.

The report includes resolved tier, raw counts, win rate, average turns, switch
and item rates, missed-KO rate, wasted-turn rate, and mean/maximum AI decision
cycles. A missed KO means the `DAMAGE`
layer marked at least one move lethal with `AI_KILL`, but the AI selected a
different slot. A wasted turn means the selected move was discouraged by the
`REDUNDANT` layer. These are heuristic-level classifications, not guesses based
only on the final battle result. Rates with no observations are `null` in JSON
and empty in CSV, never `0.0`; T2/T3 runs hard-fail if `AI_DAMAGE` produces no
KO opportunities. Decisions over the 70,224-cycle frame budget are counted.

Phase 4 send-out selection now has both direct structural tests and an
`EnemySendOut` caller-handoff trace. The latter records the previous slot,
winning combined score, ranked slot, and slot actually handed to the battle
core. Whether-to-switch policy remains covered through declarative AI scenarios.

FIGHT 2 still falls back to its seeded random 6v6 generator when the SRAM magic
byte is absent. Seed 17 is a versioned party-generation golden: it detects RNG
call-order drift before party construction and is intentionally independent of
AI behavior. The first enemy sent out is not guaranteed to be generated party
slot 0, so battle-state tests must read the active slot instead of assuming it.

## Autoplay soak test

`make autoplay` plays whole runs with an agent that reads game state from RAM
and drives the joypad itself, from the Debug 2 lobby to the Hall of Fame, one
seed per run, in parallel:

```sh
make autoplay                                   # seeds 1-8
make autoplay AUTOPLAY_ARGS='--seeds 1-64 --jobs 6'
make autoplay AUTOPLAY_ARGS='--seeds 1-16 --new-game --runs 3'
python3 tools/pyboy_smoke/autoplay.py --seed 15  # one run, events printed live
```

By default a seed starts in the Debug 2 lobby with its debug party. With
`--new-game` it starts from power-on: title screen, NEW GAME, naming, the intro
tour and Oak's Lab. `--runs N` keeps playing: a run is won at the Hall of Fame
or lost when a blackout sends the player to the Silph Co dorm (losing to the
Oak's Lab rival does not end it), and between runs the agent walks the hub
(dorm, B1F, VR) into the next one. The summary adds balance numbers over all
finished runs: champion rate, stages cleared, and where and to whom runs were
lost.

A seed ends `champion` or `blackout` (one run; a game result, not a
failure), `completed` (`--runs N` or `--stages N` reached), or fails: `stalled` (no game
progress for `--stall-frames`, a softlock suspect), `crashed` (below),
`hung` (killed after `--timeout` seconds, default 900), `frame_limit`, or `error`.
Each seed writes `artifacts/autoplay_seed<N>.json`: outcome, stages, an event
log (doors, maps, battles, reward and gift picks, `no_path`), anomalies, and
the last 200 inputs. Failed runs also get a screenshot and state dump, and
`artifacts/autoplay_summary.json` has a row per seed. The target fails if any
run failed or reported an anomaly. A full run is about 250,000 frames, roughly
25 seconds.

### AI telemetry

`--ai-telemetry` (on `autoplay.py` and `run_autoplay.py`) records one AI record per
**trainer** battle (`ai_telemetry.py`) and adds an `ai` block to
`autoplay_summary.json` (per-seed rows stay small; the records are in each seed's
report as `ai_battles`). It is read-only: the same seed plays identically with and
without it (checked 2026-10-21: outcome, frames, stages, battles won and
`last_inputs` equal; CPU cost about 1%). It reuses the harness's AI hooks
(`hook_ai_scores`, `hook_ai_personality_timing`, `hook_trainer_ai_calls`) and adds
two: `SelectEnemyMove.done` and `MainInBattleLoop`.

A record holds the opponent, tier, rolled personality, result (0 = the player won, 1 = a blackout
happened; `wBattleResult` itself stays 0 on a blackout), turns, the enemy's move ids in order, Struggle turns (and those with a
reserve alive), the most slots out of PP, enemy switches, KO candidates and missed
KOs and redundant picks (`run_ai_benchmark.classify_decisions`), `personality_flips`
(decisions where the personality layer changed the set of minimum-score slots), the
longest repeat of one move (`max_streak`) and of one power-0 move (`max_status_streak`),
decision cycles, and TrainerAI move-path cycles. `flags` are findings to read, not
failures (the exit code is unchanged):

| Flag | Meaning |
|---|---|
| `missed_ko` | a DAMAGE-layer reliable KO existed and another slot was selected |
| `status_spam` | the same power-0 move by the same enemy mon 4+ times in a row (a forced pick breaks the run) |
| `struggle_with_reserve` | Struggle selected while a reserve was alive |
| `over_frame_trainer_ai` | a planned commit (`AICommitEnemyTurn`, move path) over 70,224 cycles; unplanned commits (forced turns, FINAL_AI) run the whole decision and are timed by the decision cycles instead |
| `redundant_pick` | the selected slot carried a Redundant-layer penalty (forced picks are not counted) |
| `telemetry_error` | a telemetry hook raised during the battle |

Explosion/Self-Destruct KOs that `AIExplosionTradeVeto` forbade are policy, not misses: they are left out of `missed_ko` and counted as `explosion_vetoes` (the veto runs after the scores are captured; its mask is read at `AIExplosionTradeVeto.masked`). Player switches (2026-10-22): `planned_turns` (battle menus the player answered) and `player_switches` (how many of those the player switched on); groups add `player_switch_rate`.

A selection is `forced` when only one slot has a move, PP left and is not disabled (2026-10-21).
A forced pick breaks a `status_spam` run and is not counted in `redundant_pick`; records carry
`forced_picks`. Reason: seed 117's Withdraw x10 was the player's Disable on the other move, not a bug.

`python3 tools/pyboy_smoke/test_ai_telemetry.py` covers the pure record/summary code.
`--coverage` skips the labels that sit next to telemetry hooks.

### Bug detectors

`autoplay_checks.py` rides along on every run and looks for bugs that do not
stop play:

- Data checks, at the first overworld input poll after a map change or a battle:
  the party (count, species list, species, level, HP, moves: none, invalid,
  gaps, duplicates, PP over max, nicknames), the item pockets, money, the map
  and its warp destinations. At each battle menu: both active mons; once per
  trainer battle, the trainer's whole party. A finding is an `anomaly` event,
  the run goes on, and the first one saves `autoplay_seed<N>_anomaly.state`.
- Crashes end the run `crashed`: a jump to the `rst $38` vector ($FF padding,
  NULL, garbage), code running outside ROM, or SP outside the stack (the VBlank
  copies that borrow SP excepted). The report names the site, the stack and
  their labels. The overworld loop must also poll at one stack depth.
- Garbled screens (`autoplay_screen.py`), as `screen_*` anomalies: a
  `text_far` whose target is not a label in a real bank or does not start with
  a text command; a byte dispatched as a text command that is not a `TX_*`;
  a byte below $60 placed as a glyph (or the `<NULL>` TEXT ID ERROR char); and
  a `TextCommandProcessor`, `PlaceString`, `CopyVideoData*` or `FarCopyData*`
  pointer in ROM that lies inside code in the loaded bank. The
  code rules need `coverage_inventory`'s code labels (a ~70 s walk after a
  rebuild): the bot's entry points build them first, smoke tests use them
  only if cached.
- An illegal opcode makes PyBoy spin inside one `tick()`, out of Python's
  reach, so `run_autoplay.py` runs each seed in its own process and kills it
  at `--timeout` as `hung`, reporting the bot's last heartbeat (every 1000
  steps) instead.

`sram_fuzz.py` hunts reads of save RAM the game never wrote, the one memory
Init does not clear. It plays a seed with SRAM zeroed (twice: the runs must be
deterministic), all $FF and random, and every run must match event for event.
`--bisect` narrows a diverging fill down to the SRAM bytes that change play and
names them from the .sym:

```sh
make sram_fuzz                                  # seeds 1-4, Debug 2
make sram_fuzz SRAM_FUZZ_ARGS='--seeds 1-8 --new-game --runs 2 --bisect'
```

Random fills keep `@` out of `sPlayerName`: one there makes the title menu find
a "save", fail its checksum and report the file destroyed, which is vanilla's
handling and would shift every later frame.

Runs are deterministic for a ROM and seed: the seed is applied just before the
lobby rolls its first doors (at `StartNewGame` with `--new-game`), so rerunning
a seed reproduces its report on the same build.

Each agent step (`autoplay.py`) depends on the mode:

- overworld: `autoplay_world.py` builds the walk grid from `wOverworldMap`, the
  tileset's blockset and passable list, ledges and tile-pair collisions, plus
  arrow tiles (`DecodeArrowMovementRLE` tables) and same-map warp pads as
  teleports. BFS walks to the first reachable goal group: the lobby nurse and a
  random lobby door, the map's unbeaten trainers (from the header table the
  map script passes to `ExecuteCurMapScriptInTable`), leaders, bosses and gift
  givers (talked to once), then the room's forward exit, ranked lobby,
  `LAST_MAP`, `ROGUE_MAP`, unvisited side room. Last resort: talk to everyone.
- battle and dialogue: press only while the game polls `JoypadLowSensitivity`.
  Moves and switches come from a `benchmark_policies` policy (`--battle-policy`,
  default `type_switcher`; a Disabled move is treated as out of PP;
  `early_switcher` also leaves a losing matchup on any turn, as a human does,
  for measuring the AI's switch prediction). Reward and
  gift pickers take a random offer, then NO THANKS if the menu reopens (Debug
  2's party and box are full). With `--menu-input real` (the default) each
  choice is a goal: while that menu waits, the agent presses directions until
  its cursor (`hCurrentMenuItem`; the battle menu's column from
  `wTopMenuItemX`) is on the target, then A, so the menus' own cursor code
  runs. A cursor that cannot reach its target in 24 presses is a `menu`
  anomaly, and a text wait that starts inside a menu's redraw (directions do
  nothing until A/B) is answered and reported as `menu_text_wait`.
  `--menu-input cursor` writes the cursor byte at the menu's hook instead, as
  the AI benchmark does. `--menu-chaos P` adds a stray press (a direction, or
  B to back out of the move menu) at each menu step with chance P; the goal
  is re-read every press, so play still converges.
- busy: walking, scripted movement and fades; wait.

Hidden sprites come from `IsObjectHidden`'s own answer, hooked at
`IsObjectHidden.hidden`, not a reimplementation of its stage-map rules.

A step that sets off a script twice (a "don't go away" tile) is avoided for
the rest of the visit, and after `EXPLORE_AFTER_FRAMES` without progress the
agent talks to everyone before trying exits again (Oak's Lab wants a starter
chosen first).

Items: Potions cannot be used in battle, so between fights the agent opens
START > ITEM and uses the cheapest healing item that covers a mon below half
HP (a Revive on a fainted one), and once per lobby visit it buys healing items
from the recovery clerk (stock is randomized) up to four, or a Revive. Both are
menu errands driven by button presses and abandoned after `PLAN_STEP_LIMIT`.

Limits: the agent never chooses rewards or doors on merit (both random), never
buys key items on merit, and only picks up item balls as a last resort. Without
`--vary` it also never visits the lobby's other NPCs. Its `--new-game` balance
numbers therefore describe this agent as much as the game.

### Options that widen the hunt

All of these work on `autoplay.py` (one seed) and `run_autoplay.py` /
`make autoplay` (a batch), and combine freely. Difficulty defaults to HARD, the
balance baseline; `--difficulty NAME` overrides it.

```sh
make autoplay AUTOPLAY_ARGS='--seeds 1-16 --branches 8 --snapshots 3'
make autoplay AUTOPLAY_ARGS='--seeds 1-16 --runs 3 --vary --coverage --max-frames 2500000 --timeout 2400'
make autoplay AUTOPLAY_ARGS='--seeds 1-8 --save-checks'
make autoplay AUTOPLAY_ARGS='--seeds 1-8 --new-game --rom pokered'
make compare_builds COMPARE_ARGS='--seeds 1-24 --runs 2 --vary'
```

- `--vary`: each seed plays its own `Profile` (`draw_profile`, recorded in the
  report): battle policy, ironman, difficulty (`DIFFICULTY_MIX`, mostly HARD),
  Oak's Lab starter, items used in battle, a random key item kit (owned items
  and tiers, at most 3 equipped, written to SRAM; charge-based items work from
  run 2), Credit Exchange credits, and errands: random presses at a lobby NPC
  or sign (TMs, daycare, tutors, trades, the key swap attendant) or in the bag.
  `autoplay_checks.check_key_items` flags more than 3 equipped, an equipped
  item not owned, or a tier over the cap.
- `--branches N` (`autoplay_branch.py`): the run snapshots its key moments
  (battle start, reward and gift pickers, lobby) and plays N short
  random-input branches from up to `--snapshots` of each kind, with all checks
  and a freeze watch. Each finding prints an `autoplay_branch.py --state ...
  --key ...` command that replays it.
- `--coverage` (`coverage_inventory.py`, `autoplay_coverage.py`): hooks every
  code label until it first runs and writes `artifacts/coverage_summary.json`:
  routines never run, branches never taken, labels only one run reached.
  Known dead code (Poke Balls, X items) is listed as such, not as a gap.
- `--save-checks` (`save_reload.py`): at lobby arrivals, runs to an idle
  overworld frame, saves, reloads on a fresh emulator with only that cartridge
  RAM, compares every saved region byte for byte, then cuts power at each step
  of a save and classifies each reboot as old, new, mixed or refused.
- `--player strong`: takes rewards and gifts on merit instead of at random
  (`autoplay_team.TeamJudge`: base stat total, form-aware, plus type coverage
  the party lacks; a reward trade nets out the mon given; gifts by kind, read
  from the giver's list in ROM), and in trainer battles switches out of a
  losing matchup to a clearly better-matched reserve when a new enemy mon
  comes out (`benchmark_policies.choose_matchup_switch`). `--player merit`
  takes the offers on merit only. Sweep the same seeds with `basic` (the
  default) and `strong` to tell "too hard" from "the bot plays badly".
- `--rom pokeblue|pokered` (needs `--new-game`): plays a release build;
  artifacts get a `_pokeblue` / `_pokered` suffix. `compare_builds.py` plays the
  same seeds on all three builds and flags failures or anomalies only one
  build hits. Runs on different builds always part ways in a battle sooner or
  later (VBlank's `Random` can interrupt a main-code draw at a different
  instruction per build), so a split alone is not a finding.

### Nightly runs

`nightly.py` (`make nightly`) tests one commit, default `master`, with every
long-running check. It runs in its own worktree (`../redrogue_nightly`, reset
to the commit each night) so another session's half-made edit in the shared
tree is never tested. It builds the three ROMs and runs these suites:
- smoke and `make audit`
- a 24-seed Debug 2 sweep with branching
- a 16-seed varied new-game sweep with save checks and the coverage map
- `compare_builds` on 8 seeds
- `sram_fuzz` on 4 seeds

The full set takes about an hour. Each night writes
`../redrogue_nightly_reports/<date>_<sha>/`: logs, each suite's summary, copies
of every failed seed's report, state and screenshot, and `report.md` with a
replay command per finding. Its "Regressions" section compares against the
previous night: a newly failing test, a suite that passed and now fails, a new
kind of finding, a champion-rate drop over 15 points, or a coverage loss of
over 100 routines. A commit that already has a report is skipped unless
`--force`; `--suites` picks suites and `--quick` runs 2 seeds each, to check the
runner. Scheduling is up to you, for example with Windows Task Scheduler (the
command is in the module docstring).
