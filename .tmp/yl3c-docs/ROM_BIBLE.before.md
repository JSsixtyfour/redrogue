# ROM Bible (Red Rogue)

## 2026-09-09 Yellow Legacy YL-3B - faster Nurse Joy and healing machine

Measured from fresh forced Red, Blue, and Blue Debug builds in the current worktree after
YL-3A. The worktree also contains user-owned Species Groups Phase 2R changes; those changes
are preserved and are not attributed to YL-3B.

- `engine/events/pokecenter.asm` now records the first/repeat visit state, prints short
  first/repeat text, and heals directly without the YES/NO choice, decline path, post-heal
  dialogue, or extra nurse pauses. `engine/overworld/healing_machine.asm` copies one OAM
  entry per party member, then plays one healing-machine SFX and retains one 30-frame delay.
  Follower hiding/freezing, palette restoration, audio-bank/music restoration, and the final
  follower refresh remain in place.
- `data/text/text_4.asm` contains the first-visit text `Welcome! I'll` / `heal your #MON.` and
  repeat text `Let's heal your` / `#MON!`. Every rendered line is at most 17 characters and
  prompts have no preceding `@`.
- HOME section is `$3E43` / 15,939 bytes at `$0150-$3F92` in Red and Blue, leaving `$006D` /
  109 bytes free. Blue Debug HOME is `$3E54` / 15,956 bytes at `$0150-$3FA3`, leaving `$005D` /
  93 bytes free. Bank `$1C` section `bank1C` is `$3C3A` / 15,418 bytes at `$4000-$7C39`,
  leaving `$03C6` / 966 bytes free. `Text 4` is `$378E` / 14,222 bytes at `$4000-$778D`,
  leaving `$0872` / 2,162 bytes free. These values are from the fresh Red, Blue, and Blue
  Debug maps.
- No YL-3B section moved banks. YL-3B adds no RAM, HRAM, SRAM, union, or save-layout
  declaration changes. Concurrent Species Groups Phase 2R layout work is excluded from this
  checkpoint.
- Artifact scope: the ROM hashes below identify the current combined worktree artifacts,
  including concurrent Species Groups Phase 2R work; they are not pure YL-3B-only artifacts.
- ROM MD5: Red `F82088291864E7050CBA46203AA48B99`; Blue `1D3C6CF231A41A7DCBA68EB6F79AC7F7`;
  Blue Debug `EAC66687A0D2E3864FE1E943306D43AB`.
- Fresh forced Red/Blue/Debug builds pass. `make smoke` passes 243/243 in 52.038 seconds.
  The focused YL-3B source/runtime tests pass 4/4, including one- and six-party `HealParty`
  state restoration.
- Runtime acceptance remains pending; see the plan's `End-of-plan runtime acceptance queue`,
  YL-3B group, for the user-run Nurse Joy and healing-machine matrix.

## 2026-09-09 Yellow Legacy YL-3A - full-box reminder

Measured from fresh forced Red, Blue, and Blue Debug builds at user commit
`8b3e5f6ab19b674c89ccf61c29b0255c853c853c` (`Yellow Legacy Imports Part 2`) plus the
uncommitted YL-3A implementation.

- `engine/items/item_effects.asm` farcalls a capture-only helper after the successful
  capture-to-box transfer text. The helper lives in the existing `rogue` section and checks
  the resulting active `wBoxCount` against `MONS_PER_BOX` before printing the local far-text
  stub. `SendNewMonToBox` and its other callers are unchanged.
- Bank `$03` section `bank3` grows from `$3D7F` / 15,743 bytes to `$3D87` / 15,751 bytes,
  adding 8 bytes. Free space falls from `$001E` / 30 bytes to `$0016` / 22 bytes.
- `Text 10` grows from `$2CCB` / 11,467 bytes to `$2D1E` / 11,550 bytes, adding
  `$0053` / 83 bytes. Free space falls from `$1335` / 4,917 bytes to `$12E2` / 4,834 bytes.
- `rogue` grows from `$378F` / 14,223 bytes to `$37A1` / 14,241 bytes, adding 18 bytes;
  Red and Blue free space falls from `$012C` / 300 bytes to `$011A` / 282 bytes. Blue Debug
  `rogue` grows from `$38CD` / 14,541 bytes to `$38DF` / 14,559 bytes, adding 18 bytes;
  free space falls from `$0733` / 1,843 bytes to `$0721` / 1,825 bytes.
- No section moved banks. No ROM-bank contract, RAM, HRAM, SRAM, union, save-layout, or
  persistent warning state changed.
- ROM MD5: Red `B395294AFD086CC525B08CEFFEE6B593`; Blue `6B536A000AC2E80D57ABB6D9B6D5EDC6`;
  Blue Debug `5A15543A8DE6E7E10360A0FF43E5B77B`.
- Fresh forced Red/Blue/Debug builds pass. `make smoke` passes 239/239 in 50.527 seconds.
  The focused source-contract tests pass 3/3, and the runtime helper probe covers count 19
  without `PrintText` and count 20 with exactly one reminder entry before the blocking text
  wait.
- Runtime acceptance remains pending; see the plan's `End-of-plan runtime acceptance queue`,
  YL-3A group, for the user-run capture matrix.

## 2026-09-09 Yellow Legacy YL-2 - crossed-level move learning

Measured from fresh forced Red, Blue, and Blue Debug builds at user commit
`8b3e5f6ab19b674c89ccf61c29b0255c853c853c` (`Yellow Legacy Imports Part 2`), committed and
pushed by the user.

- `engine/battle/experience.asm` walks every level crossed by one battle EXP award in
  ascending order. It checks the primary species and then, for a fusion, the secondary species
  at each level. The pre-evolution species remains authoritative until the award completes.
- Bank `$15` section `Battle Engine 9` grows from `$0334` / 820 bytes at
  `$5294-$55C7` to `$0349` / 841 bytes at `$5294-$55DC`, adding
  `$0015` / 21 bytes in every target. Bank `$15` free space falls from
  `$1010` / 4,112 bytes to `$0FFB` / 4,091 bytes.
- `engine/pokemon/evos_moves.asm` skips the evolved-species same-current-level move grant
  for level-based battle and mid-battle evolution. Stone, trade, and Rare Candy evolution
  remain out of battle and retain the existing post-evolution move behavior.
- Bank `$31` section `Evos Moves` grows from `$1E49` / 7,753 bytes at
  `$4000-$5E48` to `$1E56` / 7,766 bytes at `$4000-$5E55`, adding
  `$000D` / 13 bytes in every target. Bank `$31` free space falls from
  `$21B7` / 8,631 bytes to `$21AA` / 8,618 bytes.
- No section moved banks. No cross-bank call, direct data read, local pointer table,
  `BANK()` assumption, fallthrough, or inline bank switch changed. The loop stores its bounds
  and prior `wCurEnemyLevel` on the stack. No WRAM, HRAM, SRAM, union, or save-layout
  declaration changed.
- ROM MD5: Red `0092188C41E264F2145EBBC23753B962`; Blue
  `ECAC35650C94A4C0CA70097C888DE33E`; Blue Debug
  `ED0CFF2119223FDB55246B6F59CE51E1`.
- Fresh forced Red/Blue/Debug builds pass. `make smoke` passes 234/234 in 49.642 seconds.
  The focused EXP regression verifies a level 18-to-21 award checks 19, 20, and 21, learns the
  intermediate level-20 move, and leaves the stack pointer balanced. A focused source-contract
  test verifies the in-battle evolution gate; it does not execute the full animated evolution
  lifecycle.

Pending runtime acceptance: the full learning matrix, including multi-prompt and decline flows,
multiple recipients, fusion ordering, threshold and delayed evolution, normal and mid-battle
evolution, stone and Rare Candy behavior, level cap, final stats/PP/species/EXP bar, and text
recovery. Build, smoke, and source-contract evidence do not prove that complete choreography.

## 2026-09-09 Yellow Legacy YL-1 - faster save presentation and slide bounds

Measured from fresh forced Red, Blue, and Blue Debug builds at baseline
`dae376d1fd58e1bdf904a93be0c3c475f9d994fe` plus YL-1, committed and pushed by the user as
`11193b5b4038e7c2a7587e0dcd47188c031fc558` (`Saving Speed Boost - Step 1 Yellow Legacy`).

- `engine/menus/save.asm` removes the post-write `Now saving...` screen and its 120-frame
  artificial wait. It retains `SaveGameData`, waits 10 frames before the existing success
  message, preserves `SFX_SAVE` and `WaitForSoundToFinish`, and reduces the final tail from
  30 to 10 frames. SRAM banks, checksums, overwrite/decline paths, custom save state, and the
  save sound contract are unchanged.
- Bank `$1C` section `bank1C` shrinks from `$3C5A` / 15,450 bytes at
  `$4000-$7C59` to `$3C3A` / 15,418 bytes at `$4000-$7C39`, reclaiming exactly
  `$0020` / 32 bytes in every target. Bank `$1C` free space grows from
  `$03A6` / 934 bytes to `$03C6` / 966 bytes.
- `engine/battle/animations.asm` changes the player and enemy slide bounds from `$61/$30`
  to the actual exclusive upper bounds `$62/$31`. The lower-right tile is therefore accepted
  instead of blanked. Both immediate replacements are size-neutral.
- Bank `$1E` section `bank1E` remains `$3FBB` / 16,315 bytes at
  `$4000-$7FBA`; bank `$1E` remains `$0045` / 69 bytes free in every target.
- No section moved banks. No call, data pointer, `BANK()` assumption, cross-section
  fallthrough, inline bank switch, or RAM/VRAM/SRAM declaration changed. Save-related calls remain
  within the existing section or target HOME routines. Slide helpers remain local to
  `_AnimationSlideMonOff` in bank `$1E` (~99% confident).
- Fresh ROM totals: Red ROMX 745,843 used / 106,125 free; Blue 745,828 / 106,140;
  Blue Debug 747,249 / 121,103. ROM0 is unchanged at 113/113/93 free. All variants retain
  SRAM 5,350 free, WRAM0 232 free, and HRAM 0 free.
- ROM MD5: Red `FBBCF3E977AB8A43D2AEA155838FDAFF`; Blue
  `CEA2B83DAE2E27436049461E62A58D4D`; Blue Debug
  `06CE986BC88C1D8AD93A3392D8535C9B`.
- Forced Red/Blue/Debug builds pass. `make smoke` passes 234/234 in 50.012 seconds,
  including the real save/load persistence smoke test. Build and smoke do not prove presentation.

Pending user runtime acceptance: create and overwrite a save, decline both confirmation paths,
reload the result, confirm the save sound finishes and control returns promptly, then exercise
player and enemy horizontal slide animations with a backsprite whose lower-right tile is visible
on DMG and CGB.

## 2026-09-08 Species Groups Phase 2 step 5 — first three species, and the Mew hole in `BaseStats`

The worked example for the 101-species Johto import: **Chikorita / Bayleef / Meganium** wired
end-to-end through all 16 species-indexed tables. Measured on a fresh build of all three targets
(`pokered`, `pokeblue`, `pokeblue_debug` force-rebuilt; `make` skips the debug target silently).

### BUG CLASS: a table whose count assert passes while its rows are misaligned

`GetMonHeader` indexes `BaseStats` flatly as `(dex - 1) * BASE_DATA_SIZE`. Vanilla kept **Mew's
28-byte row OUT of that table**, in bank `$01` beside its pics, reached by a `cp MEW / jr z, .mew`
special case. That left a **hole at dex 151**. Harmless for 25 years, because Mew was the LAST dex
number and nothing indexed past it.

The moment dex 152 exists, every row after the hole is shifted down by one:

```
dex 152 -> row index 151 : dexid=153 hp=60  ...   <- Chikorita reads BAYLEEF's stats
dex 154 -> row index 153 : dexid=175 hp=234 ...   <- Meganium reads off the END of the table
```

**`assert_table_length NUM_POKEMON - 1` passed the whole time.** It counts rows; it cannot see a
hole plus a compensating extra row, which is exactly the shape this bug has. The build was clean,
the link was clean, and 101 species would have shipped with the wrong stats.

Caught by reading `BaseStats` out of the built ROM and checking each row's own leading
`db DEX_<MON>` byte against the dex number used to index it — a self-describing field that makes
this class of bug a one-line probe. **Build success is not correctness; probe the ROM.**

**Fix (structural, not a patch):** Mew's row moved INTO `BaseStats` at its own dex position, the
`.mew` branch deleted from `GetMonHeader`, `MewBaseStats::` deleted from `data/pokemon/mew.asm`.
`MewPicFront`/`MewPicBack` stay in bank `$01`; `BASE_PIC_BANK` (Phase 2 step 6) lets the row name
them cross-bank, so nothing else had to move. The table is now dense from 1 to `NUM_POKEMON`.

**Permanent guard added** in `data/pokemon/base_stats.asm`, costing zero ROM:

```
MACRO assert_dex_row_at
	assert (@ - BaseStats) == \1 * BASE_DATA_SIZE, \
	       "BaseStats row for \1 is not at its dex offset - a row is missing, duplicated or out of dex order"
ENDM
	assert_dex_row_at DEX_MEGANIUM
```

Verified to FIRE: re-deleting Mew's include (with the count assert relaxed so it would pass)
produces `error: Assertion failed: BaseStats row for DEX_MEGANIUM is not at its dex offset`.
Anchor it at the LAST species in the table and every preceding row is covered.

### FINDING: naming a `const_skip` hole is FREE in six of the fourteen tables

Every skipped internal index already carries a placeholder row — `dname "MISSINGNO."`,
`db 0 ; MISSINGNO.`, `mon_cry SFX_CRY_00, $00, $00`, `dw MissingNoNNEvosMoves`,
`dw MissingNoDexEntry`, and a `$00` nybble pair. Naming a hole **replaces** a row rather than
appending one, so the first **38** species cost **zero bytes** in `MonsterNames`, `PokedexOrder`,
`CryData`, `EvosMovesPointerTable`, `PokedexEntryPointers` and `PokemonSpriteCategoryTable`.

This materially reduces the step-4 relocation estimate. Only 63 of the 101 species (`$BF`-`$FD`)
grow the internal-index tables:

| Table | Old estimate @101 | Real growth |
|---|---:|---:|
| `MonsterNames` | 1,010 | **630** (63 x 10) |
| `CryData` | 303 | **189** (63 x 3) |
| `PokedexOrder` | 101 | **63** |
| `PokedexEntryPointers` | 202 | **126** |
| `PokemonSpriteCategoryTable` | 51 | **32** |

The dex-indexed tables (`BaseStats` +28/mon, `MonsterPalettes` +1, `MonPartyData` +0.5) still grow
by the full 101, as do the `EvosMoves` and `PokedexText` **data** blocks.

### Measured cost

| Region | Before | After | Delta |
|---|---:|---:|---|
| ROM0 (release) | 93 free | **113 free** | **+20** — the deleted `.mew` branch |
| ROM0 (debug) | 73 free | **93 free** | **+20** |
| ROMX used (`pokered`) | 675,341 | 677,584 | +2,243 |
| WRAM0 | 258 free | **256 free** | -2 — `wPokedexOwned`/`wPokedexSeen` `flag_array` growth, 151 -> 154 |
| SRAM | 5,376 free | 5,374 free | -2 |

Per-bank tails (`TOTAL EMPTY`, release targets; debug differs only in `$01` and `$07`):

| Bank | Before | After | Note |
|---|---:|---:|---|
| `$01` | 20 | 20 | Mew's row left, but `Pics 1` backfilled it (rgblink first-fit) |
| `$03` | 109 | **68** | `CryData` — 3 species x 3 B, plus backfill |
| `$07` | 144 | **6** | `MonsterNames` — **CRITICAL, relocate before species 4** |
| `$0E` | 807 | **211** | `BaseStats` (+4 rows incl. Mew) AND the new `Pics 6` landed here |
| `$12` | 85 | **4** | `EvosMoves` — **CRITICAL, relocate before species 4** |
| `$2B` | 1,992 | **1,724** | `PokedexText` |
| `$30`/`$31`/`$32` | 16,384 each | 16,384 each | still wholly empty — the relocation targets |
| `$33` | 11,231 | 11,231 | `Sound Effect Headers 4` |
| `$34` | 16,265 | 16,265 | `Bridge Extended Effects` (119 B) |

**Step 4 is now FORCED.** `$07` (6 B) and `$12` (4 B) cannot absorb a fourth species. That is the
intended trigger: the checkpoint deliberately deferred relocation until the data actually grew,
because rgblink is first-fit and freeing space early just lets unrelated floating sections backfill
it, differently per build target.

### New pic budget — measured, and absent from the 2026-09-03 estimate

All 306 new `.pic` blobs (153 species x front+back) were compiled and measured: **77,895 bytes,
avg 254 B, = 4.75 banks.** This is the single largest consumer in Phase 2. `Pics 6` (3 species,
1,761 B) floated into `$0E`; the bulk will need `Pics 7..N` pinned to `$30`-`$32`.

48 of the new front PNGs did not compile at all — the SkidMarc25 sheet cells were trimmed to their
content bounding box, so they were neither square (a `pkmncompress` requirement) nor a multiple of
8 (an `rgbgfx` requirement). Padded to the next square multiple of 8, content horizontally centred
and bottom-aligned to match `LoadUncompressedSpriteData`. That change alone left all three ROMs
byte-identical, which is the cheapest proof it stayed in scope.

### Relocation contract note for step 4

All five growing sections are DATA whose readers already bankswitch via `BANK(label)`, so they
follow the section wherever it lands. Two constraints survive the move:

- **`EvosMovesPointerTable` is 16-bit `dw`** — the table and the data it points at must stay in the
  SAME bank.
- **`PokedexText` reaches ~22 KB and exceeds one 16 KiB bank** — it must be SPLIT across two. Safe,
  because entries are reached by `text_far`, but the split has to be deliberate.


## 2026-09-03 species-group rarity refactor + the farcall register-contract bug class

Phase 1a-1d of the Johto / Kanto Time Warp species-group work. `engine/pokemon/rarity.asm`
became a GROUP x TIER structure with assembler-computed counts; six shared accessors
replaced four duplicated hand-rolled scans. Measured on the debug build.

### Measured cost

| Region | Before | After | Delta |
|---|---:|---:|---:|
| ROMX total used | 673,600 | 673,706 | **+106** |
| ROM0 | 4 free | 4 free | 0 |
| WRAM0 | 1 free | 1 free | 0 |
| SRAM | 5,119 free | 5,119 free | 0 (the toggle byte came out of the `ds` pad in `"Save Data"`) |

Per-bank tails (debug, `TOTAL EMPTY`):

| Bank | Before | After | Note |
|---|---:|---:|---|
| `$05` | 17 | **9** | `PCRollMonClassFar` (~7 B) + two `ld e, c`. Critical - do not budget here. |
| `$06` | 4 | **23** | **Gained 19 B**: the lobby's wrong-bank rarity scan was deleted, see below. |
| `$07` | 6 | 6 | one `ld e, c` absorbed |
| `$08` | 3 | **2** | one `ld e, c`. Effectively full. |
| `$14` | 334 | 334 | untouched here; recovered to 1,007 in the Phase 1e/1f addendum below |
| `$2F` | 2,516 | **2,414** | the rarity restructure itself; ample room for the Phase 2 group lists |

### BUG CLASS: a farcall cannot carry an argument or a result in `b` or `c`

`Bankswitch` (`home/bankswitch.asm`) is:

```
	ldh a, [hLoadedROMBank]
	push af
	ld a, b            ; <- target bank arrives in b
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ld bc, .Return     ; <- DESTROYS bc BEFORE the callee runs
	push bc
	jp hl
.Return
	pop bc             ; <- DESTROYS bc AGAIN on the way out
	ld a, b
	...
```

So across a `farcall`, **only `d`, `e` and flags survive**. `a`, `b`, `c`, `h` and `l` are all
clobbered on BOTH sides. The codebase half-knew this: `procedural_forest_gen.asm` documents the
entry clobber for `b`, and `bridge_gift_menu.asm` documents the exit clobber for `a`/`b`/`c` - but
nobody had joined the two and noticed `ld bc` also kills `c` on entry.

**Ten live sites were affected.** Every cross-bank caller of `Random_Pokemon_Selection` computed a
rarity class into `c` and immediately farcalled, so the class never arrived and every one of those
rolls silently fell through to the plain odds ladder:

- `procedural_cave_gen.asm` PCRollBoss, PCRollWildEncounter
- `procedural_cemetery_gen.asm` PCemRollBoss, PCemAvoidGhostBoss
- `procedural_facility_gen.asm` PFacRollBoss
- `procedural_forest_gen.asm` PFRollBoss
- `engine/events/bridge_gift_menu.asm` (Mr. Fuji MON RESCUE)
- `engine/debug/debug_fight2.asm`
- `scripts/IndigoPlateauLobby.asm` PC trader and PC salesman

Net effect: the `ld b, 60` boss rarity bump and the salesman's bespoke odds table had **never done
anything**. Procedural bosses were exactly as rare as wild encounters.

`PCemRollBoss` had a second instance of the same class: `ld b, 60` followed by
`farcall PCRollMonClass` handed the callee `b = BANK(PCRollMonClass) = 5` as its rarity bump.

**Fix pattern, now the house rule:** give any cross-bank routine that takes or returns a value in
`a`/`bc` a `*Far` wrapper that moves the value through `d`/`e`.
`Random_Pokemon_Selection_Far`, `Random_Pokemon_Selection_Any_Far` (class in `e`),
`PCRollMonClassFar` (bump in `e`, class out in `e`) and `RogueClassifySpeciesFar`
(species in `e`, class out in `e`) are the four added here.

### Second bug fixed: cross-bank raw data read (instance #8)

`PCTraderSuperNerdSetup` (`scripts/IndigoPlateauLobby.asm`, bank `$06`) did
`ld hl, pokemon_classes` / `ld a, [hli]` - but that table lives at `2f:616d`. With bank `$06`
mapped it scanned whatever bytes sat at `$616d` in bank `$06`, classifying every trade offer
against garbage, in an unbounded loop. Replaced with `farcall RogueClassifySpeciesFar`.

The duplicated tier-constant block (`scripts/IndigoPlateauLobby.asm`, a verbatim copy of
`rarity.asm`'s EQUs) was deleted with it.

### Unbiased rolls

The shared `RogueRollSpeciesInList` now uses `Rangerandom` (`home/random.asm`), which
rejection-samples. The two formulas it replaces were both biased and disagreed with each other:
the reward path divided by 255, the trainer path by 256 - the latter making the last base species
of every trainer tier unreachable. `Rangerandom`'s own header documents the bias as ~17% relative
at c=40. **Expect `make smoke` to drift**; that is this change, not a regression.

### Phase 1e/1f addendum (same day): RoomPC TOGGLES entry + reward menu cleanup

Completed the handoff from `PHASE_1EF_SPEC.md`. Measured on the debug build.

| Region | After 1a-1d | After 1e/1f | Delta |
|---|---:|---:|---:|
| ROMX total used | 673,706 | 673,299 | **-407** |
| Bank `$14` (reward menu) free | 334 | **1,007** | **+673** |
| Bank `$2D` (RoomPC) free | 5,088 (pre-project baseline) | **4,795** | -293 (TOGGLES entry + RogueGroupToggleMenu) |

Net effect: deleting the vanilla Game Corner leftovers (`data/events/prizes.asm`,
`engine/events/prize_menu.asm`) recovered far more than the new RoomPC menu cost, so total ROM
usage went DOWN despite adding a feature.

**Bug fixed in `custom_functions/room_pc.asm` while inserting TOGGLES, unrelated to this task:**
the `.notDecorations` dispatch checked only `wNumHoFTeams` (zero/nonzero) to decide whether to open
the Hall of Fame, never the actual `hCurrentMenuItem`. With a Hall of Fame entry present, selecting
LOG OFF (the item immediately after HALL OF FAME) fell into the same branch and silently reopened
the Hall of Fame instead of logging off. Consistent with [[project_room_decoration_system]]'s note
that this file has had zero in-emulator testing. Fixed by re-reading `hCurrentMenuItem` after the
`wNumHoFTeams` check and testing `ROOM_PC_HOF` explicitly before falling through to LOG OFF.

**Extra cleanup beyond the approved delete list:** `RewardRoomBagIsFullText` in
`rogue_reward_menu.asm` became orphaned the moment its only caller, `.bagFull`, was deleted (grep
confirmed zero other references). Removed it too rather than leave freshly-created dead code.

**Not touched, left for a future pass:** `HandleRewardChoice`'s `.getMonName` label has no incoming
jump (pre-existing, not introduced by this work) - same shape as the `.normal` label that WAS
deleted, but out of scope since it wasn't on the audited list and isn't a byproduct of this change.

### Phase 2 step 1 addendum (same day): species-ID reclamation, and ROM0 recovered 23 bytes

Reclaimed 8 species index slots, taking the usable total from 94 to **102** free IDs.

| Region | Before | After | Delta |
|---|---:|---:|---:|
| **ROM0** | **4 free** | **46 free** | **+42** |
| ROMX total used | 673,299 | 671,729 | **-1,570** |
| Free species IDs | 94 | **102** | +8 |

**The ROM0 gain is the headline.** HOME had been sitting at 4 bytes - this Bible calls it "as tight
as WRAM0" - and is now at 46. It came from deleting HOME-resident code: the pseudo-mon special-cases
in `GetMonHeader` (`home/pokemon.asm`, including the whole now-unreachable `.specialID` block) and
the `FOSSIL_KABUTOPS` branch in the pic bank chain (`home/pics.asm`).

The ROM0 gain is the notable one - HOME had been sitting at 4 bytes, which this Bible calls "as
tight as WRAM0". It came from deleting the two fossil special-cases in `GetMonHeader`
(`home/pokemon.asm`) and the `FOSSIL_KABUTOPS` branch in the pic bank chain (`home/pics.asm`), both
of which live in HOME.

**What was reclaimed:**
- 5 already-dead placeholder `DEF`s (`PLACEHOLDER_POKEBALL $20`, `PLACHOLDER_GREATBALL $32`,
  `PLACEHOLDER_ULTRABALL $34`, `PLACEHOLDER_MASTERBALL $38`, `PLACEHOLDER_LEGENDARY $3D`) - each had
  exactly one reference tree-wide, its own definition.
- `FOSSIL_KABUTOPS $B6` and `FOSSIL_AERODACTYL $B7`, plus their now-orphaned `.pic` data in
  `gfx/pics.asm` and the Pewter Museum hidden-event handlers.

- `MON_GHOST $B8`, together with the **entire vanilla unidentified-ghost feature**.

**The MON_GHOST reachability analysis, because the first pass got it half wrong.** Static analysis
said it was live: `IsGhostBattle` (`engine/battle/core.asm`) fires on any `POKEMON_TOWER_*` map, and
`POKEMON_TOWER_2F`/`7F` *are* live stages in `custom_functions/random_stage_selection.asm`. That much
is true. What it missed is that the gimmick gates on the player **lacking** a `SILPH_SCOPE` - and the
only Silph Scope in the game is the Rocket Hideout B4F ball, which `data/maps/toggleable_objects.asm`
ships toggled **OFF**. The condition was therefore permanently true, the feature could never resolve
into anything useful, and it was a latent oddity waiting to fire on a tower stage rather than a
feature worth preserving.

**Lesson, and it cuts both ways:** for a vanilla feature, "unused" means unreachable from the ROGUE
STAGE POOL - check `random_stage_selection.asm` first, not the overworld you remember. But also check
the feature's *own* gating items and events, because Red Rogue disables a great deal of vanilla item
and event plumbing (see `feedback_audit_dead_features_before_relocating`); a check that looks live
can be permanently stuck one way.

**Removed as one coherent feature**, not a dangling constant: the `.isGhost` render block in
`InitWildBattle`, the whole Pokémon Tower branch of `PrintBeginningBattleText` (Silph Scope test,
ghost text, Marowak reveal), both uncatchable-ghost checks in the Poké Ball capture path
(`engine/items/item_effects.asm`), `engine/battle/ghost_marowak_anim.asm` plus its `main.asm`
include, `GhostPic` and `gfx/battle/ghost.pic`, and three orphaned text wrappers
(`EnemyAppearedText`, `UnveiledGhostText`, `GhostCantBeIDdText`).

`IsGhostBattle` is deliberately **kept as a stub that always reports a normal battle**. Three callers
test its Z flag (`TryRunningFromBattle`, `PrintGhostText`, and the Poké Ball path); returning NZ makes
every one take its ordinary branch with no further edits. A tower encounter now shows the actual mon
instead of an uncatchable GHOST placeholder - strictly better roguelike behaviour, and a safe failure
mode if the reachability analysis was ever wrong.

### Phase 2 steps 2 + 6 (same day): GetName fix, and the pic system rework came out FREE

| Region | After step 1 | After steps 2+6 | Delta |
|---|---:|---:|---:|
| **ROM0** | 46 free | **73 free** | **+27** |
| ROMX used | 671,729 | 671,729 | **0** |
| WRAM0 | 1 free | 1 free | **0** |

**Step 2 - the `GetName` HM01 bug (cost 10 B of ROM0).** Vanilla ran `cp HM01 / jp nc, GetMachineName`
BEFORE dispatching on `wNameListType`, and its own comment flagged it: the test hijacked *every* list,
so any Pokemon, move or trainer index >= `$C4` came back as "TM07". Three ASSERTs existed only to keep
those lists under the threshold, and the Pokemon one capped `NUM_POKEMON_INDEXES` at 195 - a hard wall
for the species expansion. Fixed by gating the test on `ITEM_NAME`, which is the only list that
actually needs it. Tail-call semantics preserved. All three ASSERTs dropped.

**Step 6 - pic system rework, at ZERO cost, and it GAVE BACK 37 bytes of ROM0.** pret's "Improve the
Pokemon picture system" adds a per-species pic-bank byte; the wiki assumes that grows `BASE_DATA_SIZE`.
**It does not have to.** The struct already ended in an unnamed `rb_skip`, and every one of the 151
base_stats files was already emitting that byte as `db 0 ; padding` (Mew's as `%11111111`). Naming it
`BASE_PIC_BANK`, and naming the matching `ds 1` at the end of `wMonHeader` as `wMonHPicBank`, costs
**no ROM and no WRAM** - `BASE_DATA_SIZE` stays 28 and `wMonHeader` stays the same size. Deleting the
old hardcoded compare chain in `UncompressMonSprite` then returned 37 bytes of HOME.

**Why it mattered:** that chain had no upper bound - anything at or above index `$BF` fell through to
`BANK("Pics 5")` regardless of where its pic actually lived. Pics can now live in any bank, and a
Phase 2R form override just patches `wMonHPicBank` alongside the pic pointers, so form sprites need no
special case.

Verified by measurement, not assumption: read `BASE_PIC_BANK` straight out of the built ROM for a
species in each of the five pic banks plus Mew's separate `MewBaseStats`, and compared against the
actual bank of each `*PicFront` symbol in the `.sym` - all matched. Separately confirmed all 151 files
have a `BANK()` argument identical to their own `dw *PicFront` line.

`func_fusion.asm`'s `MergeFusionBackPic` was audited and is safe - it calls `GetMonHeader` for the
secondary species before `UncompressMonSprite`, so the bank and pic pointers now come from the same
header.

### ROM0 journey this session

`4 free -> 46 (step 1, pseudo-mon + ghost removal) -> 36 (step 2 cost 10) -> 73 (step 6 freed 37)`.
HOME went from effectively exhausted to genuinely comfortable.

---

Two structural gotchas handled while removing the fossils, worth remembering:
- `DisplayMonFrontSpriteInBox` (in `museum_fossils.asm`) is **shared** with
  `route_15_binoculars.asm`, and ROUTE_15 *is* a live stage. The helper stays; only the two fossil
  handlers were removed.
- `data/text_predef_pointers.asm` is a **positional** table - deleting a `tx_pre` entry renumbers
  every id after it. The two fossil text labels were kept for exactly this reason.
- `HiddenEventMaps` / `HiddenEventPointers` are generated from one shared list by a `FOR` loop, so
  removing a map's `hidden_event_map` line keeps both halves in sync automatically.


## 2026-09-02 witch-system relocation out of Battle Core and Maps 2

Phase 1 of the witch challenge/prize expansion: move the witch's battle hooks out of `Battle Core`
(bank `$0F`) and its lobby roll out of `Maps 2` (bank `$06`) BEFORE spending that space on new
features. Pure relocation, no behaviour change intended. All three ROMs build clean.

**Measured, debug build (the binding target), before -> after:**

| Bank | Section | Free before | Free after |
|---|---|---:|---:|
| `$0F` | `Battle Core` | **17** | **199** |
| `$2F` | `rogue` | 3,226 | 2,810 |
| `$06` | `Maps 2` (section size) | `$22F5` / 8,949 B | `$223E` / 8,766 B |

- **Moved to `custom_functions/witch_battle_effects.asm`:** `HandleTurnLimitDrain` + `TurnLimitDrainText`
  (~105 B), `WitchInitTurnLimit` (the `StartBattle` turn-limit init block, ~32 B), and
  `WitchApplyMoneyEffects` (the `TrainerBattleVictory` no-money/double-money block, ~27 B). Each call
  site became one `farcall`; all consume only flags or nothing, and `Bankswitch` preserves flags.
- **`HandleTurnLimitDrain`'s one same-bank dependency,** the non-exported core.asm local
  `UpdateCurMonHPBar`, is **inlined** at the new site rather than exported. The `hWhoseTurn` branch is
  kept verbatim so bar selection is unchanged. (Separate pre-existing question, deliberately not
  touched: on the player-moves-first path `hWhoseTurn` is still 1 there, so the enemy's bar is drawn
  from the player's HP values.)
- **Bug fixed by the move (unavoidable, not optional):** the routine's faint check was
  `ld a,[wBattleMonHP]` / `or [hl]` with a comment claiming `hl` was `wBattleMonHP + 1`
  "after UpdateCurMonHPBar". It was not — that routine overwrites `hl` with an `hlcoord` before its
  predef and never restores it, so the `or` folded in a tilemap byte. Tile IDs are almost never 0, so
  the routine almost always returned NZ and its callers almost never saw the drain KO. Now reads both
  HP bytes explicitly, matching `HandleRecoilChallenge`.
- **`jr` range:** after inlining, all four of `HandleTurnLimitDrain`'s entry gates exceeded the
  128-byte `jr` range to `.noEffect` and had to become `jp`. Same class of thing the `$0E` note below
  records for `ai_damage.asm`; expect it whenever a relocated routine grows.
- **`PCWitchSetup` + `RollLobbyNPCAppearance`** moved to a new `custom_functions/witch_setup.asm` in
  the `rogue` section. `PCWitchSetup` needed `::` (its only caller is in `maps.asm`, a different
  object file, reaching it by `farcall`). Its `farcall HasMasterballClassMon` became a plain `call` —
  both are in `$2F` now.
- **`Maps 2` is a FLOATING section, so per-bank `TOTAL EMPTY` is the wrong metric for it.** Bank `$06`
  free went *down* (79 -> 71) because rgblink first-fit immediately backfilled the freed 183 bytes
  with `ProceduralCemeteryGen` (in from `$08`), while `ProceduralFacilityGen` went `$06 -> $08`,
  `Daycare Upgrade` `$06 -> $07`, `Pick Up Item` `$0B -> $08`, `Self-Target Stat Penalty` `$08 -> $0A`,
  `Stat Penalty Functions` `$07 -> $08`. The real result is that `Maps 2` itself shrank 183 bytes and
  can grow against 119,024 bytes of total free ROM. Measure the *section size*, not the bank tail.
### DEFERRED OPTION: two more Battle Core reclamation candidates (~28 B), not taken 2026-09-02

Available whenever bank `$0F` next runs short. Not done in the 2026-09-02 pass only because 199 free
bytes already exceeded what the remaining witch work needed, and it is the one part of that pass with
a runtime cost worth weighing.

- **The candidates:** the witch crit-boost block inside `CriticalHitTest` and the accuracy-boost block
  inside `MoveHitTest` (`engine/battle/core.asm`). Each is ~26 B and would collapse to a `farcall` into
  `custom_functions/witch_battle_effects.asm` alongside the three routines already moved there.
- **Register trap — the reason this is not a copy-paste of the other three.** Both blocks transform a
  threshold held in **`b`**, and **`b` cannot cross a `farcall`**: `Bankswitch` clobbers
  `a`/`b`/`c`/`h`/`l` before the callee runs, and only `d`/`e` survive. Each site therefore becomes
  `ld e, b` / `farcall Witch…` / `ld b, e`, with the routine taking its input and returning its result
  in `e`. That is 12 B replacing ~26, so the net is **~14 B per site, ~28 B total** — noticeably worse
  than the ~105/32/27 B the other three returned.
- **Runtime cost to weigh:** unlike the three already moved (once per turn, once per battle, once per
  victory), these two sit in per-attack paths. Two extra bank switches per attack is almost certainly
  imperceptible given the 2026-08-27 hardware finding that full AI move selection is not perceptible,
  but it is a real cost against a small gain, which is why it was left as a choice rather than done.
- **Also still available in `$0F`:** the paused `NoScratchText` feature (see the 2026-09-02 entry at
  the top of this file) needed exactly 1 byte it could not find in the debug build. The 199 bytes freed
  by the relocation pass unblock it whenever someone wants to flip its three `IF 0` guards.

**Smoke suite:** `test_procedural_forest_generation` and `test_procedural_cemetery_generation` fail on
this change. **This is a harness bug, not a ROM regression** — confirmed by walking into a forest
wild-area door in BGB on the affected ROM (warped in and out cleanly), and by a full `.sym` diff
showing every wild-area symbol at a byte-identical address in both builds. Root cause: the lobby exit
warp is RNG-positioned and shifting `Battle Core` moves the RNG stream, while
`preload_and_enter_wild_area` hardcodes a fixed up/down approach to the door. Written up for Codex in
`SMOKE_HARNESS_WILD_AREA_ENTRY_ISSUE_2026-09-02.md`.

### Phase 2 addendum (same day): run-scoped event block at ZERO cost

Witch expansion Phase 2 needed persistent, new-game-zeroed, blackout-wiped run state (4 earned
stat-boost bits, 4 permanent witch-prize bits, plus `VICTORY_ROAD_CLEARED`). It cost **0 bytes** of
WRAM, ROM0, and `wEventFlags`.

- **Technique: alias dead event bits, do not add them.** `constants/event_constants.asm` now defines
  `ROGUE_RUN_EVENTS_*` as `DEF x EQU EVENT_BEAT_ROUTE_17_TRAINER_0 - 1 + n`. Route 17 is unreachable
  (commented out of `RogueStageMapTable`; only reachable from Routes 16/18, themselves not stages), so
  its ten trainer bits are dead. **`NUM_EVENTS` stays `$A3F`, `wEventFlags` stays 328 bytes, WRAM0
  stays at its 1 free byte, HRAM at 0, and there is no save-format change.**
- **Why alias rather than delete/renumber:** `scripts/Route17.asm` is still assembled and uses those
  consts in five `trainer` macros under `def_trainers 1`, which hard-asserts each bit position.
  Deleting breaks the build; renumbering shifts every downstream event. `DEF … EQU` does neither.
- **Byte alignment was chosen deliberately:** `$4D0 % 8 == 0`, so the eight boost/prize bits are
  exactly `wEventFlags` byte 154 and can be read in one `ld a, [wEventFlags + (EVENT_… / 8)]`. The
  blackout wipe is then two whole-byte zeroes rather than nine `res`es, safe because byte 154 is
  entirely Route 17 bits and byte 155 is Route 17 bits plus the padding before Route 18's
  `const_next $4E0`.
- **The hazard, recorded in three places** (the const block, the commented-out `db ROUTE_17` line in
  `RogueStageMapTable`, and here): re-enabling Route 17 as a stage silently collides. There is no
  compile-time warning. Give it fresh events first.
- **Generalisable:** Route 16/18/19/21 and Victory Road 2F/3F are similarly unreachable and hold dozens
  more dead bits plus real ROM. Untouched here; see §8 as a future reclamation target.
- Cost in bank `$2F`: ~66 bytes (blackout wipe + finale gating). `$2F` debug free 2,810 -> 2,744.
- **`jr` range, again:** the new finale check's `jr nz, .hideWitch` overflowed to 167 bytes and had to
  become `jp`. Second time in one session — assume any gate added near the top of a grown routine will
  need this.

### Phase 3/4 addendum: Battle Core spend, and a bank constraint the plan got wrong

Witch challenges 14-18 and prizes 7-10. Debug-build free space `$0F` 199 -> **86**, `$06` (Maps 2,
floating) 36 -> 8, `$03` 112 -> 86, `$2C` 1976 -> 1959, `$2F` 2645 -> 2573. WRAM0 still 1 byte.

- **Challenges 14/16/17 cost ZERO Battle Core bytes**, as designed: they dispatch from inside
  `HandlePostPlayerMoveWitchEffects` (the renamed `HandleRecoilChallenge`) in the rogue bank, and the
  two `core.asm` call sites are unchanged farcalls consuming only the returned Z flag. This is the
  pattern to copy for any future "do something to the player's mon after its move" effect.
- **Challenge 15** hooks `ItemUseMedicine` (bank `$03`) via a farcalled carry-returning predicate;
  **challenge 18** is fully inline in `decrement_pp.asm` (bank `$2C`) with no farcall at all.
### 2026-09-02 correction: witch run-state left the event array

The ROGUE_RUN_EVENTS alias block described in the Phase 2 addendum above was **reduced to a single
bit**. The earned stat boosts and the permanent witch prizes were aliased onto Route 17's dead event
bits; on review that was the wrong home - they are ordinary run state, not events. They now live in
`wEarnedStatBoosts` (1 byte) and `wWitchPrizesEarned` (2 bytes) in `ram/wram.asm`, inside
`wGameProgressFlags` so they save and zero on new game. The 3 bytes came out of the dead `ds` pad
below `wGameProgressFlagsEnd` (`ds 8` -> `ds 5`), so **WRAM0 is still net-zero at 1 free byte** and
the only cost is the usual save-format shift.

`EVENT_VICTORY_ROAD_CLEARED` remains an aliased event (on `EVENT_BEAT_ROUTE_17_TRAINER_7`) because it
IS a milestone. The Route 17 collision warning still applies to that one bit, and is still recorded in
all three places.

Takeaway for future work: the alias-a-dead-event-bit trick is free and correct **for milestones**.
Reach for the `ds` pad instead when the thing you are storing is state a system reads and writes, not
an event that happened.

### 2026-09-03 post-move witch penalties now fire on a killing blow

Symptom reported: CHALLENGE_SAME_MOVE_PENALTY (14) "wasn't working". It was working; the seam was
simply being **skipped whenever the player's move KO'd the enemy**, which in real play is exactly when
you notice - spamming one move usually means the second use is the kill. Measured with a throwaway
PyBoy probe (hooks on `HandlePostPlayerMoveWitchEffects`, `.sameMovePenalty`, `ApplyWitchSelfDamage`):
a bulky enemy gave `seam+1 dmg+1 -28 HP` per repeat, a one-shot enemy gave `seam+0` - the hook never
ran.

Cause: `MainInBattleLoop` checked the enemy faint first and jumped away before the farcall:
`ld a, b / and a / jp z, HandleEnemyMonFainted / farcall HandlePostPlayerMoveWitchEffects`.

Fix (both full-turn paths): the seam now runs BEFORE the enemy-faint check, with the enemy-faint
result stashed across it as `push af` / `pop af`. This matches **vanilla**, where `RecoilEffect_` fires
inside move execution and so already hurts you on a killing blow. Enemy faint keeps priority
afterwards, also matching vanilla - and that is safe because `HandleEnemyMonFainted` already copes
with a simultaneously-dead player mon (`AnyPartyAlive`/`TryKODefiance` -> blackout at its top, and a
`wBattleMonHP == 0` test -> `ChooseNextMon` further down). Affects challenges 12, 14, 16 and 17
together, since all four share the seam.

- Cost: +6 bytes per site, +12 total in bank `$0F`.
- **`jr` range struck a fifth time**: the inserted bytes pushed `jr c, .playerMovesFirst` (the
  turn-order coin flip ~130 bytes up) out of range. Converted to `jp`. Assume any edit that grows
  `MainInBattleLoop` will do this again.
- Stack discipline verified by hand: 2 `push af`, 4 `pop af` in the region - each push has two
  mutually exclusive exits, each popping exactly once, and the `ret nz` escape check sits before the
  push.
- **Challenge 12 is NOT vanilla code.** It never was. Vanilla's `RecoilEffect_`
  (`engine/battle/move_effects/recoil.asm`) still serves the real recoil moves (Take Down,
  Double-Edge, Struggle) and is untouched by any of this; the challenge only copies its HP-subtract
  and overkill-clamp arithmetic.

### CUT CANDIDATE: witch PRIZE_RESIST_SUPER (`RogueWitchResistSuperEffective`), bank `$0F`

**~59 bytes, self-contained, safe to delete if `$0F` gets tight.** It is one witch prize (incoming
super-effective damage x3/4) and nothing else depends on it. To cut: delete the routine, revert the
hook at `AdjustDamageForMoveType`'s `.done` to a plain `farcall RoguePrismDamageBoost` (restoring that
routine's own `ldh a, [hWhoseTurn]` / `and a` / `ret nz` opener), drop `PRIZE_RESIST_SUPER` from the
prize table, and renumber. `TypeMatchupScan` must STAY - `PreviewTypeMatchup` uses it.

Already optimised once, 2026-09-02, from ~113 bytes to ~59:
- **Shared the TypeEffects walk.** Factored `PreviewTypeMatchup`'s loop into `TypeMatchupScan`
  (b = attacking type, d/e = defender types, c = seed -> c = twentieths) so both callers use one copy.
  ~42 bytes. Any future type-matchup code in bank `$0F` should call this rather than add a third walk.
- **Dropped Multiply/Divide for shifts.** `wDamage -= wDamage / 4` instead of `(wDamage * 3) / 4`:
  ~12 bytes, two fewer HOME calls, and it leaves `hMultiplicand`/`hProduct` untouched. Truncation
  differs by at most 1 and always in the player's favour.

- **PLAN ERROR WORTH RECORDING - prize 8 could not be free.** The plan had
  `RogueWitchResistSuperEffective` living in the rogue bank and falling through from
  `RoguePrismDamageBoost`, for "zero new bytes in Battle Core". Impossible: it must scan
  `TypeEffects`, which is **bank `$0F` data**, and a `ld hl, TypeEffects` / `[hli]` loop executing
  from `$2F` reads whatever is mapped there - the cross-bank read bug class. `AIGetTypeEffectiveness`
  was evaluated as a free substitute and rejected: it `ret z`s on the FIRST matching type pair, so a
  0.5x/2x dual type reads as 0.5x and genuine super-effective hits are missed. The routine therefore
  lives in `$0F` (~113 bytes) with the whose-turn branch moved to the hook site. **General rule: a
  routine that scans a ROM table can only live in that table's bank.** Check the data's bank before
  planning a routine's home, not just the routine's callers.
- **`jr` range bit four times across these phases** (`HandleTurnLimitDrain` x4 gates, the finale
  check, `ItemUseMedicine`'s softboiled retry). Any gate added near the top of a routine that has
  grown will overflow; convert to `jp` rather than restructuring.
- **Badges no longer grant stat boosts.** `ApplyBadgeStatBoosts`/`ApplySingleBadgeStatBoost` are
  renamed `ApplyEarnedStatBoosts`/`ApplySingleEarnedStatBoost` and read the ROGUE_RUN_EVENTS
  earned-boost byte (contiguous bits 0-3) instead of `wObtainedBadges` (even bits 0/2/4/6). Both
  loops got smaller as a result. Five call sites. The smoke test that exercises this was updated to
  derive the byte from `EVENT_BEAT_ROUTE_17_TRAINER_0 - 1` and now also sets `wObtainedBadges = $FF`
  as a regression guard.

**Stale figure corrected:** §1's bank table lists the `rogue` section in bank `$12` with 6,084 free.
It actually links into **`$2F`**; bank `$12` has 117 free. The table row for `$2F` ("floating linker
allocation in snapshot") is the one that matters for rogue-bank work.

## 2026-09-02 NoScratchText miss-text feature - paused, 1 byte short in _DEBUG

KEP-hack import (`KEP_IMPORT_PLAN.md`, Part B): change "attack missed!" to "…'s attack didn't leave a
scratch!" when a 2-3 damage move rounds to 0 damage at 0.25x effectiveness
(`AdjustDamageForMoveType`, `engine/battle/core.asm`). Implementation overloads `wMoveMissed` with a
new `MOVE_MISSED_NO_DAMAGE` value (no new WRAM byte) and adds a branch plus a `NoScratchText` far-text
stub to `PrintMoveFailureText`, both in the `Battle Core` section, ROMX bank `$0F`.

- **Cost is a hard floor of 18 bytes, not a starting estimate.** Tried three implementations: (1) a
  dedicated `wMoveMissed` value with its own load+compare, (2) reusing `wCriticalHitOrOHKO`'s existing
  load in `PrintMoveFailureText` with a second sentinel value, (3) a shared single write feeding both
  variables. All three landed at exactly 18 bytes total once the write (in `AdjustDamageForMoveType`),
  the read+branch (in `PrintMoveFailureText`), and the fixed 5-byte `text_far`/`text_end` stub are
  summed - reusing a register/variable saves bytes in one function only by costing the same bytes in
  the other. A 3-way text dispatch (default + 2 special cases) also has a minimum of exactly 1 extra
  `jr` no matter how the branches are ordered, since only the last-checked branch can fall through for
  free.
- **Measured against the current baseline** (this checkout, post `9e5f7372`): `Battle Core` free space
  is `$0018` / 24 bytes in Red and Blue, `$0011` / 17 bytes in `_DEBUG`. 18 bytes fits Red/Blue with 6
  to spare but overflows `_DEBUG` by exactly 1 byte (`main.asm(585): Section "Battle Core" grew too
  big (max size = 0x4000 bytes, reached 0x4001)`) - the debug-build-binds-first pattern this Bible
  already documents.
- **Per user instruction, paused rather than scavenging a byte from unrelated code.** The four edits
  are in place but disabled via `IF 0` / `ENDC` in `engine/battle/core.asm` (the `PrintMoveFailureText`
  branch, the `NoScratchText` stub, and the `AdjustDamageForMoveType` write, which currently falls back
  to its original `inc a`), so all three ROMs build clean at today's baseline free space. The two `DEF
  MOVE_MISSED_*` constants in `constants/battle_constants.asm` and the `_NoScratchText::` string in
  `data/text/text_2.asm` (bank `$22`, `Text 3`, thousands of bytes free) are left live since they cost
  nothing while unreferenced.
- **Cheapest thing to cut if `Battle Core` ever needs exactly 1 byte back for something else**, since
  this feature is already sitting there disabled at zero cost - no action needed, it simply isn't
  compiled in. To resume this feature instead: find or free 1 byte in bank `$0F` first (or fold this
  into the Yellow-audio/Phase-1-scale HOME/ROM reclamation pass already planned in the shin-red-import
  plan, which may shuffle bank contents anyway), then flip the three `IF 0` guards to build the branch.
- Builds verified: `make` produces all three ROMs clean at this state. MD5s not recorded (unrelated
  concurrent AI-work commits/WIP are also present in this tree from another session; not a clean
  isolated baseline to fingerprint).

## 2026-09-01 first-conscious follower selection

Baseline clean `54a31adc` plus the uncommitted first-conscious follower adaptation.

- `FollowerResolveActiveSpecies` scans party HP in battle-selection order and returns the first conscious party member. Map preparation, eligibility, dialogue name, and cry all consume that shared result.
- `MapEntryAfterBattle` replaces its existing `DelayFrame` plus `IsPlayerStandingOnWarp` sequence with one size-neutral banked wrapper. The wrapper first honors the existing map-scope and persistent-toggle gates, then prepares a changed active follower, preserves the original delay/warp-check order, and reloads map sprites plus player graphics in normal overworld order before the first post-battle display frame. If the whole party is fainted, it clears slot 15 before that delay.
- HOME shrinks by 3 bytes because the original 11-byte delay plus farcall sequence becomes one 8-byte farcall. Fresh ROM0 free space is 25 bytes in Red/Blue and 5 bytes in Debug.
- No section moved banks and no RAM, VRAM, sprite-table, or object layout changed. The HOME caller and all cross-bank transfers use existing `farcall`/`farjp` contracts. The active selector and follower work remain in bank `$2F`.
- The first replacement attempt called menu-oriented `ReloadMapSpriteTilePatterns_`. That routine ends with `LoadFontTilePatterns_`; `vFont` aliases `vNPCSprites2`, so the font overwrote newly loaded player/follower animation tiles and produced the reported alternating letters and sprites after the lead fainted (~99% confident). `FollowerReloadMapSpritesAfterBattle` now performs the normal LCD-off `InitMapSprites`, LCD-on, `LoadPlayerSpriteGraphics`, `UpdateSprites` order without a font load.
- Nurse healing can make slot 1 conscious again. `AnimateHealingMachine` retains its existing hide/freeze lifecycle, then tail-calls `FollowerRefreshAfterHeal`. Because healing dialogue still owns the font at that point, the hook only republishes the selected identity; the standard textbox-close lifecycle performs the eventual map/player graphics reload. Bank `$1C` grows by 5 bytes and retains ample documented space; no healing OAM or timing data changes.
- `Follower Core` grows from `$06B2` / 1,714 bytes to `$0722` / 1,826 bytes at `$4000-$4721`, an increase of 112 bytes. Fresh bank `$2F` total free space is `$0DD2` / 3,538 bytes in Red/Blue and `$0C9A` / 3,226 bytes in Debug.
- Red, Blue, and Debug builds pass. MD5: Red `5C41DA74B1978F44DFC1D99E98C3B471`; Blue `05958CDAC106852D4B44DEE557215BEC`; Debug `6643191F73B1C8683188649C4705A468`.
- The focused follower suite passes 39 tests. It covers ordered HP scanning, replacement picture selection, all-fainted clearing, map/toggle guards, banked battle/healing reload wiring, and preserved HOME call order. Full visible battle-return and healing choreography remain user runtime gates.

## 2026-09-01 Yellow-style fainted-lead follower checkpoint

Pushed reference commit `54a31adc` (`Failed Fainted Pokemon System Follower + Bridge Updates + Debug Updates + Color Fixes`). This commit also contains intentional unrelated user work.

- `FollowerIsLeadAlive` applies Yellow's two-byte HP eligibility test to Red Rogue party slot 1. `FollowerCanFollow` also suppresses the follower while Red's `BIT_BATTLE_OVER_OR_BLACKOUT` is published, covering the ten-frame post-battle delay and map handoff that otherwise allowed visible flicker. `FollowerUpdate` hides the follower, resets movement status, and clears its queue while either condition rejects it; the ordinary update lifecycle respawns it after revival. Accepted-step production uses the same combined gate.
- No section moved banks, assembled file was added, RAM field changed, or call crossed a bank. All new calls and HP reads remain inside bank `$2F` `Follower Core`.
- `Follower Core` grows from `$0684` / 1,668 bytes to `$06B2` / 1,714 bytes at `$4000-$46B1`, an increase of 46 bytes. Fresh bank `$2F` free space is `$0E42` / 3,650 bytes in Red and Blue and `$0D77` / 3,447 bytes in Debug.
- Red, Blue, and Debug builds pass. MD5: Red `49450AE41998C63D665EC8C81C8CF1F6`; Blue `480D919668E1524203277F8C540AC2C9`; Debug `BA0FB10C0B4FAC623290A07B0640A44C`.
- The focused follower source/runtime suite passed 38 synthetic tests, including transition suppression, direct zero-HP hiding, queue clearing, and nonzero-HP respawn. Live BGB testing failed: the old follower remained in stale OAM for the first post-battle overworld frame before disappearing.
- This is intentionally retained as a failed visual reference, not an accepted implementation. Red Rogue's battle-return ordering differs from Yellow's global Pikachu flag/OAM lifecycle. The replacement is the separate first-conscious adaptation above.

## 2026-08-31 follower procedural coverage

Baseline `eb66c255` plus the procedural follower eligibility change. No new source file, assembled include, RAM field, section relocation, direct cross-bank read, or new call was introduced. The existing follower and procedural loader paths are reused.

- `Follower Core` remains in bank `$2F` and shrinks from `$068E` to `$0688` because six procedural map IDs were removed from the exclusion table.
- Fresh bank `$2F` free space is `$0E6C` in Red/Blue and `$0DA1` in Debug.
- Red, Blue, and Debug builds pass. MD5: Red `4927EC0B282081125B7FF45A800FDA15`; Blue `272F6429D656496C159C37B7C216A5FF`; Debug `9D9065E7ECEBC1531965A6E2D4F4EF66`.
- Focused follower suite: 38 tests pass with two documented expected failures. Runtime coverage enters Cave/Forest through the production wild-area preload, retains the dynamic boss picture and authored object graphics, assigns the follower base 2, and covers Cemetery 1-4. BGB visual acceptance remains pending.

## 2026-08-28 lobby tile-notepad conversion

Baseline `14f2f0cf` plus existing user WIP, with successful Red/Blue/Debug builds before and after this scoped conversion. User art/build/audio/palette work is preserved and included in both baselines. No section relocation, assembled INCLUDE change, or RAM-layout change.

- `Maps 2` stays in bank `$06`: Red/Blue `$4E55-$7152`, size `$22FE` (8,958), becomes `$4E55-$7141`, size `$22ED` (8,941). Debug `$4E55-$715A`, size `$2306` (8,966), becomes `$4E55-$7149`, size `$22F5` (8,949). Net saving: 17 bytes in every target.
- Bank `$06` free: Red/Blue 63 -> 80, Debug 80 -> 97; minimum 63 -> 80. No section changes banks. Only `Maps 2` changes size versus the captured user-WIP baseline.
- Bank `$03` toggle table remains size-neutral. The old door-2 toggle row is retained as object 0/OFF to preserve global saved indices. Bank `$03` free remains 3/3/64 across Red/Blue/Debug, minimum 3.
- Caller audit: new plain call to `Lobby_IsDoor2Blocked` stays inside `Maps 2`; reused sign text pointers and handlers stay in that same section/bank. Removed two sign object records and old ShowObject/HideObject calls; added two ordinary background events. Text IDs 12/13 and service object IDs 1..11 are unchanged. No new farcall, BANK assumption, pointer-table crossing, section fallthrough, or inline bank switch. Existing helper may clobber BC, but its new caller is the map script, not a live text-assembly cursor.
- Open block `$08` retains the user's notepad artwork; blocked block `$0C` remains a wall. `wNumSigns` is refreshed to 1/2 before the entry guard. Existing text handlers are unchanged; no blocked-door message is added.
- All three ROMs build and remain 1 MiB. Linked bytes verify both background events and object count 11. Focused suite: 38 tests, 37 pass plus the explicitly expected old full-sheet capacity failure. Source and linked-data checks are not visual/runtime acceptance.
- Pending user checks: both notepads when open; no interaction at blocked door 2; route/gym/bridge/wild/mini-boss/finale text; battle/menu/Continue/entry refresh; all NPC services; DMG/CGB artwork and collision. See `FOLLOWER_CHECKPOINT_2026-08-28_NOTEPADS.md`.


**2026-08-25 Yume Task 4 palette follow-up:** forced Red, Blue, and Debug builds pass after adding the dedicated Bill's PC palette path. The previously unreferenced `PAL_26` slot was repurposed size-neutrally as `PAL_BILLS_PC`; bank `$1C` retains `$0003` bytes. The fixed CGB attribute map is at `$2A:$45E0-$482F`, size `$0250` = 592 bytes, leaving bank `$2A` with `$1019` = 4,121 bytes. `Bill's PC` is now `$2E:$6AD3-$7466`, size `$0994` = 2,452 bytes, leaving `$0B99` = 2,969 bytes. Its ROM packets are copied to existing WRAM scratch before the palette-bank farcall, so no direct cross-bank data read or RAM-layout change was introduced. CGB/SGB visual acceptance remains pending.

**2026-08-25 Yume grid-storage Task 4 measurement:** Task 4 is committed as `6a2d5335` and was reverified at current source `bfda98ab` plus the icon and PP display fixes. `Bill's PC` moved as one coupled code/data/Cable Club unit from bank `$08` to pinned bank `$2E`; the fresh section is `$2E:$6AD3-$7414`, size `$0942` = 2,370 bytes, with `BillsPC_` at `$2E:$6BCC`. Bank `$2E` retains `$0BEB` = 3,051 bytes in Red, Blue, and Debug. Removing the old placement leaves bank `$08` with `$016A/$016A/$00CD` free. The bank-crossing icon lookup now reloads the species inside bank `$1C` and returns the category in `e`; direct/generic PC callers remain bank-aware. Forced Red, Blue, and Debug builds pass. ROM0 has 29/29/9 bytes free; WRAM0 remains 1 byte free and HRAM remains full. User runtime acceptance of icons and storage operations remains pending.

**Status:** Canonical ROM capacity, bank-placement, and relocation reference for Red Rogue.
**Companion docs:** `WRAM_BIBLE.md` owns WRAM/HRAM/SRAM. `VRAM_BIBLE.md` owns VRAM and CGB hardware resources.
**Created:** 2026-08-23.

> **The central ROM rule:** total free ROM does not solve a bank overflow. A fixed ROMX section must fit wholly within its assigned 16 KiB bank, and direct calls/data references must remain in-bank unless they use an established bank-aware mechanism.

---

## 0. Ground truth and freshness

**2026-08-27 Narrow double-speed wrap around AI move selection COMPLETE. Hardware testing
answered a BIGGER question than the wrap itself: the AI decision cost is not perceptible on any
platform, with or without it.** User tested real GBC and real Super Game Boy at `wBattleCount = 70`
(guaranteed T3) - no noticeable slowdown on either. SGB has no CGB hardware at all (`hGBC` reads 0,
`SetCPUSpeed` is a hard no-op), so this cannot be the double-speed wrap masking anything; it proves
the underlying single-speed cost (section 0's scoreboard, ~114-236ms worst case) is simply not
perceptible inside real battle pacing. See `AI_PERF_INVESTIGATION.md`'s new top section for the full
account - the wrap and the `_Divide` fix remain worth keeping (real engine-wide speedup, real ROM
space freed), but "still over the frame budget" is no longer an open player-facing problem.

`engine/battle/trainer_ai.asm`'s `AIEnemyTrainerChooseMoves`: `predef SetCPUSpeed` at
entry, `predef SingleCPUSpeed` before each of its exactly two `ret`s. Cost: 15 bytes, bank `$0E`
228 -> 213. Battle forces single speed at init (`init_battle_variables.asm:2`,
`predef SingleCPUSpeed ; battle transitions have known double-speed visual faults`) for a rendering
reason that does not apply to move selection, which renders nothing - exact precedent is
`engine/battle/experience.asm`'s existing `SetCPUSpeed`/`SingleCPUSpeed` wrap around the EXP
calculation. `predef` preserves `bc`/`de`/`hl` (`GetPredefPointer`/`GetPredefRegisters`), so this is
safe around the `hl` this routine returns. `SetCPUSpeed` honours the player's 60 FPS option, so with
it off both calls are no-ops.

**Cannot be verified in PyBoy - a real emulator bug, not a bug in this change (see
`pending_contracts.json` and `PYBOY_HARNESS_REFERENCE.md`).** `core/mb.py:619` writes the FULL byte
on any `$FF4D` write, but hardware's bit 7 (current speed) is read-only; PyBoy's `switch_speed()`
XORs `key1` on every switch regardless, so it reports "double" after both a single->double AND a
double->single transition and the ROM stops toggling after one round-trip. Confirmed by direct
`rKEY1` sampling: correct engage/respect-the-option behaviour observed at decision boundaries, but
99.8% of battle frames and 10/11 move animations read double afterward - a measurement artifact of
the emulator, not the ROM. All four gates green regardless (nothing about this bug can corrupt
game state, only the *measurement* of the restore). **User is confirming on real hardware/BGB.**
Full account, including a real pre-AI-overhaul baseline (max 0.88 frames / 14.7ms, confirming the
vanilla AI was always comfortably under budget), in `AI_PERF_INVESTIGATION.md` section 7.

**2026-08-27 `_Divide` optimisation COMPLETE AND VERIFIED - `AI_PERF_INVESTIGATION.md`'s recommended
fix, implemented.** `engine/math/multiply_divide.asm`'s `_Divide` (bank `$0D`) replaced wholesale:
the old repeated-subtraction routine (cost scaled with the QUOTIENT, ~9,760 cycles/call measured)
is now shift-subtract long division (8 bit-iterations per dividend byte, cost bounded and O(b)),
ported from polishedcrystal via yumepokered's *pre*-commit `_Divide` (the variable-length version,
deliberately NOT the always-4-byte `_DivAlt` Yume promoted in its place - see
`DIVIDE_OPTIMIZATION_SPEC.md` section 1 for why the 4-byte-only version would have silently
corrupted the ~19 Red Rogue call sites that pass `b != 4`).

**This bank was in a MUCH more precarious state than the last cached figure suggested** - the
2026-08-24 Yume math entry's "468 bytes free" was stale; measured immediately before this change,
bank `$0D` had only **`$000b` = 11 bytes free in Debug** (383 in Red/Blue). The new routine is
smaller than what it replaced: **`$003b` = 59 bytes free after** (431 in Red/Blue) - **freed exactly
48 bytes in every target**, confirmed by bisecting the exact delta with `git stash push` on just this
one file.

**Measured performance win** (tier 3, seed 17, Tauros vs Snorlax, DMG-mode PyBoy - see
`AI_PERF_INVESTIGATION.md` for the full methodology and pre-existing baseline):

| Metric | Before | After | Change |
|---|---:|---:|---:|
| `Divide` per call | 9,760 cycles | **3,564** | -63.5% |
| `CalculateDamage` (net of VBlank) | 32,331 | **13,697** | -57.6% |
| One damage sim (net) | 40,362 | **21,751** | -46.1% |
| Whole T3 AI decision, wall clock | 775,919 | **480,086** | -38.1% |
| **frames of wall clock** (budget 70,224 — see note) | **11.05** | **6.84** | |
| milliseconds at 60fps | ~184ms | **~114ms** | |

Real-battle `CalculateDamage` still costs the identical amount as the AI-simulator context after the
port (13,732 real vs 13,697 sim), exactly as before it - confirming the port changed nothing about
the routine's observable behaviour in either calling context, only its speed.

**Differential-tested against the OLD routine before shipping, not just argued correct**: ~5,472 real
`(b, divisor, dividend)` cases swept through the actual HOME `Divide` wrapper on both the pre- and
post-change ROM. **Zero quotient mismatches. Zero `hRemainder` mismatches at `b=4`** (the only
configuration any caller - `PayDayEffect_` - reads that output for). A genuine, EXPLAINED difference
was found and accepted: for `b<4`, the OLD routine's `hRemainder` output leaks whatever garbage sat
in the *unused* input bytes (proven with a planted `0xAA` marker that reappeared verbatim in the old
routine's output), which no caller in the codebase ever reads. See `DIVIDE_OPTIMIZATION_SPEC.md`
section 3 for the full sweep methodology, including a real harness bug found and worked around along
the way: `call_routine`'s ROM0-target code path returns to `0x3FFF`, which is genuine ROM padding
(`$FF` = `RST 38`) in this build - unwinding into it runs unrelated real game code. Never previously
exercised, because every existing `call_routine` usage in this project targets a ROMX routine (which
routes through `Bankswitch`'s own internal `.Return`, a real ROM0 address, before ever reaching
`0x3FFF`). Worked around for testing by hooking a result directly rather than trusting any return
path; not a fix to `harness.py` itself (Codex-owned), just a documented gotcha for the next person.

**`make smoke`'s `test_fight2_seed17_party_generation_golden` rebaselined, exactly as
`DIVIDE_OPTIMIZATION_SPEC.md` anticipated** - `Divide` runs constantly during roster-build (damage
calc paths aside, `_AddPartyMon`'s own stat calculation divides), and this project's RNG-adjacent
timing is cycle-sensitive, so a cycle-count change this large across virtually all game logic was
expected to shift the seeded stream. Bisected via `git stash push -- engine/math/multiply_divide.asm
tools/pyboy_smoke/test_smoke.py` (passes with the OLD routine at HEAD, differs only with the port
applied); verified the new party is not corrupted (all 12 slots across both sides: real species, sane
levels, `HP == MaxHP`). All four gates green: `make` clean on all three ROMs, `make smoke` 34/34,
`make ai_scenarios` 56/56 (unchanged - a pure speed optimisation cannot and did not change any AI
decision), `make integration` clean.

**Frame-budget note, corrected 2026-08-27:** the AI's budget is **70,224 cycles (single speed)**,
NOT 140,448. `engine/battle/init_battle_variables.asm:2` does `predef SingleCPUSpeed ; battle
transitions have known double-speed visual faults`, so **every battle forces single speed** -
confirmed by measurement (`rKEY1 = 0x80` in the CGB lobby, `0x00` at every in-battle
`AIEnemyTrainerChooseMoves` hook). An earlier version of this entry halved these figures against a
double-speed budget; that was wrong. Also settled: PyBoy's `_cycles()` advances 70,224 per frame in
BOTH DMG and CGB-double mode (measured against `frame_count`), so never model double speed by
dividing measured cycles by 140,448.

**Still over the frame budget after this fix** (6.8 frames, down from 11.05) - the divide
optimisation was the single largest win available but was never expected to close the gap alone. Not
yet investigated further; the damage simulator's per-move farcall overhead is the next suspect per
`AI_PERF_INVESTIGATION.md`'s own "options not recommended" section (caching, only after this).

**2026-08-26 AI Overhaul Phase 7 COMPLETE - fair play as a tier axis, the smallest phase to date.**
Two new bank-`$0F` bytes spent (8-byte farcall), a 20-byte `$0E` growth (`AIGetPlayerMoveN`'s
rewrite), and a new pinned bank-`$2C` file. Measured after (minimum across Red, Blue, Debug):
bank `$0E` **228** (248 -> 228), bank `$0F` **15** (23 -> 15, debug binds - `$0F` is now down to its
last ~15 bytes and should be treated as fully exhausted, not merely "closed"), bank `$2C` **5,498**
(5,525 -> 5,498, new file `engine/battle/ai/ai_fairplay.asm`).

**What shipped, matching the plan's own one-routine scope exactly:** `AIGetPlayerMoveN`
(`ai_accessors.asm`, bank `$0E`) now branches on `AI_OMNISCIENT` (farcalled from `AIHasFlag`,
`ai_core.asm`) - omniscient tiers (T2/T3, unchanged) read the real `wBattleMonMoves`; fair-play
tiers (T0/T1, newly cleared in `AITierLayers`) read `wAISeenPlayerMoves` instead, populated by a
new zero-argument farcall, `AITrackSeenPlayerMove` (`ai_fairplay.asm`, bank `$2C`), hooked into
`engine/battle/core.asm`'s `PlayerCanExecuteMove` (bank `$0F`, hence the 8-byte-only footprint
there - all real logic lives in the pinned `$2C` file, same pattern as Phase 4/5/6's occasional,
not-per-move AI code).

**A new instance of the recurring register-contract bug class, caught before ever building - not
in the shipped ROM, but in the FIRST DRAFT of `AIGetPlayerMoveN` itself.** The slot number (`a` on
entry) has to survive the nested `farcall AIHasFlag`, but neither `de` nor `hl` is safe to stash it
in this time, for a new reason: `AIHasFlag`'s OWN body uses `hl` as scratch (copies the layer word
into it via `AIGetLayerWord`) and needs `de` as its actual input (the mask), returning it unchanged
- so a value stashed in either register survives the farcall MACRO but gets stomped by the
CALLEE'S OWN use of that same register, the exact "de/hl survive Bankswitch but not what the
callee's body does with them" lesson Phase 6 already logged, now recurring for `hl` specifically
against a callee that consumes BOTH of the only two farcall-safe registers as its own working set.
Fixed by pushing the slot number onto the STACK around the whole farcall (`push bc`/`pop bc`,
deliberately not `push af`/`pop af` - `POP AF` restores flags, `POP BC` does not, and the branch
right after needs `AIHasFlag`'s `z` result still live).

**A second, independent bug found and fixed in a DIFFERENT file while auditing every consumer of
the changed accessor:** `ai_threat.asm`'s `_AIScanPlayerMovesForKO` (the single existing caller of
`AIGetPlayerMoveN`) short-circuited on the first empty slot with the comment "the move list is
packed, so nothing follows" - true of the real `wBattleMonMoves` (always packed) but FALSE of the
new `wAISeenPlayerMoves`, which is sparse by construction (a player can reveal move slot 2 before
slot 0). Left as-was, a fair-play trainer that had only seen a later-slot move would have silently
stopped scanning at the first unrevealed EARLIER slot and never noticed the real threat behind it.
Fixed by changing the early-exit into a skip-and-continue. Caught by re-auditing every caller of the
routine being changed, not by a test failure - this project's own standing discipline
([[project-cross-bank-call-bug-recurrence]]) paying off on a same-bank logic bug, not just a
cross-bank one.

**An honest, load-bearing finding from verification, worth flagging clearly rather than burying:**
as the tier bitmask currently stands, clearing `AI_OMNISCIENT` on T0/T1 has **no observable
gameplay effect yet**. `AIGetPlayerMoveN`'s only consumer, `AIPlayerWouldKO`/`AIHealWouldStillDie`
(`ai_threat.asm`), is reached only via the `AI_THREAT` layer (T3-only in `AITierLayers`) or
`AIShouldSwitch`'s emergency trigger (gated `cp AI_TIER_SKILLED / jp c, .vanilla`, i.e. T2+ only) -
and both of those tiers keep `AI_OMNISCIENT` set. T0/T1's own active layers (`AI_REDUNDANT`,
`AI_BASIC`, `AI_TYPES`, `AI_SETUP`) never call the accessor at all. The mechanism is verified
correct end-to-end (see below) and matches the plan's literal scope, but it is currently a
future-proofed axis with no live consumer at the tiers it was flipped for - exactly the same state
`AI_OMNISCIENT` itself sat in from Phase 1 through Phase 6 before this phase gave it one. Extending
`AI_THREAT` or the switch engine's emergency trigger down to T1 (a real behavioural decision, not
mentioned in the phase's locked scope) is the only thing that would make this observable in play.

**Verified in-emulator via two separate mechanisms, because the direct one required discovering a
harness limitation first.** `call_routine`/`probe_routine_until`'s existing entry technique - even
a from-scratch injection using the same PC/SP setup - routes any address `>= 0x4000` through
`Bankswitch`, which is WRONG for `AIGetPlayerMoveN` specifically: its argument arrives in `a`, and
`Bankswitch`'s own `ld a, b` (right before its `jp hl`) clobbers it before the callee's first
instruction ever runs, silently substituting the target bank number as the "slot" argument instead
of whatever the caller intended. This is the identical, already-documented reason the routine cannot
be farcalled in real gameplay - the diagnostic tooling has the same blind spot as a naive callsite
would. Fixed for testing purposes by mapping the target bank directly (mirroring `call_routine`'s
own bank-restore step) and jumping straight to the routine's address, bypassing `Bankswitch`
entirely - the same shape as its one real, same-bank caller. A named local label (`.exit`, zero
bytes, kept in the shipped file for future hookability) let a `hook_flag` capture `a` at the exact
return point rather than trusting a synthetic return address, since `call_routine`'s own restore
step is independently documented as unable to report a routine's output. Confirmed: T1 with
`wAISeenPlayerMoves = [0, GROWL, 0, 0]` returns slot 0 -> `0`, slot 1 -> `GROWL`; T3 with the
identical WRAM state returns slot 0 -> the real first move, slot 1 -> the real second move,
regardless of what `wAISeenPlayerMoves` held - confirming the omniscient branch still ignores it
entirely. Separately, real menu-driven play (selecting move slot 2, not the default slot 1, via a
`MoveSelectionMenu` hook to time the input) confirmed `AITrackSeenPlayerMove` writes into the
CORRECT slot of `wAISeenPlayerMoves`, not just slot 0.

**2026-08-26 AI Overhaul Phase 6, Sonnet portion COMPLETE - new pinned section in bank `$2C`,
banks `$03` and `$0E` both tighter than the handoff spec assumed.** New file
`engine/battle/ai/ai_roster.asm` (roster DV/stat-exp rolling + item-AI ace check), pinned
`SECTION "Trainer AI Roster", ROMX, BANK[$2C]` - same relocation bank as the switching/plan
engines, for the same reason (Red/Blue/Debug first-fit independently, Debug is tightest).

`PHASE_6_SPEC.md` called bank `$03` "ample" (38 bytes free at the time). That undersold the actual
need: the DV roll, the stat-exp roll, and the HP fix together would have needed ~65-84 bytes done
inline, well over budget. Moved almost all of the real logic into the new bank-`$2C` file instead;
`_AddPartyMon`'s own two call sites cost only ~22 bytes net. Measured after: bank `$03` **16 bytes**
free (38 -> 16, pokered/pokeblue bind), bank `$0E` **248 bytes** free (321 -> 248, debug binds - the
item-AI tier gate + ace-check dispatch + `AIIncreaseStat`'s idempotence/KO-simulator additions),
bank `$2C` **5,525 bytes** free (5,730 -> 5,525, pokered binds).

Three register-contract bugs were found and fixed here, all via direct in-emulator data inspection
(reading generated party species/level/HP/DVs against an independently-verified expectation or a
`git stash`-baselined HEAD) rather than trusted from a clean build - see `AI_SYSTEM.md`'s Phase 6
section for the full writeup. The load-bearing lesson for future bank-`$2C` work: **"de survives a
farcall" is a claim about the farcall macro and `Bankswitch` itself, not about what a nested-farcalled
callee does internally** - `AIGetTier` falling through to `AIResolveTier` clobbers `d`/`e` as its own
scratch, which broke a caller that assumed `de` would come back untouched.

**2026-09-02 AI Overhaul F18 (scenario coverage backfill for Phases 4/6/7) - no bank cost, two
process notes worth keeping.** Three new `unittest` files
(`test_ai_switching.py`'s `AIShouldSwitchTest`, `test_ai_roster.py`, `test_ai_fairplay.py`), 42 new
tests, all against already-shipped code via direct `call_routine`/`probe_routine_until` calls - no
ROM logic changed except one zero-byte local label (`AIActiveMonIsAce.isAce`, `ai_roster.asm`, bank
`$2C`), added purely so a bare `scf/ret` exit had a hookable address, matching the
`AIGetPlayerMoveN.exit` precedent. Bank `$2C` unchanged at 1,976.

**Two things worth recording for future harness work, both found while building this:**
1. **A hand-rolled PC hijack MUST push a return-address stack sentinel before jumping**, exactly
   like `call_routine`/`probe_routine_until` already do internally. Omitting it (first draft of the
   `AIGetPlayerMoveN` test helper) let the routine's own `ret` pop garbage off the parked-VBlank
   stack and jump there, burning an entire `tick()` frame churning through unrelated memory as
   instructions - not a crash, a silent multi-second-per-call hang, caught only because a 30-second
   watchdog script was run before committing to the permanent test.
2. **`DebugFight2Setup.buildInjected` (`engine/debug/debug_fight2.asm`, Codex-owned) writes
   `wAIDebugTierOverride` AFTER building both parties**, so `inject_fight2_spec(ai_tier=N)` cannot
   currently exercise tier-scaled DV/stat-exp rolling for ANY N - every injected enemy mon silently
   gets the T0 fixed pair. Logged as
   `pending_contracts.json`:`debugfight2-tier-override-written-after-dv-roll`, not fixed here. The
   AI-side code (`AIRollEnemyDVs`/`AIFinishEnemyMonStats`) is unaffected and verified correct by
   calling `_AddPartyMon` directly with the tier pre-resolved, bypassing the buggy harness ordering
   entirely - every DV floor and stat-exp value matched the formula exactly (T1: level<<6, T2:
   level<<7, T3: level<<8). Worth knowing before trusting ANY inject_fight2_spec-based DV
   measurement until this is fixed.

**2026-09-02 AI Overhaul follow-ups F9, F14, F15, F17 measurement (Sonnet handoff, spec by Opus).**
Four independent battle-engine edits, all confined to banks `$0E` and `$2C`, neither under real
pressure (bank `$0E` debug minimum 402 bytes free before this work; bank `$2C` debug minimum ~1,976).

- **F9** (`AI_SETUP` usefulness gate): new `AIOwnsPhysicalMove` (`trainer_ai.asm`) plus one new
  `wBuffer` byte (`AI_BUF_PHYSICAL`, offset 29 - `wBuffer` is now an EXACT 30-byte fit with nothing
  spare left; the next thing wanting scratch there needs a real reallocation, not a "there's still
  room" assumption).
- **F17** (stat-up cap / stat-down floor): `AIRedundant_StatUp` (new) and `AIRedundant_StatDown` (new,
  replacing `AIRedundant_SubOnly` for the 16 stat-down table entries; the 4 non-stat `SubOnly` users -
  flinch/confusion-side/drain - are unaffected), both in `ai_redundant.asm`.
- **F14** (charge moves, evasion, Toxic-then-trap): `AIPlayerIsStalled` and `AIPlayerHasChipDamage`
  (new, `ai_predicates.asm`); `AISmart_Charge`/`AISmart_InvulnerableCharge`/`AISmart_Evasion`/
  `AISmart_Poison` (new) and an extended `AISmart_Trapping` (`ai_smart.asm`); a new
  `AI_FITNESS_TRAP_CHIP_BONUS` applied to `AIFit_WrapLock`/`AIFit_AgilityWrap` (`ai_plans.asm`, bank
  `$2C`).
- **F15** (graded `AI_RISKY` ladder): explicit `OHKO_EFFECT`/`METRONOME_EFFECT` detection plus a new
  `AIAnyScoreBelowBaseline` local routine, all in `ai_risky.asm`.

**A real register-safety bug caught during F14's `ai_plans.asm` work, before it ever reached a
build** (traced through `home/bankswitch.asm`, not assumed - the same discipline
`project_register_contract_decides_bank` already tracks): the fitness-bonus insertions first tried
stashing the base fitness value in `b` across the `farcall AIPlayerHasChipDamage` call. `bc` DOES
survive the farcall macro's own inbound step, but Bankswitch's return path (`pop bc` at its
`.Return` label) overwrites `bc` with the bytes it saved on entry - the ORIGINAL bank number and
flags, not whatever the caller stashed there before the call. So `bc` cannot carry a value THROUGH a
farcall despite that surviving-the-macro appearance; only `de` and `hl` are genuinely untouched by
Bankswitch throughout. Fixed by stashing in `d` instead. Worth stating as its own rule rather than
folding into the existing "de survives" note: the existing note is about *inbound* arguments, this
one is about carrying a *caller's own local value* across a farcall boundary, which is a different
and easier mistake to make.

**Verified in-emulator via `layer_trace` for every new heuristic, not assumed from source** - two
real authoring mistakes were caught this way before any fixture shipped: two early Metronome fixture
drafts used boards where the enemy was never actually losing, so `AI_RISKY`'s own top-level
`AIPlayerWouldKO` gate silently never fired and the drafts tested nothing; and the OHKO-tier
fixture's first hand-guessed expected score was wrong by 2 points because that board also happened
to qualify for the OhkoFish PLAN, whose own contribution the hand guess hadn't accounted for. Both
were caught by actually running a probe script (the same `hook_ai_scores`/`inject_fight2_spec`
machinery `run_ai_scenarios.py` itself uses) before writing the fixture, not by the test suite
catching them after the fact.

**Measured after (all three ROMs build clean, no warnings):** bank `$0E` debug minimum **402 bytes**
free (was ~213 stale / genuinely higher after 2026-09-01's F2 measurement - see that entry; this
session's four features together cost roughly 450 bytes total against the pre-session real
headroom). Bank `$2C` debug minimum **1,976 bytes** free (cost: ~20 bytes, the two fitness-bonus
insertions only - everything else in F9/F14/F15/F17 lives in bank `$0E`).

**Gates:** `make` clean on `pokered`/`pokeblue`/`pokeblue_debug`; `make ai_scenarios` 71/71 (56 → 71,
15 new fixtures, three existing fixtures rebaselined for real and correctly-traced score changes -
`plan_toxicstall_poisons_then_would_heal`, `plan_substall_poison_shields_then_chips`,
`plan_ohkofish_gambles_when_losing_and_faster`); `make integration` clean; `make smoke` 152/154 with
the same two pre-existing failures this project has carried since before this session
(`test_follower_yellow_runtime` CGB classification, `test_lobby_pose_layout`'s missing
`jp UpdateSprites`) - neither touches battle code.

**2026-09-01 AI Overhaul follow-ups F2 and F4 measurement.** Two small, independent battle-engine
edits, both landing in already-tight banks, so both were measured rather than assumed.

**F2 (Metronome / Mirror Move vs the type chart), bank `$0E`, +8 bytes.** Two `cp`/`jr z` pairs added
to `AIMoveChoiceModification3` (`engine/battle/trainer_ai.asm`) so `METRONOME_EFFECT` and
`MIRROR_MOVE_EFFECT` skip the type-effectiveness layer entirely, exactly as `SPECIAL_DAMAGE_EFFECT`
and `SUPER_FANG_EFFECT` already did. Chosen over the plan's original "retype Metronome to BIRD"
because it is data-free, fixes two moves instead of one, and does not change what the move-info
preview screen displays (`BIRD` has a real name string in `data/types/names.asm`).

**F4 (stat-down burn/paralysis re-application), bank `$0F`, +2 bytes; bank `$08`, +55 bytes.**
`StatModifierDownEffect`'s tail (`engine/battle/effects.asm`) was `call QuarterSpeedDueToParalysis` /
`jp HalveAttackDueToBurn` - 6 bytes, both penalties unconditionally. It is now a single 8-byte
`jpfar ApplyTargetStatPenalty`, a new routine appended to the existing floating
`Self-Target Stat Penalty` section (`custom_functions/apply_self_stat_penalty.asm`), which dispatches
on the move effect so only the stat that was actually recalculated gets its penalty re-applied.

*The `jpfar`-into-a-routine-that-`farcall`s-back pattern was traced through `home/bankswitch.asm`
before being used, not assumed.* `jpfar` is `jp Bankswitch`, so it reuses the caller's existing
return address; the inner `farcall` pushes a second `Bankswitch` frame; both frames unwind through
the same shared `.Return` label in order, restoring `$08` then `$0F`. Nested `Bankswitch` frames are
safe, and this file already relied on it (`ApplySelfTargetStatPenalty` farcalls back into Battle
Core from the same section).

**Measured after (all three ROMs build clean, no warnings):**

| Bank | Before | After | Note |
|---|---:|---:|---|
| `$0E` Battle Engine 7 | 213 (stale) | **854** | F2's +8 is included. The "before" number was drift, not spend - see the table row. |
| `$0F` Battle Core | 15 (stale; ~19 real) | **17** | Debug binds. Red/Blue read 24. |
| `$08` | 205 | **116** | The `Self-Target Stat Penalty` floater grew 61 -> 116 bytes and stayed in `$08` in all three targets. |

**Gates:** `make` clean on `pokered` + `pokeblue` + `pokeblue_debug`; `make ai_scenarios` 56/56;
`make integration` clean; `make smoke` 152/154, with the two failures
(`test_follower_yellow_runtime` CGB-classification, `test_lobby_pose_layout`'s missing
`jp UpdateSprites`) **bisect-confirmed pre-existing** by stashing all three edited files, rebuilding,
and re-running those two modules alone. Neither touches battle code.

**2026-08-26 AI Overhaul Phase 6, Opus portion - bank `$0F` is now CLOSED.** Two edits inside
`LoadEnemyMonData` (`engine/battle/core.asm`, Battle Core, bank `$0F`), both required so that
**2026-08-26 AI Overhaul Phase 6, Opus portion - bank `$0F` is now CLOSED.** Two edits inside
`LoadEnemyMonData` (`engine/battle/core.asm`, Battle Core, bank `$0F`), both required so that
enemy DVs and stat exp can be owned by the roster instead of hardcoded at send-out: read
`wEnemyMon1DVs` instead of forcing `ATKDEFDV_TRAINER`/`SPDSPCDV_TRAINER`, and point `CalcStats` at
`wEnemyMon1HPExp - 1` with `b = 1` instead of `wEnemyMonHP` with `b = 0`.

Measured after: bank `$0F` `$0017` = **23 bytes** free in `pokeblue_debug` (`$001e` = 30 in
Red/Blue; the debug figure binds, as always). Cost **exactly 30 bytes**, matching the hand budget
made before writing. Banks `$0E` (**321**) and `$2C` (**5,730**) untouched by this phase.

**The Phase 3 Step 3 warning about this bank is now upgraded from "relocate something out first" to
"assume closed".** 23 bytes will not absorb a farcall plus a register shuffle. Anything else that
wants to sit beside the damage formula needs a relocation designed first, and the Phase 4 trick that
recovered space here (replacing an inline scan with a `farcall`) has no remaining candidate - the
inline scan it consumed was the one obvious one.

**A placement lesson worth recording, because the plan document got it wrong.** `AI_OVERHAUL_PLAN.md`
scoped this phase's Battle Core work as one edit ("read roster DVs"). The **stat-exp half is also a
`$0F` edit** and was unlisted: `CalcStats` only considers stat exp when passed `b = 1` *and* pointed
at the party struct's stat-exp block, and that decision is made inside `LoadEnemyMonData`. A phase
budgeted at ~11 bytes actually needed 30. **When a phase says "read X from somewhere else instead",
check whether the consuming routine also needs to be told to USE it** - the read and the opt-in can
be two separate edits in the same tight bank.

**Verification technique reused successfully for the third time:** to prove the edit was a no-op
against the current roster (which still writes fixed DVs and zeroed stat exp), enemy DVs, stat exp
and all five stats were dumped for all 6 roster mons plus the active battle mon across FIGHT2 seeds
17/42/3, with the tracked file `git stash push`ed and popped between runs. Byte-identical. This is
the same technique Phase 5 used to disprove RNG drift, and it generalises to any "this should change
nothing yet" landing.

**2026-08-26 AI Overhaul Phase 5 COMPLETE (Sonnet portion: the twelve remaining plan bodies).** All
landed in the already-pinned `$2C` section from the Opus framework entry below - no new sections.
Measured after (minimum across Red, Blue, Debug): bank `$2C` **5,730 bytes** free (was 6,447 - 717
bytes for twelve plans). Bank `$0E` **unchanged at 321** - nothing needed to live there, confirming
the framework's `$0E`/`$2C` split was sized correctly on the first pass rather than needing a
later correction.

**Two bug classes this project keeps re-finding, caught here before ever building - both worth a
permanent note since they will recur:**
1. A farcall clobbers `a` (`Bankswitch`'s first instruction is `ldh a, [hLoadedROMBank]`), so any
   base value a later branch depends on must be loaded AFTER the farcall that sets the carry it
   will be tested against, never before. `AIFit_AgilityWrap` (the framework's own reference plan)
   got this right; the first drafts of two new plans loaded their fitness constant BEFORE the
   farcall, silently discarding it on the branch that mattered.
2. A routine's bank must be checked at its own definition, not assumed from where it is used.
   `AISubWouldSurvive` lives in bank `$0E` (`ai_plan.asm`); code in bank `$2C` reaching it needs
   `farcall`, not `call`. Both new callers were first written with a plain `call`.

**One real cross-phase interaction, not a bug, found via `layer_trace` and resolved by
rebaselining one pre-existing fixture with the reasoning recorded in its own `note` field:** a
Phase 3 threat fixture's own Hypnosis move started legitimately qualifying for the new SleepLead
plan once it went live, producing a genuine tie on a board where nothing else was competing for
attention. Confirmed AI_THREAT itself stayed silent before accepting the tie.

**2026-08-26 AI Overhaul Phase 5 framework (Opus portion: move-class system, plan selector, one
reference plan). A LAYER DELIBERATELY SPLIT ACROSS TWO BANKS — the pattern is the point of this
entry.** The `AI_PLAN` layer is bit 7 of the AI layer word and so is reached by
`AIEnemyTrainerChooseMoves`' same-bank `jp hl`, which pins it to bank `$0E`. `$0E` had **472 bytes**
free against a plan system several times that, and this bank has no eviction candidates left worth
the risk.

Resolution: put in `$0E` **only what the calling convention forces there**, and farcall the rest.
`engine/battle/ai/ai_plan.asm` (bank `$0E`, **151 bytes**) holds the dispatched entry point and its
score-application loop (needs `AIEncourage`'s plain-call `hl` contract), the classification loop
(needs `ReadMove`, whose `Moves` table is in this bank), `AISubWouldSurvive`, and a **four-byte
`ReadMove` trampoline** — `AIReadMoveFromE`, which exists solely because `ReadMove` takes its
argument in `a` and `a` cannot survive a farcall. That trampoline replaced what would otherwise have
been a ~50-byte in-bank scan-and-inspect helper, and it is the single edit that decided where the
bank boundary fell. `engine/battle/ai/ai_plans.asm` is a new **pinned**
`SECTION "Trainer AI Plans", ROMX, BANK[$2C]` (section 5 rule 6) holding the selector, plan table,
effect→class table and every plan body — kept as a SEPARATE section from `ai_switching.asm`'s so
either can be relocated without dragging the other.

Measured after (minimum across Red, Blue, Debug): bank `$0E` **321**, bank `$2C` **6,447**, bank
`$0F` **53 (untouched)**.

**Reusable rule this establishes, and the generalisation of Phase 3's:** the register contract
decides the bank, but so does the *call frequency*. Phase 2a pulled `AIEncourage` INTO `$0E`
because it runs per move; Phase 3 pushed the damage simulator OUT to `$0F` because of a
back-to-back register handoff; Phase 5 shows the third case — **when a routine is forced into a full
bank by its entry convention alone, split it, and let a tiny in-bank shim carry the arguments the
farcall cannot.** Before assuming a feature will not fit in a pinned bank, ask how much of it is
actually pinned.

**Also worth recording: a cheap, reliable way to prove a change caused no RNG drift**, since this
project's smoke fixtures are cycle- and RNG-sensitive and one pre-existing failure is easy to
confuse with a new one. `git stash push <tracked files only>`, rebuild, re-run the single failing
test, `git stash pop`. New untracked files stay on disk but are not assembled, because the
`INCLUDE`s reaching them live in the stashed files. Phase 5 used this to prove the FIGHT2
deterministic-party failure produced a **byte-identical** wrong party at HEAD.

**2026-08-26 AI Overhaul Phase 4 final measurement (Sonnet portion: anti-ping-pong guard, HP-weighted
switch-in scoring, urgency roll).** All landed in the already-pinned `$2C` section from the Opus
allocation entry below - no new sections. Measured after (minimum across Red, Blue, Debug):
bank `$2C` **6,882 bytes** free (`$1ae2`/`$1af2` depending on target - see the Opus entry for the
starting point). No pressure; this bank has room for the rest of the plan's switching-adjacent work.

**One assembler-level lesson from this pass, worth a note since it will recur:** several `jr`
instructions in `ai_switching.asm` needed converting to `jp` as the file grew - not because bank
`$2C` ran short (it has thousands of bytes free), but because RGBDS's `jr` has a hard ±127-byte
reach regardless of how much ROM space remains. **Free bytes in a bank do not mean a `jr` can reach
across it.** When a routine grows past what was originally a short forward/backward jump, check
`jr` distances before assuming a build failure means a budget problem.

**2026-08-26 AI Overhaul Phase 4 allocation - the hooks FREED space in the tight banks.** Planned
against section 1 and section 5 before any code was written, per this document's own rule.

Measured after (minimum across Red, Blue and Debug, as section 1 requires):

| Bank | Before | After | Note |
|---:|---:|---:|---|
| `$0F` Battle Core | 31 | **53** | `EnemySendOut`'s ~30-byte inline first-healthy scan became an 8-byte `farcall` |
| `$0E` Battle Engine 7 | 522 | **472** | `AIHasSuperEffectiveMove` + the `AISwitchIfEnoughMons` hook |
| `$2C` (new pinned section) | 10,037 | **7,044** | `SECTION "Trainer AI Switching", ROMX, BANK[$2C]` |

**Note the `$0F` number went UP.** The Phase 3 Step 3 entry below warned `$0F` was exhausted at 31
bytes and that Phase 4 would need a relocation first. It did not: replacing an inline scan with a
farcall is a net saving, so the phase that adds an entire switching engine actually *relieved* the
bank it was predicted to overflow. Worth remembering as a planning pattern - before budgeting a
relocation, check whether the hook site contains code the new routine subsumes.

**The new section is PINNED, not floated**, per section 5 rule 6. `ai_core.asm`'s section is floated
and lands in `$05`; a second floated section of this size risked landing in a different bank per
target, and Debug is consistently tightest. Verified identical placement in all three: `$2C`.

**FARCALL RETURN CONVENTION - verified from `home/bankswitch.asm`, and it is less restrictive than
the inbound rule everyone remembers.** `Bankswitch`'s return path is:

```
.Return
	pop bc
	ld a, b
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret
```

None of those instructions touch flags, and `pop bc` touches only `bc`. So **across a farcall
RETURN: carry survives, `de` and `hl` survive, and only `a` and `bc` are destroyed.** A farcalled
routine may therefore return a boolean in CARRY or a value in `de`/`hl`. This is what let Phase 4's
switch predicates live in `$2C` and answer in carry with no WRAM signalling channel. It is the
mirror of the well-known *inbound* restriction (an argument cannot travel in `a`, because
`Bankswitch`'s FIRST instruction is `ldh a, [hLoadedROMBank]`) - the two are often conflated into a
blanket "farcalls destroy everything", which is wrong and costs real design options.

Corollary used in the same phase: `AIGetTier` returns the tier in `a`, which cannot survive the trip
- but it also RESOLVES `wAITier` as a side effect, so the safe pattern is to farcall it for the
resolution and then read the value back from WRAM.


**2026-08-25 AI Overhaul Phase 3 Step 3 measurement - bank `$0F` is now genuinely exhausted.**
Added `AIIsHighCritMove` to `engine/battle/core.asm` (Battle Core, bank `$0F`) and
`engine/battle/ai/ai_risky.asm` plus additions to `ai_smart.asm`/`ai_predicates.asm` to bank `$0E`.
Measured after: bank `$0F` `$0026` = **38 bytes** free (from `$0097` = 151 at Step 2's end - the
`AIIsHighCritMove` lookup cost 15 bytes but the margin was already this thin). Bank `$0E` `$037e` =
**894 bytes** free. All three targets link clean, zero warnings; `make smoke` 25/26 (usual
pre-existing failure); `make ai_scenarios` **39 scenarios**; `make integration` clean.

**Bank `$0F` is no longer a "budget before writing" bank - it is a "relocate something out first"
bank.** 38 bytes will not fit a second lookup routine of any kind. Phase 4's `EnemySendOut` hook,
already flagged at Step 2's handoff as needing this bank, must either fit in under 38 bytes or a
relocation must land first. Re-read section 5 before starting that work.

**A third instance of the recurring cross-bank bug class, this time on a DATA lookup, not a CALL.**
`AIIsHighCritMove` reads `HighCriticalMoves` (bank `$0F` data) and had to be farcalled from
`ai_risky.asm` (bank `$0E`) for the same reason a routine does: reading cross-bank data directly reads
whatever byte happens to be at that address in whichever bank the MMU has mapped, with no assembler
warning - identical to a cross-bank `call`, just for `ld a,[hl]` instead of `call`. Its first draft
took the move id to look up in `a`, which - as with every prior instance of this - cannot survive a
farcall, since `Bankswitch`'s first instruction is `ldh a, [hLoadedROMBank]`. Fixed by changing the
routine's own contract to take the argument in `e` instead, the one register that survives a farcall
in both directions. Third occurrence of this exact class this project (`AIEncourage`/`AIDiscourage`
in Phase 2a, the accessor seam in Phase 3 Step 2, now this) - see
[[project-cross-bank-call-bug-recurrence]] in the memory index; the structural tell each time was a
routine/table living in a DIFFERENT bank than a hot caller that reaches it with something other than
a bank-aware mechanism.

**2026-08-25 AI Overhaul Phase 3 Step 2 measurement, and a cross-bank `call` bug that had already
shipped.** Added `engine/battle/ai/ai_threat.asm` and `engine/battle/ai/ai_accessors.asm` to
`"Battle Engine 7"` (bank `$0E`), and a second entry point onto the existing damage simulator in
Battle Core (bank `$0F`). Measured after: bank `$0E` `$0645` = **1605 bytes** free, bank `$0F`
`$0097` = **151 bytes** free. All three targets link clean; `make smoke` 25/26 (the usual
pre-existing failure), `make ai_scenarios` 21 scenarios, `make integration` clean.

**The bug, because it is a placement bug and belongs in this file:** the AI's player-state accessor
seam was written into `ai_core.asm`, which is a floating section that landed in **bank `$06`**.
`AISmart_DreamEater`, in bank `$0E`, called it with a plain same-bank `call`. That resolved to
`$0E:7FA8` - inside bank `$0E`'s own empty tail - so on the release ROMs (`rgbfix -p 0x00`) it
executed `nop` padding to the end of the bank and ran off into VRAM, and on the debug ROM
(`-p 0xff`) it hit `rst $38`. RGBDS emitted no warning, exactly as in the Phase 2a case. It escaped
testing only because no scenario gave an enemy a Dream Eater move. **Note the release/debug padding
byte changes the failure mode** (`$00` = `nop` slide vs `$FF` = `rst $38`), so a debug-only repro can
look like a clean trap while the release ROM silently executes into VRAM - do not assume the two
behave alike when diagnosing a stray call.

Fixed by moving the seam into bank `$0E`. It also *had* to move for an independent reason worth
recording next to the register-contract rule below: `AIGetPlayerMoveN` takes its argument in `a`, and
`Bankswitch`'s first instruction is `ldh a, [hLoadedROMBank]`, so `a` cannot survive a farcall. A
routine whose argument arrives in `a` is **not callable across banks at all** without changing its
contract - that is a placement constraint, not a performance preference.


**2026-08-25 AI Overhaul Phase 3 Step 1 measurement, and a bank rule that points the OPPOSITE way to
Phase 2a's.** `AIEstimateDamage` was added to `engine/battle/core.asm` (Battle Core, bank `$0F`) and
`engine/battle/ai/ai_damage.asm` was added to `"Battle Engine 7"` (bank `$0E`). Measured after:
bank `$0F` `$00ab` = **171 bytes** free (from `$010f` = 271 before - the simulator cost 100 bytes;
note the plan's long-standing "51 bytes free in `$0F`" figure was stale and had already improved).
Bank `$0E` `$07d4` = **2004 bytes** free. ROM0 unaffected. All three targets link clean, zero
warnings; `make smoke` 25/26 with **byte-identical** deterministic-party values to the previous
build, i.e. no RNG drift despite editing `core.asm`, because the change adds a new routine rather
than altering any existing instruction sequence; `make ai_scenarios` (16 scenarios) and
`make integration` both pass.

**The rule, stated generally because it caught the design by surprise:** Phase 2a's lesson was "a
routine called from the per-move scoring loop must be pulled INTO bank `$0E`." Phase 3's is the
mirror: `GetDamageVarsForEnemyAttack` hands its results to `CalculateDamage` in `b/c/d/e`, so those
two calls must be back-to-back **plain same-bank** calls - any farcall between them destroys `bc`
through `Bankswitch`'s own `ld bc, .Return`. That makes it **impossible** to host the simulator in
`$0E` without reimplementing the damage formula, so it stays in `$0F` beside the formula and the AI
layers pay one farcall per move to reach it. Generalised: **an inter-routine register contract
decides bank placement, and it can force code either toward or away from its caller.** Deciding
placement from "where does the caller live" alone is what produces both failure modes. With `$0F`
now at 171 bytes, Phase 3 Step 2's player-side estimator (which needs the same treatment for
`GetDamageVarsForPlayerAttack`) must be budgeted before it is written.

**2026-08-25 AI Overhaul Phase 2b measurement.** `engine/battle/ai/ai_smart.asm` (new, ~340 lines:
`AILayerSmart`'s dispatcher, `AISmartCrossCutting`, 15 per-effect handlers) landed the same way Phase
2a's rule requires - INCLUDEd into `main.asm`'s `"Battle Engine 7"` section, pinned to bank `$0E`
beside `trainer_ai.asm`, no farcall involved. Bank `$0E` measured after: `$07f0` (2032 bytes) free in
Red/Blue (Debug not separately re-measured this pass, expect a similar few-hundred-byte reduction
from Phase 2a's `2621`/`2249` baseline - `ai_smart.asm` alone accounts for most of the ~589-byte
Red/Blue delta). ROM0 unaffected. All three targets link clean, zero warnings; `make smoke` 25/26
(the same pre-existing, unrelated FIGHT 2 RNG-drift mismatch); `make ai_scenarios` and
`make integration` both pass. Full account, including two real bugs this phase's testing surfaced (a
pre-existing Phase 2a low-byte-comparison inversion in `AIRedundant_Substitute`, and a turn-1
anti-spam false positive), is in `AI_OVERHAUL_PLAN.md`'s Phase 2b section and `AI_SYSTEM.md`.

**2026-08-25 AI Overhaul Phase 2a placement lesson (new rule, not just a measurement).** While
bringing up `AILayerRedundant` (`engine/battle/ai/ai_redundant.asm`), `AIEncourage`/`AIDiscourage`
were moved from the floating "Trainer AI Core" section (landed in bank `$05` at build time) into a
new file `engine/battle/ai/ai_score_helpers.asm`, INCLUDEd into `main.asm`'s existing `"Battle
Engine 7"` section so it is pinned to bank `$0E` alongside `trainer_ai.asm`. Reason, stated as a
rule for the AI subsystem specifically: `AIEnemyTrainerChooseMoves`'s scoring-layer dispatch
(`engine/battle/trainer_ai.asm`) reaches every layer with a plain same-bank `jp hl`, not a
farcall - so every `AILayer*` routine is already forced into bank `$0E` by that dispatch mechanism,
regardless of where anything else in the AI subsystem lives. `AIEncourage`/`AIDiscourage` are called
by nearly every layer, several times per move, so leaving them in a separately-placed bank forced
every call through `farcall`/`callfar`, which cost three compounding bugs before the mismeasure was
caught: `farcall`'s macro consumes `hl` as its own jump-target register before the bank switch
happens, so a pointer argument cannot travel in `hl` across it; `Bankswitch`'s own first instruction
(`ldh a, [hLoadedROMBank]`) clobbers `a` before the callee ever runs, so a magnitude cannot travel in
`a` either; and `Bankswitch`'s return path clobbers `bc` unconditionally as its own bank-restore
bookkeeping. None of the three produced an assembler or linker warning - `rgbasm`/`rgblink` have no
way to know two labels end up in different banks from a plain `call`, so the original same-bank
`call AIDiscourage` (before farcall was even tried) linked clean and then executed whatever garbage
happened to occupy that byte offset in whichever bank was actually mapped in, which read back to
PyBoy as a frozen `PC=$0038` (the `RST 38` vector, reached by decoding `$FF`-filled unmapped memory)
with the stack pointer creeping down forever. **Rule for future AI work:** any routine called from
inside a per-move scoring loop belongs in bank `$0E` beside `trainer_ai.asm`, full stop - do not let
it default into a separately-floated section just because it was written alongside less-frequently-
called setup code (tier resolution, once per battle, is the one thing in `ai_core.asm` that
legitimately still farcalls out and should stay that way). Full account, including the PyBoy hook
sequence used to isolate it (register-state dumps, then a hook on the exact `jp hl` instruction,
then a hook on the discourage entry point) is in `AI_OVERHAUL_PLAN.md`'s Phase 2a section.
Bank `$0E` measured after the move: `$0a3d` (2621 bytes) free in Red/Blue, `$08c9` (2249) in Debug.
ROM0 unaffected (`$001d`/`$001d`/`$0009`, unchanged from before this work). All three targets link
clean; `make smoke` 25/26 (the one failure is the pre-existing, unrelated FIGHT 2 RNG-drift mismatch,
confirmed present on a clean `HEAD` build with none of this work applied); `make ai_scenarios` and
`make integration` both pass.

**2026-08-24 Yume battle move-info Task 3 measurement:** Red, Blue, and Blue Debug builds succeed at source baseline `7a1a29a8e1ce7bbb9591a7f8798763d2ada4a0e6` plus Yume Tasks 1-3. Battle Core bank `$0F` was full in Debug before the task. The contiguous battle-picture helper block moved from `$0F` to `Battle Pic Helpers` in pinned bank `$2E`, size `$00BE` = 190 bytes. `AnimateSendingOutMon`, `CopyUncompressedPicToTilemap`, and `LoadMonBackPic` retain their `predef` entry contracts; `CopyUncompressedPicToHL` retains its explicit BANK/switch caller; both fallthrough relationships remain inside the moved unit. The enlarged move renderer and strings are `Battle Move Info` at `$2E:$6808-$6A14`, size `$020D` = 525 bytes; its sole caller is `farcall`, ROMX dependencies are bank-aware, and far-return values use `e` plus Z/C flags. `Battle Pic Helpers` follows at `$2E:$6A15-$6AD2`. Resulting free space is `$010F/$010F/$0108` in bank `$0F` and `$152D` in bank `$2E`; ROM0 remains 31/31/11 bytes free. Smoke passes the Focus Energy crit-threshold probe and remains 25/26 only because of the established deterministic FIGHT 2 mismatch. User visual and battle-frequency acceptance remains pending.

**2026-08-24 Yume Pokedex Task 2 measurement:** forced Red, Blue, and Blue Debug builds succeed at source baseline `7a1a29a8e1ce7bbb9591a7f8798763d2ada4a0e6` plus Yume Tasks 1-2. The new `Pokedex Stats Bar Graphics` section is pinned to bank `$2E` at `$66F8-$6807`, size `$0110` = 272 bytes. `LoadPokedexTilePatterns` reaches it through `BANK(StatsBarGraphics)` and copies it to a temporary Pokedex-only VRAM range; the section has no code or local-pointer dependency. Bank `$2E` then had `$17F8` = 6,136 bytes free in every variant. ROM0 remains 31 bytes free in Red/Blue and 11 in Debug. Focused linked-asset and bar-render tests pass; user Pokedex visual acceptance remains pending.

**2026-08-24 Yume math Task 1 corrected measurement:** forced Red, Blue, and Blue Debug builds succeed at source baseline `7a1a29a8e1ce7bbb9591a7f8798763d2ada4a0e6` plus Yume Tasks 1-3. Only Yume's optimized `_Multiply` is retained; HOME `Multiply` now preserves `de` to maintain Red Rogue's established caller contract. `_Divide` is restored to Red Rogue's original implementation because Yume's four-byte-only contract ignores the valid-byte count supplied in `b`. Optimized division is deferred pending explicit 1-, 2-, 3-, and 4-byte compatibility work. The hybrid math section starts at `$0D:$7D5E`; `_Divide` starts at `$0D:$7D92`. ROM0 has 29/29/9 bytes free in Red/Blue/Debug. ROMX usage is 657,778 Red, 657,763 Blue, and 659,061 Debug with the complete current Yume Tasks 1-3 working tree. All three links pass; focused user runtime retest of lobby selection and battle entry remains pending.

**2026-08-23 superseding measurement for the Enhanced Colors / 60 FPS work:** all three ROMs link successfully. The affected-bank minimums are ROM0 `$0019` = 25 bytes, bank `$01` `$001C` = 28 bytes, and bank `$12` `$17C4` = 6,084 bytes. `Remove Pokemon` moved from bank `$01` to `$12`, range `$6791-$683B`, size `$00AB` = 171 bytes. The existing HOME `jpfar _RemovePokemon` is its only exported entry; the implementation has no direct cross-bank code/data dependency. Focused CGB PyBoy acceptance reached the lobby with `wOptions2 & $C0 == $C0`, `rKEY1` bit 7 set, and the HRAM OAM-DMA wait immediate patched to `$50`. Smoke remains 24/25 with only the established deterministic FIGHT 2 party mismatch.

**2026-08-24 battle palette wiring measurement:** all three ROMs link successfully after restoring ShinRed's CGB attack-animation palette calls in `SetAnimationPalette`. `bank1E` now spans `$4000-$7FBA` (`$3FBB` bytes) and has `$0045` = 69 bytes free in Red, Blue, and Debug, a four-byte net growth from the immediately preceding successful maps. The new edges are plain calls to HOME wrappers `UpdateGBCPal_OBP0` and `UpdateGBCPal_OBP1`, plus the existing bank-aware `SetAttackANimPal` predef. A focused CGB PyBoy Surf probe reached animation `57`, move type `21` (Water), and palette `$11` (`PAL_BLUEMON`). The companion player-head OAM correction in `Battle Core` is size-neutral (`ld [hl], $2`); fresh maps remain 7 bytes free in Red/Blue and exactly full in Debug. The same probe confirmed all 21 intro-head OAM attributes equal `$02`. Full smoke remains 25/26 with only the established deterministic FIGHT 2 party mismatch. BGB visual acceptance remains pending.

**2026-08-24 follower Phase 1 resolver measurement:** forced Red, Blue, and Debug builds succeed at source baseline `2f12cd1a6686ec0ff85028e73b6a4c237b0c9338` plus the focused neutral-resolver WIP. `PCGetBossOWSprite` in `ProceduralCaveGen` now calls `PCGetPokemonSpriteCategory`, whose input/output category contract uses `e` so a future ROMX `farcall` can preserve the result. The packed table was renamed from procedural-boss/follower ownership to `PokemonSpriteCategoryTable`; boss translation remains unchanged. The refactor adds 8 bytes to bank `$05`, reducing minimum free space from `$0097` = 151 to `$008F` = 143 bytes in every variant. Red ROMX is 656,882 bytes used, Blue is 656,867, and Debug is 658,165. Runtime procedural-boss acceptance remains pending.

The 2026-08-23 diagnostic sequence below is retained as relocation history. It is no longer the current build state; forced three-target builds now succeed as recorded above. The initial failing attempt reported:

```text
error: `color_index` is not a macro (four occurrences in engine/gfx/palettes.asm)
error: Section "bank3" grew too big (max size = 0x4000 bytes, reached 0x401A)
error: Section "bank1C" grew too big (max size = 0x4000 bytes, reached 0x4217)
```

At that historical point:

- Bank-free figures not explicitly superseded by a dated row remained 2026-08-22 snapshots.
- After relocating `Bag Item Quantity` and `In-Game Trades` to pinned bank `$2E`, a second assembly attempt reported **no bank overflow errors**. It now stops only on the four pre-existing `color_index` errors. This proves the two assembly-time capacity failures are resolved, but not a completed link.
- Re-run the update procedure in section 6 after the assembly errors and overflows are resolved.

**2026-08-27 pureRGB import measurement (tile-block redraw skip + text-sound guard).** Forced Red, Blue, and Blue Debug builds succeed, zero warnings; `make smoke` 35/35 after each of the two changes.

- **Item 1, `engine/overworld/update_map.asm`.** Vanilla's linear address-range on-screen test in `ReplaceTileBlock` was replaced by pureRGB's per-row `IsBCInHLTileBlockMapView`, plus shinpokered's `cp [hl] / ret z` same-block early-out. `CompareHLWithBC` had no callers outside this file and was deleted. Pinned section `bank3` grew `$3FB3` -> `$3FC5`, **+18 bytes**, against a hard ceiling of `$4000`. ROM0 delta exactly zero.
- **Item 2, the text-sound guard: BUILT, THEN REVERTED THE SAME DAY. Do not retry it.** It moved `TextCommand_SOUND`'s dispatch into a floating `SECTION "Text Sound Guard", ROMX` and reclaimed 17 bytes of ROM0 (34/34/14 -> 51/51/31). It built clean and passed `make smoke` 35/35, **and it was still badly wrong.** Reverted; ROM0 is back to 34/34/14 and bank `$03` free is `$003B` = 59 bytes with the pinned `bank3` section at `$3FC5`. See the failure analysis below.

**Floater churn worth recording, because bank `$03` keeps demonstrating this mechanism.** Bank `$03` reported only `$0010` = 16 bytes free *before* any of this work, which read as a wall. It was not: `bank3` is pinned in `layout.link` and its leftover had been first-fit backfilled by the unpinned 61-byte `Self-Target Stat Penalty`. Real headroom was the `$4000 - $3FB3` = 77 bytes inside the pinned section. Growing `bank3` by 18 bytes evicted that floater automatically, and it moved to ROMX `$06` (Red/Blue) and ROMX `$01` (Debug), a different bank per target, exactly as `project_romx_firstfit_bank_pressure` describes. **Rule: when sizing growth of a section pinned in `layout.link`, read that section's distance from `$4000`, not the bank's `TOTAL EMPTY`** - floaters sharing the bank are displaceable and relocate themselves.

### 2026-08-27 failure analysis: never zero `wAudioFadeOutControl` to force a sound

Recorded because it cost three separate in-game regressions and a clean build plus a full green smoke suite did not catch any of them.

**What was attempted.** pureRGB/shinpokered's text-sound fix saves `wAudioFadeOutControl`, zeroes it across the `PlaySound` call, and restores it, so a fade-out in progress cannot defer the sound out of existence.

**Why that is wrong in this fork.** `home/audio.asm:102-106` states the contract outright: *"If the fade-counter is non-zero, we don't change the audio ROM bank because it's needed to keep playing the music as it fades out. The FadeOutAudio routine will take care of copying `[wAudioSavedROMBank]` to `[wAudioROMBank]` when the music has faded out."* So a nonzero `wAudioFadeOutControl` means **a bank switch is pending**: `wAudioROMBank` still names the OLD bank and `wAudioSavedROMBank` the new one. Sound IDs are bank-relative, so forcing the play resolves the ID against the wrong bank and destroys the pending switch. Observed: buying a Pokemon from the lobby salesman played **evolution music**; the level-up sound played but was **the wrong sound**; picking up an item gave **glitching music, a corrupted text box, and no sound at all**.

**The fix was also unnecessary - the fork already solves that problem, by a different mechanism.** `PrintLetterDelay` (`home/print_text.asm:27-32`) sets bit 2 of `hSFXPlayingDuringText` when a CHAN5 SFX is in flight during zero-delay text, and `PlaySound` (`home/audio.asm:124-133`) tests that bit and calls `WaitForSoundToFinish` before starting a new sound.

**The verification error worth not repeating.** The conclusion "the Shin Phase 2 text-SFX fix never landed" came from grepping `home/text.asm` for the *reference implementation's symbols* (`wAudioFadeOutControl`, `TEXT_DELAY_MASK`, `BIT_NO_TEXT_DELAY`) and finding none. The fork had solved the same problem in `PlaySound`/`PrintLetterDelay` via an HRAM flag, in files that were never searched. **Search for whether the problem is solved, not for whether the reference's code shape is present.**

In-emulator acceptance: item 1 confirmed working by the user. Item 2 reverted, not shipped.

### Last successful overall ROM measurement

| Measurement | Value |
|---|---:|
| Physical ROM image | 1,048,576 bytes (1 MiB, 64 banks) |
| ROM0 used | 16,353 / 16,384 bytes |
| ROMX used | 656,882 bytes in Red; 656,867 Blue; 658,165 Debug |
| Total meaningful bytes used | 673,235 bytes in Red (64.21% of physical image) |
| Free inside linked ROM banks | 178,733 bytes including ROM0 in Red |
| Completely empty internal banks | `$30-$32` = 49,152 bytes |
| Padding banks after highest linked bank `$33` | `$34-$3F` = 196,608 bytes |

The 1 MiB file size is padding to a valid cartridge size. It does not mean every bank is assigned in `layout.link` or safe for arbitrary placement.

---

## 1. Bank budget table

Values are the **minimum free bytes across Red, Blue, and Blue Debug** from the last successful maps. Use the minimum, not the roomiest target. `EMPTY` means no section was linked into that bank.

| Bank | Minimum free | State / placement note |
|---:|---:|---|
| `$00` | 25 | HOME / ROM0. Critical. Never treat as relocation space. Updated 2026-08-23. |
| `$01` | 28 | Critical, Debug-limited. Updated after moving `Remove Pokemon`. |
| `$02` | 17 | Critical |
| `$03` | **16** | The 2026-08-23 "26 bytes over in WIP" note is RESOLVED. Phase 6's Sonnet portion (tier-scaled DV/stat-exp roster rolling) spent ~22 bytes here on two small farcall sites; the real logic lives in bank `$2C` instead. Updated 2026-08-26. |
| `$04` | 53 | Critical |
| `$05` | 143 | Tight. Updated 2026-08-24 after the 8-byte follower neutral-resolver refactor. |
| `$06` | 41 | Critical |
| `$07` | 50 | Critical |
| `$08` | **116** | Audio bank. Now also the first-fit home of the floating `Self-Target Stat Penalty` section, grown 61 -> 116 bytes by follow-up F4; it landed in `$08` in ALL THREE targets this time, unlike the 2026-08-26 split. Measured 2026-09-01. |
| `$09` | 12 | Critical |
| `$0A` | 93 | Critical |
| `$0B` | 68 | Debug-limited |
| `$0C` | 80 | Critical; player back pics share-bank contract |
| `$0D` | **59** | **Critical, Debug-limited.** The 2026-08-24 "468" figure was stale (drifted to 11 by unrelated work before this measurement). `_Divide` optimisation freed 48 bytes; updated 2026-08-27. |
| `$0E` | **291** | Pinned home of every `AILayer*` routine (same-bank `jp hl` dispatch). Spent ~450 bytes on 2026-09-02 for follow-ups F9/F14/F15/F17, ~41 for F19/F20, ~23 for F16 (Quick Attack priority) and ~47 for F22 (rider-wasted-on-kill gate), against the 854-byte headroom the 2026-09-01 re-measurement found. **Note for anyone editing `ai_damage.asm`:** that layer is now large enough that three of its internal jumps had to become `jp` rather than `jr` (the 128-byte relative range); expect the same if you grow it further. Re-measure before trusting any figure here; this bank's floaters move often. Updated 2026-09-02. |
| `$0F` | **17** | Battle Core. **EXHAUSTED - do not budget anything else here without a relocation first.** Phase 4 recovered it from 0 via a farcall swap; Phase 6 spent 30 of 53; Phase 7's `AITrackSeenPlayerMove` hook spent 8 more; follow-up F4 spent 2 more (a 6-byte `call`+`jp` pair became an 8-byte `jpfar`). Red/Blue read 24; **Debug binds at 17.** Updated 2026-09-01. |
| `$10` | 177 | Tight |
| `$11` | 440 | Debug-limited |
| `$12` | 6,084 | Contains pinned `Remove Pokemon` (`$00AB` bytes); still a good candidate after contract audit. |
| `$13` | 85 | Trainer/player front-pic share-bank contract |
| `$14` | 627 | Tight |
| `$15` | 4,144 | Moderate room. Updated 2026-08-27 after EXP Share display preservation; see section 14. |
| `$16` | 6,102 | Good candidate after contract audit |
| `$17` | 6,983 | Good candidate after contract audit |
| `$18` | 3,561 | Moderate room |
| `$19` | 48 | Tilesets, critical |
| `$1A` | 112 | Tilesets, critical |
| `$1B` | 0 | `Tilesets 3` exactly fills `$4000-$7FFF` |
| `$1C` | 3 | Critical. The 2026-08-23 "535 bytes over in WIP" note is RESOLVED - measured clean 2026-08-26, but with almost no margin left. |
| `$1D` | 4,970 | Moderate room |
| `$1E` | 69 | Critical. Updated 2026-08-24 after attack-animation palette wiring. |
| `$1F` | 1,967 | Audio bank; preserve for audio when practical |
| `$20` | 5,320 | Text bank |
| `$21` | 4,959 | Text bank |
| `$22` | 4,557 | Text bank |
| `$23` | 2,170 | Text bank |
| `$24` | 5,884 | Text bank |
| `$25` | 6,989 | Text bank |
| `$26` | 4,853 | Text bank |
| `$27` | 5,154 | Text bank |
| `$28` | 3,298 | Text bank |
| `$29` | 4,918 | Text bank |
| `$2A` | 3,937 | Text bank, Debug-limited |
| `$2B` | 1,992 | Pokedex text |
| `$2C` | **1,976** | Strong relocation bank; holds four pinned AI sections (switching engine, plan engine, Phase 6's `ai_roster.asm`, and Phase 7's `ai_fairplay.asm`). **The 5,498 figure was stale** - the true 2026-09-02 debug minimum is 1,976 after first-fit churn from unrelated work moved floaters in; this session's own F14 spend here was only ~20 bytes (two fitness-bonus insertions in `ai_plans.asm`). Re-measure before trusting any figure here. Updated 2026-09-02. |
| `$2D` | 5,088 | Room/maps/custom systems |
| `$2E` | 3,051 | Established relocation bank; updated 2026-08-25 after Yume Task 4 Bill's PC payload |
| `$2F` | 5,978 | Floating linker allocation in snapshot; pin before relying on it |
| `$30` | 16,384 | Completely empty |
| `$31` | 16,384 | Completely empty |
| `$32` | 16,384 | Completely empty |
| `$33` | 11,231 | AUDIO_4; reserve for AUDIO_4 growth |
| `$34-$3F` | 16,384 each | Physical padding after highest linked bank; add explicit `layout.link` assignments before use |

**Parser caution:** the automated tail parser only records explicit `EMPTY:` ranges. A bank without such a line may be exactly full, fragmented, or require manual inspection. Never infer 16 KiB free merely because a row is absent from a quick report.

---

## 2. Relocation contract checklist

Before moving an `INCLUDE`, classify every exported and imported edge.

| Edge | Safe across banks? | Required action |
|---|---|---|
| `predef Foo` / `add_predef Foo` | Yes | `dba Foo` stores bank and address automatically. Rebuild and confirm pointer bank. |
| `farcall Foo`, `callfar Foo`, `farjp Foo` | Yes | Confirm macro calling convention and return behavior. |
| `BANK(Foo)` plus established far-copy/dispatch | Usually | Confirm the consumer really switches to `BANK(Foo)`. |
| Plain `call Foo` or `jp Foo` | No | Keep same bank or convert through an appropriate bank-aware path. |
| `dw Foo` consumed as a local pointer | Usually no | Pointer lacks a bank byte. Keep producer and target together or redesign table/consumer. |
| Direct `ld hl, Foo` / `ld de, Foo` data read | No | Keep same bank or use an established far-copy/data-dispatch mechanism. |
| Fallthrough or local `jr` | No | Move the entire connected code block together. |
| ROMX routine that switches banks mid-body | Dangerous | Do not relocate casually; execution disappears when its own bank is switched out. |

After a move, inspect `.map`/`.sym` for both endpoints. A successful link proves addressability, not runtime correctness.

---

## 3. Current bank `$1C` overflow and in-game trades

### Recommended move

Move the complete line:

```asm
INCLUDE "engine/events/in_game_trades.asm"
```

out of `SECTION "bank1C", ROMX` and into its own named section, then pin that section to bank `$2E` in `layout.link` near `Predefs` and `Battle Engine 6`.

Suggested structure:

```asm
SECTION "In-Game Trades", ROMX

INCLUDE "engine/events/in_game_trades.asm"
```

```text
ROMX $2E
    ...
    "In-Game Trades"
```

### Why `$2E`

- Last successful minimum free space: 7,513 bytes.
- The trade module measured `$0349` bytes (841 bytes) in the last successful map, from `$1C:5AF5` through `$1C:5E3D`.
- It would leave approximately 6,672 bytes in `$2E` before other current-WIP growth.
- It frees approximately 841 bytes from `$1C`, enough to cover the present 535-byte overflow with about 306 bytes of provisional headroom.
- `$2E` already owns `Predefs`, and both `DoInGameTradeDialogue` and `RogueDoInGameTradeDialogue` are exported through `add_predef` entries whose `dba` records the destination bank automatically.

### Call adjustments

No external call-site changes are expected for the current source (~95% confident): all located gameplay callers invoke one of the two entry points through `predef`, and the predef table stores bank plus address. The module's internal plain calls and 16-bit pointer tables remain valid because the **whole include moves together**.

Required verification after moving:

1. Confirm both labels and both generated `*Predef` entries resolve to `$2E` in all three `.sym` files.
2. Search again for direct external `call`, `jp`, `ld hl`, `ld de`, or `dw` references to any label defined by `in_game_trades.asm`.
3. Full-build all three ROMs.
4. Emulator-check one vanilla NPC trade and one Rogue/legendary trade, including cancel, wrong-mon, successful animation, trade evolution, return to map, and post-trade text.

Do **not** split code from `data/events/trades.asm` or the trade text pointer tables without redesigning the local 16-bit references.

---

## 4. Current bank `$03` overflow

The last successful bank `$03` had only 2 bytes free. Current WIP adds exactly the 26-byte overage through the new enhanced-color paths in `item_effects.asm` and `update_map.asm` (~95% confident from the source diff and assembler delta). This bank needs a relocation, not byte shaving.

### Lowest-risk candidate found

Move `INCLUDE "engine/items/get_bag_item_quantity.asm"` into a separately named section pinned to `$2E` (~90% confident).

- Last successful measured span: `$03:7BF5-$03:7C6E`, `$007A` bytes (122 bytes).
- The exported `GetQuantityOfItemInBag` is represented in `PredefPointers` through `add_predef`, so its bank follows automatically.
- Its cross-bank dependencies (`IsTMHMItem`, `HasTMHM`, `IsKeyPocketItem`, `IsKeyItemActive`, `GetPocketItemCount`) already use `farcall`.
- `GetPredefRegisters` is a HOME helper.
- `GetIndexOfItemInBag` has no located external source references in the current tree, but must still remain with the include and be re-searched after the move.
- Moving 122 bytes would turn a 26-byte overflow into roughly 96 bytes free, based on the current diagnostic.

Pin it explicitly. Leaving a small section floating risks target-dependent first-fit placement, already documented in `layout.link` for `Random` and `Extra Options Menu`.

### Alternatives

- Moving only the new `RedrawMapView_NoChangeAutoBGTransfer` routine is **not** a clean relocation: it jumps into `RedrawMapView.done_AutoBGTransfer` with a same-bank `jp`.
- The hidden-event text handlers at the end of bank `$03` are coupled to 16-bit local text IDs and the bank-3 bookshelf dispatcher. Do not move them individually.
- Micro-optimizing 26 bytes would restore a build but leave no growth margin. Prefer a 100+ byte bank-independent leaf.

---

## 5. Placement strategy

Use these priorities when assigning new sections:

1. Keep hard same-bank clusters together: audio engine families, graphics loaded through one shared `BANK()` assumption, local pointer tables, and routines joined by direct calls/data reads.
2. Put bank-independent farcalled/predef leaves into explicitly pinned relocation banks.
3. Prefer `$2C` or `$2E` for general relocated leaves after measuring all three variants.
4. Preserve `$08`, `$1F`, and `$33` for their audio families.
5. Treat `$30-$32` as expansion banks that need explicit ownership, not a first-fit dumping ground.
6. Pin any new floating section once its intended budget matters. Red, Blue, and Debug can otherwise choose different first-fit banks.
7. Budget against the minimum free bytes across all required targets plus a deliberate margin.

Suggested warning bands:

| Free bytes | State |
|---:|---|
| `0-63` | Critical |
| `64-255` | Very tight |
| `256-1023` | Tight |
| `1024-4095` | Moderate |
| `4096+` | Relocation candidate after contract audit |

---

## 6. Update procedure

### Required build

```powershell
wsl make 2>&1
```

Do not update measured tables from a failed build. Confirm fresh timestamps for all six artifacts:

```powershell
Get-Item pokered.gbc,pokeblue.gbc,pokeblue_debug.gbc,pokered.map,pokeblue.map,pokeblue_debug.map |
    Select-Object Name,Length,LastWriteTime
```

### Overall totals

Read the `SUMMARY:` block at the top of each `.map`. Record ROM0 used/free and ROMX used/free. Use the worst target.

### Per-bank tail report

```powershell
$maps = 'pokered.map','pokeblue.map','pokeblue_debug.map'
foreach ($map in $maps) {
    "MAP $map"
    $bank = $null
    Get-Content $map | ForEach-Object {
        if ($_ -match '^ROMX bank #(\d+):') {
            $bank = [int]$matches[1]
        } elseif ($null -ne $bank -and $_ -match '^\s+EMPTY:.*\(\$([0-9a-fA-F]+) bytes?\)') {
            [pscustomobject]@{
                Bank = ('${0:X2}' -f $bank)
                Free = [Convert]::ToInt32($matches[1], 16)
            }
            $bank = $null
        }
    }
}
```

This reports only explicit tail `EMPTY:` ranges. Also inspect banks printed as bare `EMPTY`, banks with no tail, and any bank with multiple placement constraints. The map summary is authoritative for totals.

### Relocation verification record

For every move added to this Bible, record:

- date and commit or explicit WIP state;
- old bank/range/size;
- new bank/range/size;
- minimum free bytes before and after across all three targets;
- direct-call/data-pointer audit result;
- build result;
- emulator scenarios completed or still pending.

---

## 7. Current action ledger

| Date | Problem | Proposed action | Expected result | Status |
|---|---|---|---|---|
| 2026-08-24 | Yume's Pokedex page needs 272 bytes of bar graphics, while their natural font-graphics bank `$04` has only 4 bytes free | Put the self-contained asset in `Pokedex Stats Bar Graphics`, pin it to `$2E`, and load it through `BANK(StatsBarGraphics)` | Add the exact reference graphics without growing bank `$04` or ROM0 | Implemented in WIP; all three ROMs build; section is `$2E:$66F8-$6807` (`$0110` bytes); bank `$2E` retains `$17F8`; linked payload and 160 rendered bar tiles verified; user visual acceptance pending |
| 2026-08-24 | Yume battle move info cannot fit in full Debug Battle Core bank `$0F` | Move the bank-independent `$00BE` battle-picture helper unit and the enlarged `$020D` move renderer to pinned bank `$2E`; retain predef/explicit-bank edges and use far-return register `e` for the renderer's ROMX helpers | Add the six-field preview while restoring usable Battle Core headroom for this and later Shin work | Implemented in WIP; all three ROMs build; bank `$0F` now has `$010F/$010F/$0108` free and `$2E` retains `$152D`; Focus Energy smoke passes; user visual/frequency acceptance pending |
| 2026-08-24 | Vanilla multiply/divide loops are slower and the divider hangs on divisor zero | Replace the complete bank-local arithmetic file with Yume's Polished Crystal adaptation; retain the existing HOME wrapper contracts | Faster variable-length arithmetic, a defined divisor-zero return, and reclaimed bank `$0D` space without HOME growth | Implemented in WIP; all three ROMs build; bank `$0D` grows from `$014F` to `$01D4` free; 1,271 PyBoy arithmetic cases pass; smoke 25/26 with only the established FIGHT 2 mismatch; user gameplay checklist pending |
| 2026-08-24 | Procedural bosses own a misleadingly named packed species table, while the follower needs the same categories across a bank boundary | Rename the table to neutral ownership, define symbolic category constants, and split category lookup from unchanged boss sprite translation with an `e` input/output contract | Establish one shared species-category source without changing boss output or losing a future follower result to the bank trampoline | Implemented in WIP; forced Red/Blue/Debug builds pass; bank `$05` grows by 8 bytes and has `$008F` = 143 bytes free in every variant; procedural boss runtime acceptance pending |
| 2026-08-23 | Activating ShinRed's full attribute installation from `SetPal_Overworld` first crashes at bank `$08:$6ADB`, then after correcting its unsafe ROMX audio switches freezes with `SP = $5513` in ROM and broad `$39` RAM corruption; the narrowed version still leaves the lobby white because Red Rogue's first adaptation aliases ShinRed's bank-1 primary fade buffer and bank-2 working buffer to the same `$D500` address without reserving bank-1 storage | Keep the independently valid `Func_3082` `farcall` correction and the narrowed attribute ownership; preserve the primary palette snapshot at `$D500` in WRAM bank 2, copy it to a distinct `$D500` workspace in WRAM bank 3 for each fade step, carry palette indices across bank transitions in registers, and never push in one WRAM bank and pop in another | Remove live bank-1 map/save-data reads and writes from the palette path while restoring ShinRed's two-buffer fade contract without consuming ordinary WRAM | Implemented in WIP; all three ROMs build; bank `$1C` has `$000D` = 13 bytes free and helper bank `$2C` has a minimum `$23FB` = 9,211 bytes free; no WRAM0 layout or save address changed; user new-game, fade, and lobby acceptance pending |
| 2026-08-24 | After the two-buffer repair, fades complete but every overworld tile is reddish | Restore the missing enhanced-overworld default command and transfer the already-generated 1 KiB attribute buffer into both CGB BG maps with a local bank-safe general-DMA routine; correct ongoing text/scroll guards to test active-enhanced bit 3 rather than skip-generation bit 4 | Assign each tile its intended palette instead of palette 0 while avoiding the prior ROMX farcall with bank 2 selected | Implemented in WIP; all three ROMs build; bank `$1C` remains `$000D` = 13 bytes free and helper bank `$2C` has a minimum `$23C6` = 9,158 bytes free; user map-color and transition acceptance pending |
| 2026-08-24 | Live CGB probe of the reddish lobby shows all 1,024 generated/installed attribute bytes are zero and all eight hardware BG palettes are identical | Pin the 1,874-byte `Overworld CGB Tile Palettes` section from bank `$04` to its only consumers in helper bank `$2C`; restore the palette index in `a` after selecting WRAM bank 1; replace imported `set 1`/`res 1` `rSVBK` assumptions with explicit bank 2/bank 1 selectors | Eliminate the direct cross-bank table read, generate attributes in the same bank the installer reads, and select all eight palette families | Implemented in WIP; all three ROMs build; focused CGB lobby probe observes attributes `0,2,3,4,6`, an exact 1,024-byte WRAM2-to-VRAM1 match, and eight distinct BG palettes; section is `$0752` = 1,874 bytes in bank `$2C`; resulting bank `$2C` minimum is `$1C79` = 7,289 bytes (Red; Blue/Debug `$1C89`), while bank `$04` repacks to `$0004` free in all variants; debug ROM MD5 `53A7139427BA5AD8F1D88DD674FF4F16`; BGB fade and broader map acceptance pending |
| 2026-08-24 | Enhanced colors look correct while text is open but revert to displaced palette regions after text closes or map rows/columns redraw | Restore ShinRed's missing VBlank dispatch to `GBCEnhancedRedrawRowOrColumn`; Red Rogue already saved redraw mode in `hVblankBackup`, but never consumed it | Keep VRAM bank 1 palette attributes synchronized with BG tile rows and columns after scrolling and full-screen redraws | Implemented in WIP; all three ROMs build; four consecutive movement redraws each dispatch once and preserve an exact 1,024-byte WRAM2-to-VRAM1 match; a start-menu BG-map swap temporarily targets map 1 and returns map 0 to zero mismatches on close; smoke is 25/26 with only the established deterministic FIGHT 2 party mismatch; ROM0 minimum is `$000B` = 11 bytes in Debug (`$001F` Red/Blue); debug ROM MD5 `B426E44C7ACDE4C1C7ABB728916735D1`; BGB map and fade acceptance pending |
| 2026-08-23 | Oak-speech fade-outs leave the CGB screen white until a textbox or menu triggers another palette update | Restore ShinRed's omitted `UpdateGBCPal_BGP` call after every `FadeInIntroPic` DMG palette step and after `MovePicLeft` restores `$E4` | Keep CGB hardware palettes synchronized with Oak speech's six-step DMG fade and normal-palette restoration | Implemented in WIP; all three ROMs build; bank `$01` has a minimum `$0016` = 22 bytes free; supplied BGB state at the stuck fade has a valid interrupt/stack state and confirms this is separate from the reported later crash; user Oak-speech visual acceptance pending |
| 2026-08-23 | Enhanced Colors is saved on (`wOptions2 = $C0`) but the ShinRed enhanced-overworld active flag remains clear, leaving the lab on normal Yellow CGB palettes and routing fades through the normal palette buffer | Restore the palette portion of ShinRed's alternate `SetPal_Overworld` dispatch through a bank-aware helper: clear transient bit 3 before every palette command, set it for enhanced overworld installation, transfer enhanced palettes while WRAM bank 2 is selected, and skip the normal SGB packet return | Restore the warm ShinRed palette family and make all four smooth CGB fades consume the enhanced palette buffer without duplicating Red Rogue's attribute installation | Implemented in WIP; all three narrowed ROMs build; bank `$1C` has `$000C` = 12 bytes free in every variant, and helper bank `$2C` has a minimum `$23EB` = 9,195 bytes free; user BGB palette/fade acceptance pending |
| 2026-08-23 | `$1C` reaches `$4217` | Move complete `In-Game Trades` section to pinned `$2E` | Free ~841 in `$1C`; consume ~841 in `$2E` | Implemented; overflow gone at assembly; link/runtime pending |
| 2026-08-23 | `$03` reaches `$401A` | Move `get_bag_item_quantity.asm` as pinned section to `$2E` | Free ~122 in `$03`; leave ~96 current headroom | Implemented; overflow gone at assembly; link/runtime pending |
| 2026-08-23 | Fresh maps unavailable | Fix four `color_index` macro errors, then rebuild three targets | Replace 2026-08-22 snapshot with current measurements | Pending |
| 2026-08-23 | Issue 2 retains the previous yellow/brown BG palette on stricter CGB emulation | Restore ShinRed's mode-safe, two-byte color transfers for `rBGPD` and `rOBPD`; remove the proven-unused 51-byte party-icon routine to fit bank `$1C` | Prevent blocked mode-3 palette writes; leave 43 bytes free in `$1C` | Implemented in WIP; all three ROMs build; user emulator acceptance pending |
| 2026-08-23 | Issue 6 displays stale title colors on blank transition frames, especially after repeated title/main/debug entries | Restore ShinRed's CGB update calls in HOME `GBPalNormal` and `GBPalWhiteOut`; replace the raw initializer with ShinRed's `DMGPalToGBCPal` conversion flow for BGP, OBP0, and OBP1, adapted to Red Rogue's bank-2 workspace; restore ShinRed's conditional three-frame wait after palette and attribute installation | Keep DMG registers, `wLast*` caches, CGB hardware palettes, and the presented frame synchronized across repeated entries | Implemented in WIP; all three ROMs build; HOME minimum total free is 54 bytes and bank `$1C` minimum free is `$003D` = 61 bytes; focused CGB probe reaches the Debug menu without another input; smoke 24/25 with only the known FIGHT 2 mismatch; user BGB acceptance pending |
| 2026-08-23 | BGB state on Issue 6's persistent purple Debug menu shows random `wMapPalOffset = $C7`, invalid `rBGP = $BA`, and a purple `$38AB` CGB palette while CPU already waits in `HandleMenuInput` | Restore ShinRed's missing `xor a` / `ld [wMapPalOffset], a` title-exit initialization before `LoadGBPal` | Prevent random/saved dark-map offsets from indexing before `FadePal4` and generating arbitrary DMG/CGB palettes | Implemented in WIP; all three ROMs build; bank `$01` minimum free is 2 bytes in Blue Debug; seeded `$C7` exact-sequence CGB probe passes; smoke 24/25 with only the known FIGHT 2 mismatch; user BGB acceptance pending |
| 2026-08-23 | Issue 7 corrupts title, Debug, and clerk lower-menu tiles after Up/Down input | Guard `PrintBagInfoText`'s non-bag path with the active list-menu input flag, require the exact Room PC watched-key context before honoring saved `BIT_ROOM_DESC_BOX`, and remove redundant edge redraw calls; the rejected cursor initialization and routine removal were reverted | Prevent stale list or Room PC description state from drawing into generic menus | Implemented in WIP; clerk fix accepted; attached title state proves `$30` Room PC flags and sole `$FF` at Room description destination `(1,14)`; all three ROMs build; HOME total free is 94 bytes Red/Blue and 74 Debug, bank `$01` remains 9/9/2 bytes free, and bank `$2F` has `$144C` Debug bytes free; combined stale-list/Room-flag CGB title/Debug probe passes; user title acceptance pending |
| 2026-08-23 | Issue 9 shows border-like `$7D,$7E` tiles at the copyright screen's bottom-right after Select | Remove the imported ShinRed gamma-toggle confirmation tile writes while retaining the toggle and confirmation sound | Copyright tilemap remains visually clean after Select | Implemented in WIP; BGB state exactly matches explicit writes to `(18,17),(19,17)`; all three ROMs build; bank `$10` has `$0060` = 96 bytes free in every variant; focused CGB Select probe leaves both cells `$7F`; user BGB acceptance pending |
| 2026-08-23 | Procedural generation and the 13-object Indigo Plateau Lobby run at normal CGB CPU speed despite the imported ShinRed 60 fps option defaulting on | Enable the configured CGB CPU speed once on lobby entry, restore single speed in HOME `WarpFound2` when leaving the lobby, and wrap every active cave/forest/cemetery preload and finalizer in a caller-speed-preserving double-speed envelope | Reduce CPU-bound generation latency and lobby frame overruns without globally enabling ShinRed's not-yet-ported 60 fps overworld timing changes | Implemented in WIP; `ProcStageHooks` remains in bank `$2C` and grows from `$00FD` to `$0149`, leaving minimum `$23FA` = 9,210 bytes free; lobby script remains in bank `$06`, whose minimum tail falls from `$0029` to `$0024` = 36 bytes; HOME grows 11 bytes and retains 63 bytes in Blue Debug; all three ROMs build; smoke 24/25 with only the established deterministic FIGHT 2 party mismatch; focused CGB hook observes `$80` in `rKEY1` at cave-generator entry when the option is enabled; full CGB lobby/generator timing and restoration acceptance pending |
| 2026-08-23 | Make Enhanced Colors and ShinRed-style 60 FPS user-selectable, saved, and default-on without doubling overworld movement speed or breaking DMA/timing-sensitive scenes | Claim `wOptions2` bits 6-7; add menu rows; port ShinRed overworld/player/NPC/scripted/ledge cadence; patch the HRAM OAM-DMA wait to `$28/$50`; preserve single-speed battle, Oak speech, Hall of Fame/credits, link, and S.S. Anne boundaries; move already-`jpfar` `Remove Pokemon` from `$01` to pinned `$12` | Default-on enhanced color and smooth CGB overworld timing with safe fallbacks and 171 bytes reclaimed from fixed bank `$01` | Implemented in WIP; all three ROMs build; ROM0 minimum `$0019`, bank `$01` minimum `$001C`, bank `$12` minimum `$17C4`; focused CGB PyBoy test passes saved defaults, `rKEY1`, and `$50` DMA wait; smoke 24/25 with only the established FIGHT 2 mismatch; user emulator visual/movement acceptance pending |

---

## 8. ROM reclamation audit

This section tracks code and data that could be deleted, stubbed, consolidated, or moved. It is deliberately more conservative than a search for labels containing `Unused`.

### Classification rules

| Class | Meaning |
|---|---|
| **Proven unreferenced** | The current source has a definition and no source reference or table entry. Usually safe to delete after a full build. |
| **Feature-removal candidate** | The code is live and internally referenced, but Red Rogue does not intend to expose the feature. Removing it requires deleting or stubbing every entry path and preserving table/index contracts. |
| **Easy relocation** | The complete section already uses bank-aware entry paths or is intentionally floating. Pinning it elsewhere should not change behavior, subject to a fresh cross-bank audit. |
| **Conditional / historical unused** | A vanilla name says `Unused`, but a table, animation ID, trainer-class slot, or Red Rogue system still references it. Do not delete without changing the consumer. |

> **Removal rule:** source reachability, tables, and runtime dispatch establish whether bytes are removable. A name or comment containing `Unused` is only a lead.

### Verification standard

For every removal:

1. Search the symbol and any numeric/table slot it occupies.
2. Identify the containing bank and measure the byte range from fresh `.sym`/`.map` files.
3. Preserve fixed table lengths and numeric IDs with an alias, stub, or replacement entry when necessary.
4. Rebuild Red, Blue, and Blue Debug.
5. Re-measure the exact bank. Report potential bytes separately from actual linked bytes.
6. Runtime-test any neighboring dispatch table or feature path that was changed.

The measurements below use the last successful 2026-08-22 maps unless stated otherwise. Current WIP measurements remain pending the palette macro fix.

---

## 9. Link cable removal project

Red Rogue does not use link battles or player-to-player trades. The link system is therefore a high-value feature-removal candidate (~95% confident), especially because it occupies ROM0 and bank `$01`, two of the tightest banks. It is **not** one removable include: serial interrupt code, cable-club UI, maps, scripts, battle branches, text, graphics, sprite data, predefs, and fixed tables all participate.

### Critical distinction: preserve in-game trades

Do not remove the common trade animation engine, `InternalClockTradeAnim`, `engine/movie/trade.asm`, `engine/movie/trade2.asm`, or `gfx/trade.asm`. `engine/events/in_game_trades.asm` invokes `predef InternalClockTradeAnim`, so those assets remain live even after cable play is deleted.

Only the external-clock link path and cable-only entry points are candidates inside the shared trade engine.

### Measured primary candidates

| Bank | Candidate | Snapshot bytes | Action / dependency |
|---:|---|---:|---|
| `$00` | `home/serial.asm` | `$01E1` = 481 | Replace the serial interrupt body and any still-required public entry labels with minimal safe stubs. Update the `$0058` serial vector contract. Potential saving is less than 481 because at least an interrupt-safe return path must remain. |
| `$01` | `engine/link/cable_club.asm` | `$07BD` = 1,981 | Remove after deleting `CableClub_Run` predef use and table/NPC entry paths. Largest single bank `$01` win. |
| `$01` | `engine/link/cable_club_npc.asm` | `$0111` = 273 | Remove receptionist dispatch from `TX_SCRIPT_CABLE_CLUB_RECEPTIONIST` or redirect it to a short unavailable-text stub. |
| `$01` | `engine/link/print_waiting_text.asm` | `$002E` = 46 | Remove after link battle and cable-club callers are gone. |
| `$01` | `LinkMenu` code and its three text stubs in `main_menu.asm` | about `$0144` = 324 | Remove the `$5C81-$5DC4` link-menu block. `SpecialEnterMap` is shared and must remain. `CableClubOptionsText` is another 30 bytes at `$5E0E-$5E2B`. |
| `$04` | `LinkReceptionistSprite` | 192 | Replace the fixed sprite-table slot with an existing harmless sprite/alias, then remove `gfx/sprites/link_receptionist.2bpp`. Do not shift sprite IDs. |
| `$08` | `CableClubLeftGameboy` / `CableClubRightGameboy` | about 67 | Remove only after Trade Center and Colosseum hidden-event entries are removed. These live inside `bills_pc.asm`; preserve neighboring PC code. |
| `$13` | Trade Center and Colosseum header/script/object/block cluster | about 150 | Replace map-header slots with a safe dummy/unreachable map contract rather than shifting map IDs. Snapshot cluster starts at `$7F0A`. |
| `$1E` | `LinkCableTiles` tilemap payload | 36 | Preserve the tilemap pointer-table index by aliasing it to a harmless existing tilemap, then delete the payload. |

The primary rows alone represent roughly **3.5 KiB of potential ROM**, before cable-only text, battle branches, special-warps data, map pointer bytes, and the external-clock trade sequence. Actual savings must be re-measured after stubs and fixed-slot aliases (~90% confident).

### Additional link-only surfaces to audit

- `home/header.asm`: serial interrupt vector at `$0058`.
- `home/joypad2.asm`: `predef CableClub_Run` entry path.
- `home/text_script.asm`: `TX_SCRIPT_CABLE_CLUB_RECEPTIONIST` dispatch.
- `engine/menus/main_menu.asm`: `LinkMenu`, cable option strings, serial exchange calls.
- `engine/menus/start_sub_menus.asm`: Trade Center / Colosseum restrictions.
- `engine/menus/text_box.asm`: `CableClub_TextBoxBorder` calls.
- `engine/overworld/special_warps.asm` and `data/maps/special_warps.asm`: four cable-room warps.
- `engine/battle/core.asm`: `LinkBattleExchangeData`, link-loss text, link-state branches, and shared-PRNG paths. This is important for bank `$0F`, which had only 30 bytes free.
- `engine/battle/link_battle_versus_text.asm`: cable-only battle presentation.
- `engine/movie/trade.asm`: remove only `ExternalClockTradeAnim` and external-only sequence entries after proving the internal animation has no dependency on them.
- `scripts/*Pokecenter.asm`: calls to `Serial_TryEstablishingExternallyClockedConnection`.
- `scripts/TradeCenter.asm`, `scripts/Colosseum.asm`, their headers and objects.
- `data/predef_pointers.asm`: `CableClub_Run` and `ExternalClockTradeAnim`; preserve predef indexing rules when deleting entries.
- `data/maps/map_header_pointers.asm` and `map_header_banks.asm`: fixed map-ID slots.
- `data/events/hidden_events.asm`: cable table Game Boy events and school link-help entries.
- `engine/events/hidden_events/school_blackboard.asm`, `data/text/text_2.asm`, and related text-predef pointers: link-help material.
- `data/sprites/sprites.asm` and `gfx/sprites/link_receptionist.2bpp`.
- Link-related WRAM/HRAM. ROM removal may make RAM reclaim possible, but that work belongs in `WRAM_BIBLE.md` and requires a separate union/save-layout audit.

### Recommended removal order

1. Make cable entry paths explicitly unavailable: receptionist, cable table, Pokecenter serial probes, and special warps.
2. Remove/stub cable maps and fixed map/table entries without renumbering IDs.
3. Remove `CableClub_Run`, `LinkMenu`, cable NPC, and waiting UI.
4. Remove link-battle branches from Battle Core and cable-only battle presentation.
5. Reduce HOME serial support to the minimum interrupt-safe stub.
6. Remove link-only sprite, tilemap, and text payloads.
7. Prune only the external-clock half of the shared trade animation.
8. Re-search `Serial`, `CableClub`, `LinkMenu`, `TradeCenter`, `Colosseum`, `ExternalClockTrade`, and link-state constants before building.

This order prevents a partial deletion from leaving a reachable hang or an invalid fixed-table pointer (~95% confident).

---

## 10. Proven or strong unused-code candidates

These are smaller than the cable system but useful in critical banks.

| Bank | Symbol/file | Potential bytes | Confidence / note |
|---:|---|---:|---|
| `$01` | `UnusedReadSpriteDataFunction` in `engine/overworld/movement.asm` | 10 potential | No located source caller or table entry, but the temporary Issue 7 reclamation was reverted after that diagnosis failed. Current bank `$01` free remains 9 bytes Red/Blue and 2 Debug (~98% confident it is unreferenced; not reclaimed). |
| `$0F` | `UnusedHighCriticalMoves` in `data/battle/unused_critical_hit_moves.asm` | 5 | No consumer; the live `HighCriticalMoves` table is separate at `$64DA`. Valuable because Battle Core had 30 bytes free (~98% confident). |
| `$15` | `UnusedPlayerNameLengthFunc` in `engine/events/diploma.asm` | 13 | No located source reference; snapshot `$6CF1-$6CFD` (~98% confident). |
| `$1C` | `UnusedPartyMonSpriteFunction` in `engine/gfx/mon_icons.asm` | 51 actual | Reclaimed 2026-08-23. The definition and its internal tile-loader helper had no source caller or table entry. Fresh Red/Blue/Debug maps leave `$002B` = 43 bytes free in bank `$1C`; runtime party-icon regression remains pending (~98% confident). |
| `$1E` | `FlashScreenUnused` in `engine/battle/animations.asm` | 19 | No located pointer-table or direct reference; snapshot `$502A-$503C` (~95% confident). |
| `$1E` | `AnimationUnusedPalette1-4` | small, re-measure | No located source references. Delete as a group and allow adjacent fallthrough labels to be rechecked (~95% confident). |
| `$1E` | `AnimationUnusedShakeScreen` | 2 | No located source reference; it falls through into the live vertical-shake routine, so delete only its two-byte `ld b,$5` prefix (~98% confident). |

### Things named unused that are not currently free deletions

- `TailWhipAnimationUnused` is referenced by `data/battle_anims/special_effects.asm`. Removing it requires changing the `TAIL_WHIP` special-effect table entry.
- `UnusedBadgeNames` is still required as the fixed `UNUSED_NAME` slot in `NamePointers`. It has already been reduced to a one-byte `"@"` stub. Do not delete the label or shift the table.
- `UnusedJugglerData` and its name/move-choice entries occupy the fixed `UNUSED_JUGGLER` trainer-class slot. Alias or stub the slot; do not shift trainer constants.
- `UnusedAnim` remains part of animation-ID data. Verify its table index before changing it.
- Text labels named unused may still be referenced from map text-pointer arrays, text-predef tables, or historical fixed IDs. Removing only the text body can break a 16-bit pointer table.

---

## 11. Easy relocation opportunities

The 2026-08-22 map shows multiple **un-pinned ROMX sections** in critically tight banks. These are often better first moves than deleting behavior. The sizes and current banks below are snapshot values.

### Highest-priority moves

| Current bank | Free before move | Floating section | Size | Why it is movable / action |
|---:|---:|---|---:|---|
| `$01` | 1 | `HUD Pokeball GFX` | 372 | Source explicitly states all entry points are `callfar` and graphics use `BANK()`. Pin elsewhere (~99% confident). |
| `$01` | 1 | `Single Badge Stat Boost` | 130 | Separate floating section. Audit its callers, then pin (~90% confident). |
| `$02` | 17 | `Poke Flute Item Use` | 268 | Source says its entry stub is bank-aware. Pin elsewhere (~98% confident). |
| `$04` | 53 | `Overworld CGB Tile Palettes` | 1,874 | Source says currently unreferenced. Best immediate action is move it to an expansion bank while CGB work is active; deletion is possible only if the feature plan rejects it (~98% confident for relocation). |
| `$05` | 15 | `ProceduralCaveGen` | 4,570 | Whole generated cluster is already floating. Pin to a roomy/expansion bank after confirming all external entries are farcalls (~90% confident). |
| `$05` | 15 | `Credit Exchange` | 936 | Named floating leaf; audit callers and pin (~90% confident). |
| `$06` | 41 | `ProceduralFacilityGen` | 2,587 | Whole generated cluster is already floating. If the facility remains shelved, it is also a feature-removal candidate; otherwise pin elsewhere (~90% confident). |
| `$06` | 41 | `Trainer AI Core` | 189 | Separate section intended for cross-bank use. Pin after confirming AI dispatch contracts (~95% confident). |
| `$07` | 50 | `ProceduralForestGen` | 3,564 | Whole generated cluster is already floating; pin after farcall audit (~90% confident). |
| `$07` | 50 | `EXP Bar` | 611 | Separate section; audit entry points and pin (~90% confident). |
| `$07` | 50 | `Self-Target Stat Penalty` | 61 | Small floating leaf; pin with related battle helpers (~95% confident). |
| `$08` | 120 | `Pick Up Item` | 372 | Move out to preserve AUDIO_2 growth. Audit entry dispatch and pin (~90% confident). |
| `$08` | 120 | `Pokemon Data 1` | 570 | Source states cry data is accessed through `GetCryData` bank switching. Pin elsewhere (~98% confident). |
| `$08` | 120 | `Drain HP Effect` | 167 | Source explicitly documents `jpfar`/HOME-only dependencies. Pin elsewhere (~99% confident). |
| `$0A` | 93 | `Daycare Upgrade` | 160 | Separate floating section; audit and pin (~90% confident). |
| `$0B` | 68 | `Stat Penalty Functions` | 157 | Source explicitly created it for farcall access. Pin elsewhere (~98% confident). |
| `$0E` | 323 | `ProceduralCemeteryGen` | 2,938 | Whole generated cluster is already floating; pin after farcall audit (~90% confident). |
| `$0E` | 323 | `Rogue` | 2,125 | Floating text/custom section. Move as a whole only after checking whether local 16-bit pointers couple it to `rogue` or another section (~75% confident). |
| `$10` | 177 | `Evos Moves` | 5,984 | Source explicitly documents bank-aware calls/predefs. Strong expansion-bank candidate (~98% confident). |

These moves could restore **more than 20 KiB of combined headroom across tight banks** without deleting gameplay, though each bank benefits only from sections moved out of that bank.

### Large placement candidates and expansion-bank plan

| Snapshot bank | Section | Size | Recommendation |
|---:|---|---:|---|
| `$2A` | `rogue` | 10,973 | Fits alone in one 16 KiB expansion bank. Audit direct edges to the separate `Rogue` section before pinning (~75% confident). |
| `$2A` | `CGB Screen Attributes` | 10,406 | Fresh 2026-08-23 Red/Blue/Debug maps after the Issue 1 DMA-alignment fix. Loader and generated tables intentionally move together. Pin them to a dedicated expansion bank for stable placement (~95% confident). |
| `$10` | `Evos Moves` | 5,984 | Pin to an expansion bank or combine with audited small leaves. |

Suggested ownership, subject to fresh maps after the palette fix:

- `$30`: one large procedural/rogue cluster or `Evos Moves` plus audited small leaves.
- `$31`: `CGB Screen Attributes` alone with growth margin.
- `$32`: another large cluster plus related small farcalled leaves.
- `$34+`: available only after explicitly extending/assigning linker ownership and confirming final cartridge padding/header behavior.

Do not pack these solely by arithmetic. Keep same-bank pointer clusters intact, and avoid mixing planned audio growth into `$33`.

2026-08-23 Issue 1 verification: the floating `CGB Screen Attributes` section moved from snapshot bank `$2F` to `$2A` after adding the required 16-byte alignment before `BGMapAttributes_Unknown1`. Its measured section size is `$28A6` = 10,406 bytes in Red, Blue, and Debug. Bank `$2A` has a minimum total free space of `$1263` = 4,707 bytes across all three fresh maps. All packet labels now have a zero low nibble, all three ROMs build, and a CGB PyBoy probe through frame 1200 found no attribute with VRAM-bank bit 3 set; rendered Game Freak frames no longer contain the white square. User emulator checks of the main menu and overworld text-box cases remain pending.

### Why pinning matters

The linker currently first-fits floating sections into banks `$01`, `$02`, `$04-$08`, `$0A`, `$0B`, `$0E`, and `$10`. This consumes the exact emergency slack needed by those banks and may differ by build target. Once a section is proven bank-independent, pin it deliberately in `layout.link` (~99% confident).

---

## 12. Broader feature-removal backlog

These require product decisions and reachability audits before byte estimates can be trusted:

| Candidate | Likely ROM surfaces | Main caution |
|---|---|---|
| Procedural Facility, if still shelved | generator, maps, SRAM staging support, hooks, text/data | Confirm no stage table, debug path, or shared helper still references it. SRAM savings are tracked separately. |
| Diploma | event routine, text, graphics/path | Confirm whether Pokedex completion remains reachable or desired. |
| Safari/link-era vanilla flows | battle/menu/event code, maps, text | Red Rogue may reuse variables, text, or helpers even if the original feature is unreachable. |
| Unreachable vanilla maps | map headers, scripts, objects, blocks, wild data, text | Map IDs and header tables are fixed; use dummy aliases rather than renumbering. Check Fly, blackout, warps, debug, and procedural tables. |
| Unused music/SFX entries | headers plus channel data | Audio pointer tables and numeric IDs are fixed; alias header slots before deleting channel data. Preserve audio-bank same-bank contracts. |
| Duplicate/obsolete graphics | sprite/pic/tile data | `BANK()` loaders may assume several assets share one bank. Confirm every selectable appearance/form. |
| Debug-only code in release ROMs | debug menu, FIGHT 2 harness, fixtures | Prefer conditional assembly so Debug retains tools while Red/Blue reclaim bytes. Compare all three maps separately. |

For unreachable-map and audio audits, build a table of numeric IDs, pointer slots, current callers, and safe alias targets before deleting any payload. This is where the largest total ROM savings may exist, but it is higher risk than pinning floating leaves or removing the self-contained cable feature.

---

## 13. Yume Bill's PC compact SWAP checkpoint

**Measured:** 2026-08-26, source baseline `cb2b6196` plus the uncommitted Bill's PC icon-parity and compact-SWAP slice.

- Placement remains pinned in ROMX bank `$2E`; no section or bank relocation occurred.
- Before SWAP, the current `Bill's PC` section was `$2E:$6AD3-$744B`, size `$0979`, with `$0BB4` = 2,996 bytes free in bank `$2E` across Red, Blue, and Debug.
- After SWAP, the section is `$2E:$6AD3-$75C6`, size `$0AF4`, a growth of `$017B` = 379 bytes.
- Fresh forced maps leave `$0A39` = 2,617 bytes free in bank `$2E` in Red, Blue, and Debug.
- ROM0 remains 29/29/9 bytes free; WRAM0 remains 1 byte free; HRAM remains full. No RAM declaration or VRAM-allocation change was made.
- Plain calls and direct data reads remain within the pinned `Bill's PC` section or target HOME/shared WRAM. No new bank switch, `BANK()` assumption, pointer table, fallthrough across section boundaries, or mid-routine bank switch was introduced.
- Red, Blue, and Blue Debug all assemble and link. Runtime verification remains pending for menu geometry, cancellation, same-domain record/name swaps, compact-tail moves, count/terminator integrity, save/load, Change Box, custom forms/fusions, and rejected occupied party-to-box selections.

### Occupied party-to-box SWAP extension

**Measured:** 2026-08-26, baseline `d3f4e1e6` plus the uncommitted occupied cross-domain exchange.

- Placement remains in ROMX bank `$2E`; no linker, section, RAM, SRAM, or VRAM declaration changed.
- The `Bill's PC` section grew from `$0AF4` to `$0BF5` (+`$0101` = 257 bytes), ending at `$76C7`.
- Fresh forced Red, Blue, and Blue Debug maps leave `$0938` = 2,360 bytes free in bank `$2E` in every variant. ROM0 remains 29/29/9 bytes free; WRAM0 remains 1 byte free; HRAM remains full.
- Party and box struct pointers use their distinct `$2C` and `$21` strides. Species, OT, and nickname arrays use equal-stride exchange helpers. No new cross-bank direct call or data read was introduced.
- The exchange leaves counts and terminators unchanged, preserves the shared boxed record, writes the outgoing party level into `MON_BOX_LEVEL`, and recalculates the incoming party level/stats through the established load/EXP/fusion/stat path.
- All three ROMs assemble and link. Runtime acceptance remains pending for both selection directions, full party/box, one-member party, record/name/PP/status preservation, fusion/forms, battle loading, save/load, and unchanged counts/order.

### Highlighted Bill's PC icon animation

**Measured:** 2026-08-26, accepted SWAP baseline `b74e44f2` plus the uncommitted animation slice.

- Placement remains in ROMX bank `$2E`; no linker, RAM, SRAM, or assembled-asset placement changed.
- The `Bill's PC` section grew from `$0BF5` to `$0DD8` (+`$01E3` = 483 bytes), ending at `$78AA`.
- Fresh forced Red, Blue, and Blue Debug maps leave `$0755` = 1,877 bytes free in bank `$2E` in every variant. ROM0 remains 29/29/9 bytes free; WRAM0 remains 1 byte free; HRAM remains full.
- Existing icon assets are loaded by established bank-aware video-copy helpers. No direct cross-bank data read or new bank-switching path was introduced.
- Ten formerly short branches were converted from `jr` to equivalent `jp` forms after the added block exceeded JR range. The first build failed at link and was not used for measurements; the corrected forced three-ROM build passed.
- Runtime acceptance remains pending for animation timing, cursor movement/restoration, duplicate categories, SWAP source/destination cursors, redraws/messages, and DMG/CGB presentation.

### PartyMenu-parity animation correction

**Measured:** 2026-08-26, same accepted baseline `b74e44f2` plus the corrected uncommitted animation slice.

- The first animation build copied four raw source tiles and used a fixed 16-frame cadence. Runtime testing showed malformed Monster/Pikachu motion and slower animation than PartyMenu.
- Direct icons now reproduce PartyMenu's symmetric OAM construction in BG tiles: source tiles `offset+0` and `offset+2` form the left half, and generated X-flipped copies form the right half. Static and alternate frame sources now match `MonPartySpritePointers`, including Snake and Quadruped phase order.
- The fixed boxed-mon cadence is now 6 frames, matching the normal healthy PartyMenu cadence. Box records do not expose PartyMenu's immediately available HP-color speed selector.
- The top-border hint is now `START CHANGE BOX`, clarifying that START opens the box selector when no SWAP is pending. B still clears a pending SWAP before START can change boxes.
- The `Bill's PC` section is now `$2E:$6AD3-$7A6E`, size `$0F9C`, leaving `$0591` = 1,425 bytes free in bank `$2E` across Red, Blue, and Debug. ROM0 remains 29/29/9 bytes free; WRAM0 remains 1 byte free; HRAM remains full.
- The larger mirror-copy expansions required three additional `jr` to `jp` corrections before the successful build. Fresh forced Red, Blue, and Blue Debug builds pass. Runtime acceptance remains pending for exact visual cadence/poses, cursor restoration, and Change Box discoverability.

**Accepted checkpoint:** commit `4efed90c3372d9597100bf85f92584b70f7c3d5c` (`PC Update`), pushed to `origin/master` on 2026-08-26. User runtime testing accepted the corrected icon motion, cadence, and Change Box hint. The measured placement and `$0591` bank `$2E` free-space figure above are the committed checkpoint values.

## 14. EXP Share deferred-message buffer preservation

**Measured:** 2026-08-27, baseline `112127cba5aa8175c8d90933eeb75c6a39513443` plus this uncommitted fix.

- The supplied BGB state matched the original Debug ROM MD5 `E963D812294A8071BFBB52EAAD1A8E9F`. Its shared `wStringBuffer` / `wExpAmountGained` bytes contained `THUNDERPUNCH`; the first two bytes `$93,$87` explain the displayed decimal 37767. Move learning occurs after the award but before the deferred party message.
- `GainExperience` now saves each eligible recipient's two-byte display amount on the stack before its UI, restoring it after the no-level-up or complete level-up path, including both existing fusion learn-move passes. Fainted/ineligible slots bypass both operations. Award arithmetic and message timing are unchanged; no RAM declarations changed.
- Old/new bank: `$15` in every variant. `Battle Engine 9` grew from `$5294-$5595`, size `$0302` (770), to `$5294-$55A7`, size `$0314` (788), a net 18 bytes.
- Bank `$15` minimum free space across Red/Blue/Debug: `$1042` (4,162) before -> `$1030` (4,144) after. The earlier table's 4,156 was stale. Following sections shift 18 bytes within the same bank; none changes banks.
- Contract audit: only same-routine stack operations and direct WRAM reads/writes were added. The no-level-up jump now reaches the local restore label; early skips still reach `.nextMon`. No new call, data pointer, BANK() assumption, section boundary, fallthrough across banks, or mid-routine bank switch was introduced. Existing bank-aware callers and local text pointers remain in their original banks.
- Forced Red, Blue, and Debug builds pass; all ROMs are 1,048,576 bytes. Full PyBoy smoke suite: **35/35 passed**. The new regression runs actual EXP/level-up/learn-move code and checks no level-up, level-up without learning, THUNDERPUNCH learning, skipped slots, and stack balance. THUNDERPUNCH writes `$9387` before restoration; the party-message input is 70 and stored EXP increases by 70.
- Test entry uses one normal Joypad call because the FIGHT 2 boot frame ends inside VBlank with interrupts disabled. Direct frame-boundary injection stalled in text waits; this was corrected in the test only, without altering the shared harness or ROM behavior.
- New Debug ROM MD5: `4A1B6F42B241C5587D4CDC199EB97B81`. The old BGB state is evidence for the old ROM only, not a matching state for this build.
- User BGB acceptance pending: reproduce from a normal save on the new ROM, earn shared EXP while learning/replacing/declining a move, check the final party message, and repeat with a fainted final party slot. Fusion secondary learning remains a manual checklist item; the regression covers ordinary learning, not fusion choreography.

## 15. Percent and bag-arrow glyphs (2026-08-27)

- Global font tiles `$E9/$EA` replace unused small kana with the user-supplied percent glyph and Yume 35d3bf9's left arrow. The supplied percent image is 7x7, padded to 8x8. Exact 1bpp rows are assembled in `gfx/font.asm`; the original PNG remains unchanged. FontGraphics stays 1,024 bytes, with no section relocation or VRAM/RAM allocation change. The previous `$C0` left-arrow mapping is removed; existing bag strings now use `$EA`. Source searches found no active small-kana consumers or raw `$E9/$EA` references in the menu/engine code.
- Numeric Accuracy and Crit append `%` at column 9, inside the existing border at column 10. Status-move Crit remains `-`, and screen redraw clears prior suffixes. No arithmetic behavior changes.
- `Battle Move Info` stays in bank `$2E`, growing from `$6B4D-$6D59` (`$020D`) to `$6B4D-$6D61` (`$0215`), +8 bytes. Bank `$2E` minimum free across all three ROMs changes `$024C` -> `$0244` (580 bytes). ROM0 free is 34/34/14; WRAM0 free 1; HRAM free 0.
- Contract audit: no new calls, pointer tables, bank switches, or cross-bank reads. Four immediate tile writes use PrintNumber's existing end-cursor return contract. Font overlays preserve every byte outside the two replacement slots.
- Forced Red/Blue/Debug builds and `git diff --check` pass. All three ROMs are 1 MiB; all 1,024 linked font bytes in each ROM match the expected original-plus-two-glyph overlay. BGB visual acceptance remains pending: bag pocket arrows, town-map return, ordinary/status/guaranteed-crit move previews, disabled moves, and DMG/CGB presentation.

**Acceptance:** user confirmed the glyph update works and committed it as `f6e1cf23` (`font updates`).

## 16. Yume HP artwork, size-neutral overlay (2026-08-27)

- Baseline `f6e1cf23` plus uncommitted HP overlay. Imported exact donor `gfx/font/hp_bar.png` (Yume 35d3bf9; SHA256 `3D1C55D433B080A4A3485E128B36E72AC1FAFD0F8899556624AB4BBC256AE33B`).
- Reordered donor tiles into existing HP IDs: donor 1 -> `$62`, donor 2-11 -> `$63-$6C`, donor 0 -> `$71`. Original `$6D-$70` and `$72-$7F` remain untouched, preserving the connected battle cap, level/status glyphs, HUD borders and EXP aliases. Donor fill tiles/simple cap are byte-identical to existing ones; only the two HP-label tiles change materially.
- Old/new bank: `$04`. `Font Graphics` remains `$4F00-$6457`, size `$1558`; HP/status payload remains `$5A20-$5BFF`, size `$01E0` (480 bytes). Bank `$04` minimum free remains `$0004` in Red, Blue, and Debug. No RAM, VRAM, section-size, or linker-placement change.
- Existing DrawHPBar and every caller/loader are unchanged. No new plain calls, data-pointer tables, BANK assumptions, fallthrough, or bank switches. Existing bank-aware loader consumes the same length at the same address.
- Forced Red/Blue/Debug builds and diff-check pass. All 480 linked HP/status bytes match the expected remapped donor plus preserved original payload in each ROM. User visual acceptance pending for party, status, both battle HUDs, empty/partial/full HP, healing/damage, level-up, EXP bar, DMG and CGB.

**Acceptance:** user reports the HP update looks good, committed as `a71c8676` (`HP update`), matching origin/master. General visual acceptance; individual checklist coverage was not itemized.

## 17. Status view navigation checkpoint (2026-08-27)

- Baseline `a71c8676` plus uncommitted navigation-only slice. START cycles NORMAL -> DVs -> STAT.EXP -> NORMAL; the initial view is always NORMAL. A/B retains the caller's existing page transition. The old held-SELECT/START peek interaction is removed.
- A new `Status View Navigation` section is explicitly pinned to bank `$2E`, `$7DBC-$7E28`, size `$006D` (109 bytes). Minimum bank free across Red/Blue/Debug changes `$0244` (580) -> `$01D7` (471).
- Existing `Battle Engine 1` remains in bank `$04` at `$6458`, shrinking `$1421` -> `$1404` (29 bytes), ending `$785B`. Linker floating-section repacking leaves bank `$04` minimum free `$0003` (previously `$0004`), rather than turning the full local shrink into bank slack. Current trailing sections are Credit Exchange, Procedural Facility Maps and Daycare Upgrade.
- Two status-screen hooks call the new helper through farcall. Its renderer calls existing bank-$04 PrintStatsBox through farcall with mode in e and box type in d. Mode is stack-preserved around Joypad and rendering; no RAM/VRAM declarations or saved state are added. Remaining helper calls target HOME or its own section; strings are local. No direct cross-bank reads, pointer tables or inline ROMX bank switches are introduced.
- Active labels occupy x1..8 on the stats box's top border y8; START uses x13..17,y8. Existing border redraw clears the previous label. Existing DV/stat-exp computations, fusion and active-battle stats, palette setup, HP and move-page PP code are unchanged.
- Forced Red/Blue/Debug builds and diff-check pass; all three ROMs are 1 MiB. Fresh symbols confirm helper bank `$2E`, PrintStatsBox `$04`, and Joypad/DelayFrame/PlaceString HOME.
- Runtime pending: repeated START taps and hold/release, wraparound, A/B page behavior, opening/reopening, party/PC/battle/fusions, and DMG/CGB visuals. Graphical START badge and donor DV/stat-exp layouts/bars remain the next separate slice.

**Acceptance:** user reports navigation works; committed/pushed `c9f7e06f`. General runtime acceptance, not individual checklist coverage.

## 18. Status DV/stat-experience artwork (2026-08-27)

- Baseline `c9f7e06f` plus uncommitted presentation slice. Exact Yume 35d3bf9 stat-exp bar sheet and final three START tiles from its status sheet are assembled as a 224-byte payload. Full stat labels remain visible in the DV view; HP's derived DV is now included. All five stat-exp fields use Yume's raw 0..65535 scale over 32 pixels; only 65535 is fully filled. Normal view restores the original HP fraction and stat numbers.
- `Status View Navigation` moves as a complete code/local-string/asset cluster from bank `$2E`, `$7DBC-$7E28`, size `$006D`, to bank `$2C`: Red `$5C80-$5ED3`; Blue/Debug `$5C70-$5EC3`; size `$0254` (596 bytes). New graphics account for 224 bytes. No other section changes banks in the Red map comparison.
- Minimum bank `$2C` free changes `$152F` (5423) -> `$12DB` (4827); bank `$2E` free changes `$01D7` -> `$0244` (580). Bank `$04` remains `$0003` free; its source and section size are unchanged.
- Existing status entry/wait hooks are farcalls and follow the relocated symbols. Internal branches, calls and strings move together. PrintStatsBox remains a farcall to `$04`, supplied d/e; other external calls are HOME, including CopyVideoData with explicit BANK(StatusViewGraphics). No direct cross-bank data reads or ROMX inline bank switching.
- Graphics occupy unused English-font IDs `$C0-$CD` ($8C00-$8CDF, VRAM bank 0), not Yume's `$31-$3B` backsprite range. Fusion overlays and battle back pictures retain all their tiles. Existing font reload restores these slots; they have no active English text consumers. No RAM/VRAM declarations or save state fields change.
- Existing type/OT/ID arrangement, fusion/stat loading, move page and PP logic remain unchanged. Graphical START occupies x13..15,y8; active label remains x1..8,y8. DV values use full stat labels and HP's number area; stat-exp bars occupy x3..8 on rows10/12/14/16 and x12..17,row4.
- Forced Red/Blue/Debug builds and diff-check pass. All ROMs remain 1 MiB; all 224 linked graphics bytes match the donor-derived payload in each ROM.
- Runtime pending: START cycle/return to normal, HP DV, empty/partial/full training bars, normal/boxed/fusion and active-battle views, move-page PP, return-to-battle sprite preservation, and DMG/CGB visuals. Build/payload checks are not visual acceptance.

**Acceptance:** user reports artwork looks good; committed/pushed `7142862c`. General visual acceptance recorded; unitemized edge cases remain follow-up. Checkpoint is documentation-only and uses the prior successful build measurements above.

## 19. Follower resume baseline, isolated core only (2026-08-27)

- User-confirmed prior follower commit `7a1a29a8` is an ancestor of current `master`/`origin/master` `adff20a29353a42d785417828b021db9d2367d44`. This slice extends `engine/overworld/follower.asm` and adds isolated assembly tests; the follower file remains excluded from the game.
- No game ROM placement or RAM/VRAM allocation changes. `Follower Core Draft` has no assigned game bank and is absent from all three fresh maps/symbols. The synthetic test ROM's section is not a game capacity measurement. No new assembled game INCLUDE, linker entry, or relocation was made.
- Forced Red/Blue/Debug builds pass, all 1,048,576 bytes. Fresh free bytes below are the current committed-game baseline, not savings or consumption caused by the isolated draft:

| Area | Red free | Blue free | Debug free | Minimum |
|---|---:|---:|---:|---:|
| ROM0 | 34 | 34 | 14 | 14 |
| ROMX $01 | 0 | 0 | 41 | 0 |
| ROMX $03 | 59 | 59 | 59 | 59 |
| ROMX $05 | 1 | 1 | 8 | 1 |
| ROMX $2C | 4,827 | 4,843 | 4,843 | 4,827 |
| ROMX $2E | 580 | 580 | 580 | 580 |

- The old follower baseline's 143 free bytes in bank $05 must not be used for new integration. Fresh `ProceduralCaveGen` is still bank $05, size $11E2, with `PCGetPokemonSpriteCategory` at $6BD2 and its table at $6C05. Differences in overall bank slack reflect intervening committed work/linker packing. WRAM0 free remains 1; HRAM free remains 0.
- Draft call/data audit: only HOME `FillMemory` is an external plain call. Movement data and all other calls remain inside the isolated section. Explicit D/E banked inputs avoid the A-clobbering trampoline. No inline bank switch, external local-pointer table, BANK assumption, or cross-section fallthrough was introduced. Final placement and lifecycle callers remain unaudited until integration exists.
- Game ROM MD5: Red `D8E9787C27053385848A1DF666FF2E48`, Blue `6DC01E664CF1DB4994CDFCC1D11ABC52`, Debug `6E3325203ACF7D5E6DB9440CB12587A0`. See `FOLLOWER_CHECKPOINT_2026-08-27.md` for isolated tests and pending in-game movement/visual acceptance. There is no playable follower in these ROMs.

### Accepted follower commit and ready-state continuation

The user committed the preceding slice as `ee438190` (`Follower System Part 2`). On resume, `master` is that commit and the local `origin/master` reference remains `adff20a2`. The subsequent ready/idle/reseed/deferred-init extension remains excluded from the game and adds no game allocation or placement change.

- Forced Red/Blue/Debug builds pass with identical ROM MD5 values to the baseline above. Fresh game maps retain the same free-space figures in the table. No `Follower Core Draft` section or follower runtime symbol appears in the game artifacts.
- The isolated core now calls HOME `Random` in addition to HOME `FillMemory`. Fresh symbols put Random at `$00:$3E85` (Red/Blue), `$00:$3E99` (Debug), and FillMemory at `$00:$378A` / `$00:$379E`. Random's existing HOME wrapper saves registers and restores the caller bank after its banked RNG call. The new idle action pointer table and hop data stay local to the unplaced core section; there is no inline bank switch or cross-section fallthrough.
- 19/19 isolated actual-assembly tests pass, including complete movement after an odd idle half-tick. These use deterministic RNG inputs and synthetic RAM, so they are not a game scheduling, randomness or visual acceptance result. See `FOLLOWER_CHECKPOINT_2026-08-27_READY_STATES.md` for exact coverage and the remaining lifecycle/placement gate.

## 20. Fix batch first slice (2026-08-28, historical b4a88199 WIP build)

Six scoped fixes, subsequently committed by the user in 39a2866b. No RAM-layout changes. Source footprint: Home -5 bytes, bank3 -5 bytes, bank1 +4 bytes; Battle Core and ED loader are size neutral. No explicit section or INCLUDE move was made. The linker repacked existing floating sections in Red/Blue; Debug placements stayed unchanged. All three builds passed; emulator acceptance remains pending.

Full saved baseline/final maps and symbols: FIX_BATCH_2026-08-28. These are historical measurements, not the current 14f2f0cf baseline. Caller audit completed for Pick Up Item (predef), Daycare Upgrade (farcall), Drain HP Effect (jpfar), Self-Target Stat Penalty (farcall), and Trainer AI Core (farcall, local tables). EXP Bar, HUD Pokeball GFX, Pokemon Data 1 and Single Badge Stat Boost follow-up audit completed: callers use bank-aware interfaces and graphics/data bank selection.

# First fix batch: measured ROM changes

Baseline: b4a88199 plus pre-existing status_view.asm WIP. All three baseline and final builds passed. No RAM layout changes.

| ROM | Section | Old bank | New bank | Old bytes | New bytes |
|---|---|---:|---:|---:|---:|
| pokered | bank1 | $01 | $01 | 15772 | 15776 |
| pokered | bank3 | $03 | $03 | 16325 | 16320 |
| pokered | Daycare Upgrade | $07 | $05 | 160 | 160 |
| pokered | Drain HP Effect | $06 | $05 | 167 | 167 |
| pokered | EXP Bar | $01 | $05 | 611 | 611 |
| pokered | Home | $00 | $00 | 16023 | 16018 |
| pokered | HUD Pokeball GFX | $05 | $07 | 372 | 372 |
| pokered | Pick Up Item | $07 | $0B | 372 | 372 |
| pokered | Pokemon Data 1 | $05 | $01 | 570 | 570 |
| pokered | Self-Target Stat Penalty | $06 | $03 | 61 | 61 |
| pokered | Single Badge Stat Boost | $08 | $07 | 130 | 130 |
| pokered | Trainer AI Core | $07 | $06 | 142 | 142 |
| pokeblue | bank1 | $01 | $01 | 15772 | 15776 |
| pokeblue | bank3 | $03 | $03 | 16325 | 16320 |
| pokeblue | Daycare Upgrade | $07 | $05 | 160 | 160 |
| pokeblue | Drain HP Effect | $06 | $05 | 167 | 167 |
| pokeblue | EXP Bar | $01 | $05 | 611 | 611 |
| pokeblue | Home | $00 | $00 | 16023 | 16018 |
| pokeblue | HUD Pokeball GFX | $05 | $07 | 372 | 372 |
| pokeblue | Pick Up Item | $07 | $0B | 372 | 372 |
| pokeblue | Pokemon Data 1 | $05 | $01 | 570 | 570 |
| pokeblue | Self-Target Stat Penalty | $06 | $03 | 61 | 61 |
| pokeblue | Single Badge Stat Boost | $08 | $07 | 130 | 130 |
| pokeblue | Trainer AI Core | $07 | $06 | 142 | 142 |
| pokeblue_debug | bank1 | $01 | $01 | 16281 | 16285 |
| pokeblue_debug | bank3 | $03 | $03 | 16325 | 16320 |
| pokeblue_debug | Home | $00 | $00 | 16043 | 16038 |


| Bank | Baseline minimum free | Final minimum free |
|---|---:|---:|---:|
| $00 | 14 | 19 |
| $01 | 0 | 37 |
| $03 | 59 | 3 |
| $05 | 5 | 5 |
| $06 | 2 | 80 |
| $07 | 17 | 17 |
| $08 | 232 | 362 |
| $0B | 37 | 37 |
| $0F | 15 | 15 |


## 21. Laundry-list completion: HM removal and unused Jessie/James (2026-08-28)

Baseline 53b712e0 built artifacts; final same HEAD plus scoped source changes. All Red/Blue/Debug builds pass; all ROMs 1 MiB. Nine focused machine-state tests pass. No RAM-layout change. Visual/audio/overworld acceptance remains with the user.

Full old/new section-bank/size table, minimum free-space table, maps, symbols and MD5s are in FIX_BATCH_2026-08-28/resume_53b712e0/ROM_MEASUREMENTS.md. This report is part of the measurement record for this entry.

- Jessie James Portrait: new pinned bank $2C, 504 bytes. Jessie James Sprites: new pinned bank $2C, 768 bytes. Minimum free bank $2C: 3914 -> 2642. Trainer portrait dispatcher selects BANK(JessieJamesPic); sprite table carries each asset bank. Existing IDs preserved, appended walker classification handled. No encounters or procedural selection wiring.
- HM removal shrinks Home 17 bytes, bank1 298 bytes, bank3 659 bytes and Battle Engine 1 430 bytes. Trainer tables/dispatcher add 12 bytes to Battle Engine 2, 2 to Battle Engine 3, 55 to Battle Engine 7 and 11 to Battle Core. Minimum HOME free 19 -> 36, Battle Core bank $0F 30 -> 19. Exact per-target sections in the report.
- Linker repacking audit complete: Procedural Facility Maps banks $04 -> $01 Red/Blue and $05 Debug, with BANK(header) and co-located map pointer data; Credit Exchange $04 -> $0E all, entered through HOME bank-aware text handler; Stat Penalty Functions $04 -> $05 Red/Blue and $08 Debug, external farcalls only. No stale direct cross-bank references found in these clusters (~98% confidence).
- Repacked Daycare Upgrade, Drain HP Effect, EXP Bar, HUD Pokeball GFX, Pick Up Item, Self-Target Stat Penalty, Single Badge Stat Boost and Trainer AI Core retain established farcall/predef/BANK(data) interfaces. Local helpers and tables remain in their sections; no inline ROM-bank switch or new cross-section fallthrough.
- Prior slice now committed in 53b712e0: bank1C $3FFD -> $3C71 (16381 -> 15473), net SGB saving 908 bytes, minimum free 3 -> 911. Tilemap trim/reconstruction remains within bank $1C, no RAM change; converter round trips passed. Move Swap Sound is a new pinned $2C section of 96 bytes, entered by farcall from the BC-preserving text handler and calling HOME helpers only. Evolution header copy explicitly selects BANK(BaseStats) through FarCopyData, avoiding the relocated evolution code's bank mismatch.

Pending acceptance: SGB border/palettes, move-swap audible behavior, Jessie/James graphics in a temporary test placement, normal HM teaching/battle use and absence of field actions. Use a land save before upgrading; legacy surf saves normalize to walking and may be stranded. Unused legacy field assets/helpers remain; this is not exhaustive dead-byte reclamation.

## 22. Follower integration placement (2026-08-28)

Baseline: user checkpoint `a1902877`, followed by the excluded pose-staging work. This placement includes the previously excluded follower and lobby-pose workers without adding gameplay hooks yet.

- Bank `$05`: added `FollowerResolveSpriteSheetToDescriptor`, 29 bytes, beside `PCGetPokemonSpriteCategory`, `PokemonSpriteCategoryTable`, `SpriteSheetPointerTable`, and `ReadSpriteSheetData`. It accepts a compile-time-controlled 12-tile `SPRITE_*` ID in `e` and publishes address/count/bank through WRAM because `farcall` destroys `a`/`bc`/`hl`. Minimum free space changed from 44 to **15 bytes** in Red/Blue and from 74 to **45 bytes** in Debug.
- Bank `$2D`: pinned `Follower Core Draft`, `$06fe` / 1,790 bytes, and `Lobby Pose Draft`, `$044c` / 1,100 bytes. Minimum free space changed from `$13e0` / 5,088 bytes to **`$0896` / 2,198 bytes** in all three variants.
- The neutral category map remains in bank `$05`; the new follower-bank translation selects the existing 12-tile Monster, Bird, Seel, Fairy, Voltorb decoration, Snorlax decoration, Omanyte decoration, Pikachu, and Chansey walking sheets. This avoids the boss resolver's four-tile Poké Ball/Fossil/Snorlax sheets.
- Plain calls/data reads were audited: the bank `$05` wrapper directly reads only its same-bank sprite table. External users must `farcall` it and consume the WRAM descriptor. The two bank `$2D` workers use HOME calls, internal calls, farcalls, or caller-owned WRAM descriptors; no new cross-bank plain call or direct data read was introduced (~98% confident).
- Forced Red, Blue, and Debug builds pass. All output ROMs are 1 MiB. Focused follower/lobby suite: 71 tests pass with one intentional expected failure tracking the not-yet-replaced old lobby full-sheet allocator.

Pending runtime work: compact general map loader, lifecycle invalidation, movement/camera hooks, lobby cache transactions, healing ownership, option UI, interaction text, and emulator acceptance.

## 23. Follower compact map loader and approved object cuts (2026-08-28)

Baseline: user checkpoint `8ee5bad9`, which contains the placement recorded above. This slice connects the follower graphics loader to ordinary current-map sprite loading, but still does not tick or interact with the follower in gameplay.

- The approved authored-object cuts are complete: `POWERPLANT_VOLTORB4`, `MTMOON1F_ESCAPE_ROPE`, and `VICTORYROAD1F_RARE_CANDY`. All three maps now contain exactly 14 authored objects. Mt. Moon constants were corrected to the authored object order. Retired Mt. Moon and Victory Road toggle rows remain as inert object 0/OFF entries so later saved toggle indices do not move.
- `InitMapSprites` now derives walking and still sheets from the current authored map roster indoors and outdoors. Ordinary maps reserve walking-sheet slot 2 for the follower and load authored walking sheets into slots 3-10. Zero-object maps still reach follower loading.
- `FollowerLoadMapGraphics` reconciles the enabled option and current lead species, translates every supported category to an existing 12-tile walking sheet, resolves its banked descriptor, copies standing and walking halves into slot 2, and schedules a behind-player rebuild. Text reloads use the LCD-on copy path.
- Indigo Plateau Lobby is deliberately guarded in this intermediate build. It retains slot 2 for its ten authored walking sheets and clears the follower until the already-implemented three-cache stationary-pose worker is connected. This is a temporary integration safety gate, not final follower policy (~99% confident).
- Bank `$05` `Battle Engine 2` is now `$0748` bytes and the bank minimum free space is **2 bytes** in Red/Blue and **32 bytes** in Debug, down from 15/15/45. No further bank `$05` growth should be accepted without relocation or reclamation (~99% confident).
- Bank `$2D` `Follower Core Draft` is now `$07a8` / 1,960 bytes, up from `$06fe` / 1,790. `Lobby Pose Draft` remains `$044c` / 1,100 bytes. Bank `$2D` free is **`$07ec` / 2,028 bytes** in every variant, down from `$0896` / 2,198.
- Banked-call audit: bank `$05` farcalls the pinned bank `$2D` loader; the loader uses farcalls for the category and descriptor resolvers, HOME copy helpers for VRAM transfer, and only local plain calls inside bank `$2D`. No direct cross-bank data read or unsafe ROMX inline bank switch was introduced (~98% confident).
- Red, Blue, and Debug builds pass; all ROMs remain 1 MiB. MD5: Red `8513B58830DE7B425352CC973AFD7421`, Blue `F06930CCE929255D4246FD80644C7538`, Debug `071B936760CFE4A87231F745177CC99E`. The focused follower/lobby suite passes 70 tests with one intentional expected lobby allocator failure.

Pending runtime work: connect the lobby pose publisher and remove the temporary lobby suppression, then add the slot-15 sprite-update exception and accepted-step/tick/camera hooks. Emulator movement and visual acceptance remain pending.

### Compact-loader compatibility follow-up

- The uncalled fixed outdoor loader and `data/maps/sprite_sets.asm` are now excluded from assembly behind `IF 0`; current source retains them as historical reference. Current-map loading is the sole live sprite-loader path. A full reference scan found no remaining caller, direct table reader, pointer-table dependency, `BANK()` assumption, or fallthrough into the excluded block (~98% confident).
- The linker reused the reclaimed bank `$05` range for other floating sections. Fresh bank `$05` minimum free space is **8 bytes** in Red, Blue, and Debug. This replaces the previous 2/2/32 snapshot; it is not  reclaimed-space headroom that can be assumed stable.
- Route reward Poké Balls, fossils, boulders, and other four-tile objects remain independent of the walking allocation. Map object/state slots retain their authored numbers, while still graphics retain image bases 11/12 and physical tile regions `$78/$7c`. The follower uses state slot 15 and image base 2 and is not added to `wNumSprites` (~99% confident).
- Pewter City scripted Super Nerd/Youngster facing, Pewter Pokécenter Jigglypuff rotation, and the shared nurse healing poses previously embedded old fixed-loader image nibbles. They now derive the live actor `IMAGEBASEOFFSET`, subtract one, and convert it to the renderer image nibble before adding facing. This preserves choreography under compact allocation (~99% confident; emulator choreography pending).
- All three ROMs build. MD5: Red `4BDB3084EA409647C247AA82BECD1FF9`, Blue `1D9D41D7AD28E211FE9BC1E2ACE46021`, Debug `55535E5739860BE9724F190D27ED06FD`. The focused sprite-budget suite passes 7 tests plus one intentional expected lobby failure.

## 24. Follower ordinary-map movement hooks (2026-08-28)

Baseline: user checkpoint `393db6f7`, which includes the compact-loader compatibility work above. The lobby remains behind its temporary safety gate.

- HOME now farcalls `FollowerUpdate` once from the normal overworld loop and farcalls `FollowerApplyCameraScroll` with the exact signed player scroll deltas. Accepted steps set a one-byte pending marker in existing follower scratch; the next banked update clears it and calls `FollowerQueuePlayerStep`. This reduced the HOME bridge enough for Debug to link without adding RAM.
- The generic 16-slot sprite updater skips state slot 15, preventing it from entering `UpdateNPCSprite` and indexing nonexistent authored `wMapSpriteData`. Sprite collision scans also skip slot 15, so the follower is visible but nonblocking (~99% confident).
- The pending-step marker shares `wFollowerLoadAction`, whose loader use is synchronous. Every loader success/disable exit now clears it before returning. A map load overwrites stale saved scratch before any follower update, and inactive state ignores the consumed step (~98% confident).
- Cross-bank audit: all three HOME-to-bank-`$2D` calls use `farcall`; camera deltas are passed in `de`, which survives the trampoline and the callee, while `bc` is saved around the call. No plain cross-bank call, direct banked data read, or ROMX inline bank switch was introduced (~99% confident).
- Fresh free space: HOME 31/31/11 bytes in Red/Blue/Debug, minimum 11; bank `$05` 8 bytes in all variants; bank `$2D` `$07d2` / 2,002 bytes in all variants. WRAM/HRAM layout is unchanged.
- Red, Blue, and Debug builds pass. MD5: Red `CEA36A5297F191B236D2BE2F8CE227BA`, Blue `9EA3AA3F248326CADF24D16DB1CA8D85`, Debug `3C2A507EF783952E30430C01FF525E49`. Focused follower/lobby suite: 73 tests pass with one intentional expected lobby allocator failure.

Pending acceptance: actual ordinary-map spawn, one-step lag, all directions, ledges, fast/60 FPS cadence, connected-edge behavior, battle/text return, and visual/collision behavior in DMG/CGB. Build and isolated machine-state coverage do not establish emulator choreography.

## 25. Follower player option (2026-08-29)

Baseline: user checkpoint `2554d99a`; final user commit `eced2e58`. This slice adds the persistent enabled-by-default follower toggle without changing RAM layout or moving an assembled section.

- `wOptions2` bit 3 is named `BIT_FOLLOWER_DISABLED`. Clear means follower ON; set means OFF. `InitOptions_` deliberately leaves it clear while continuing to enable enhanced colors and 60 FPS.
- Extra Options now has six rows. `FOLLOWER` displays the inverted bit correctly and masks only bit 3, preserving difficulty, audio, color, and speed settings.
- Fresh Red, Blue, and Debug maps place `Extra Options Menu` at `$2E:$6772-$6A75`, size **`$0304` / 772 bytes**. Bank `$2E` retains **`$020B` / 523 bytes** in all three variants.
- No section, include, pointer table, direct data read, `BANK()` assumption, or call boundary moved. The menu remains in its existing floating `Extra Options Menu` section; its existing caller contract is unchanged (~99% confident).
- Forced Red, Blue, and Debug builds pass. The focused follower sprite-budget suite passes nine tests with one intentional expected failure for the not-yet-replaced lobby allocator. Runtime menu navigation and save persistence remain user acceptance items.

## 26. Lobby pose-cache lifecycle reset (2026-08-29)

Baseline: committed follower-option checkpoint `eced2e58`; final source is uncommitted pending user checkpoint.

- The existing lobby branch of bank `$2D` `FollowerLoadMapGraphics` now calls the same-bank `LobbyPoseCacheReset` on the integrated `wLobbyPoseCacheState` before temporary lobby suppression. This establishes the full sprite-reload invalidation boundary without adding a bank `$05` loader hook or a bank `$01` renderer hook.
- The reset invalidates all requested/committed descriptors, dirty/valid flags, and healing ownership. It runs after the map loader farcall reaches bank `$2D`; no new cross-bank plain call, direct data read, `BANK()` assumption, section move, or RAM-layout change is introduced (~99% confident).
- `Follower Core Draft` grows from `$07C2` to **`$07C8` / 1,992 bytes**. `Lobby Pose Draft` remains **`$044C` / 1,100 bytes**. Fresh bank `$2D` minimum free space is **`$07CC` / 1,996 bytes** in Red, Blue, and Debug.
- Forced Red, Blue, and Debug builds pass. Focused source, cache-manager, and pose-assembly coverage passes 36 tests with one intentional expected failure tracking the old full-sheet lobby allocator.

Pending: compact lobby sheet allocation, request generation from current facings/OAM offsets, early-VBlank publication, healing ownership call sites, removal of temporary suppression, and emulator visual acceptance.

## 27. Live lobby follower allocation and pose publication (2026-08-29)

Baseline: user checkpoint `802a06db`. This slice activates the specialized Indigo Plateau Lobby allocation and removes temporary follower suppression when that allocation succeeds.

- Bank `$2D` `Follower Core Draft` is **`$07D0` / 2,000 bytes**, from `$6C20-$73EF`. `Lobby Pose Draft` is **`$06D6` / 1,750 bytes**, from `$73F0-$7AC5`. Fresh minimum free space is **`$053A` / 1,338 bytes** in Red, Blue, and Debug.
- The lobby retains all eleven authored NPCs. Seven actor types receive full 12-tile sheets in physical bases 3-9; the salesman remains the only walking NPC and keeps a full sheet. Channeler, Super Nerd, and Game Boy Kid share image base 10 through independent four-tile caches at physical tile bases `$6C`, `$70`, and `$74`.
- Cache maintenance derives each actor's current renderer image and shadow-OAM offset, patches only its four tile IDs, and publishes changed tile data through the existing `hVBlankCopy*` mailbox. The descriptor is written with interrupts disabled and size is published last; VBlank copies tiles before shadow-OAM DMA (~98% confident).
- Cache maintenance returns while `hUpdateSpritesEnabled == $FF`, preserving the nurse healing machine's ownership of shadow OAM entries 33-39. Normal cache work resumes after sprite updates are re-enabled (~97% confident; emulator choreography pending).
- The ordinary LCD-off follower graphics copies now use `FarCopyData3`, matching the actual `a:de` source and `hl` destination contract. The prior `FarCopyData2` calls reversed those operands and likely copied in the wrong direction (~99% confident).
- No RAM layout, section bank, include placement, or cross-bank direct-read contract changed. The bank `$2D` workers call each other directly and use established farcall/HOME copy seams for external banks and VRAM transfers.
- Forced Red, Blue, and Debug builds pass. All ROMs remain 1 MiB. MD5: Red `D2CCDD6AC4B84C3A3F69D73BEFFB2DEB`, Blue `15358C232F181BD37B58A3B610785EC6`, Debug `F1DC95C7B70ECC262A621C71210E3716`. Focused follower, pose-cache, pose-assembly, and sprite-budget suites pass **69 tests**.

Pending acceptance: visually confirm all lobby NPCs and the follower on entry, NPC facing changes, salesman's walking animation, nurse healing-machine animation and recovery, text-driven sprite reloads, toggle OFF/ON behavior, and DMG/CGB cadence. Build and isolated machine-state coverage do not prove final OAM/VRAM choreography.

## 28. Centralized follower party-identity refresh (2026-08-29)

Baseline: user checkpoint `b7a02c9f`; accepted final user commit `38bd88e6`. This slice adds no RAM and does not move an assembled section or include.

- Bank `$2D` `Follower Core Draft` grows from `$07D0` to **`$0801` / 2,049 bytes**, now `$6C20-$7420`. `Lobby Pose Draft` remains **`$06D6` / 1,750 bytes** and shifts with the preceding fixed section to `$7421-$7AF6`. Fresh minimum free space is **`$0509` / 1,289 bytes** in Red, Blue, and Debug.
- `FollowerUpdate` now polls `wPartyCount`, the primary `wPartySpecies` entry, the persistent OFF bit, and temporary suppression once at the existing normal overworld tick. Stable identity does not reload or disturb the queue. A changed or newly eligible identity calls HOME `ReloadMapSpriteTilePatterns`, whose established banked implementation disables LCD, rebuilds current map sprite allocation, reloads follower slot 2, and returns to the caller. Disabled or empty-party state clears immediately (~97% confident).
- This central boundary covers party reorder, evolution, PC deposit/withdrawal, party removal/addition, trades, daycare, gifts, custom mutations, and option changes when normal overworld control resumes, without adding hooks to each writer (~97% confident). Fainting does not change identity by approved policy.
- The bank `$2D` routine calls a HOME wrapper, not a plain cross-ROMX call. The HOME wrapper uses the established far jump to the relocated reload implementation, which returns after restoring map sprite graphics. No direct cross-bank data read, inline ROMX bank switch, or new RAM contract is introduced (~98% confident).
- Forced Red, Blue, and Debug builds pass. All ROMs remain 1 MiB. MD5: Red `FC56C96D8C601812B2172587AE866E7D`, Blue `83A09BDA7A218713EA8590586CE8379C`, Debug `2B37A075D9172E23AE32C3FC75FF99BB`. The complete focused follower/lobby suite passes **70 tests**.

Pending acceptance: reorder the lead, evolve the lead, deposit/remove the lead, withdraw/add into an empty party where allowed, toggle OFF/ON, and exercise relevant custom gift/trade/daycare paths. Confirm the follower disappears or reloads once normal overworld control resumes and that no stale sheet appears.

## 29. Follower runtime containment after failed acceptance (2026-08-29)

Commit `38bd88e6` failed runtime acceptance. The prior sections 27 and 28 remain historical measurements, not accepted behavior. User evidence showed repeated white/lobby flicker, corrupt NPC graphics, absent follower/witch, and broken slow player animation and movement outside the lobby.

- Root cause: the normal follower tick could call `ReloadMapSpriteTilePatterns`; its loaders used `wFontLoaded == 0` as permission for direct VRAM writes even though the LCD was on during ordinary gameplay. Repeated reloads could corrupt graphics and stall the overworld (~99% confident).
- Containment removes the live identity-refresh call and helper. It also removes `LobbyPoseUpdate` from the live tick and restores the lobby loader branch that clears/suppresses the follower without calling the specialized allocator.
- The specialized lobby code remains assembled but unreachable from gameplay. No RAM layout or include placement changes.
- Fresh bank `$2D`: `Follower Core Draft` **`$07C8` / 1,992 bytes** at `$6C20-$73E7`; dormant `Lobby Pose Draft` **`$06D6` / 1,750 bytes** at `$73E8-$7ABD`; free **`$0542` / 1,346 bytes** in every variant.
- Forced Red, Blue, and Debug builds pass. MD5: Red `3891D1243357C4359B6AFD383EFBE7E0`, Blue `4C370540CD27411FB884F089F228308C`, Debug `1F4522E3194487A3DF8EC9739AC65880`. Focused suite: **69 tests pass**.

Pending: user must verify normal player movement and ordinary-map follower behavior first, then stable lobby NPC rendering with no follower. No further follower features should be activated before this gate passes.

## 30. Follower Checkpoint C contained graphics reservation (2026-08-29)

Baseline: accepted clean follower baseline `4ef06335`. This is a deliberately contained donor-style loader test, not global follower integration.

- `LoadMapSpriteTilePatterns` retains the existing Red Rogue indoor/outdoor loader and allocation algorithm. On `SILPH_CO_B1F` and `SILPH_CO_DORM` only, the initial walking image-base maximum changes from 1 to 2, so authored walking sheets begin at base 3 and base 2 remains reserved and empty. Yellow's unused-picture guard is also ported so Dorm's disabled decoration slots do not resolve sprite ID 0 as graphics.
- No follower file is included, slot 15 is unpublished and unticked, no species graphics are loaded, and every other map retains its prior allocator path. This avoids changing the lobby or outdoor sprite sets while establishing a donor-faithful test seam (~99% confident).
- `Battle Engine 2` is now `$074B` / 1,867 bytes at bank `$05:$6340-$6A8A`, a 14-byte increase from the clean baseline's inferred `$073D`. Fresh minimum bank `$05` free space is 28 bytes in Red/Blue and 58 bytes in Debug.
- Forced Red, Blue, and Debug builds pass. All ROMs remain 1 MiB. MD5: Red `B0E6BE7D79AFFFFF5BEF5007F57E5FBB`, Blue `DFCFBB196DF57D338A42027A6B79F5F8`, Debug `5F45F8464933A18D13E5721B243CB246`. Focused sprite-budget tests pass 4 tests plus the existing intentional lobby expected failure.

Pending user runtime acceptance: normal player and NPC animation in Silph Co B1F and Dorm, Dorm decoration variants, B1F scripted movement, text open/close reload, and warps between both maps. No follower should appear.

## 31. Follower Checkpoint D contained stationary Pikachu

**Measured:** 2026-08-29, user Checkpoint C commit `c9a94971` plus the uncommitted Checkpoint D test slice.

- A new pinned `Follower Baseline` section is assembled in ROMX bank `$2D` at `$6C20-$6CE4`, size **`$00C5` / 197 bytes**. It publishes fixed Pikachu in state slot 15 only on `SILPH_CO_B1F` and `SILPH_CO_DORM`; it contains no queue, party resolver, option, interaction, warp policy, or follower RAM.
- Bank `$05` calls the new section with `farcall` after the existing sprite loader finishes. The bank `$2D` worker uses `BANK(PikachuSprite)` with established HOME copy helpers and only local plain calls. No direct cross-bank read or unsafe ROMX bank switch was introduced (~99% confident).
- Bank `$01` `_UpdateSprites` gives slot 15 a stationary screen-position update and retains the original player and authored-NPC paths. Fresh minimum free space is **1 byte** in Red/Blue and **38 bytes** in Debug. Bank `$05` retains **20/20/50 bytes**. Bank `$2D` retains **`$131B` / 4,891 bytes** in every variant.
- Text-close sprite reloads occur while `wFontLoaded` is set. That path reloads Pikachu's walking graphics but does not republish or reposition slot 15; initial LCD-off map loading performs the publication (~99% confident).
- No WRAM, HRAM, SRAM, VRAM declaration, or object-count layout changed. Red, Blue, and Debug builds pass. MD5: Red `B82168A3EE26A96397C23E6676E0203D`, Blue `923C076017D508C5435AC2D907911647`, Debug `7C8B2CE24F0BFDD2A993201CDC01048B`. Focused coverage passes 10 tests with one intentional expected lobby-capacity failure.

Pending runtime acceptance: fixed Pikachu appearance behind the player, stationary map position under player movement and camera scroll, normal player/NPC animation and collision, text open/close stability, map reload/warp behavior, and clean removal on excluded maps.

**Reverted:** Runtime testing found that Pikachu did not appear. The entire uncommitted stationary-publisher slice was removed on 2026-08-29, returning live source to user commit `c9a94971`. The measurements above are retained as rejected historical evidence and are not current placement figures.

## 32. Coherent Yellow-derived fixed-Pikachu follower slice

**Measured:** 2026-08-30, user commit `c9a94971` plus the uncommitted contained implementation.

- New bank `$2F` `Follower Core` is `$02EF` / 751 bytes at `$4000-$42EE`. It contains only the fixed-Pikachu B1F/Dorm spawn, Yellow sentinel queue, accepted-step following, ordinary movement, overlap hiding, text recovery, image update, and slot-specific camera correction.
- `Subtract Paid Money` moved intact from fixed bank `$01` to bank `$2F:$42EF-$4311`, `$0023` / 35 bytes. Its implementation has one entry through the existing HOME `SubtractAmountPaidFromMoney` far-jump wrapper; the Pokemart calls that HOME label. Its outbound calls remain HOME or predef. No plain cross-ROMX call, direct banked data read, pointer-table dependency, `BANK()` assumption, fallthrough, or mid-routine bank switch was found (~99% confident).
- `_UpdateSprites` retains Yellow's slot-15 ownership through a banked tail dispatch. Accepted steps and actual camera scrolling use separate HOME farcalls. The camera hook receives authoritative signed deltas only from `AdvancePlayerSprite.scrollBackgroundAndSprites`, and preserves the prior BC/DE return contract (~99% confident).
- Fresh minimum free space: HOME **34 bytes** Red/Blue and **14 bytes** Debug; bank `$01` **4/4/59 bytes**; bank `$05` **31 bytes** in all variants; bank `$2F` **`$1205` / 4,613 bytes** Red/Blue and **`$113A` / 4,410 bytes** Debug.
- Red, Blue, and Debug builds pass. MD5: Red `EB6BAE397C0F94C03FEE9776F2C9CA71`, Blue `47C0BADB90AA29EFC165585374B216FE`, Debug `45650D05EC1AA9E0AD3B83675211182A`. Focused source and sprite-budget coverage passes 11 tests with one intentional lobby expected failure. A live Debug-ROM PyBoy smoke reaches the real Dorm map-load lifecycle, verifies Pikachu in slot 15/base 2, records two accepted steps, and verifies visible one-step-lag following.

Pending: user BGB acceptance in Dorm and B1F, including four directions, blocked movement, camera edges, text, decorations/NPCs, and map departure. PyBoy machine-state evidence does not establish final visual choreography.

## 33. Follower ordinary-behavior correction slice

**Measured:** 2026-08-30, current `master` commit `937e25be` plus the uncommitted contained follower implementation. The commit's bridge-stage computer change is intentional and unrelated.

- `Follower Core` is now `$0392` / 914 bytes at bank `$2F:$4000-$4391`. The added code is a slot-explicit port of Yellow's `WillPikachuSpawnOnTheScreen`: map bounds, the four background tiles under Pikachu, image `$FF` on coverage, and grass priority. It runs in Yellow's original order before font-loaded recovery (~99% confident).
- `Subtract Paid Money` remains intact at bank `$2F:$4392-$43B4`, `$0023` / 35 bytes, with the same HOME far-jump entry contract. No new cross-bank data read, plain cross-ROMX call, or mid-routine bank switch was introduced (~99% confident).
- Bank `$01` skips slot 15 as a normal collision target. Fresh minimum free space is HOME **34/34/14 bytes** Red/Blue/Debug; bank `$01` **1/1/56 bytes**; bank `$05` **31 bytes** in all variants; bank `$2F` **`$1162` / 4,450 bytes** Red/Blue and **`$1097` / 4,247 bytes** Debug.
- Red, Blue, and Debug builds pass. MD5: Red `C6E85CC5C861CAE67224CF338F2D0EF1`, Blue `06AC454A6EE2BAA14083D87556535D93`, Debug `D6C768807432ABD0DE53D79533C225F0`. Focused source and sprite-budget coverage passes 15 tests with one intentional lobby expected failure. The live Debug-ROM Dorm matrix verifies production following, covered and uncovered Start-menu positions, Trainer Card cleared-tilemap suppression, and overworld tilemap restoration.

Pending: user BGB visual acceptance in sparse B1F and crowded Dorm. The software overlap-hide flicker path is removed (~97% confident), but crowded horizontal scanlines can still exceed the Game Boy's 10-sprites-per-scanline hardware limit and must be distinguished by comparing the sparse and crowded maps (~95% confident).

## 34. Accepted fixed-Pikachu transitions and standard interaction baseline

**Measured:** 2026-08-30, clean `master` commit `925d9b94`, synchronized with `origin/master`.

- Bank `$2F` `Follower Core` is **`$05D8` / 1,496 bytes** at `$4000-$45D7`. It now contains the contained-map graphics path, Yellow-derived queue and movement, ledges, visibility and textbox recovery, Yellow warp-placement policies, connected-edge state handling, battle persistence, front-facing A-button interaction, and face-player behavior.
- `Subtract Paid Money` remains intact at bank `$2F:$45D8-$45FA`, **`$0023` / 35 bytes**. Red Rogue custom code resumes at `$45FB`. Fresh bank `$2F` free space is **`$0F1C` / 3,868 bytes** in Red and Blue and **`$0E51` / 3,665 bytes** in Debug.
- `High Home` is **`$009E` / 158 bytes** at `$0061-$00FE`. The `FollowerInteraction` trampoline occupies `$00F7-$00FE`, leaving `$00FF` free. Fresh total ROM0 free space is **22 bytes** in Red, **22 bytes** in Blue, and **2 bytes** in Debug.
- Interaction preserves the authored object/sign scan and adds a temporary slot-15 front-tile scan. Slot 15 remains excluded from normal collision, so talking does not make the follower solid (~98% confident).
- The text path reuses unused predef text slot `$1E`, so `data/text_predef_pointers.asm` remains size-neutral. Standard `DisplayTextID` owns the bottom textbox, font lifecycle, sprite refresh, prompt, and close behavior. `hNoWaitAfterText` is set only around the explicit prompt and cleared afterward (~98% confident).
- The interaction-facing bit is consumed before font/status processing. The follower faces opposite the player, resets the relevant animation counters, and preserves its queue and map coordinates (~97% confident).
- User runtime testing accepts ordinary following, sustained catch-up, wall recovery, battle return, Route 1 ledge behavior, the Route 1 graphics correction, and the Yellow transition slice. Connected-edge state handling is assembled but has no active Red Rogue gameplay fixture.
- No WRAM, HRAM, or SRAM layout changed in this wave. Red, Blue, and Debug builds pass. MD5: Red `008D4560FCE29C6E865D31A3E50022F5`, Blue `570AFCEAB4BDB7FBBAEBF1CF753E744C`, Debug `13789EA6427B5DCFB497960FCF48B127`. The focused follower suite passes **22 tests**.

Pending: visually confirm the corrected standard bottom dialogue box in BGB. Checkpoint G then replaces fixed Pikachu identity with lead-species resolution and existing overworld sprite categories at safe lifecycle boundaries, followed by species-name-plus-`!` text and the species cry. The rejected per-frame identity polling and live VRAM reload architecture remains prohibited.

## 35. Contained all-species identity and interaction correction

**Measured:** 2026-08-31, `master` commit `925d9b94` plus the uncommitted Checkpoint G correction wave.

- Bank `$2F` `Follower Core` is **`$064D` / 1,613 bytes** at `$4000-$464C`. `Subtract Paid Money` remains intact at `$464D-$466F`, **`$0023` / 35 bytes**. Red Rogue custom code begins at `$4670`.
- Fresh bank `$2F` free space is **`$0EA7` / 3,751 bytes** in Red and Blue and **`$0DDC` / 3,548 bytes** in Debug. Bank `$05`, which contains the existing category resolver and map sprite loader, has **`$005B` / 91 bytes** free in every variant. `High Home` remains `$0061-$00FE`, and total ROM0 free remains 22/22/2 bytes.
- `FollowerPrepareMap` now reads the ordered lead from `wPartySpecies` only at the established map/text sprite-preparation boundary. It farcalls bank `$05` `PCGetPokemonSpriteCategory`, receives the category in `E`, and translates all nine categories to 12-tile walking sheets. Poké Ball, Fossil, and Snorlax categories use the existing Voltorb, Omanyte, and Snorlax decoration walking sheets rather than unsafe four-tile object sheets (~99% confident).
- Indoor loading treats any active slot-15 picture as the reserved follower. Route 1 inserts the resolved sheet into fixed-set entry 0 and forces the Pallet/Viridian set to rebuild when leaving the modified layout. No per-frame party poll or LCD-on direct VRAM reload was added (~98% confident).
- A lead-sheet change during the normal font-loaded menu-close reload preserves map coordinates, screen coordinates, movement state, queue, and facing. It changes only the slot-15 picture/base and runs Yellow's normal text refresh, preventing the prior invisible/down-facing first frame (~98% confident).
- Interaction uses `GetMonName` with `wNamedObjectIndex`, prints `wNameBuffer` plus `!`, calls HOME `PlayCry`, and retains the standard prompt. The handler preserves `bc`, the live text cursor. It does not use aliased `wCurPartySpecies`/`wCurItem` (~99% confident).
- Yellow `GetPikachuWalkingAnimationSpeed` uses 2 logical ticks at happiness 80 or above and 5 otherwise. This slice retains the exact 2-tick happy cadence for Pikachu and uses Yellow's 5-tick cadence for other species as a conservative baseline. Any per-species/category tuning remains a visual design follow-up, not donor behavior.
- No WRAM, HRAM, or SRAM layout changed. All three ROM variants build. MD5: Red `68DE7239B6BA3666FA0A772702D065AA`, Blue `3D98D718FD5A15391D73C29FADED05A5`, Debug `4BA411886BBB62D303391F4C80D064D2`. Focused verification passes **59 tests**, plus one longstanding expected lobby-capacity failure.

Pending BGB acceptance: species name and cry ordering, prompt hold, immediate visible/facing-correct lead replacement, Pikachu cadence, and the slower non-Pikachu cadence on several sprite categories.

## 36. Follower toggle and restored interaction text

**Measured:** 2026-08-31, accepted `master` commit `c03c30f4` plus the uncommitted text rollback.

- Existing `wOptions2` bit 3 is now the persistent follower-disable bit. Clear means ON, preserving the behavior of existing and new saves. This names an unused bit in an existing byte and does not change WRAM, HRAM, SRAM, save size, or initialization layout.
- Extra Options now has six rows: Audio, Instant Text, Levels, Colors, Follower, and 60 FPS. LEFT or RIGHT toggles the follower row. The option takes effect at the established `FollowerPrepareMap` map/text sprite-preparation boundary; OFF clears slot 15 and its queue, while ON resolves the current lead again.
- The attempted name-before-cry implementation regressed the interaction text and was reverted at the user's request. The restored handler calls `GetMonName`, starts `PlayCry`, then returns the established `text_ram wNameBuffer`, `text "!"`, `prompt` stream. The text cursor `bc` remains preserved. Further ordering changes are user-owned. Per user direction, dynamic long/custom species names are not subject to a new 17-character audit in this checkpoint.
- Bank `$2F` `Follower Core` is **`$065D` / 1,629 bytes** at `$4000-$465C`, up 16 bytes from section 35 for the toggle gate. `Subtract Paid Money` remains intact at `$465D-$467F`, **`$0023` / 35 bytes**. Fresh bank `$2F` free space is **`$0E97` / 3,735 bytes** in Red and Blue and **`$0DCC` / 3,532 bytes** in Debug.
- Bank `$2E` `Extra Options Menu` is **`$02FB` / 763 bytes** at `$6772-$6A6C`. Fresh bank `$2E` free space is **`$0214` / 532 bytes** in all three variants. No section moved banks and no new assembled file was added.
- The attempted party-menu immediate-visibility repair was rejected and fully reverted after user testing reported a crash on party-screen exit. The known behavior remains: after changing the lead through the party screen, the replacement can stay hidden until the next player step. A live PyBoy choreography records this as an expected failure instead of claiming acceptance (~99% confident).
- Red, Blue, and Debug builds pass; all ROMs remain 1 MiB. MD5: Red `CA34935FA1D5BD19576F78FAEDC3CAF0`, Blue `6D376B0E6565A259841DC2169E9CF78E`, Debug `88EE7CAF85504788273DC75C19573A08`. The focused follower suite passes **63 tests** with two intentional expected failures: party-swap immediate visibility and the existing lobby-capacity case.

User acceptance: the follower toggle works and everything else in the wave is accepted. The name-before-cry experiment is rejected and reverted. Next work is a separately scoped map-coverage expansion.
## 37. Follower Checkpoint G approved object cuts (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at `master` commit `c03c30f4` plus the uncommitted text rollback and approved object cuts.

- No section or pointer target moved between banks. The cuts remove one object record and its text-pointer entry from each affected map bank.
- Power Plant, bank `$07`: removed one 8-byte trainer-style object record plus one 2-byte text pointer. Minimum free space increased from `$000C` to `$0016` across variants; Red/Blue currently have `$0057`.
- Mt. Moon 1F, bank `$18`: removed one 7-byte item object record plus one 2-byte text pointer. Minimum free space increased from `$006C` to `$0075`.
- Victory Road 1F, bank `$23`: removed one 7-byte item object record plus one 2-byte text pointer. Minimum free space increased from `$1B47` to `$1B50`.
- Plain calls, direct reads, local pointer tables, `BANK()` assumptions, fallthrough, and bank switching are unchanged. The edited pointer tables remain local to their existing map sections.
- Serialized toggle indices are preserved by retired `0, OFF` entries for the Mt. Moon Escape Rope and Victory Road Rare Candy rows. Power Plant's removed Voltorb had no toggle row.
- All three ROM variants build. The 63-test focused follower suite passes with the two documented expected failures. Runtime map choreography remains pending user verification.
## 38. Follower ordinary map coverage group 1 (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at `master` commit `416d5911` plus the uncommitted Power Plant, Mt. Moon 1F, and Victory Road 1F coverage wave.

- No section moved banks and no assembled file was added.
- Bank `$2F` `Follower Core` grew from `$065D` to `$0669` bytes at `$4000-$4668`. Fresh free space is `$0E8B` in Red/Blue and `$0DC0` in Debug.
- Bank `$05`, containing `LoadMapSpriteTilePatterns`, spends 12 bytes on the three additional indoor reservation checks. Fresh free space is `$004F` in all variants, down from `$005B`.
- The new follower map comparisons are local to bank `$2F`. The new VRAM reservation comparisons are local to the existing bank `$05` loader. No plain cross-bank call, direct cross-bank data read, local pointer-table change, `BANK()` assumption, fallthrough dependency, or inline bank switch was added.
- The outside fixed sprite-set loader is unchanged. Lobby and exceptional systems remain excluded.
- All three ROM variants build. The 65-test focused follower suite passes with the two documented expected failures. A Debug 2 lobby-to-stage test confirms slot 15 and image base 2 on all three maps. Full route-entry and gameplay choreography remain pending user acceptance.
## 39. Follower generalized ordinary coverage (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at `master` commit `4812c98d` plus the uncommitted generalized indoor and selected-route wave.

- No section moved banks and no assembled file was added.
- Bank `$2F` `Follower Core` is `$068E` bytes at `$4000-$468D`. Fresh free space is `$0E66` in Red/Blue and `$0D9B` in Debug.
- Bank `$05` `Battle Engine 2`, containing `LoadMapSpriteTilePatterns` and `InitOutsideMapSprites`, grew from `$07B5` to `$07ED`. Fresh bank `$05` free space is `$0017` in every variant.
- The loader reserves image base 2 before authored sheets only for indoor object-list allocation. Outside synthetic fixed sets already place the follower in entry 0/base 2 and must not reserve it a second time. The rejected double-reservation build shifted physical sheets by one and produced Route 3/9 sprite aliases and flicker (~99% confident from shared-set behavior and the user screenshots). Selected Pewter/Cerulean routes remove the unused Rocket sheet before inserting the follower; Route 1 retains its unused Swimmer-sheet rule. Same-set exit checks restore original fixed sets.
- All new calls and data reads remain inside their existing banks. The bank `$2F` exclusion table and Yellow array helper are local; `BC` is preserved around that scan. The bank `$05` outside predicate and set compaction are local. No new `BANK()` assumption, cross-bank plain call/read, fallthrough dependency, or inline bank switch was added.
- All three ROM variants build. The 68-test focused follower suite passes with two documented expected failures. Debug 2 exercises the selected routes, all gyms, and representative indoor stage families. MD5: Red `EAF65D010104E89C6DFA27CF2A1D69D0`, Blue `E087958A241872D55928389C85A985DE`, Debug `B81E27F6F0041A1E2C51DFF1A63D6A0A`. Corrected Route 3/9 BGB visual acceptance remains pending.

## 40. Follower global outdoor sprite-set reservation (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at `master` commit `334f08b9` plus the uncommitted global outdoor coverage wave.

- No section moved banks and no assembled file or RAM field was added. Bank `$2F` `Follower Core` is **`$067A` / 1,658 bytes** at `$4000-$4679`, leaving **`$0E7A` / 3,706 bytes** free in Red and Blue and **`$0DAF` / 3,503 bytes** in Debug.
- Bank `$05` `Battle Engine 2`, containing `LoadMapSpriteTilePatterns` and `InitOutsideMapSprites`, is **`$07E5` / 2,021 bytes** at `$6340-$6B24`. Fresh bank `$05` free space is **`$001F` / 31 bytes** in every variant.
- Every ordinary outdoor map is now eligible. The fixed-set loader scans walking entries 0 through 8, compares them with current active authored object PictureIDs, removes the first unused entry, retains the other eight in order, and inserts the resolved follower at entry 0/base 2. Split-map halves are therefore resolved from their live authored actors rather than a map-specific drop table (~98% confident).
- If all nine walking sheets are in active authored use, the defensive fallback clears slot 15 and leaves the original sprite set intact. Static coverage checks every outdoor object file and fixed or split set. No current map reaches that limit, so no object file receives a false warning. The test failure directs future work to add a `FOLLOWER SPRITE LIMIT` comment to the affected object file before enabling it.
- All new calls and data reads remain within their existing banks. No plain cross-bank call/read, local pointer-table dependency, `BANK()` assumption, fallthrough dependency, or inline bank switch was introduced (~99% confident).
- Red, Blue, and Debug builds pass. MD5: Red `8647E9E85B3490D618F48C775DDEF2C3`, Blue `A8C3D59EDFD4E3EBC5EAC9217D2C4443`, Debug `2A4BB0868F330CC40AAB58F3F39B0861`. The focused suite passes **38 tests** with the two documented expected failures. A live Debug-ROM sweep independently enters every outdoor map and verifies slot 15, the resolved follower PictureID, and image base 2.

Pending: representative BGB visual acceptance across distinct fixed sets and both halves of split maps. Automated machine-state coverage does not prove final NPC/item artwork, scanline behavior, or transition visuals.

## 41. Follower special-relocation spawn-state bridge (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at `master` commit `a86e9419` plus the uncommitted special-transition bridge.

- `PrepareForSpecialWarp` in fixed bank `$01` now clears `wFollowerSpawnState`, then publishes state 1 for Fly and the shared Dig/Escape Rope path or retains state 0 for dungeon warps and blackout. This is a 20-byte ordering adaptation: Yellow writes the same Fly/teleport/dungeon outcomes during `EnterMapAnim`, but Red Rogue's current `FollowerPrepareMap` consumes placement before that animation runs. Copying only Yellow's late assignments would not affect the current arrival and could leak into a later transition (~98% confident).
- Bank `$01` section `bank1` is **`$3C6A` / 15,466 bytes** at `$4000-$7C69`. Bank `$01` has **0 bytes free** in all three variants after all fixed sections. Treat it as closed; any further bank-1 growth requires a measured relocation or reclamation first.
- The bridge reads and writes only local RAM/status symbols and falls through to the existing same-bank `LoadSpecialWarpData`. No new call, direct cross-bank read, pointer-table dependency, `BANK()` assumption, fallthrough across a section, or inline bank switch was introduced (~99% confident).
- ROM0, bank `$05`, and bank `$2F` follower placement are unchanged. No WRAM, HRAM, SRAM, or VRAM layout changed.
- Red, Blue, and Debug builds pass. MD5: Red `E4B61B4FA31B6BD3DD247D037528C51F`, Blue `DE38B2E3E805B4E331E37399DBBE5712`, Debug `8AE6479FB917DB2D4536C7C433916450`. The focused suite passes **39 tests** with the two documented expected failures.

Pending: user runtime acceptance of Fly, Dig, Escape Rope, and blackout. Build and source-gate success do not prove transition choreography.

**Runtime acceptance:** user reports the special-transition slice works well and pushed it as `97084ba3`.

## 42. Yellow follower arrow-tile spinning (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at clean `master` commit `97084ba3` plus the uncommitted spinner branch.

- `FollowerUpdateImage` now ports Yellow's `BIT_SPINNING` branch: it copies the low image/facing nibble from `wSpritePlayerStateData1ImageIndex`, combines it with the follower's own reserved base-2 high nibble, and stores the follower image. No new state, hook, call, data table, or asset was added.
- Bank `$2F` `Follower Core` grows from `$067A` to **`$0689` / 1,673 bytes** at `$4000-$4688`. Fresh bank `$2F` free space is **`$0E6B` / 3,691 bytes** in Red and Blue and **`$0DA0` / 3,488 bytes** in Debug.
- The change reads only existing WRAM state inside the existing bank `$2F` routine. It adds no plain or banked call, direct ROM data read, pointer-table dependency, `BANK()` assumption, fallthrough across a section, or inline bank switch (~99% confident).
- No WRAM, HRAM, SRAM, VRAM layout, sprite pointer table, or map sheet budget changed.
- Red, Blue, and Debug builds pass. MD5: Red `EBBDFE9552EE20AAEE6168315B4C4443`, Blue `226197142AF29ABA76B488DC59DE72C9`, Debug `5E707C9BB04B54C6756066591B5C00E3`. The focused suite passes **40 tests** with the two documented expected failures.

Pending: BGB visual acceptance on a real arrow-tile sequence. Static donor correspondence and build success do not prove the visible synchronized rotation.

## 43. Follower lobby fixed-pose packing (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at clean `master` commit `6a5847a1` plus the uncommitted lobby wave.

- No section moved banks, no assembled file was added, and no sprite constant after `$4A` changed value. The two legacy unused still IDs `$48/$49` remain available under their old names for outside-set filler references and gain lobby aliases for the fixed-south Move Relearner and fixed-right Game Boy Kid.
- Bank `$01` section `bank1` grows by **`$0014` / 20 bytes**, from **`$3C6A` / 15,466 bytes** to **`$3C7E` / 15,486 bytes**. Sixteen bytes select the Game Boy Kid's fixed-right OAM entry, and four bytes add that facing-table entry. Fresh bank `$01` free space is **`$0028` / 40 bytes** in Red and Blue and **`$0010` / 16 bytes** in Debug, down from `$003C` / 60 and `$0024` / 36 respectively.
- Bank `$2F` `Follower Core` shrinks by one byte from **`$0689`** to **`$0688` / 1,672 bytes** at `$4000-$4687` because the lobby map ID is removed from the local exclusion table. Fresh bank `$2F` free space is **`$0E6C` / 3,692 bytes** in Red and Blue and **`$0DA1` / 3,489 bytes** in Debug.
- `SpriteSheetPointerTable` remains size-neutral. Its two old four-tile filler entries now point at four-tile slices of the existing Silph President south pose and Game Boy Kid left pose. The latter uses the new fixed-right OAM entry to reproduce the normal walking-sheet horizontal flip. No graphics bytes were duplicated.
- The lobby retains all 11 authored objects. Its unique-sheet budget is exactly eight 12-tile walking sheets plus both 4-tile slots, while the follower retains slot 15 and image base 2. The clerks keep their normal 12-tile sheet and can still face south or right. The object file carries an explicit `FOLLOWER SPRITE LIMIT` warning for future additions.
- The added code and data remain within bank `$01`; the follower eligibility-table deletion remains within bank `$2F`. No plain cross-bank call/read, local pointer-table width change, `BANK()` assumption, fallthrough across sections, or inline bank switch was introduced (~99% confident).
- Red, Blue, and Debug builds pass. MD5: Red `5D28691B8108233F02F7C1BBC34E2B07`, Blue `85225967970EC05BC332880C29FAFA23`, Debug `11F34FC26D4E13FEA4CF796BDB023738`. The focused source and complete follower runtime suites pass **46 tests** with the one documented party-swap immediate-visibility expected failure. PyBoy verifies all 11 authored lobby picture IDs/image bases and the follower's reserved base 2; it does not prove final artwork or interaction behavior.

Pending BGB acceptance on DMG/SGB/CGB: follower appearance and movement, all lobby NPC artwork, clerk south/right facing, Move Relearner south pose, Game Boy Kid right pose, every service, menus, exits, and the unchanged healing-machine sequence. If the constrained layout is unstable, lobby suppression remains the accepted fallback.


## 44. Lobby fixed-south revision and healing suppression (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at clean `master` commit `5bb3de16` plus the uncommitted correction wave.

- The Game Boy Kid returns to its original 12-tile directional sheet. The second lobby-only four-tile alias now points at the Granny sheet's south-facing tiles for the counter-bound Daycare Lady. The fixed-south Move Relearner remains the other four-tile alias. Object count, object record sizes, sprite table width, and every sprite ID remain unchanged.
- Bank `$01` section `bank1` shrinks by **`$0014` / 20 bytes**, from `$3C7E` to **`$3C6A` / 15,466 bytes**, because the Game Boy Kid fixed-right OAM branch and table entry are removed. Current total bank `$01` free space is **0 bytes** in Red and Blue because fixed `Self-Target Stat Penalty` occupies `$7FC3-$7FFF`; Debug has **`$0024` / 36 bytes** free. The minimum across variants is therefore zero and bank `$01` remains closed despite the section shrink.
- Bank `$1C` section `bank1C` grows by **`$000D` / 13 bytes**, from `$3C71` to **`$3C7E` / 15,486 bytes**. Fresh free space is **`$0382` / 898 bytes** in all variants. `AnimateHealingMachine` sets slot 15's image index to `$FF`, farcalls bank `$01` `PrepareOAMData` to remove it from shadow OAM immediately, and only then freezes sprite updates. The existing final `UpdateSprites` republishes the follower after healing.
- The new farcall has no register input contract and restores bank `$1C` before execution continues. No plain cross-bank call/read, direct cross-bank data access, pointer-table width change, `BANK()` assumption, fallthrough across sections, inline bank switch, or RAM-layout change was introduced (~99% confident).
- Red, Blue, and Debug builds pass. MD5: Red `3B03E9D39694A7DEA5147923D92B0E8B`, Blue `43EBC1369864E6EAE3F8CA9DB9D255B7`, Debug `52A5D2004A6E02953062D731909E9635`. The complete focused follower/lobby set passes **48 tests** with the one documented party-swap immediate-visibility expected failure. Live PyBoy coverage verifies the revised 11-object image-base assignment and observes image `$FF` at the post-shadow-OAM healing seam.

Pending BGB acceptance: confirm the Daycare Lady remains visually correct facing south, the Game Boy Kid uses its restored full sheet, the follower disappears before the healing balls animate, and it returns normally after Nurse Joy finishes.


## 45. Nurse healing image-base correction (2026-08-31)

Measured from fresh Red, Blue, and Blue Debug builds at clean `master` commit `5bb3de16` plus the uncommitted lobby/healing correction wave.

- Root cause: Red's original healing dialogue writes Nurse Joy image indices `$18/$14`, which select image base 2. With the follower reserving base 2, those poses render the follower sheet as Nurse Joy (~99% confident from the image-index contract and user runtime result).
- The two pose constants change size-neutrally to `$28/$24`, selecting Nurse Joy's follower-era base 3. To keep them correct when the follower option is OFF, indoor sprite allocation also reserves base 2 whenever object slot 1 is `SPRITE_NURSE`.
- Bank `$05` `Battle Engine 2` grows by **`$0007` / 7 bytes**, from `$07E5` to **`$07EC` / 2,028 bytes** at `$6340-$6B2B`. Fresh bank `$05` free space is **`$0018` / 24 bytes** in all variants, down from `$001F` / 31. Bank `$01` nurse-dialogue size is unchanged; bank `$1C` healing suppression is unchanged from section 44.
- The loader check and allocation remain within bank `$05`. The nurse pose edits are immediate-value replacements within bank `$01`. No new call, cross-bank data read, pointer-table dependency, `BANK()` assumption, fallthrough dependency, inline bank switch, or RAM-layout change was introduced (~99% confident).
- Red, Blue, and Debug builds pass. MD5: Red `15C0ACC216A49A5D05148079981A98E3`, Blue `4DC806608D18A8D706CFF6B29588B52A`, Debug `5E5A91D8364D9F3B35203BB5C2F85BC4`. The complete focused follower/lobby set passes **49 tests** with the one documented party-swap immediate-visibility expected failure.

Pending BGB acceptance: Nurse Joy must retain her own artwork when turning to the machine and bowing, while the follower remains hidden for the animation and returns afterward. Test once with the follower enabled and once with the follower option disabled.

**Runtime acceptance:** user confirms the follower disappearance works and Nurse Joy no longer becomes the follower.

## 46. Follower dialogue and League/finale coverage (2026-09-01)

Measured from fresh Red, Blue, and Blue Debug builds at clean `master` commit `ddc296f1` plus the uncommitted dialogue and finale wave.

- Interaction now follows the established procedural-boss text structure. `FollowerFindInteraction` resolves `wNameBuffer` before the standard predef text call. `FollowerPokemonText` runs a bank `$23` `text_far` stream containing the species name, `!`, and `text_promptbutton`; only after that acknowledgment does its `text_asm` tail play and finish the cry, preserve `bc`, and end the text script. Runtime hooks prove the cry has not started at the prompt and that the ordinary close/reload lifecycle completes after acknowledgment (~99% confident).
- Bank `$23` gains the 8-byte `_FollowerPokemonInteractionText` stream at `$4A3E`; fresh free space is **`$0872` / 2,162 bytes** in all three variants. No existing text pointer or section moved.
- Removing the six one-byte map exclusions offsets the dialogue handler growth. Bank `$2F` `Follower Core` is **`$0684` / 1,668 bytes** at `$4000-$4683`, leaving **`$0E70` / 3,696 bytes** free in Red and Blue and **`$0DA5` / 3,493 bytes** in Debug. Relative to section 43/45, the section shrinks 4 bytes overall.
- Lorelei, Bruno, Agatha, Lance, Champion, and Hall of Fame now receive slot 15/base 2. The first four and Hall of Fame author one walking sheet each; Champion authors two. This is well below the indoor allocation ceiling of eight authored walking sheets plus the reserved follower. No object or sprite-set cut is required.
- Forced player movement in the Elite Four, Lance, Champion, and Hall of Fame uses the normal simulated input path, which reaches the existing accepted-step follower queue. Oak's independent Champion movement remains an authored `MoveSprite` sequence. The Hall of Fame presentation clears the screen and disables sprite updates before credits, then resets through `Init`; static review finds no need for a follower-only suppression hook (~90% confident). Full visible choreography remains a user runtime gate.
- No WRAM, HRAM, SRAM, VRAM layout, sprite pointer, object record, or map script changed. No new plain cross-bank call/read, local pointer-table dependency, `BANK()` assumption, fallthrough dependency, or inline bank switch was introduced (~99% confident).
- Red, Blue, and Debug builds pass. MD5: Red `5C9375B5632CCD774682315BC66FE0AD`, Blue `C60ACA165B58BFEFCDE4DD9B1BD19CE9`, Debug `9131327EAE93CC2E053C7752691A91AA`. The complete follower source/runtime suite passes **37 tests** with the one documented party-swap immediate-visibility expected failure. A Debug 2 direct-map sweep verifies nonzero follower PictureID and image base 2 in all six newly enabled rooms.

Pending BGB acceptance: dialogue presentation/order; randomized Elite Four traversal; Lance's long forced walk; Champion battle return, Oak movement, and player follow; Hall of Fame presentation, credits transition, and reset.

## 47. Party-reorder follower visibility correction (2026-09-01)

Measured from fresh Red, Blue, and Blue Debug builds at clean `master` commit `0cb559c0` plus the uncommitted party-menu correction.

- Root cause: `StartMenu_Pokemon.exitMenu` restores map sprite graphics through `ReloadMapSpriteTilePatterns_`. That routine temporarily clears `BIT_FONT_LOADED` before `InitMapSprites`. If the lead changed, `FollowerPrepareMap` therefore treated the new sheet as a fresh spawn rather than a text/menu refresh, placed it on the player's coordinates, and correctly hid it for overlap until the next accepted step (~99% confident from the call order and live failing state: ready status, base 2, follower/player map coordinates equal, image `$FF`).
- The fix calls bank `$2F` `FollowerPrepareMap` from the party-menu exit while the font context is still active, immediately before the existing restore/reload call. It preserves the accepted follower pose and updates the PictureID; the unchanged LCD-off reload then installs the new sheet. This deliberately does not modify `ReloadMapSpriteTilePatterns_`, whose previous font-state experiment caused a party-exit crash.
- Bank `$04` gains one eight-byte `farcall`, reducing fresh free space from `$0058` / 88 bytes to **`$0050` / 80 bytes** in all three variants. Bank `$2F` code size and all RAM/VRAM layouts are unchanged.
- The new call has no input or return-value contract. It occurs after the party-menu whiteout and before the existing restore, with no live register value crossing either call. No plain cross-bank call/read, pointer-table dependency, `BANK()` assumption, fallthrough dependency, inline bank switch, or RAM-layout change was introduced (~99% confident).
- Red, Blue, and Debug builds pass. MD5: Red `5506CC8393FBBF159CAFD78C055874B9`, Blue `D0660F48438D0D53CF96DFA9B99CEFDC`, Debug `6D0158F87479967968C82539ACD9C99D`. The combined source, runtime, and sprite-budget suite passes **43 tests** with no expected failures. The real party-menu choreography changes the authoritative lead, exits both party and Start menus, verifies the new follower sheet, and verifies image visibility before any accepted player step.

Pending BGB acceptance: reorder the lead from the Start-menu party screen, back out normally, and confirm the new follower appears immediately with the old follower's position and facing. Repeat without reordering to confirm ordinary party-menu exit remains unchanged.

## 2026-09-06 Bridge special-Pokemon eligibility checkpoint

Measured from fresh forced Red, Blue, and Blue Debug builds at `master` commit `7d604d13` plus the uncommitted C1 special-gift eligibility change and concurrent user-owned AI/debug harness work.

- Bank `$14` section `Hidden Events 2` grows by **`$0083` / 131 bytes**, from `$104F` / 4,175 bytes to **`$10D2` / 4,306 bytes** at `$6BD7-$7CA8`.
- Fresh bank `$14` free space is **`$0357` / 855 bytes** in Red, Blue, and Debug, down from `$03DA` / 986 bytes.
- `BridgeGiftIsEligible` recognizes the routine pointers for Super Ditto, Captain Farfetch'd, Oak Pikachu, and Mr. Fuji's dynamically rolled rescue Pokemon. Rescue reuses exact-species party/current-box filtering. The three special-form gifts scan party and current-box structs for the same species with `BIT_SPECIAL_FORM`, so a generic counterpart does not suppress them. Other `GIFT_SPECIAL` routines retain their existing eligibility behavior.
- All added code and referenced routine labels remain within `Hidden Events 2` in bank `$14`. No cross-bank call/read, `BANK()` assumption, pointer-table width change, fallthrough across a section, inline bank switch, or RAM-layout change was introduced (~98% confident).
- Super Ditto delivery now explicitly sets `BIT_SPECIAL_FORM` through the existing delivery-safe party/box helper. This makes the new ownership predicate observable without changing its capability behavior.
- Forced Red, Blue, and Debug builds pass. MD5: Red `B0F3FBA3D1BF18D19303EBB0F5196B5E`; Blue `04D823798922796F8FD350E1A8C21CC0`; Debug `29268A6810F31D0E375DA731A2D58986`.

Pending: runtime offer filtering with generic and special-form counterparts in party and current box, plus the broader C1b cancellation/full-storage acceptance checklist.

## 2026-09-07 Bridge C2 run-global interface

Measured from fresh forced Red, Blue, and Blue Debug builds at `master` commit `4314322f` plus the uncommitted C2 implementation.

- The witch/event expansion had already completed the badge-stat portion: `ApplyEarnedStatBoosts` and `ApplySingleEarnedStatBoost` read `wEarnedStatBoosts`; `wObtainedBadges` no longer controls 1.125x stats. C2 reuses that path and does not add a competing Battle Core hook (~99% confident).
- `custom_functions/bridge_effects.asm` is included inside the existing pinned `rogue` section in bank `$2F`. It adds 92 bytes, including the inherited Witch Special grant correction. The section changes from `$2E7C` to `$2ED8` in Red/Blue and from `$2FBA` to `$3016` in Debug.
- Bank `$2F` free space changes from `$0A3F` / 2,623 to `$09E3` / 2,531 bytes in Red/Blue and from `$0901` / 2,305 to `$08A5` / 2,213 bytes in Debug. Minimum remaining is 2,213 bytes.
- Public grant/check routines accept the effect index in `e`, the established farcall-safe input register. They return ownership through carry and do not expose a banked data pointer. No plain cross-bank call, direct banked data read, pointer-table change, `BANK()` assumption, section fallthrough, or inline bank switch was introduced (~99% confident).
- Forced Red, Blue, and Debug builds pass. MD5: Red `D7F2CA9A31B29265F31CCBE6F4DD9512`; Blue `A7A4214AC2479879FDD5C00E3D755BA0`; Debug `2EE476127914ABE22C28C93A6705716E`.

## 2026-09-08 Bridge C3-C10 completion checkpoint

Measured from fresh forced Red, Blue, and Blue Debug builds at `master` `5bb3cd3f` plus the uncommitted Bridge presentation/test corrections. The user-owned `357b7bde` commit contains the combined Bridge work together with Pokemon import batches, so a clean Bridge-only total delta cannot be reconstructed from that commit. Current placement figures below are authoritative; only the Officer Jenny sheet has an exact isolated byte delta.

- Bank `$12`, `Hidden Events 2`: `$1468` / 5,224 bytes at `$6847-$7CAE`; `$0351` / 849 bytes free in all targets. This retains menu dispatch, descriptors, and compact wrappers.
- Bank `$14`, `Bridge Gift Text`: `$0557` / 1,367 bytes at `$7967-$7EBD`; `$0142` / 322 bytes free in all targets.
- Bank `$34`, `Bridge Extended Effects`: `$0188` / 392 bytes at `$414D-$42D4`; the bank retains `$0AC0` / 2,752 bytes free in all targets. Status, healing, and Second Chance code moved here instead of overflowing the Bridge menu bank.
- Floating `rogue` section: Red/Blue place it in bank `$2F` at `$4745-$7ED3`, `$378F` / 14,223 bytes, leaving `$012C` / 300 bytes. Debug places it in bank `$35` at `$4000-$78CC`, `$38CD` / 14,541 bytes, leaving `$0733` / 1,843 bytes. Mist selection, selected-effect ownership, global effects, and custom gift finalization use this section. Callers use the established farcall-safe `d`/`e`/flags contracts.
- Bank `$05`, `NPC Sprites 2`: `$2340` / 9,024 bytes at `$4000-$633F`; the bank retains only `$000D` / 13 bytes in all targets. Officer Jenny adds exactly `$0180` / 384 bytes by repeating Yellow's authored 192-byte sheet to satisfy this fork's 12-tile loader contract. Treat bank `$05` as effectively closed.
- No Bridge routine was left executing across an inline ROMX bank switch, no new plain cross-bank call or direct cross-bank data read was introduced, and the moved Second Chance/Mist code is reached through established farcalls or same-bank calls (~97% confident).
- Forced builds pass at 1 MiB. MD5: Red `BD38A3D63E472A6E845093037DCAD359`; Blue `23AFC10B9003C22B0C6AFED331BFA26B`; Debug `2FE48D39FCE9FDF4A8B7885156B6A096`. Focused Bridge tests pass 44/44 and full smoke passes 234/234.

Pending runtime acceptance: every-room giver/menu/PC choreography, party-full box retrieval and cancellation paths, selected-effect transfer choreography, Mist Stone animation and branching, Officer Jenny/Flora visuals and collision, and Dragon palette behavior in status, battle, and box contexts.

