# Yellow Legacy Import Plan

**Status:** YL-4B item 4 MOVE viewer is implemented in the current worktree atop user commit `6aceacb9`; runtime review and user commit are pending. Stop before the next checkpoint.
**Audit date:** 2026-08-27 (America/Chicago).
**Execution reconciliation:** 2026-09-08 (America/Chicago). Current source and Git were re-audited after the follower system, 5x4 Bill's PC, bridge work, and related imports landed.
**Design clarification:** 2026-08-27. Marker categories, party/PC coverage, all-context overworld coverage, and faster healing are specified; Joy/Jenny is deferred. Source findings remain the original audit snapshot, not a fresh implementation audit.
**Original planning baseline:** `master`, `b4a8819934a7a24bfe55b9f831dd5ccc8a17c279` (`Movedex Extreme Yellow Import`).
**Current execution baseline:** `master`, `dae376d1fd58e1bdf904a93be0c3c475f9d994fe` (`Bridge Improvements Finalized`), matching `origin/master` at YL-0.
**Yellow Legacy donor:** [cRz-Shadows/Pokemon_Yellow_Legacy](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/tree/15169d137e2ef778e8765f7f3381acc4093dc169), `15169d137e2ef778e8765f7f3381acc4093dc169`, fetched from `main`.
**Reference document:** [Yellow Legacy by TSP (5).pdf](<F:/Downloads/Yellow Legacy by TSP (5).pdf>), 65 pages. Relevant feature pages 5-8, Pokedex screenshots on page 24, Joy/Jenny teams on page 54, credits on pages 62-65.
**Existing work to preserve:** the original status-view WIP has since landed. At YL-0 the tracked worktree was clean; preserve user-owned untracked `.claude/settings.json`, `.tmp/bridge-system-verify/`, and `CLAUDE.md`.

### YL-0 checkpoint record (2026-09-08)

- Scope reconciliation: item 3 (DVs / StatEXP comparison) is explicitly skipped. Items 2, 7, 13, and 14 are present/equivalent and remain regression-only; do not re-port them. Item 14 landed in commit `39a2866b` and no longer belongs in YL-1 implementation.
- New-system reconciliation: preserve the production Yellow-derived follower lifecycle in `engine/overworld/follower_yellow_test.asm` and the 5x4 party/box UI in `engine/pokemon/bills_pc.asm`. Species-specific art must adapt their existing consumer-specific loaders rather than replace either system.
- Art policy: initially import only suitable donor species art. Unsupported species, forms, and fusions retain the existing category fallback.
- Authored-map scope for item 9: Copycat's House 2F Doduo only; Mr. Fuji's House; legendary encounters; and bridge rooms containing relevant Pokemon. Other Copycat dolls remain unchanged.
- Follower budget: preserve the existing one-follower/eight-authored-walking-sheet limit and its current suppression behavior.
- Git/checkpoint policy: the user owns commits. Stop after every plan checkpoint for review and user commit before continuing.
- Fresh build: `wsl make -B pokered.gbc pokeblue.gbc pokeblue_debug.gbc` passed for all three variants.
- Routine regression gate: `wsl make smoke` passed 234/234 tests in 51.505 seconds.
- ROM identity (MD5): Red `BD38A3D63E472A6E845093037DCAD359`; Blue `23AFC10B9003C22B0C6AFED331BFA26B`; Blue Debug `2FE48D39FCE9FDF4A8B7885156B6A096`.
- Fresh capacity summary: Red ROM0 113 free, ROMX 106093 free in 52 banks; Blue ROM0 113 free, ROMX 106108 free in 52 banks; Blue Debug ROM0 93 free, ROMX 121071 free in 53 banks. All variants report SRAM 5350 free, WRAM0 232 free, and HRAM 0 free.
- RAM/layout impact: none. YL-0 changed documentation only; no repository source, asset, ROM placement, or RAM declaration changed.
- Runtime boundary: build and automated smoke evidence are complete. No new feature behavior exists to accept at YL-0.
- Next gate: YL-1 is now items 6 and 10 only. Stop here until the user reviews and commits this checkpoint.

### YL-1 checkpoint record (2026-09-09)

- Commit: `11193b5b4038e7c2a7587e0dcd47188c031fc558` (`Saving Speed Boost - Step 1 Yellow Legacy`), committed and pushed by the user on `master`.
- Item 6: removed the post-write `Now saving...` screen and 120-frame artificial wait; retained a 10-frame pre-message pause, the existing success text and save sound, sound completion, and a user-accepted 10-frame final tail.
- Item 10: corrected the player/enemy exclusive slide bounds from `$61/$30` to `$62/$31`; the two immediate replacements are size-neutral.
- Save integrity: `SaveGameData`, confirmations, SRAM selection, checksums, party/box/custom data, and audio completion remain unchanged (~98% confident).
- Placement: bank `$1C` section `bank1C` shrank by 32 bytes, `$3C5A` to `$3C3A`; free space increased from 934 to 966 bytes. Bank `$1E` section `bank1E` and its 69 free bytes are unchanged.
- Fresh build: Red, Blue, and Blue Debug all passed. ROM MD5: Red `FBBCF3E977AB8A43D2AEA155838FDAFF`; Blue `CEA2B83DAE2E27436049461E62A58D4D`; Blue Debug `06CE986BC88C1D8AD93A3392D8535C9B`.
- Routine regression gate: `wsl make smoke` passed 234/234 tests in 50.012 seconds, including the actual save/load persistence smoke.
- RAM/layout impact: no RAM, VRAM, or SRAM declaration changed; no section moved banks.
- Runtime acceptance: see the [End-of-plan runtime acceptance queue](#end-of-plan-runtime-acceptance-queue), YL-1 group. The user intends to run this queue after the implementation checkpoints.
- Stop gate: YL-1 was accepted for implementation sequencing; its runtime items remain queued at the end of the plan.

### YL-2 checkpoint record (2026-09-09)

- Commit: user commit `8b3e5f6ab19b674c89ccf61c29b0255c853c853c` (`Yellow Legacy Imports Part 2`), committed and pushed on `master`.
- Baseline: implemented atop user commit `11193b5b4038e7c2a7587e0dcd47188c031fc558`; no commit was created by Codex.
- Item 19: battle EXP now checks every crossed level in ascending order rather than only the final level. Each check uses the pre-evolution species because evolution occurs after the complete EXP award, matching the user's selected actual-timeline rule.
- Fusion contract: each crossed level checks the primary species first and the secondary species second, preserving duplicate filtering and the existing no-evolution fusion rule.
- Evolution contract: level-based battle and mid-battle evolution skip the old evolved-species same-current-level move grant because the pre-evolution timeline already offered all crossed levels. Stone, trade, and Rare Candy evolution remain out of battle and retain their established post-evolution move behavior.
- State contract: the first crossed level, final level, and prior `wCurEnemyLevel` are stack-local. The existing saved `wExpAmountGained` and string-buffer behavior remain intact. No WRAM, HRAM, SRAM, union, or save-layout declaration changed.
- Placement: bank `$15` section `Battle Engine 9` grew from `$0334` at `$5294-$55C7` to `$0349` at `$5294-$55DC`, adding 21 bytes; minimum free space is `$0FFB` / 4,091 bytes. Bank `$31` section `Evos Moves` grew from `$1E49` at `$4000-$5E48` to `$1E56` at `$4000-$5E55`, adding 13 bytes; minimum free space is `$21AA` / 8,618 bytes. Values match Red, Blue, and Blue Debug.
- Fresh build: `wsl make -B pokered.gbc pokeblue.gbc pokeblue_debug.gbc` passed. ROM MD5: Red `0092188C41E264F2145EBBC23753B962`; Blue `ECAC35650C94A4C0CA70097C888DE33E`; Blue Debug `ED0CFF2119223FDB55246B6F59CE51E1`.
- Automated verification: `wsl make smoke` passed 234/234 tests in 49.642 seconds. The focused EXP test covers no-level, one-level, and 18-to-21 awards, verifies checks at 19/20/21, confirms the level-20 move is learned, and asserts stack-pointer equality. A source-contract test verifies that nonzero `hIsInBattle` skips the post-evolution learn call while zero falls through.
- Runtime acceptance: see the [End-of-plan runtime acceptance queue](#end-of-plan-runtime-acceptance-queue), YL-2 group. The user intends to run this queue after the implementation checkpoints.
- Stop gate: YL-2 is committed and pushed; its runtime matrix remains queued. Await user review and commit of YL-3A before beginning YL-3B.

### YL-3A checkpoint record (2026-09-09)

- Baseline: implemented atop user commit `8b3e5f6ab19b674c89ccf61c29b0255c853c853c` (`Yellow Legacy Imports Part 2`); no commit was created by Codex.
- Item 16: after a successful capture is transferred to the active box and the existing transfer text finishes, `ItemUseBall` farcalls a capture-only helper. The helper checks the resulting active `wBoxCount` against `MONS_PER_BOX` (`20`) and prints only on the final-slot transition.
- Text: the donor-faithful reminder is `The #MON BOX / is now full. / It won't hold / more #MON. / paragraph Change the BOX at / a #MON CENTER! / prompt`, with every rendered line at most 17 characters and no `@` before `prompt`.
- Scope and state contract: the helper is not called by `SendNewMonToBox` or any other caller. No RAM, HRAM, SRAM, union, save-layout, or persistent warned flag was added. Existing active-box selection and capture-to-party/full-box rejection remain unchanged.
- Placement: bank `$03` section `bank3` grows from `$3D7F` to `$3D87`, adding 8 bytes; free space falls from `$001E` to `$0016`. `Text 10` grows from `$2CCB` to `$2D1E`, adding `$0053` / 83 bytes; free space falls from `$1335` to `$12E2`. The `rogue` section grows from `$378F` to `$37A1`, adding 18 bytes with `$012C` to `$011A` free in Red and Blue. Blue Debug `rogue` grows from `$38CD` to `$38DF`, adding 18 bytes with `$0733` to `$0721` free.
- No section moved banks and no RAM/SRAM layout changed.
- Fresh verification: forced Red, Blue, and Blue Debug builds passed. `wsl make smoke` passed 239/239 tests in 50.527 seconds, including the count-19 no-print and count-20 single-print helper harness probe. The focused source-contract tests passed 3/3.
- ROM MD5: Red `B395294AFD086CC525B08CEFFEE6B593`; Blue `6B536A000AC2E80D57ABB6D9B6D5EDC6`; Blue Debug `5A15543A8DE6E7E10360A0FF43E5B77B`.
- Runtime acceptance: see the [End-of-plan runtime acceptance queue](#end-of-plan-runtime-acceptance-queue), YL-3A group. The user intends to run this queue at the end of the plan.
- Stop gate: await user runtime review and commit. Do not begin YL-3B.

### YL-3B checkpoint record (2026-09-09)

- Baseline: implemented in the current worktree after YL-3A; no commit was created by Codex. Concurrent Species Groups Phase 2R changes remain user-owned and were preserved.
- Item 5: `DisplayPokemonCenterDialogue_` now saves the screen, records first/repeat visit state, prints a short first or repeat message, and proceeds directly to healing. The YES/NO choice, decline path, post-heal dialogue, and extra nurse pauses are removed.
- Healing machine: `AnimateHealingMachine` copies one OAM entry per party member, then plays one `SFX_HEALING_MACHINE` and retains one 30-frame delay. Follower hiding/freezing, palette restoration, audio-bank/music restoration, and the final follower refresh remain in place.
- Text: first visit is `Welcome! I'll` / `heal your #MON.`; repeat visit is `Let's heal your` / `#MON!`; every rendered line is at most 17 characters and prompts have no preceding `@`.
- Placement: fresh maps show `Home` ending at `$3F92` (`$006D` / 109 bytes free) in Red and Blue, and at `$3FA3` (`$005D` / 93 bytes free) in Blue Debug. `bank1C` ends at `$7C39` (`$03C6` / 966 bytes free) and `Text 4` ends at `$778D` (`$0872` / 2,162 bytes free) in all three variants. No YL-3B section moved banks.
- RAM/layout impact: YL-3B adds no RAM, HRAM, SRAM, union, or save-layout changes. Concurrent Species Groups Phase 2R layout work is excluded from this checkpoint.
- Fresh verification: forced Red, Blue, and Blue Debug builds passed. `wsl make smoke` passed 243/243 tests in 52.038 seconds. The focused YL-3B source/runtime tests passed 4/4, including one- and six-party `HealParty` state restoration.
- Artifact scope: the ROM hashes below identify the current combined worktree artifacts, including concurrent Species Groups Phase 2R work; they are not pure YL-3B-only artifacts.
- ROM MD5: Red `F82088291864E7050CBA46203AA48B99`; Blue `1D3C6CF231A41A7DCBA68EB6F79AC7F7`; Blue Debug `EAC66687A0D2E3864FE1E943306D43AB`.
- Runtime acceptance: see the [End-of-plan runtime acceptance queue](#end-of-plan-runtime-acceptance-queue), YL-3B group. The user intends to run this queue at the end of the plan.
- Stop gate: await user runtime review and commit. Do not begin YL-3C.

### YL-3C item 11 checkpoint record (2026-09-09)

- Baseline: the user committed YL-3B together with the first Regional Forms increment as `18963f7a` (`yellow legacy 3b and increment 1 of regional forms`). Ongoing Regional Forms source and assets remain user-owned concurrent work and are not attributed to this checkpoint.
- `engine/menus/start_sub_menus.asm` now follows the pinned donor fix by waiting three frames on the DMG path after the Trainer Card palette command and again after map reload, before each palette reveal. Red Rogue's `wOnSGB` is also raised on CGB, so the new waits execute only on DMG and do not add CGB delay.
- The existing full transaction is preserved: white-out, screen clear, sprite update, `hTileAnimations` save/disable, appearance-aware `DrawTrainerInfo`, badges, palette setup, input wait, font and menu-buffer restoration, map reload, palette restoration, tile-animation restoration, and Start-menu redisplay. No broad palette or fade refactor was made.
- Focused source-contract tests pass 2/2. Fresh forced Red, Blue, and Blue Debug builds pass. The full smoke run passes 244/245; both new Trainer Card tests pass, while the unrelated `test_fight2_injects_exact_ai_scenario_and_honors_menu_move` test repeatedly fails because the current concurrent-work artifact produces no AI score records. YL-3C item 11 does not touch battle or debug injection code, so this failure is unrelated to the Trainer Card patch (~99% confident), but the suite is not recorded as fully passing.
- Bank `$04` section `Battle Engine 1` grows by exactly `$000E` / 14 bytes, from `$1296` / 4,758 bytes to `$12A4` / 4,772 bytes at `$6458-$76FB`. Bank `$04` free space falls from `$001A` / 26 bytes to `$000C` / 12 bytes in Red, Blue, and Blue Debug. No section moves bank and no RAM, HRAM, SRAM, union, or save-layout declaration changes.
- Artifact scope: the hashes identify combined-worktree artifacts containing ongoing Regional Forms work; they are not pure YL-3C item 11 artifacts. ROM MD5: Red `844A297E520F04C3D72403962E2A8E6D`; Blue `24A69EE7E2EA5DCC8CFE666C71A69A5A`; Blue Debug `2DFC81FF5B8D065F05440522F7495C23`.
- Runtime acceptance: see the YL-3C item 11 group at the absolute bottom of the end-of-plan runtime queue.
- Stop gate: await user review and commit. Do not begin YL-3C item 17 font cleanup.

### YL-3C item 17 checkpoint record (2026-09-09)

- Baseline: the user committed item 11 together with the current Regional Forms increment as `697e53db` (`Exemplary Meowth Regional Form test and Yellow Legacy Import 3C`). Ongoing Regional Forms source and assets remain user-owned concurrent work and are not attributed to item 17.
- `gfx/font/font_battle_extra.png` now owns the existing bold-P glyph at composite tile `$72`. `constants/charmap.asm` removes the unused Japanese opening-quote alias and maps `<BOLD_P>` in the battle-extra block. `engine/pokemon/status_screen.asm` no longer copies a separate `PTile`, and the redundant tracked `gfx/font/P.png` asset is removed.
- The established runtime alias is preserved: status PP uses `<BOLD_P> = $72`, while battles overwrite `$72` with `<EXP_BAR_FULL>` and `$70` with `<EXP_BAR_PARTIAL>`. All five `CalcAndLoadExpBarDynamicTile` battle reload sites remain. The optional donor battle PP display is explicitly omitted.
- Focused source/asset contracts pass 3/3, including exact compiled tile bytes `00 00 FC FC C6 C6 C6 C6 C6 C6 FC FC C0 C0 C0 C0`. Fresh forced Red, Blue, and Blue Debug builds pass. Ordinary smoke passes 247/248; the only failure is the already-known debug AI-injection smoke test in the concurrent-work artifact. Per user direction, no `make ai_scenarios` run or separate AI investigation was performed.
- `Font Graphics` remains `$1558` / 5,464 bytes at `$4F00-$6457`, size-neutral. `Battle Engine 1` shrinks exactly `$0014` / 20 bytes, from `$12A4` / 4,772 bytes to `$1290` / 4,752 bytes at `$6458-$76E7`. Because concurrent Regional Forms work added 13 bytes elsewhere in bank `$04`, combined-worktree bank free space rises only from `$000C` / 12 bytes to `$0013` / 19 bytes. No section moves bank and no RAM, HRAM, SRAM, union, save-layout, or VRAM-layout declaration changes.
- Artifact scope: the hashes identify combined-worktree artifacts containing ongoing Regional Forms work; they are not pure YL-3C item 17 artifacts. ROM MD5: Red `CC34AD3E01C2D685D8FEA4EE8A6A3E2D`; Blue `AABF50531C1BDCF422C58CD8B92146FB`; Blue Debug `67DE8505433349EE20EA62708E26A368`.
- Runtime acceptance: see the item 17 group at the absolute bottom of the end-of-plan runtime queue.
- Stop gate: await user review and commit. Do not begin YL-4A.

### YL-4A item 1 checkpoint record (2026-09-09)

- Baseline: the user committed YL-3C item 17 as `9dd05c3b` (`Fixes to exemplary Test and Yellow Legacy 3c Import`). The worktree was otherwise clean except user-owned untracked `.claude/` and `CLAUDE.md`, which remain untouched.
- Marker state: one trailing HUD cell per side now reads the active mon's per-instance `MON_CATCH_RATE` flags directly from `wBattleMon` or `wEnemyMon`. A type variant overrides Ghost, which overrides shiny, matching the user's one-visible-marker rule. Water, Rock, Dragon, Ghost, and shiny receive distinct placeholder glyphs; an unknown future type variant receives a generic `V` fallback.
- Placement: the enemy marker is at tilemap `(9,1)` and the player marker at `(13,8)`, inside the existing HUD clears and CGB palette rectangles without touching names, status/level text, HP bars, borders, or the EXP row. One shared farcall at the end of `PlaceHUDTiles` redraws the marker for both sides. Font tiles `$D0-$D5` were previously blank and are loaded by the existing complete font copy; `$70`, `$72`, and `$76` battle aliases remain untouched.
- Evolution correction: all evolution routes converge on the common `EvolutionAfterBattle` lifecycle. When `BIT_TYPE_VARIANT` is set, it now saves the instance's `MON_TYPE2`, performs the ordinary evolved-species type reset, and restores that variant type. Ordinary evolutions still receive both evolved base types. Capture was not changed because Red Rogue does not use normal capture as a supported acquisition path.
- Scope boundary: the existing entrance sparkle and any future Ghost entrance effect remain out of scope. Marker glyphs are editable placeholders, not final artwork.
- Placement: bank `$05` `Battle Engine 2` grows by exactly 8 bytes to `$07F0` at `$6340-$6B2F`; bank free space falls from `$000D` / 13 to `$0005` / 5 bytes in all targets. Bank `$31` `Evos Moves` grows by `$0022` / 34 bytes, from `$1E56` to `$1E78` at `$4000-$5E77`; free space falls from `$21AA` / 8,618 to `$2188` / 8,584 bytes. The floating `rogue` section grows by `$004B` / 75 bytes to `$37EC` in Red/Blue and `$392A` in Debug, leaving `$00CF` / 207 bytes in bank `$2F` for Red/Blue and `$06D6` / 1,750 bytes in bank `$35` for Debug. Tight bank `$17` remains unchanged with `Hidden Events 3` `$0462`, `Pics 11` `$1B67`, and 2 bytes free.
- Bank/RAM review: the bank `$05` caller uses the established farcall and its `e` side discriminator survives `Bankswitch`; the helper reads only WRAM battle structs and returns no value. No section moved banks and no WRAM, HRAM, SRAM, union, save-layout, or VRAM-layout declaration changed.
- Verification: the focused marker/evolution contracts pass 3/3. Fresh forced Red, Blue, and Blue Debug builds pass. Ordinary smoke passes 250/251; the sole failure is the already-known `test_fight2_injects_exact_ai_scenario_and_honors_menu_move` debug AI-injection test. YL-4A does not touch AI or debug injection code, so that failure is unrelated (~99% confident). Per user direction, `make ai_scenarios` was not run and the failure was not investigated.
- Artifact identity: ROM MD5 Red `AC813FA79BB2DD66CDE8E85AF2A30CF7`; Blue `B1C2FE080C54DF27B049866336AD4DC9`; Blue Debug `95DD5CD74A9AC49EE4235105C8647205`.
- Runtime acceptance: see the YL-4A group at the absolute bottom of the end-of-plan runtime queue.
- Stop gate: await user review and commit. Do not begin YL-4B.

### YL-4B item 4 checkpoint record (2026-09-09)

- Baseline: the user committed YL-4A as `6aceacb9`. Concurrent Pokemon/reward work remains user-owned and is excluded from this checkpoint.
- Scope: the Pokedex side menu replaces `AREA` with `MOVE`. Encounter-location aggregation and the original plan's step 4 are explicitly skipped by user direction. MOVE presents base-species LEVEL UP, TM/HM, and TUTOR information; CURRENT remains a loaded-mon status-screen feature.
- Donor correspondence: the donor MOVE selection maps to `.choseMove`; its move-list preparation maps to Red Rogue's existing level-up, TM/HM, and tutor walkers; its grouped navigation maps to a dedicated three-view START cycle plus the existing cursor-scrolling helper; and its cleanup maps to the Pokedex's existing `b = 0` graphics/list rebuild path. Intentional deviations are no AREA/encounter display, no CURRENT page, Red Rogue's existing move-info strip, and species-only rather than loaded-mon/fusion context.
- State and lifecycle: `.choseMove` passes the already-converted internal species ID in `e` through a farcall to bank `$2C`. The viewer saves and disables tile animation, loads the existing status-view graphics, and restores the former tile-animation state on exit. It temporarily clears and restores `wLoadedMon + MON_CATCH_RATE` plus the four existing transient form-context bytes, preventing stale fusion metadata from adding a secondary species and stale regional-form context from replacing the base-species header (~97% confident). No new RAM or duplicated learnset reader was added.
- Runtime correction: user testing exposed Pokédex artwork tile `$6E` beside each level where the Learndex expected `<LV>`. The viewer now reloads the established HP/status glyph set before drawing (~98% confident), and TUTOR was added to the START cycle by user direction.
- Placement: bank `$10` `Pokedex` grows exactly `$0009` / 9 bytes, from `$3067` to `$3070`, leaving `$01A3` / 419 bytes in all three variants. Bank `$2C` `Status View Navigation` grows exactly `$00BF` / 191 bytes, from `$079C` to `$085B`; current free space is `$03BB` / 955 bytes in Red and `$03CB` / 971 bytes in Blue and Blue Debug. No section moved banks.
- Verification: focused source-contract tests pass 2/2. Fresh forced Red, Blue, and Blue Debug builds pass. Ordinary smoke progressed through the new YL-4B tests, then was interrupted after stalling at the already-known `test_fight2_injects_exact_ai_scenario_and_honors_menu_move` debug AI-injection test. The suite is not recorded as complete, and per user direction no `make ai_scenarios` run or AI investigation was performed.
- Artifact scope: the hashes identify combined-worktree artifacts containing concurrent Pokemon/reward work; they are not pure YL-4B artifacts. ROM MD5: Red `85BB9508B1D83397DA227C1380AE8E5E`; Blue `5B5D90EAD3902965D3A3C31A4F7A07B7`; Blue Debug `751640E99C82790CD99F2AE198323551`.
- RAM/layout impact: YL-4B adds no WRAM, HRAM, SRAM, union, save-layout, or VRAM-layout declaration. Concurrent user-owned `ram/wram.asm` changes are not part of this checkpoint.
- Runtime acceptance: see the YL-4B group at the absolute bottom of the end-of-plan runtime queue.
- Stop gate: await user review and commit before beginning the next Yellow Legacy checkpoint.

## 1. Scope and authority

This plan reconciles all 19 requested items with the current source. Items 8 and 12 are one implementation project, but both remain in the coverage table. Optional ideas from the PDF are a separate backlog, not additions to the approved scope.

The PDF is feature/reference material, not instructions. Current Red Rogue source and Git establish local implementation status; the pinned donor establishes what is available to copy. Neither a donor feature list nor an older tracker proves that a Red Rogue feature is missing.

No source, graphics, RAM declarations, ROM placement, Git branch, commit, or ROM was changed for this audit. No builds or emulator tests were run. "Present" below means source evidence, not newly verified runtime acceptance. Confidence percentages describe the static technical finding, not the chance of passing an emulator test.

Three bounded Luna Max agents audited (a) UI/icons/Pokedex, (b) battle and learning correctness, and (c) speed/storage/tile animation. The main agent reviewed the PDF, exact linked patches, trainer battles, font cleanup, and integration plan.

### Working rules for execution

- Obtain approval for a named phase before editing. Stop at its checkpoint; do not automatically continue into the next phase.
- Re-read the repository's current `AGENTS.md`, [ROM Bible](<K:/Other computers/My Laptop/Red Rogue Files/ROM_BIBLE.md>), and, before any RAM declaration change, [WRAM Bible](<K:/Other computers/My Laptop/Red Rogue Files/WRAM_BIBLE.md>).
- Inspect the nearest existing Red Rogue analogue first. Copy proven donor logic selectively, reconciling Red Rogue data formats, SRAM access, custom forms, AI, text, and graphics.
- Never cherry-pick the linked commits wholesale. The caught-icon commit also changes enemy stat-down accuracy; the spinner commit changes unrelated maps, palettes, objects, and dialogue.
- Keep implementation branches, commits, pushes, WIP cleanup, save wipes, and broad memory reclamation outside scope unless separately requested.
- Rebuild Red, Blue, and Blue Debug together after each approved code phase. Prefer `wsl make -B pokered.gbc pokeblue.gbc pokeblue_debug.gbc` for a fresh checkpoint, rather than relying on old artifacts.
- One main agent owns shared integration files, RAM declarations, `main.asm`, `home.asm`, `layout.link`, and the final build. Never run concurrent builds in the shared checkout.
- Before ROM moves, audit plain calls, direct data reads, local pointers, `BANK()`, fallthrough, and switches performed inside routines. Interrupt-time animation needs a separate timing review.
- After successful placement changes, record old/new bank, section-size delta, and minimum free space across fresh three-variant maps in the ROM Bible. Do not reuse this draft's historical capacity notes as a budget.
- For RAM changes, document lifecycle, save/new-game initialization, banking, and actual rather than potential union savings. No capacity reservation or memory relocation is approved here.
- User performs runtime choreography/visual acceptance by default. Supply a focused checklist. Automated checks complement, not replace, BGB/DMG/CGB acceptance.

## 2. Coverage and recommended disposition

All statuses below are static-source findings; detailed evidence and confidence follow.

| # | Requested item | Red Rogue status | Disposition |
|---|---|---|---|
| 1 | Caught icon repurposed for variants | Missing variant marker | Ghost/Water/Rock + shiny confirmed; layout remains to review |
| 2 | Forget HMs | Present | Regression only |
| 3 | DVs / StatEXP comparison | Present with different presentation | Skipped by user on 2026-09-08 |
| 4 | Pokedex learnsets / encounters | Partial, overlapping user Learndex WIP | Coordinate WIP, then shared browsing/encounter design |
| 5 | Faster Nurse Joy | Implemented in YL-3B; awaiting runtime review/commit | No YES/NO; brief first/repeat text; one healing-machine pass |
| 6 | Faster saves | Implemented in `11193b5b` | Runtime presentation acceptance pending |
| 7 | Faster spinners | Comparable Shin implementation present | Compare and regression-test, do not re-port |
| 8 | Unique party icons | Partial categories/specific icons | Combine with 12; party and PC both required |
| 9 | Unique overworld Pokemon sprites | Partial | All situations, including bridge rooms/followers/procedural |
| 10 | Backsprite lower-right tile loss | Implemented in `11193b5b` | Runtime visual acceptance pending |
| 11 | Trainer Card DMG garbage | Donor transition sequencing absent | Reproduce, adapt entry and exit ordering |
| 12 | All unique party icons tutorial | Same project as 8 | One icon project with PC compatibility gate |
| 13 | Haze/freeze permanent attack lock | Specific recharge fix present | Regression only |
| 14 | Transform assumed Ditto | Fixed in commit `39a2866b` | Regression only; preserve custom flags/DVs |
| 15 | Joy/Jenny battles | Not present | Deferred: miniboss/future-system role undecided |
| 16 | Box-full reminder after catch | Implemented in YL-3A; awaiting runtime review/commit | Successful final-slot capture notification |
| 17 | Japanese quote / bold P consolidation | Not consolidated | Small font cleanup with EXP-tile safeguards |
| 18 | Move tile animation out of HOME | Still in HOME | Separate optional capacity/timing phase |
| 19 | Multi-level move-learning fix | Implemented in YL-2; awaiting runtime review/commit | Crossed-level and evolution contracts implemented; full runtime matrix pending |

**First implementation checkpoint:** YL-1 now contains items **6 and 10** only. Item 14 is already present and receives regression coverage rather than a duplicate port.

## 3. Detailed import notes

### 1. Already-caught icon, repurposed as a variant indicator

**Finding:** Red Rogue lacks this donor HUD marker (~98% confident). The [KEP patch](https://github.com/MementoMartha/kep-hack/commit/00efe3c6b461773a20b424fbf548cb38c880c9ac) checks ownership and draws tile `$D0` at `(1,1)`. Current `engine/battle/core.asm:2388+` and `engine/battle/draw_hud_pokeball_gfx.asm:134-164` are the integration anchors.

**Confirmed scope (2026-08-27):** Convert the caught-icon concept into markers for the Ghost, Water, and Rock variant flags/state, plus shiny Pokemon. These describe the individual Pokemon, not normal elemental typing or Pokedex ownership. Resolve existing variant/shiny fields; do not infer flags from a species type or the unidentified Tower ghost encounter. Fusion and other special forms are not extra marker categories unless separately requested.

**Remaining presentation choice:** Exact glyphs, HUD positions, and overlap treatment will be reviewed before this phase. Recommended layout: a type-variant marker plus an independent shiny sparkle so a shiny variant can show both. This is a proposal, not a user-selected priority rule. Audit both player and enemy HUD contexts rather than retaining the old enemy-only assumption; ask about placement after presenting the layout. Use existing shiny/variant state, without silently adding new encounter-generation rules.

**Implementation:** Keep the HUD hook small and put substantial classification in an appropriate ROMX helper. Preserve caller registers and redraw/clear the marker with the HUD so it cannot survive a switch or next battle. Allocate/load a glyph compatible with the current font and EXP bar; raw donor `$D0` would display the current font's unrelated tile unless deliberately replaced (~99% confident). Do not replace the full font or import the patch's unrelated AI behavior.

**Acceptance:** Normal versus variant, wild versus trainer/special encounters, overlapping flags, Transform, switching/fainting/capture, repeated HUD redraws, status return, EXP gain, DMG/CGB. Verify no stale marker, identity leak for unidentified ghosts, or tile collision.


### 2. HMs can be forgotten

**Finding:** Already allowed in the ordinary move-forgetting path (~98% confident). Current `engine/pokemon/learn_move.asm:170-179` returns the selected move without an HM rejection. Yellow Legacy achieves the same result by disabling its rejection branch.

**Recommendation:** No feature port. Check all five HM moves through ordinary replacement and the existing deleter/relearner interfaces. Preserve Red Rogue's permanent TM/HM ownership and existing access to field abilities; do not import Yellow Legacy's item-PC restriction as an unrelated bag rewrite. A leftover unused `HMCantDeleteText` does not mean the restriction is active.


### 3. Party stats: DVs and StatEXP compared

**Finding:** Red Rogue already exposes both, with a different UI (~99% confident). This is a comparison/acceptance item, not a missing-feature port.

| Aspect | Yellow Legacy | Current Red Rogue |
|---|---|---|
| Access | Hold SELECT/START while entering STATS | START cycles existing normal/DV/StatEXP views |
| DVs | Numeric values, including derived HP DV | Numeric DVs and derived HP DV in `StatusViewDVs` |
| StatEXP | Raw numeric counters | Current cycling view draws five raw-experience bars; an underlying alternate renderer also computes the contribution on a /63 scale |
| Existing integration | Yellow party/status layout | Red Rogue loaded-mon, active-battle stats, fusion, and current page ownership |

**Anchors:** Donor `engine/pokemon/status_screen.asm:126-167,304-373,566-619`. Current `engine/pokemon/status_view.asm:1-232`, especially `StatusViewDVs` and `StatusViewStatExp`; `engine/pokemon/status_screen.asm:295-501` contains the alternate renderer. The current raw bars use a 32-pixel scale and treat `$ffff` as full. These are different presentations of the same training data, not missing data fields (~99% confident).

**Recommendation:** Keep the current navigation/artwork. If exact raw 0-65535 numbers are wanted, propose a small optional numeric presentation after the user's current WIP is checkpointed. Do not replace the status screen or add hidden held-button behavior just to match the donor.

**Acceptance:** Normal/DV/StatEXP cycling, HP DV formula, zero/max training, HP/status restoration when leaving an alternate view, party/box/daycare, active battle and fusion. Explain raw experience versus computed stat contribution so the UI does not imply the /63 value is a raw counter.


### 4. Pokedex learnsets and encounters

**Finding:** Yellow Legacy has a concrete reusable Pokedex implementation, while Red Rogue currently has a separate partial status-page Learndex (~99% confident). Do not confuse the donor's Pokedex with its ordinary status screen.

**Donor implementation:** [engine/menus/pokedex.asm](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/menus/pokedex.asm) repurposes PRINT as MOVE, sets `wMoveListCounter`, and uses `Pokedex_PrintMovesText` at line 672. It renders level/move rows followed by TM/HM rows, five entries per display group. Helpers are `PrepareLevelUpMoveList` in `engine/pokemon/evos_moves.asm:834+` and `GetTMMoves` in `engine/items/tms.asm:42+`. The PDF page 24 shows both screens.

For locations, `engine/items/town_map.asm:381` calls `FindWildLocationsOfMon` in `engine/items/item_effects.asm:3150+`. That scans land/water tables, calls `CheckMapForFishingMon` from `data/wild/super_rod.asm`, then `AddStaticEncounters` for gifts/static Pokemon/fossils. The static entries are hardcoded Kanto locations and must not be imported as Red Rogue encounter data (~99% confident).

**Current state:** `constants/menu_constants.asm:101-121` defines current/level-up/TM-HM/tutor views. The uncommitted additions in `engine/pokemon/status_view.asm` implement a level-up view with initial moves and scrolling; `.DrawTMHM` and `.DrawTutor` remain stubs. This is not proof of a completed Pokedex-wide feature. The existing Pokedex retains its own data/cry/area/quit path and imported base-stat presentation.

**Important reconciliation:** WIP comments near `status_view.asm:423-430` say a fusion only learns primary-species moves. Current `engine/battle/experience.asm:340-367` explicitly learns the secondary's moves too. The comment and display policy need review against actual behavior (~99% confident). No WIP was edited for this plan.

**Recommended sequence:**

1. Confirm the current Learndex owner's intended scope and checkpoint it. Do not absorb or rewrite that WIP under this import.
2. Use donor browsing behavior as reference, but share Red Rogue's existing move/compatibility readers rather than maintain a second data interpretation. Decide whether a Pokedex MOVE entry should reuse the status-page renderer or a neutral shared renderer.
3. Add/read TM/HM compatibility independently of whether the TM is owned. Respect Red Rogue's `sTMBitfield` ownership and fusion-aware `CanLearnTM` separately. Keep tutor display in its existing plan unless explicitly added here.
4. Skipped by user direction: do not add encounter-source aggregation or retain the AREA/town-map view as part of this port.

**Acceptance:** Species not in party, seen/caught gating, zero/long lists, initial moves, repeated same-level entries, scroll ends, move names, TM/HM compatibility, fusion primary/secondary policy, zero/current-run encounter sources, gifts/fishing/static entries, return to normal Pokedex/status and battle. Audit `wMoveBuffer`, `GetMonHeader`, copy bounds, species scratch, and bank restoration. Reuse data only after checking format and lifetime; no donor RAM fields are pre-approved.


### 5. Faster Nurse Joy: what is actually faster?

**Finding:** Yellow Legacy's repeat-visit speedup primarily shortens dialogue and skips the repeat YES/NO menu using `EVENT_FIRST_POKECENTER`. Its healing-machine delays are not faster than Red Rogue's (~99% confident from both sources).

**Compare:** Red Rogue `engine/events/pokecenter.asm` still prints welcome/need-your-Pokemon/fighting-fit/farewell text, asks YES/NO each time, and uses a 20-frame bow. The initial "shall we heal" paragraph is already skipped after the first visit through `BIT_USED_POKECENTER`. The donor uses its event to skip more of the text and confirmation, but also carries Pikachu-specific sprite handling, walking, and extra waits. [Donor center routine](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/events/pokecenter.asm).

Both `engine/overworld/healing_machine.asm` versions wait **30 frames per party member**, flash **8 times at 10 frames**, wait for the healing music, and then wait **32 frames**. Thus a six-member party has 180 frames of ball-placement waits alone, about three seconds at normal frame cadence. Flash time overlaps the music wait, so do not add the complete jingle duration and flash duration as independent costs. These are source-based estimates, not stopwatch measurements.

**Confirmed healing flow (2026-08-27):** Remove YES/NO confirmation. Nurse Joy gives a short statement that she will heal the party, then proceeds directly to healing; subsequent dialogue should be even shorter. Skip the sequential phase of laying out the party Poke Balls, rather than merely shortening its per-ball delay. Keep the brief healing sequence/jingle as the initial implementation target. Do not import Yellow's Pikachu choreography. Reuse existing visit state only if its lifecycle fits any repeat-visit text shortcut; no new persistent event is assumed necessary.

**Implementation boundary:** Bypass sequential ball placement without bypassing required machine/OAM setup, audio-bank save/restore, palette restoration, or HP/status/PP healing. Whether balls appear all at once during the brief healing effect is a presentation detail for that phase; sequential placement is explicitly excluded. Remove redundant pauses/bow time as appropriate, measure cadence, and preserve special-form hooks, blackout destination, follower state, and CGB handling. Removing the entire healing jingle is not an agreed requirement.

**Acceptance:** First/repeat visits heal without a YES/NO prompt; no sequential ball-placement stage; 1/6-member parties, full-HP and fainted/statused parties, depleted and PP-Up-adjusted moves, save/reload, and DMG/CGB lobby speed options. Verify all health state and final audio/palette/OAM restoration. Do not speed up audio by canceling a pending audio-bank transition. Runtime cadence remains subject to user acceptance.


### 6. Faster saves

**Finding:** The requested artificial delay remains in Red Rogue (~99% confident). In `engine/menus/save.asm:189-205`, `SaveGameData` returns before a "Now saving..." display, **120-frame wait**, saved message/sound, and **30-frame final wait**. This is presentation latency after the write, not evidence of slow SRAM writing.

[The tutorial](https://github.com/pret/pokered/wiki/Remove-Artificial-Save-Delay) removes the artificial saving delay. [Yellow Legacy save routine](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/menus/save.asm) omits the long wait and retains short 10-frame waits around its success sound.

**Recommended phase:** Remove the 120-frame presentation wait, retain truthful success reporting and wait for the save sound, and decide whether to shorten the 30-frame tail to 10. That removes approximately 2.0 seconds, or 2.33 seconds if the tail is also reduced by 20 frames, at normal frame cadence. This is an estimate of removed waits, not an end-to-end benchmark.

Do not copy the donor's save implementation or touch SRAM banking, checksums, party/box data, TM bitfield, custom save state, gamma event persistence, save verification, or overwrite confirmation. Do not advertise improved data integrity or write speed from this change.

**Acceptance:** New save, overwrite, declined save, reload/reset, box switch, representative custom run state and CGB options; confirm matching saved contents and the success sound. Measure input-to-control-return frames separately from the actual write routine. No new RAM is needed by the proposed change.


### 7. Faster spinning tiles

**Finding:** Already has a comparable Shin-based speedup (~98% confident), so this is comparison/regression work rather than a fresh import. Current `engine/overworld/spinners.asm` contains `wSpinnerTileFrameCount` gating and `CopySpinnerTiles`; the overworld caller uses `CheckForSpinAndDelay`. The fast copy masks interrupts while temporarily repurposing SP and restores SP before enabling interrupts.

[The exact KEP commit](https://github.com/MementoMartha/kep-hack/commit/7c5c2a3047dd74b9ed014053172e0222b49d486b) includes spinner animation fixes and many unrelated changes. Compare only the spinner table/graphics/copy/cadence contracts. The current Yellow Legacy spinner implementation is not automatically an upgrade over Red Rogue.

**Review detail:** Current executable limiter logic selects a count of 2 by default and 4 with `BIT_60_FPS`; its opening comment describes a different cadence. Treat the code plus measured ticks as authoritative and flag the comment mismatch for review, not as proof of a runtime defect (~95% confident on that source discrepancy).

**Acceptance:** Gym and Facility arrow graphics, all directions/stop tiles, facing order, long spinner paths, DMG and CGB speed configurations, exact final position, interrupt/SP restoration, and VRAM safety. Measure elapsed frames before proposing any further speed change. Do not reuse donor HRAM addresses or copy the entire multi-file patch.


### 8 and 12. All unique party menu icons

**Finding:** Partially supported, but not all-species unique (~99% confident). Current mappings are category-based with dedicated Pikachu/Chansey support; Yellow Legacy supplies per-species icons. These two requested items are a single project.

**Current anchors:** `constants/icon_constants.asm`; `data/pokemon/menu_icons.asm` uses a packed `nybble_array`; `data/icon_pointers.asm`; `engine/gfx/mon_icons.asm:91-263`. Donor equivalents use species-specific constants/mapping and `MonIcons`/`MonIcons2` art in `gfx/sprites.asm:143-302`. [Tutorial](https://github.com/pret/pokered/wiki/Add-All-Unique-Party-Menu-Sprite-Icons).

**Implementation design:** A four-bit category mapping cannot simply hold every species ID (~100% confident). Adapt the donor's representation, banking, and loader together, preserving internal-ID/Pokedex-ID conversion and both animation frames. Do not load all species' art into VRAM at once.

**PC compatibility gate:** Current `engine/pokemon/bills_pc.asm:993-1017` calls the same category resolver, and its BG-tile grid/selected animation rely on the existing category tiles. The party screen uses OAM. Replacing the shared resolver with species IDs without adapting or separating the PC consumer would break that contract (~99% confident).

**Confirmed coverage (2026-08-27):** Unique species icons are required in both party menus and Bill's PC, including the PC's six party slots and 20 box slots. Plan PC BG-tile allocation/streaming together with the party OAM loader before replacing shared lookups. A temporary category adapter is allowed only as internal staging, not as the completed PC result. Keep overworld mappings separate from party-art IDs; share suitable assets where formats permit.

**Acceptance:** All base species mapped, both animation frames, six mixed party members, fainted/status behavior, naming/battle/TM-selection contexts, PC grid and selected animation, empty slots, box switching and SWAP, form/fusion/ghost fallback. Define fallback and asset credits before copying. Budget the assembled graphics from fresh maps; no bank is reserved yet.


### 9. Unique overworld Pokemon in homes and towns

**Finding:** Yellow Legacy has concrete species-specific authored NPC sprites; Red Rogue has only partial equivalent coverage at the audit baseline (~98% confident). **Confirmed coverage (2026-08-27):** Unique Pokemon sprites should cover all situations, including homes/towns, bridge-room Pokemon, followers, and procedural Pokemon/NPCs. The earlier authored-NPC-only recommendation is superseded.

**Donor examples:** `constants/sprite_constants.asm` includes dedicated Bulbasaur, Sandshrew, Jigglypuff, Clefairy, Pidgey, Slowpoke, and many other sprite IDs. Authored uses include:

- `data/maps/objects/CeruleanMelaniesHouse.asm:18-20`: Bulbasaur/Sandshrew.
- `PokemonFanClub.asm:21-22`: Clefairy/Seel.
- `SaffronPidgeyHouse.asm:19` and `VermilionPidgeyHouse.asm:17`: Pidgey.
- `FuchsiaCity.asm:51`: Slowpoke; `PewterPokecenter.asm:21`: Jigglypuff.

**Red Rogue approach:** Inventory every Pokemon display path: authored map objects, bridge rooms, room displays, dynamically chosen species, procedural encounters/bosses, and follower graphics. Reuse existing suitable sprites and established object/loader conventions. Build a coverage matrix from actual species and consumers; use proven donor art/dispatch where suitable. Do not copy whole Yellow maps/story scripts or redesign movement, bridge rewards, or encounter selection as part of this graphics scope.

For dynamic species NPCs, start from the existing neutral species/category resolver and design species-specific lookup/loading across all relevant consumers. Preserve object identity, movement and lifecycle contracts. Audit actual inclusion/readiness of follower/procedural code rather than infer it from a file or commit title. Missing sheets or unsupported frames must become explicit asset tasks or user-reviewed exceptions, not silently remain permanent generic categories. New art creation or external donors require a separate asset/provenance decision when a coverage gap is found.

**Follower compatibility update (2026-08-31):** New species-specific follower art such as Spearow, Doduo, or Zapdos is compatible with the accepted slot-15/base-2 follower architecture. Each follower-capable asset must be a complete 12-tile walking sheet with the standard four facing directions and walking frames, a `SpriteSheetPointerTable` entry, and a species-specific resolver entry. Adding assets to ROM does not consume additional live VRAM by itself: only the current lead's sheet occupies follower base 2. The existing map budget remains one follower plus at most eight distinct active authored walking sheets. A map that uses all nine authored walking sheets must carry a `FOLLOWER SPRITE LIMIT` warning in its object file and suppress the follower until an explicit sheet cut or loader policy is approved. Audit `NUM_SPRITES`, the walking/still classification boundaries, pointer-table bank placement, asset provenance, and form/fusion fallback whenever the sprite ID space expands.

**Acceptance:** Cover bridge rooms, authored NPCs, followers, and procedural/static/dynamic Pokemon displays. Test correct species art, collision, facing, movement, cry/dialogue, simultaneous sprite/VRAM limits, map/menu transitions, and walking/still frames. Define form/fusion fallback before implementation and report unfilled asset gaps. Change sprite coverage, not encounters or bridge gameplay.


### 10. Lower-right backsprite tiles disappear during sliding

**Finding:** Missing the donor boundary fix (~99% confident). Current `engine/battle/animations.asm:1835-1844` uses `cp $61` after adding a column stride, excluding the last valid back-picture tile. [Donor animations](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/battle/animations.asm) uses `cp $62`, the exclusive upper bound. Its enemy-side counterpart uses `$31` rather than current `$30`.

**Implementation scope:** Port the bounded comparisons after confirming the active tile ranges. This is a tile-number boundary fix, not a replacement of backsprite artwork or animation engine. The enemy edge is documented as visually hidden by slide order, but its companion bound should be reviewed in the same change.

**Acceptance:** Horizontal retreat/slide, Softboiled half-slide, Substitute removal/restoration, ordinary and fusion back pictures, both battle sides, DMG/CGB. Check the lower-right tile before and throughout movement. Existing trainer-head palette fixes are out of scope.


### 11. Trainer Card transition garbage on DMG

**Finding:** Likely missing the donor transition sequencing fix (~85% confident on source mismatch; runtime cause remains unproven here). Current `engine/menus/start_sub_menus.asm:529-551` restores palettes immediately after setup, and returns to redisplay the start menu. [Donor StartMenu_TrainerInfo](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/menus/start_sub_menus.asm) waits three frames on the non-SGB path before revealing the card, and on exit redraws the start menu before another wait/palette reveal.

**Implementation scope:** Compare the whole entry/exit transaction, not just insert a delay at entry. Adapt the donor's draw/wait/reveal ordering to Red Rogue's CGB attributes, player appearances, menu buffers, and existing palette functions. A non-SGB test is not a DMG-only test; review how it behaves on CGB. Reproduce before declaring the causal diagnosis confirmed.

**Acceptance:** Frame-step card entry and exit on DMG and CGB; fresh boot and repeated menu use; each supported player appearance; check both tilemap and VRAM/attributes. No broad palette/fade refactor.


### 13. Haze after freeze can leave a Pokemon unable to attack

**Finding:** The specific requested permanent lock fix is already present (~99% confident). It is in the enemy-inflicted freeze path, not in Haze's effect routine. Current `engine/battle/effects.asm:305-315` calls `ClearHyperBeam` before setting the player's freeze status.

The [upstream bug explanation and fix](https://github.com/pret/pokered/wiki/%5BARCHIVED%5D-Bugs-and-Glitches#haze-can-prevent-a-pok%C3%A9mon-from-attacking-after-curing-freeze) identifies the combination of retained Hyper Beam recharge and Haze's no-action sentinel. The existing freeze-path clear prevents that combination (~99% confident). Merely observing identical Haze helpers would not establish this.

**Recommendation:** No new import. Keep Haze's intended current-turn handling. Regression: player uses Hyper Beam, enemy freezes the recharging player, enemy uses Haze, then the player can select and execute later moves. Mirror the sides and include sleep/status controls. Distinguish a deliberately skipped current turn from a permanent inability to attack.


### 14. Transform assumes every transformed wild Pokemon is Ditto

**Finding:** Missing specifically in capture reconstruction (~99% confident). Current `engine/items/item_effects.asm:507-515` forces `DITTO` into `wEnemyMonSpecies2` for an already transformed target. [Donor item effects](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/items/item_effects.asm) preserves the original identity instead.

**Implementation scope:** Remove the two hardcoded assignments after tracing original-species initialization, preserving the existing transformed/non-transformed split, original-DV handling, `LoadEnemyMonData`, capture result, and party/box destination. Do not replace Transform wholesale.

Current `engine/battle/move_effects/transform.asm:61-91` deliberately avoids copying `MON_CATCH_RATE`, since Red Rogue stores form/fusion flags there, and protects original DVs on repeated Transform. Preserve both. Normal Transform's five-PP copies and SuperTransform's separate full-PP behavior are not part of this fix.

**Acceptance:** Catch a non-Ditto that obtained Transform, ordinary transformed Ditto, repeated Transform, normal untransformed catches, party/box destinations, original DVs and custom flags. Confirm the caught identity/nickname/Pokedex update agree. Check Light Ball Pikachu, Thick Club Marowak, ghost/type variants and fusions where relevant.


### 15. Nurse Joy and Officer Jenny battles

**Finding:** Yellow Legacy supplies both optional repeatable postgame battles; Red Rogue has neither trainer class at this baseline (~99% confident). A Jenny-named bridge gift list is not a Jenny battle.

**Donor behavior and assets:** [FuchsiaPokecenter.asm](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/scripts/FuchsiaPokecenter.asm) heals first, gates Joy's challenge on donor `wGameStage`, offers YES/NO, and records a win. [VermilionCity_2.asm](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/scripts/VermilionCity_2.asm) gates Jenny behind the Squirtle gift and postgame, with rematches enabled. Do not transplant these progression flags into Red Rogue.

Donor `data/trainers/parties.asm:803-809` supplies:

- Joy: level 65 Kangaskhan, Snorlax, Starmie, Porygon, Exeggutor, Chansey.
- Jenny: level 65 Pidgeot, Blastoise, Tangela, Gengar, Parasect, Arcanine.

Custom moves are in `data/trainers/special_moves.asm:586,609`; portraits are `gfx/trainers/joy.png` and `jenny.png`, assembled through `gfx/pics.asm`. Jenny's overworld asset is `gfx/sprites/officer_jenny.png`. The PDF page 54 illustrates both rosters. Preserve the teams as design references; do not automatically import Yellow Legacy's move balance or fixed levels.

**Red Rogue integration:** `constants/trainer_constants.asm:69-71` ends with `RIVAL_MINIBOSS` / `GIOVANNI_MINIBOSS`; use those existing table-extension conventions. Audit every trainer-indexed table, picture bank selection, money, music/encounter classification, roster decoder, AI tier resolution, and procedural class selection. With the current offset of 200, two additional consecutive classes would encode as 250/251, but validate every sentinel/comparison before assigning them (~99% confident on the arithmetic, not yet an exhaustive consumer audit).

**User decision (2026-08-27): DEFERRED.** Joy and Jenny remain desired import candidates, but their role is intentionally undecided. They may become minibosses or belong to a system not yet implemented. Do not select hub/bridge challenges, postgame exhibitions, teams, scaling, rewards, or repeat rules on the user's behalf. Retain donor assets/teams/contracts as references for a future design discussion. This deferred phase does not block other imports.

**Do not do yet:** Implement or activate Joy/Jenny battles, allocate trainer classes/events, add maps, change bridge rewards, or import donor story scripts. Revisit when the destination system is chosen and explicitly approved. Keep ordinary healing and existing Jenny gifts independent of any eventual battle unless the user later specifies otherwise.

**Delegation after design approval:** One Luna Max agent inventories all trainer tables and portrait contracts; one can prepare the selected data/assets. Main agent owns script/state integration and shared tables; a separate reviewer checks loss/refusal/rematch and reward gates.

**Acceptance:** Challenge refusal leaves services unchanged; wins and losses return to valid map state; blackout resets the script correctly; save/load and new-run resets respect the chosen repeat policy; rewards cannot duplicate unintentionally; existing minibosses and normal trainers retain their teams/AI. Audit every text segment to 17 characters, including the class-name prefix on EndBattleText. Credit Joy portrait to ZuperZACH and Jenny portrait to Karlos.


### 16. Box-full reminder

**Finding before YL-3A:** The post-capture reminder was missing (~95% confident). The existing full-party/full-box check before throwing a ball was a different behavior. Current `engine/items/item_effects.asm:594-596` sent a successful capture to the box but had no corresponding post-transfer full-box notification.

**YL-3A implementation:** Adapted [Shin's reminder](https://github.com/jojobear13/shinpokered/commit/7223a046997168913e67444b509ec15462bc7ec1) after the successful capture-to-box transfer text, checking the actual resulting active `wBoxCount == MONS_PER_BOX`. The larger logic lives in the existing rogue section and is reached through one farcall from the capture path because bank3 had limited slack before the change. The local far-text stub points to the new `text_6.asm` paragraph. No SRAM access, named-object/species scratch, or persistent flag was added.

**Scope:** Trigger when a capture fills the active box. Do not automatically extend it to bridge gifts, purchases, trades, or all-box scanning; those have different failure/reward semantics. Do not switch boxes automatically.

**Acceptance:** Capture into active box from 19 to 20, successful non-final insertion, already-full failure, capture into a non-full party, and switch to another box. Message appears once only after success, and it names the intended PC action. No persistent "warned" flag is proposed.


### 17. Remove Japanese opening quote / consolidate bold P

**Finding:** Not yet consolidated. Red Rogue still maps the unused quote to `$72`, separately loads `PTile` into that slot on the status screen, and assembles `gfx/font/P.1bpp` (~99% confident).

**Evidence:** `constants/charmap.asm:65-90`; `engine/pokemon/status_screen.asm:136-139,293`; `gfx/font.asm:15-26`. Yellow Legacy maps `<BOLD_P>` in the battle-extra font and uses that loaded glyph. [Original tutorial](https://github.com/pret/pokered/wiki/Remove-Japanese-Opening-Quote-and-put-BOLD-P-in-gfx-font-font_battle_extra.png).

**Recommendation:** A small, selective cleanup, after the status-screen WIP is checkpointed. Replace only the quote tile in the existing composite font source, change the charmap ownership/comment, remove the redundant PTile load and asset include after checking every consumer. Do not replace the full font sheet: the current HP art and percent/arrow substitutions must survive.

**Critical constraint:** `engine/battle/exp_bar.asm:18-24` uses `$72` as the full EXP-bar tile in battle. `engine/battle/core.asm:2910-2917` explicitly reloads those patterns when returning from party/status. Importing the tutorial's optional battle PP display at the same tile would conflict with this alias (~99% confident). Keep all EXP reloads and omit that optional tutorial extension.

**Acceptance:** Status PP glyph, HP bar and other glyphs remain correct; enter/exit status repeatedly from battle with empty/partial/full EXP bar; verify full 20x18 tilemap and live VRAM if a glitch appears. Measure actual ROM savings only after all three builds. No new RAM is expected; that is a design target, not a measured result.

### 18. Move overworld tile animation out of HOME

**Finding:** Not imported (~99% confident). Current `home/vcopy.asm:386-461` still contains water/flower animation bodies and the flower data. This is separate from the recently committed tile-block redraw optimization.

**Donor/reference:** [pureRGB 09c037f](https://github.com/Vortyne/pureRGB/commit/09c037f5df39cd99fe4e13b4d5fee8ed86206e7b) moves bodies/data to `engine/gfx/animated_tiles_code.asm` and leaves banked jumps. Treat Yellow Legacy's additional scanline guard as a separate change requiring justification, not part of a mechanical relocation.

**Recommendation:** A dedicated, optional ROM0 reclamation phase, not bundled into a visual fix or necessary for every earlier phase. Retain the small cadence/gating entry point as needed, place the bodies with the flower graphics in a suitable measured bank, and use an interrupt-safe established bank wrapper. `UpdateMovingBgTiles` is reached from VBlank, so audit interrupted-bank restoration, registers, scratch/stack ownership, VRAM access window, and every direct data read.

Do not quote a byte-saving estimate as reclaimed space. Measure source size, wrapper growth, relocated bytes, destination slack, and worst-case VBlank timing after successful three-variant builds. There may be a ROM0 space gain at a timing/ROMX cost; it is not automatically a speed improvement.

**Acceptance:** Water and all flower frames, map changes, menus with tile animation disabled/restored, DMG/CGB, supported CPU speeds, busy sprite/VRAM frames, no bank corruption or missed audio/OAM work. Update ROM Bible with old/new bank and section sizes and pending visual acceptance. No RAM layout change is inherently required, but do not invent scratch space.


### 19. Multiple-level-up learnset skipping

**Finding:** YL-2 implements the formerly missing intermediate-level fix; same-level multiple-move support remains intact. Battle EXP now walks every crossed level in ascending order, primary then fusion secondary, using stack-local bounds and the pre-evolution species.

**Donor:** [Yellow Legacy experience.asm](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/engine/battle/experience.asm) stores the old level and walks each gained level. [The supplied pureRGB patch](https://github.com/Vortyne/pureRGB/commit/9c38ff4a1afb8c0773202b37c8b9068b4b9f4354) also addresses learning on the evolved species across the relevant level range. Its `wTempCoins1` scratch reuse is not permission to use that byte in Red Rogue.

**Implemented design:** The user selected the actual-timeline rule: learn crossed levels only from the pre-evolution species during a multi-level battle EXP award. Level-based battle and mid-battle evolution therefore suppress the later evolved-species same-current-level grant. Stone, trade, and Rare Candy evolution retain their established behavior. The loop uses only the stack, preserves EXP-bar endpoints and saved EXP/string state, and does not allocate RAM.

**Acceptance:** Gain several levels containing moves at intermediate and final levels; two moves at one level; duplicate known moves; decline one and still see later prompts; full four-move replacement; multiple EXP recipients; fusion primary/secondary learnsets; evolution threshold crossing and delayed/stone/mid-battle evolution; level cap and Rare Candy controls. Verify final level, stats, PP, species, and EXP bar. No implementation should proceed on the assumption that a donor scratch byte is unused.


## 4. Proposed execution phases

These are checkpoints, not authorization to execute the entire list.

| Phase | Scope | Delegation | Gate / completion |
|---|---|---|---|
| YL-0 | Reconcile HEAD/WIP; baseline builds and tests; confirm already-present 2/7/13/14; skip 3 | Luna read-only audit; main owns baseline and scope | Completed 2026-09-08; user WIP preserved; fresh capacity and ROM identity recorded; 234/234 smoke |
| YL-1 | 6 faster save and 10 slide bound | Luna prepares bounded edits; separate Luna reviews; main integrates | Committed `11193b5b`; three ROMs and 234/234 smoke pass; runtime queue pending |
| YL-2 | 19 intermediate-level learning and evolution contracts | Luna mapped call sites/data lifetimes; main integrated stack-local loop and tests | Committed and pushed by the user as `8b3e5f6a`; builds and 234/234 smoke pass; runtime matrix queued |
| YL-3A | 16 full-box reminder | One bounded Luna implementation/review pair | Implemented atop `8b3e5f6a`; forced three-ROM builds and 239/239 smoke pass; only successful final-slot captures notify; runtime review and user commit pending |
| YL-3B | 5 faster Nurse Joy | Luna implements confirmed no-prompt/no-ball-placement flow; main reviews setup/restoration | Implemented; forced three-ROM builds and 243/243 smoke pass; runtime review and user commit pending |
| YL-3C | 11 card transition; 17 font cleanup, in separate patches | Both patches committed through user commit `9dd05c3b` | Item 17 builds pass and focused tests pass 3/3; ordinary smoke 247/248 with the known AI-injection failure; runtime queue pending |
| YL-4A | 1 Ghost/Water/Rock/Dragon + shiny markers | Three bounded read-only audits; main integrated HUD, font, and evolution correction | Implemented; builds and focused 3/3 pass; ordinary smoke 250/251 with the known AI-injection failure; runtime queue pending |
| YL-4B | 4 Pokedex integration | Luna audits/reuses donor readers; main coordinates existing Learndex WIP | No competing implementation; compatibility and encounter policy approved |
| YL-5 | 8+12 unique party and PC icons | Luna asset/table inventory; party OAM and PC BG audits | Both contexts complete; category-only PC is not acceptance |
| YL-6A | 9 unique sprites across overworld contexts | Luna audits separate authored/bridge/follower/procedural consumers; main owns shared loader | Complete coverage inventory and asset gaps; preserve gameplay/lifecycle |
| YL-6B | 15 Joy/Jenny, deferred | Reference audit only until user selects role/system | No battle activation, class/event allocation or rewards yet |
| YL-R | 18 HOME tile-animation relocation | Luna caller/data inventory; main owns interrupt/bank/timing review | Dedicated fresh-map and VBlank evidence; optional, separate approval |

### Dependencies and scheduling

- YL-0 is mandatory before code changes. YL-1 is the suggested first small checkpoint.
- YL-2 and the learnset portion of YL-4B must agree on actual learning semantics, especially fusions. Do not make the UI promise moves the engine will not offer, or hide secondary moves the engine does offer.
- YL-3C/font and YL-4A/HUD share graphics concerns; finish one patch before editing shared font/tile paths.
- YL-5 must reconcile the PC consumer before replacing any global party-icon lookup. Unique icons in both party and PC are required; separate technical substeps do not reduce that acceptance scope.
- YL-6A includes bridge rooms, followers and procedural Pokemon. It expands art coverage without authorizing changes to their gameplay or movement systems. YL-6B remains deferred; any later battle design must preserve the agreed healing service unless explicitly changed.
- YL-R can move earlier only if fresh capacity measurements show it is needed and the user approves that specific relocation. Do not make an interrupt-sensitive move merely because ROM0 is generally tight.
- Read-only agent audits can run in parallel. Shared source mutations and builds remain serialized.

## 5. Delegation and checkpoint contract

Use **Luna Max** for bounded source audits, data/table work, isolated implementation after interfaces are agreed, and focused independent review. Keep ambiguous mechanics, shared architecture, ROM/RAM placement, and integration in the main agent. Escalate the model only when expected rework or complexity makes Luna inefficient.

Each assignment must state:

1. The exact item/phase and permitted files; everything else is read-only.
2. Pinned donor revision and the specific behavior to preserve.
3. Register, bank, SRAM, tile, and state-lifetime contracts.
4. Required tests, build ownership, and completion evidence.
5. Explicit exclusions: no commits, branch switches, resets, unrelated fixes, whole-file donor replacements, or unilateral RAM allocation.

Agents can audit separate systems in parallel. They must not simultaneously edit `engine/battle/core.asm`, `engine/items/item_effects.asm`, `engine/pokemon/evos_moves.asm`, font tables, shared constants, RAM files, or placement files. If two phases touch the same file, serialize them or have one agent supply a reviewed patch specification for the main agent. An agent's success report is not the integration acceptance gate.

At each approved checkpoint, record:

| Evidence | Required record |
|---|---|
| Source identity | HEAD, exact diff, preserved WIP, donor SHA, file/asset provenance |
| Build | Red / Blue / Blue Debug results, matching ROM hashes and symbols |
| Capacity | Changed section sizes and minimum free bytes across all three fresh maps |
| RAM | New/changed bytes, aliases, initialization, lifetime, save implications |
| Static review | Calls/pointers/banks, SRAM restoration, text width, graphics IDs |
| Regression checks | Existing smoke and relevant focused tests, with exact failures |
| User acceptance | Focused emulator checklist; pending items stated explicitly |
| Handoff | Update this plan and applicable Bible; wait for the next instruction |

No numeric headroom in this draft is promised. Existing map files were present, but were not rebuilt or treated as fresh measurements for this plan.

## 6. Confirmed decisions and remaining questions

The user's 2026-08-27 clarification settles the scope below. These are planning decisions, not an instruction to start code implementation.

| Topic | Status | Recorded direction |
|---|---|---|
| Marker categories | Confirmed | Ghost, Water, and Rock variant flags/state, plus shiny Pokemon; not an ordinary caught indicator |
| Marker layout/overlap | Presentation decision deferred | Propose a type marker plus separate shiny sparkle; present glyphs and player/enemy HUD placement before implementation |
| Party/PC icons | Confirmed | Unique species icons in party menus and Bill's PC, including both party and box grids |
| Overworld coverage | Confirmed, broad | All Pokemon display situations, including bridge rooms, followers, authored NPCs and procedural Pokemon |
| Nurse interaction | Confirmed | No YES/NO; short statement followed by healing, even shorter subsequent text |
| Nurse animation | Confirmed | Skip sequential Poke Ball placement and go directly to healing; retain necessary setup/restoration |
| Joy/Jenny role | Deliberately deferred | Could be minibosses or part of a future system; no role, placement, rewards or battle activation selected |
| Pokedex encounters | Still open | Decide possible sources versus current-run availability and reconcile existing Learndex work before that phase |
| Form/fusion artwork | Technical inventory, then targeted decision | Identify missing assets and presentation choices; no silent permanent generic fallback for required species |
| Memory/loader details | Technical investigation | Main agent resolves contracts and measures capacity; ask only if a meaningful feature tradeoff or separately approved layout change is needed |

Ask remaining gameplay/presentation questions immediately before the relevant phase, with concrete options or mockups. Do not repeatedly ask the now-settled scope questions. Keep Joy/Jenny deferred without blocking other work.

## 7. Optional PDF follow-ups, not approved scope

Keep this shortlist separate from the 19 items. First establish whether the behavior is already fixed.

- **Inventory stack overflow audit (PDF p6):** inspect legacy inventory and the five-pocket/TM-bitfield dispatch together, including adding to a 99 stack, split stacks, full pockets, PC items, and bulk gifts. Do not assume the legacy routine alone represents every active caller.
- **Adjacent rendering fixes (PDF p7):** if item 10/11 reproductions reveal tearing, audit trainer/Pokemon slide timing and enemy Double-Edge animation. Treat these as separate defects, not automatic additions to the graphics patch.
- **Remaining battle correctness checks (PDF p8):** interrupted Fly/Dig and HP healing at differences of 255/511 are useful narrow regression candidates. Compare current Shin/other imported fixes before proposing more code.
- **Donor art:** consider selected backsprite or gym-leader art only through a separate asset list and credit audit. The current request concerns two specific rendering bugs, not a wholesale art replacement.

Do not import donor AI, move/type balance, hard-mode rules, badge boosts, encounter tables, story progression, mart economy, or Kanto postgame wholesale. Those intersect major Red Rogue systems and are not implied by this request.

## 8. Sources, provenance, and reproducibility

### User-supplied references

- [Yellow Legacy repository](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy).
- [KEP caught icon commit](https://github.com/MementoMartha/kep-hack/commit/00efe3c6b461773a20b424fbf548cb38c880c9ac).
- [Remove artificial save delay](https://github.com/pret/pokered/wiki/Remove-Artificial-Save-Delay).
- [KEP spinner commit](https://github.com/MementoMartha/kep-hack/commit/7c5c2a3047dd74b9ed014053172e0222b49d486b).
- [All unique party icons tutorial](https://github.com/pret/pokered/wiki/Add-All-Unique-Party-Menu-Sprite-Icons).
- [Shin box-full reminder commit](https://github.com/jojobear13/shinpokered/commit/7223a046997168913e67444b509ec15462bc7ec1).
- [Japanese quote / bold P tutorial](https://github.com/pret/pokered/wiki/Remove-Japanese-Opening-Quote-and-put-BOLD-P-in-gfx-font-font_battle_extra.png).
- [pureRGB tile-animation relocation](https://github.com/Vortyne/pureRGB/commit/09c037f5df39cd99fe4e13b4d5fee8ed86206e7b).
- [pureRGB multi-level learning fix](https://github.com/Vortyne/pureRGB/commit/9c38ff4a1afb8c0773202b37c8b9068b4b9f4354).

Exact KEP caught-icon, KEP spinner, and pureRGB learning patches were fetched when the GitHub HTML views were unavailable. They were inspected, not applied.

### Credit gate

Before importing art, copy the pinned donor's applicable credits and check asset-specific permission/provenance. [Yellow Legacy README at the audited revision](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy/blob/15169d137e2ef778e8765f7f3381acc4093dc169/README.md) expressly requests credit for reused backsprite/overworld art. Its party-art credits include Chamber, Soloo993, Blue Emerald, Lake, Neslug, and Pikachu25; the PDF credits list Tom Wang, so reconcile that attribution rather than silently dropping either record. Overworld artists include Isona, Alakadoof, and Karlos. Joy/Jenny portraits credit ZuperZACH/Karlos respectively. Code attribution should name the actual upstream authors, not just Yellow Legacy.

### Audit reproduction

Local source links/paths in this plan are relative to `C:\Users\justi\redrogue` unless otherwise stated. Donor file paths are relative to the pinned Yellow Legacy checkout. Line numbers are audit-time anchors and can drift.

The temporary audit checkout was `C:\Users\justi\AppData\Local\Temp\redrogue-yellow-legacy-audit\donor`. Temporary PDF extracts and rendered reference pages are not required for execution: the pinned URLs, original PDF, and source anchors above are the durable references.

Reconcile this draft again whenever HEAD, the status-view WIP, the follower system, or the PC icon implementation changes. A previous import plan's checkbox is never a substitute for that check.

## End-of-plan runtime acceptance queue

The user intends to run these grouped runtime checks after the implementation checkpoints, rather than stopping the coding sequence for each presentation or gameplay choreography item. Build and smoke evidence remain supporting evidence only. Future checkpoint runtime suggestions should be appended to this queue and referenced from the checkpoint record.

### YL-1: save timing and backsprite slide bounds

- Create a new save, accept an overwrite, decline both save confirmation paths, reload the result, and confirm the saved party, box, and representative custom run state are preserved.
- Confirm the save success sound still plays to completion and control returns promptly after the shortened waits. Exercise a box switch and the CGB options path as part of save/load coverage.
- On DMG and CGB, exercise player and enemy horizontal slide animations with a backsprite whose lower-right tile is occupied. Confirm the tile remains visible and no neighboring tile or palette is corrupted.

### YL-2: crossed-level move learning and evolution timeline

- Award no level, one level, and a multi-level 18-to-21 gain. Confirm intermediate and final-level prompts occur in ascending order, including two moves at one level.
- Confirm duplicate known moves are skipped, declining one move does not suppress later eligible prompts, and a full four-move set still offers the normal replacement flow.
- Exercise multiple EXP recipients and EXP All, then verify each recipient's final level, moves, PP, stats, EXP bar, text flow, and stack recovery.
- Exercise fusion learning and confirm primary species moves are offered before secondary species moves at every crossed level, with duplicate filtering preserved.
- Cross an evolution threshold through normal battle EXP and mid-battle evolution, confirming the pre-evolution species supplies crossed-level moves and no retroactive evolved-species current-level move is offered. Separately test stone, trade, and Rare Candy evolution behavior.
- Test the level cap, delayed evolution choice, final species, stats, PP, EXP bar, and return to ordinary battle or map control.

### YL-3A: capture fills the active box

- With the active box at 19, capture successfully with a full party. Confirm the mon is inserted, the existing transfer text appears, then the reminder appears exactly once with the full donor wording and closes cleanly.
- With the active box at 18, capture successfully and confirm the transfer text appears without the reminder. Confirm the active box reaches 19.
- With the active box already at 20, confirm the pre-capture full-box rejection prevents the capture, insertion, transfer text, and reminder.
- With the party not full, capture successfully into the party and confirm no box reminder appears. Confirm ordinary party data and control flow remain correct.
- Switch the active box, repeat a 19-to-20 capture, and confirm only that active box triggers the reminder. Repeat a later capture or use another box to confirm there is no stale warned state.
- Verify the captured species, nickname, OT, moves, DVs, PP, box count, bridge metadata, active box index, SRAM bank, and subsequent PC/map control after both the transfer and reminder text. Do not extend this acceptance to bridge gifts, purchases, trades, or all-box scanning.

### YL-3B: Nurse Joy and healing-machine speedup

- On a first visit, confirm Nurse Joy prints only `Welcome! I'll` / `heal your #MON.` and immediately begins healing without a YES/NO prompt. On a repeat visit, confirm she prints only `Let's heal your` / `#MON!`.
- Exercise one-member and six-member parties, including full-HP, fainted, and major-status cases. Confirm every member's HP and status are restored and control returns to the map.
- Set depleted move PP with and without PP Up bits, then heal one and six members. Confirm base PP is restored while PP Up bits and the resulting higher maximum PP are preserved.
- Confirm there is no sequential party-ball placement stage: the machine presents the compact OAM/healing effect, plays one healing-machine audio cadence, and returns after the retained final 30-frame delay without an extra per-member pause.
- Confirm the nurse image changes through the healing pose and back to the normal pose, the follower is hidden before OAM freezing and refreshed afterward, palettes are restored, and music/audio-bank state returns to the pre-heal track.
- Verify first/repeat visit flag behavior across leaving and re-entering the center, save/reload, and a new run. Confirm `BIT_USED_POKECENTER` and the existing related visit state do not leave the player stuck in a prompt or healing loop.
- Exercise the normal overworld, blackout return, follower-enabled, and follower-disabled paths. Test DMG and CGB, including the CGB speed option, and check that no control lock, sprite corruption, or palette residue remains.

### YL-3C item 11: Trainer Card DMG transition settling

- On DMG, enter and leave the Trainer Card from a fresh boot and repeatedly from the Start menu. Frame-step both transitions and confirm no outgoing tile IDs are briefly rendered with incoming graphics, no garbage appears, and the restored map and Start menu are complete before reveal.
- Repeat on CGB with normal and double-speed options. Confirm the CGB path does not gain the DMG-only delay and that background palettes, object palettes, attributes, and map music remain correct.
- Exercise every supported player appearance. Confirm the correct appearance-aware front picture, badges, name, money, and play time render without stale tiles or palette residue.
- Compare the live 20x18 tilemap, VRAM tile patterns, and CGB attributes immediately before entry, while the screen is white, at Trainer Card reveal, after exit reload, and at Start-menu redisplay.

### YL-3C item 17: bold-P font consolidation and EXP-bar alias

- Open status from the Start menu, PC, and an active battle. On the moves page, confirm every known move row shows a clean bold `PP`, including a four-move Pokemon and PP values with PP Ups.
- Repeatedly enter and leave the battle party/status screens through cancel, switch, item, and send-out paths. Confirm tile `$72` changes from bold P on status to the full EXP-bar tile on battle return, with no lingering P or quote glyph.
- Exercise empty, partial, nearly full, and full EXP bars. Confirm `$70` supplies the dynamic partial tile, `$72` supplies full tiles, and the row fills right-to-left without corrupting HP/status/HUD borders.
- Verify Pokedex Pokeball marks after entering and leaving status and battle screens, because that screen intentionally overwrites its own `$72` tile.
- Repeat on DMG and CGB, including double speed. Inspect the full 20x18 tilemap and live `vChars2` tiles `$70` and `$72` at status display and after battle restoration.

### YL-4A item 1: per-instance battle markers and evolution preservation

- On DMG and CGB, send out player Ghost, Water, Rock, Dragon, shiny, and ordinary Pokemon. Confirm exactly one marker appears at player `(13,8)`, the correct placeholder glyph is used, and ordinary Pokemon leave the cell blank.
- Exercise enemy Ghost and any available flagged enemy fixture. Confirm the marker appears at enemy `(9,1)` without colliding with name, status, level, HP, borders, or palettes. Ordinary wild and trainer enemies should remain unmarked under their current loader policy.
- Create overlapping states and confirm priority is type variant, then Ghost, then shiny. In particular, shiny plus Water/Rock/Dragon must show only the type marker. Confirm the generic `V` appears if a test fixture sets `BIT_TYPE_VARIANT` with an unsupported stored type.
- Force HUD redraws through damage, healing, status changes, switching, fainting, party/status inspection, and battle-menu return. Confirm markers neither disappear nor leave stale glyphs when the active mon changes to an ordinary one.
- Evolve Water, Rock, and Dragon variants through representative normal battle, Rare Candy, stone, trade, daycare, and mid-battle paths where applicable. Confirm the evolved party struct retains the original variant `MON_TYPE2`, battle calculations and status display use that type, and the marker remains the same. Confirm an ordinary dual-typed evolution still receives both evolved species base types.
- Repeat save/load and party/box movement for marked Pokemon, then enter battle. Confirm their instance flags, stored variant type, marker, stats, moves, and PP remain intact. No normal-capture acceptance is required for this game.
- Inspect the live 20x18 tilemap and font VRAM tiles `$D0-$D5` on both hardware modes. Confirm the marker glyphs are editable placeholders only and that existing `$70`, `$72`, and `$76` EXP/HUD aliases remain correct.

### YL-4B item 4: Pokedex MOVE viewer

- Open the Pokedex on a seen species that is not in the party, choose MOVE, and confirm LEVEL UP includes its starting moves and later level-up moves in order. Repeat with an internal species ID that differs from its Pokedex number.
- Press START repeatedly and confirm the viewer cycles LEVEL UP, TM/HM, TUTOR, then LEVEL UP. Confirm CURRENT never appears.
- Use UP and DOWN on short, empty, and long lists. Confirm scrolling clamps at both ends, move names and levels remain aligned, and the move-info strip updates for the selected row.
- Confirm TM/HM compatibility is shown regardless of TM ownership. Open MOVE after inspecting a fusion or regional form and verify stale secondary-species compatibility and stale form learnsets do not leak into an ordinary base species.
- Exit with A and B. Confirm the same Pokedex row, scroll position, caught/seen markers, graphics, palette, and menu controls return without stale status-view tiles.
- Repeat on DMG and CGB, including double speed. Inspect transition fades, tile animation restoration, the 20x18 tilemap, and status/Pokedex graphics reload boundaries.
