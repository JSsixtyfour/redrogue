# Red Rogue

A roguelike built on the [pret/pokered](https://github.com/pret/pokered) disassembly.

# Credits
# Pokémon Red Rogue Team
## Developer
- The_Smashfather - Developer
## Sprite Artists
- halofactory: Trainer Back Sprites
- SkidMarc25: Red/Green Style Johto Pokemon Sprites
- Kyle Glor: Pokemon Sprites
- TheQuickSlash
- Sope!
## Playtesters
- 1upShyGuy
- goombapatrol
- halofactory
- pun
- Josh Brody
# Source Mod Credits
## Shin Pokemon Red
### Creators:
- jojobear13
     - Enhanced Colors
     - Gamma Colors
     - 60 FPS
     - Gen 1 Bug Fixes
     - Shiny system
     - PokemonYellow Audio Backport
     - Daycare Upgrades
     - EXP bar
     - AI Work
     - Random Upgrades
     - DV Upgrades
     - and much muchmore
## Credits For Pokemon Yume:
### Creator:
- PokefanMarcel - Developer
   - Bill's PC grid
   - battle move-info panel
   - status-screen art
   - running sprites
   - player-select system
   - math routines
   - Item Bag System
   - and much more
## Credits For Pokemon Extreme Yellow:
### Creator:
- RainbowMetalPigeon
   - mid-battle evolution
   - move descriptions
   - difficulty modes
   - Cubone overworld sprite
   - AI Work
## Credits For Kanto Expansion Pak:
### Creator:
- MementoMartha
   - Post GSC Species Data
   - Sprites for Various Regional Forms, Eeveelutions, and other Pokemon
## Credits For Red++:
### Creator:
- JustRegularLuna
   - Johto Species Data
   - Sprites for Various Regional Forms, Eeveelutions, and other Pokemon
## Credits For Polished Crystal:
### Creator:
- Rangi
   - Multiplication & Division Routine
### Creator:
## Credits For pureRGB:
### Creator:
- Vortyne - Developer
   - HBlank tile copying,
   - map-redraw speedups,
   - assorted fixes.
## Credits For Yellow Legacy:
### Creators:
- TheSmithPlays - Developer
- cRz Shadows - Developer
### Sprite Artists:
- Pokemon overworld sprites
    - Isona
    - Alakadoof
    - Karlos
- Pokemon party sprites
    - Chamber
    - Soloo993
    - Blue Emerald
    - Lake
    - Neslug
    - Pikachu25
- Green sprite
    - Madame Frog/Hatun
    - Ghost-MissingNo
- Nurse Joy Battle Sprite - ZuperZACH
- Officer Jenny Battle Sprite - Karlos

### Code Credits:
- PlagueVonKarma:
    - KEP’s AI is based on Vortyne’s PureRGB AI, with elements from Jojobear13’s Shinred AI
        - https://github.com/PlagueVonKarma/kep-hack/blob/0af5bd126bd1d1b69bfd9b7fe3da20e1b14f094c/engine/battle/trainer_ai.asm
        - https://github.com/PlagueVonKarma/kep-hack/commit/0af5bd126bd1d1b69bfd9b7fe3da20e1b14f094c
        - https://github.com/PlagueVonKarma/kep-hack/commit/e6763371e4fcb26da70709fe0566ab4a8d1d2083
        - https://github.com/PlagueVonKarma/kep-hack/commit/c8f27d8bce0a0708d347f510694be4fba8158c65
    - [Already Caught Icon](https://github.com/PlagueVonKarma/kep-hack/commit/00efe3c6b461773a20b424fbf548cb38c880c9ac)
    - [Move Relearner & Move Deleter](https://github.com/pret/pokered/wiki/Adding-a-Move-Relearner-&-Move-Deleter)
    - [DV / Stat Exp display in stat menu](https://github.com/PlagueVonKarma/kep-hack/commit/98110eddc82ff056a0c8420dc96fe5d9bbd9cb79)
    - [Faster Spinners](https://github.com/PlagueVonKarma/kep-hack/commit/7c5c2a3047dd74b9ed014053172e0222b49d486b)
    - [Shorter Exp All Message](https://github.com/pret/pokered/wiki/Experience-System-&-Exp.-All-Enhancements-(Single-message,-etc))
- Jojobear13:
    - [Box full reminder ](https://github.com/jojobear13/shinpokered/commit/7223a046997168913e67444b509ec15462bc7ec1)
    - [Player animation is faster when running](https://github.com/jojobear13/shinpokered/commit/34b1776a54c7617f749e8ca2757721d58a59c150)
    - [Pokemon can now learn more than 1 move per level](https://github.com/jojobear13/shinpokered/commit/d3357ca3b68af11a66e4f60459cd354f65e99e39)
    - [TM names display on pick up](https://github.com/jojobear13/shinpokered/commit/34c4a36a581769a59e45449fd2bdcad31ee54a99)
- YakiNeen:
    - [Remove Redundant TrainerNamePointers](https://github.com/pret/pokered/wiki/Remove-Redundant-TrainerNamePointers)
    - [Remove Some Japanese Text Grammar Functions](https://github.com/pret/pokered/wiki/Remove-Some-Japanese-Text-Grammar-Functions)
    - [Remove Unused Tile in gfx overworld fishing_rod.png](https://github.com/pret/pokered/wiki/Remove-Unused-Tile-in-gfx-overworld-fishing_rod.png)
    - [Remove Dakutens and Handakutens feature](https://github.com/pret/pokered/wiki/Remove-Dakutens-and-Handakutens-feature)
    - [Remove Japanese Opening Quote and put BOLD P in gfx font font_battle_extra.png](https://github.com/pret/pokered/wiki/Remove-Japanese-Opening-Quote-and-put-BOLD-P-in-gfx-font-font_battle_extra.png)
    - [Remove Blank Leader Names](https://github.com/pret/pokered/wiki/Remove-Blank-Leader-Names)
    - [Collision check when Jumping a Ledge](https://github.com/pret/pokered/wiki/Collision-check-when-Jumping-a-Ledge)
- Vortyne:
    - [Multiple-level-up learnset skipping bug fix](https://github.com/Vortyne/pureRGB/commit/9c38ff4a1afb8c0773202b37c8b9068b4b9f4354)
    - [Move overworld tile anim code out of home bank](https://github.com/Vortyne/pureRGB/commit/09c037f5df39cd99fe4e13b4d5fee8ed86206e7b)
- Pgattic:
    - [Running Shoes (https://github.com/pret/pokered/wiki/Running-Shoes)
    - [Remove Artificial Save Delay](https://github.com/pret/pokered/wiki/Remove-Artificial-Save-Delay)
- Xillicis:
    - [Remove 25% chance for enemy stat down moves to miss](https://github.com/pret/pokered/wiki/Remove-25%25-chance-for-enemy-stat-down-moves-to-miss)
    - [Implement move priority system](https://github.com/pret/pokered/wiki/Implement-move-priority-system)
- Dannye - [Add All Unique Party Menu Sprite Icons](https://github.com/pret/pokered/wiki/Add-All-Unique-Party-Menu-Sprite-Icons)
- SoupPotato/Dannye - [Functioning EXP bar in battle](https://github.com/AhabsStudios/pokekaizen/commit/0332a4d1ca74b4993b2f4bc8d926bac971a0751d)
- Voloved - [Add Item Sorting In Bag](https://github.com/pret/pokered/wiki/Add-Item-Sorting-In-Bag)
- Mateo - [Move Relearner/Tutor]([https://github.com/pret/pokered/wiki/Add-Item-Sorting-In-Bag](https://github.com/pret/pokered/wiki/Adding-a-Move-Relearner-&-Move-Deleter))
- SatoMew (presumably more people worked on these but satomew is the only page author) - [Bugs and Glitches](https://github.com/pret/pokered/wiki/%5BARCHIVED%5D-Bugs-and-Glitches)
- JustRegularLuna
     - [Running Shoes](https://github.com/pret/pokered/wiki/Running-Shoes)
     - [Trainers are Not Pokemon](https://github.com/pret/pokered/wiki/Trainers-are-not-Pokemon)
- suloku [Experience Share](https://github.com/pret/pokered/wiki/Experience-System-&-Exp.-All-Enhancements-(Single-message,-etc))
- **Patrik Rak:** CMWC random number generator (with optimisations by Einar Saukas and Alan Albrecht).

**Tutorials**
- The pret/pokered wiki tutorial authors.

**Research and inspiration**
- The Smogon RBY community.
- pokeemerald-expansion.
- pmariglia's foul-play / poke-engine.
- genericmadscientist's Pokemon Stadium 2 write-up.

**Pokemon** is (c) Nintendo, Creatures Inc. and GAME FREAK inc. Red Rogue is a non-commercial fan
project and is not affiliated with or endorsed by them.

**pret/pokered contributors** (from the disassembly's git history, deduplicated):
95girl, Adam AKA Coolboyman, Akatsuki-py, Akihiro Otomo, Alchav, Amber Brault, AnonymousRandomPerson,
Antonio Nino Diaz, bitman44, BlueZangoose, Bryan Bishop, Chatot4444, colawsol, Colton G. Rushton,
CreamElDudJafar, Daniel Harding (dannye), deak311andris, DrNyk, edave64, Eggy0, Engezerstorung,
IIMarckus, Joe Farebrother, Jordan Moore, kagnusdev, KuroiIeWa5Da, Lin, Linus Unneback, luckytyphlosion,
Marcus Huderle, Mathias Bynens, Matt, Matthew Glazar, mid-kid, Mr Wint, Narishma-gb, Nishant Chatterjee,
Nog-Frog, Panda Habert, PikalaxALT, Pokechu22, PokefanMarcel, Pokeglitch, Preeyan Parmar,
RainbowMetalPigeon, Rangi, Remy Oukaour, Rotekoppen, Sam Nelson, Sanky, Sanqui, SatoMew, Sawakita,
SnorlaxMonster, stag019, strager, stringflow, Summate, Sylvie, TheFakeMateo, Thomas Winwood,
Urs-Bjorn Schmidt, Victor M. Gonzalez, Vortyne, vulcandth, xCrystal, xeons, YamaArashi, yenatch,
Yoann Fievez, Zachary Buhman, and two contributors recorded only by machine address (Adam, David).

## Building

See [INSTALL.md](INSTALL.md) for toolchain setup (rgbds version in `.rgbds-version`). Build from WSL
or Linux:

```sh
make            # pokered.gbc, pokeblue.gbc, pokeblue_debug.gbc
```

Always build all three ROMs when verifying a change. Every link is also archived to `builds/` with its
matching `.sym`, stamped with date and git hash (`BUILD_KEEP=N` keeps the newest N per ROM).

## Verification

| Target | What it checks |
| --- | --- |
| `make smoke` | PyBoy smoke suite against `pokeblue_debug.gbc`. `make smoke TEST='*pattern*'` runs a subset; `python3 tools/pyboy_smoke/run_smoke.py --list` lists test IDs. See [tools/pyboy_smoke/README.md](tools/pyboy_smoke/README.md). |
| `make audit` | Static bank/call/clobber, stack, SRAM, and text-trap analyzers over all three ROMs. `INFO=1` shows info-level findings; triage lives in `tools/static_audit/allowlist.txt`. |
| `make space` | Free bytes per bank (total and largest gap, min across all three ROMs) with deltas since the last run, plus which labels changed bank or shifted (`tools/sym_diff.py`). `SPACE_ARGS='--all'` shows every bank; `SPACE_ARGS='--min-free ROM0=64'` enforces a floor. |
| `make audits_long` | The slower standalone regression guards registered in `tools/pyboy_smoke/audits.json` (about 5 minutes). `AUDITS='*cave*'` narrows the set; `run_audits.py --list` shows what each guards. |
| `make integration` | Slower tier that drives complete gameplay interactions. |
| `make balance_report` | Balance model self-check and report. |

`git config core.hooksPath tools/hooks` enables a pre-commit hook that runs the source-only map and
text audits (a few seconds, and only when relevant files are staged) and compiles staged Python.

A clean build proves only that the ROM links. Visual and timing behavior (palettes, fades, raster
effects, walk cadence) still needs a BGB check.

## Releasing to testers

```sh
make release
```

From WSL, with everything committed and pushed. It asks for "What's new", "What to test" (Enter
on "What's new" lets the playtest bot draft it from the commit messages) and whether saves from an
earlier build still work, then:

1. Refuses uncommitted changes or an unpushed commit, before building anything.
2. Relinks all three ROMs (so every archive carries this commit), then runs the quick checks
   (`make save_schema`, `make save_converter`, a space report) before `make audit` and `make smoke`, so a
   quick failure shows up early. Any failure stops it; nothing is sent. Each check's output is logged.
3. Finds the ROMs this run built by content (each archive must match the ROM the build just wrote)
   and keeps a package in `builds/releases/pokeblue_debug_<stamp>_<hash>/`: all three ROMs with
   `.sym` and `.map`, the check logs, and `manifest.json` (full commit, SHA-1 and SHA-256 of every
   file, tool versions, check results, save compatibility, and manual acceptance: pending). A package
   is never overwritten with different bytes. The debug `.gbc`/`.sym` also stay directly in
   `builds/releases/` for crash lookups. `BUILD_KEEP` never prunes any of it.
4. Sends the ROM and the manifest to the playtest bot through a Discord webhook. The bot checks the
   ROM against the manifest's hash, makes the patches, updates the patch page, marks reports Fixed
   from `Fixes RR-0012` commits, announces, and replies under the webhook's message in that channel.
   `sent.json` in the package records the message.

`make release RELEASE_ARGS='--notes "New gym" --testing "Gym 3"'` skips the questions,
`--no-announce` sets the build without announcing it, and `--dry-run` does everything except send.

**Save compatibility** is one of `supported` (you loaded a save from an earlier build in this one; say
which with `--save-compat-from 74f82c1b`), `new_save_required`, or `unverified` (the default when you
press Enter). `--save-compat` and `--save-compat-notes "..."` skip the question. Testers see it as
"Your save" in the announcement.

`python3 -m unittest tools/test_release.py` tests the script with git, make and Discord faked.

**One-time setup:** in a private developers' channel, **Edit Channel > Integrations > Webhooks > New
Webhook**, copy its URL, and put it in an untracked `.env` at the repo root:

```
RELEASE_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

The bot side (its `release_webhook_id` and the Message Content intent) is in the playtest bot's
README.

## Crash screen

In the debug build, a crash shows a screen instead of freezing. It catches a jump into unused ROM
or to `$0000`, which is how most of this project's bugs end. Release builds still just hang.
`tools/crash_lookup.py` turns that screen into routine names, using the `.sym` that `builds/`
archived for that exact build.

**When a tester sends a crash screenshot**, open PowerShell in the repo folder (type `powershell` in
File Explorer's address bar while in `redrogue`) and run:

```
py tools\crash_lookup.py
```

It asks for four things, all copied from the screen:

| It asks for | Where it is on the screen | Example |
| --- | --- | --- |
| ID line | line 4, after `ID` | `9dba3ff3-dirty` |
| Date and time | line 3 (only needed if you built that commit more than once; Enter skips) | `2026-10-01 13:24` |
| PC line | after `PC` | `00:3E7C` |
| The six STACK words | the three `STACK` lines, left to right, top to bottom | `352B 01DC 2240 3733 3785 3070` |

Or type it all on one line: `py tools\crash_lookup.py 9dba3ff3 00:3E7C 352B 01DC 2240 3733 3785 3070`
(add `--built "2026-10-01 13:24"` to pick between builds of the same commit). From WSL, use
`python3 tools/crash_lookup.py` the same way.

**Reading the answer:**
- `PC` is where the CPU ended up. If it says the byte is `$FF` padding, the bug is whatever *jumped
  there*, not the code at that address.
- Each `stack` line is a lead on who called whom, most recent first. HOME addresses (below `4000`)
  are exact. Addresses from `4000` to `7FFF` are looked up in the crash's bank, which is wrong if
  that call came through a farcall from another bank. A word that lands exactly on a label (no
  `+$..`) is usually a saved register, not a call.
- The screen also shows the registers, the WRAM bank (anything other than `01` at a crash is itself
  a clue, see WRAM Bible section I1), and the map with X and Y.

Next step is the usual one: put a BGB breakpoint on the routine the stack names, and reproduce.

**From Discord:** `/report crash id:RR-0012 build:9dba3ff3 pc:1F:5A3C stack:352B 01DC ...` does the
same lookup on the bot's machine and posts it in the report's private thread. It uses `--exact`, so if
two builds share that ID it lists them and asks for `built` (the screen's date line) rather than
guessing. It works for builds sent with `make release` (the bot keeps their `.gbc` and `.sym`); the
playtest bot's README has the one-time setup. `--json` prints the result as data.

## Reproduction bundles

To gather everything about one report in one folder:

```
py tools\repro_bundle.py RR-0012 --export redrogue_playtest_export.json --evidence C:\Downloads\rr12
```

`--export` is a JSON file from the bot's `/export`; `--evidence` is a folder of files you downloaded for
the report (screenshots, video, `.sav`, BGB `.sn1` states). It writes `builds/repro/RR-0012/`
(git-ignored, never overwritten): `reproduction.md` (steps, expected and actual to fill in, environment,
history, retests), the files unchanged, the report's build's ROM and `.sym` when they match the hashes
the bot recorded, and `manifest.json` with every file's SHA-256. Each BGB state's recorded ROM MD5 is
checked against that build's ROM, and a mismatch, an unknown build or a missing file is called out at
the top. It never downloads anything or unpacks archives.

`python3 -m unittest tools/test_release.py tools/test_crash_lookup.py tools/test_repro_bundle.py` runs
the tests for these tools (CI runs them too).

It needs that build's `.sym`. Builds sent with `make release` are kept for good in
`builds/releases/`, which the tool searches too. Anything else lives only in `builds/`, where
`BUILD_KEEP` (default 20 per ROM) prunes older ones within a day or two of normal work: copy those
somewhere safe and pass the `.sym` path in place of the ID. A clean commit can also be rebuilt for
the same addresses; a `-dirty` build cannot.

## Save format

Every save carries a header (`RRSG` plus `SAVE_SCHEMA_ID` from `constants/save_constants.asm`) at
SRAM bank 1 `$a040`. Continue refuses a save from another format and leaves it untouched; testers
convert it on the patch page ("Convert your save"), which runs the converter `make release` builds.

| Target | What it checks |
| --- | --- |
| `make save_schema` | The save layout against `tools/save_schemas/schema_<id>.json`. Fails if a saved field moved, or a constant a save can store (event, toggle, item, species, map...) was renumbered or removed, without bumping `SAVE_SCHEMA_ID`, or a persisted SRAM label has no policy in `tools/save_schemas/policy.json`. Comments, added constants and unsaved RAM never trip it. `make release` runs it right after the build. |
| `make save_converter` | Builds the converter package and runs its Node tests. `SAVE_FIXTURES=<dir>` adds real saves. |

Changing the save format (bump, migration, tests, real-save gate) is in `SAVE_COMPATIBILITY_RUNBOOK.md`
in Red Rogue Files. `python3 tools/save_compat/saves.py make|continue` makes real saves with PyBoy and
cold-boot checks them.

## Preview pages

Two scripts build a single self-contained HTML page each, from the source files they describe. Open
the page in any browser. Nothing is installed and nothing outside the standard library is needed.
Re-run a script after editing what it reads; the page never updates on its own.

```
py tools\palette_preview.py     # writes tools\palette_preview.html
py tools\textbox_writer.py      # writes tools\textbox_writer.html
```

From WSL, use `python3` the same way. `--out <path>` writes the page somewhere else.

**Palette Bench** (`palette_preview.py`) draws every tileset in every Enhanced Colors base set, as
mapped blocks or raw tiles, with two base sets side by side to compare a variant (forest spring vs
fall, facility default vs red). Hover a tile for its table entry and slot; click a slot to highlight
the tiles that use it. It reads `data/gfx/overworld_tile_palettes.asm` (which slot each tile uses),
the base sets in `custom_functions/func_enhancedcolor.asm` (what colours each slot holds), the tileset
lists, and the built `.2bpp`/`.bst` files, so **run `make` first**. The "In-game gamma" box applies the
game's `GBCGamma` correction, so the page matches hardware; off, it shows the raw source values. When a
base set gains a new consumer, update `BASE_SET_USES` at the top of the script so the page's "used by"
line stays right.

To try colours, click a swatch or any pixel in a sheet and adjust it with the R/G/B sliders (0-31) or
the picker. Set the second base set to "Same set, as in source" to see your edit next to the original.
Edits stay in that browser only. **Copy slot asm** gives the 5 lines for that slot, ready to paste over
the same slot in `func_enhancedcolor.asm`; **Copy set asm** gives the whole set but leaves out comment
lines inside it. Re-run the script after pasting, and reset the edits once the source has them.

**Textbox Writer** (`textbox_writer.py`) turns prose into `text`/`line`/`cont`/`para` macros wrapped
to the 18-tile dialogue box, previewed in the game's own font. A blank line starts a `para`, a single
line break forces a new line, and `{wStringBuffer:12}` inserts a `text_ram` with 12 tiles reserved.
Widths follow rgbasm's charmap (`'s` is one tile, `#` is four), and `<PLAYER>`/`<RIVAL>` count at their
7-tile maximum. Its Check tab measures macros pasted from an existing `text/*.asm` file. It reads
`constants/charmap.asm` and `gfx/font/`, so re-run it after changing either.

## Project docs

Design plans, the ROM and WRAM space ledgers, and debugging guides live outside the repo, in the
`Red Rogue Files` folder. Agent instructions are in `CLAUDE.md` and `AGENTS.md`.
